#!/usr/bin/env python3
"""Service-role moderation for Grouply localhost only; never prints credentials."""
import argparse
import json
from pathlib import Path
from queue import Empty, Queue
import subprocess
import sys
from threading import Thread
import time
import uuid

from backend_local import local_status, request


def check_locks():
    root = Path(__file__).resolve().parents[1]
    command = ["docker", "exec", "-i", "supabase_db_Grouply", "psql", "-U", "postgres", "-d", "postgres",
               "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1"]

    def sql(statement):
        result = subprocess.run(command, input=statement, cwd=root, capture_output=True, text=True, timeout=12)
        if result.returncode:
            raise RuntimeError("Local lock-test SQL failed: " + result.stderr.strip())
        return result.stdout.strip()

    class Session:
        def __init__(self):
            self.process = subprocess.Popen(command, cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT, text=True, bufsize=1)
            self.lines = Queue()

            def collect():
                for line in self.process.stdout:
                    self.lines.put(line.rstrip())
                self.lines.put(None)

            self.reader = Thread(target=collect, daemon=True)
            self.reader.start()
            self.pid = int(self.run("BEGIN; SET LOCAL statement_timeout='4s'; SET LOCAL deadlock_timeout='100ms'; SELECT pg_backend_pid();")[-1])

        def send(self, statement):
            marker = "finished_" + uuid.uuid4().hex
            self.process.stdin.write(statement + "\nSELECT '" + marker + "';\n")
            self.process.stdin.flush()
            return marker

        def receive(self, marker):
            output = []
            deadline = time.monotonic() + 7
            while time.monotonic() < deadline:
                try:
                    line = self.lines.get(timeout=max(0.01, deadline - time.monotonic()))
                except Empty:
                    break
                if line == marker:
                    return output
                if line is None:
                    raise RuntimeError("Lock-test session failed: " + " ".join(output))
                if line:
                    output.append(line)
            raise RuntimeError("Lock-test session timed out")

        def run(self, statement):
            return self.receive(self.send(statement))

        def close(self):
            if self.process.poll() is None:
                try:
                    self.process.stdin.write("ROLLBACK;\n\\q\n")
                    self.process.stdin.flush()
                except (BrokenPipeError, OSError):
                    pass
                try:
                    self.process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=3)
            self.reader.join(timeout=1)

    def blocked(waiter, holder):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if sql(f"SELECT {holder.pid}=ANY(pg_blocking_pids({waiter.pid}));") == "t":
                return
            time.sleep(0.02)
        raise RuntimeError("Expected lock interleaving was not reached")

    actor, coordinator, group, project, own_message, target_message, report = [str(uuid.uuid4()) for _ in range(7)]

    def login(identity):
        claims = json.dumps({"sub": identity, "role": "authenticated"})
        return "SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claims','" + claims + "',true);"

    def mutate(action, payload):
        return "SELECT public.grouply_mutate('" + action + "','" + json.dumps(payload) + "'::jsonb);"

    setup = f"""
      BEGIN;
      INSERT INTO auth.users(id,raw_user_meta_data) VALUES ('{actor}','{{"name":"Lock fixture actor"}}'),('{coordinator}','{{"name":"Lock fixture coordinator"}}');
      INSERT INTO public.groups(id,name,coordinator_id) VALUES('{group}','Lock fixture','{coordinator}');
      INSERT INTO public.group_members VALUES('{group}','{actor}'),('{group}','{coordinator}');
      INSERT INTO public.projects(id,group_id,title,due_at) VALUES('{project}','{group}','Lock fixture',now()+interval '1 day');
      INSERT INTO public.chat_messages(id,group_id,sender_id,content) VALUES('{own_message}','{group}','{actor}','Actor history'),('{target_message}','{group}','{coordinator}','Reported history');
      INSERT INTO private.content_reports(id,message_id,reporter_id,reason) VALUES('{report}','{target_message}','{actor}','Lock fixture report');
      COMMIT;
    """
    cleanup = f"""
      BEGIN;
      DELETE FROM private.content_reports WHERE id='{report}';
      DELETE FROM public.chat_messages WHERE group_id='{group}';
      DELETE FROM public.activity_events WHERE group_id='{group}';
      DELETE FROM public.tasks WHERE project_id='{project}';
      DELETE FROM public.projects WHERE id='{project}';
      DELETE FROM public.group_members WHERE group_id='{group}';
      DELETE FROM public.groups WHERE id='{group}';
      DELETE FROM public.profiles WHERE id IN ('{actor}','{coordinator}');
      DELETE FROM auth.users WHERE id IN ('{actor}','{coordinator}');
      COMMIT;
    """
    sql(setup)
    failures = []
    try:
        first = second = None
        try:
            first, second = Session(), Session()
            first.run(f"SELECT id FROM public.groups WHERE id='{group}' FOR UPDATE;")
            waiting = second.send(login(actor) + mutate("sendMessage", {"groupID": group, "clientID": str(uuid.uuid4()), "text": "Concurrent member mutation"}))
            blocked(second, first)
            created = first.run(login(coordinator) + mutate("createTask", {"projectID": project, "title": "Concurrent assignment", "assigneeID": actor, "reviewerID": coordinator, "dueAt": "2099-01-01T00:00:00Z"}))
            assert any('"id"' in line for line in created), "Assignment did not complete"
            first.run("ROLLBACK;")
            completed = second.receive(waiting)
            assert any('"id"' in line for line in completed), "Member mutation did not complete"
            second.run("ROLLBACK;")
            print("PASS: coordinator assignment / waiting member mutation, both complete")
        except (RuntimeError, AssertionError) as error:
            failures.append("assignment/member mutation")
            print("FAIL: assignment/member mutation: " + str(error), file=sys.stderr)
        finally:
            for session in (first, second):
                if session is not None:
                    session.close()

        for former_member in (False, True):
            if former_member:
                sql(f"DELETE FROM public.group_members WHERE group_id='{group}' AND user_id='{actor}';")
            for decision in ("dismissed", "removed"):
                first = second = None
                label = "delete / moderation " + decision + (" former-member reporter" if former_member else " active-member reporter")
                try:
                    first, second = Session(), Session()
                    first.run(f"SELECT id FROM private.content_reports WHERE id='{report}' FOR UPDATE;")
                    waiting = second.send(login(actor) + mutate("deleteAccount", {}))
                    blocked(second, first)
                    body = json.dumps({"id": report, "decision": decision, "note": "Deterministic lock regression"})
                    reviewed = first.run("SET LOCAL ROLE service_role; SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',true); SELECT public.grouply_moderation('review','" + body + "'::jsonb);")
                    assert any('"status": "' + decision + '"' in line for line in reviewed), "Moderation did not complete"
                    first.run("ROLLBACK;")
                    deleted = second.receive(waiting)
                    assert any('"deleted": true' in line for line in deleted), "Deletion did not complete"
                    second.run("ROLLBACK;")
                    print("PASS: " + label + ", both complete")
                except (RuntimeError, AssertionError) as error:
                    failures.append(label)
                    print("FAIL: " + label + ": " + str(error), file=sys.stderr)
                finally:
                    for session in (first, second):
                        if session is not None:
                            session.close()
    finally:
        sql(cleanup)
        assert sql(f"SELECT count(*) FROM auth.users WHERE id IN ('{actor}','{coordinator}');") == "0", "Disposable lock fixtures were not cleaned"
    if failures:
        raise RuntimeError("Lock regressions failed: " + ", ".join(failures))
    print("PASS: all five deterministic two-session checks; disposable fixtures removed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("queue", help="List the oldest 100 pending reports")
    commands.add_parser("check-locks", help="Exercise five deterministic lock races with disposable local fixtures")
    review = commands.add_parser("review", help="Resolve one report by ID")
    review.add_argument("id", type=uuid.UUID)
    review.add_argument("decision", choices=("dismissed", "removed"))
    review.add_argument("--note", required=True)
    args = parser.parse_args()
    payload = {}
    if args.command == "review":
        if not 1 <= len(args.note.strip()) <= 1000:
            parser.error("Resolution note must contain 1–1000 characters.")
        payload = {"id": str(args.id), "decision": args.decision, "note": args.note.strip()}
    status = local_status()
    if args.command == "check-locks":
        check_locks()
        return
    key = status["SERVICE_ROLE_KEY"]
    code, result = request(status["API_URL"], key, "rest/v1/rpc/grouply_moderation",
                           {"action": args.command, "payload": payload}, key)
    if code != 200:
        raise RuntimeError("Local moderation rejected (HTTP " + str(code) + "). No credentials printed.")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, ValueError, OSError):
        print("Moderation failed. Check Grouply local status and report ID; credentials are not logged.", file=sys.stderr)
        sys.exit(1)
