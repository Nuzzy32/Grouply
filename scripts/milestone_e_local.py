#!/usr/bin/env python3
"""Opt-in localhost-only Milestone E HTTP checks; never applies migrations.

Run after the parent confirms migration readiness:
    python3 scripts/milestone_e_local.py --run
Offline guard/cleanup checks:
    python3 scripts/milestone_e_local.py --self-check
Only random users created by this invocation may be deleted. Retained
orphan groups/history are intentionally not purged. No credentials are persisted.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
import secrets
import sys
import traceback
from urllib.parse import urlsplit
import uuid

from backend_local import ROOT, local_status, request


def require_local(url):
    parsed = urlsplit(url)
    assert parsed.scheme == "http" and parsed.hostname in ("localhost", "127.0.0.1")
    assert parsed.port == 55321 and parsed.path in ("", "/")
    assert not (parsed.username or parsed.password or parsed.query or parsed.fragment)
    return url.rstrip("/")


class Verification:
    def __init__(self, status):
        self.url = require_local(status["API_URL"])
        self.public = status.get("PUBLISHABLE_KEY") or status["ANON_KEY"]
        self.service = status["SERVICE_ROLE_KEY"]
        self.prefix = "milestone-e-" + uuid.uuid4().hex
        self.users = {}
        self.created = {}
        self.tasks = set()
        self.checks = []
        self.stage = "fixtures"

    def call(self, path, body=None, user=None, admin=False, method="POST"):
        key = self.service if admin else self.public
        token = self.service if admin else self.users[user]["access_token"] if user else None
        return request(self.url, key, path, body, token, method)

    def create_user(self, name):
        email = self.prefix + "-" + name + "@grouply.local"
        password = secrets.token_urlsafe(32)
        code, result = self.call("auth/v1/admin/users", {
            "email": email, "password": password, "email_confirm": True,
            "user_metadata": {"name": "Milestone E " + name},
        }, admin=True)
        assert code in (200, 201), "fixture creation rejected"
        user_id = str(uuid.UUID(result["id"]))
        self.created[user_id] = email
        assert result["email"] == email, "unexpected fixture identity"
        self.users[name] = {"id": user_id, "email": email, "password": password}
        code, session = self.call("auth/v1/token?grant_type=password", {
            "email": email, "password": password,
        })
        assert code == 200 and session["user"]["id"] == user_id, "fixture login rejected"
        self.users[name] = {"id": user_id, "email": email, "password": password,
                            "access_token": session["access_token"],
                            "refresh_token": session["refresh_token"]}

    def rpc(self, user, action, payload, error=None):
        code, result = self.call("rest/v1/rpc/grouply_mutate", {
            "action": action, "payload": payload,
        }, user=user)
        if error:
            assert code == 400 and result.get("message") == error, "unexpected mutation denial"
        else:
            assert code == 200, "mutation rejected"
            if action == "createTask":
                self.tasks.add(result["id"])
        return result

    def snapshot(self, user):
        code, result = self.call("rest/v1/rpc/grouply_snapshot", {}, user=user)
        assert code == 200 and result["currentUserID"] == self.users[user]["id"]
        return result

    def revision(self, user):
        code, rows = self.call("rest/v1/user_sync_state?select=user_id,revision", user=user, method="GET")
        assert code == 200 and len(rows) == 1 and rows[0]["user_id"] == self.users[user]["id"]
        return rows[0]["revision"]

    def moderate(self, action, payload):
        code, result = self.call("rest/v1/rpc/grouply_moderation", {
            "action": action, "payload": payload,
        }, admin=True)
        assert code == 200, "service moderation rejected"
        return result

    def complete_task(self, assignee, reviewer, task):
        self.rpc(assignee, "startTask", {"id": task, "expectedVersion": 1})
        self.rpc(assignee, "submitWork", {
            "taskID": task, "note": "Disposable local verification", "links": [], "expectedVersion": 2,
        })
        self.rpc(reviewer, "review", {
            "taskID": task, "approve": True, "feedback": "Verified", "expectedVersion": 3,
        })
        assert next(row for row in self.snapshot(reviewer)["tasks"] if row["id"] == task)["status"] == "done"

    def assert_deleted(self, user, group):
        account = self.users[user]
        code, _ = self.call("auth/v1/admin/users/" + account["id"], admin=True, method="GET")
        assert code == 404, "Auth identity survived deletion"
        code, body = self.call("rest/v1/rpc/grouply_snapshot", {}, user=user)
        assert code in (400, 401, 403) and (code != 400 or body.get("message") == "unauthorized")
        for table in ("profiles", "groups", "group_members", "chat_messages", "chat_reads", "user_blocks", "user_sync_state"):
            code, rows = self.call("rest/v1/" + table + "?select=*", user=user, method="GET")
            assert code in (401, 403) or (code == 200 and rows == []), "old JWT retained REST access"
        code, _ = self.call("rest/v1/rpc/grouply_mutate", {
            "action": "sendMessage", "payload": {"groupID": group, "clientID": str(uuid.uuid4()), "text": "Denied"},
        }, user=user)
        assert code in (400, 401, 403), "old JWT retained mutation access"
        for grant, payload in (
            ("refresh_token", {"refresh_token": account["refresh_token"]}),
            ("password", {"email": account["email"], "password": account["password"]}),
        ):
            code, _ = self.call("auth/v1/token?grant_type=" + grant, payload)
            assert code in (400, 401, 403), "deleted account authenticated"

    def run(self):
        for name in ("owner", "member", "outsider"):
            self.create_user(name)
        owner, member, outsider = (self.users[name]["id"] for name in ("owner", "member", "outsider"))
        group = self.rpc("owner", "createGroup", {"name": self.prefix})["id"]
        invite = self.rpc("owner", "generateInvite", {"groupID": group})["invite"]["code"]
        self.rpc("member", "joinGroup", {"code": invite})
        message = self.rpc("owner", "sendMessage", {
            "groupID": group, "clientID": str(uuid.uuid4()), "text": "Retained anonymous history",
        })["id"]
        moderated = self.rpc("owner", "sendMessage", {
            "groupID": group, "clientID": str(uuid.uuid4()), "text": "Disposable reported message",
        })["id"]

        self.stage = "report_privacy"
        self.rpc("outsider", "reportMessage", {"id": message, "reason": "Denied"}, "forbidden")
        code, rows = self.call("rest/v1/chat_messages?id=eq." + message, user="outsider", method="GET")
        assert code == 200 and rows == [], "nonmember read shared chat"
        for name in ("member", None):
            for action, payload in (("queue", {}), ("review", {"id": str(uuid.uuid4()), "decision": "removed", "note": "Denied"})):
                code, _ = self.call("rest/v1/rpc/grouply_moderation", {"action": action, "payload": payload}, user=name)
                assert code in (401, 403), "ordinary/anonymous moderation allowed"
        report = self.rpc("member", "reportMessage", {"id": message, "reason": "Local dismissal check"})["id"]
        duplicate = self.rpc("member", "reportMessage", {"id": message, "reason": "Duplicate"})["id"]
        assert report == duplicate, "duplicate report created"
        reports = [row for row in self.snapshot("member")["reports"] if row["id"] == report]
        assert len(reports) == 1 and reports[0]["status"] == "pending" and reports[0]["reviewedAt"] is None
        assert all(row["id"] != report for row in self.snapshot("owner")["reports"])
        assert self.snapshot("outsider")["reports"] == []
        for name in ("owner", "member", "outsider"):
            code, _ = self.call("rest/v1/content_reports?select=*", user=name, method="GET")
            assert code in (401, 403, 404), "private reports exposed via REST"
        self.rpc("member", "leaveGroup", {"id": group})
        assert any(row["id"] == report for row in self.snapshot("member")["reports"]), "own report lost after leaving"
        invite = self.rpc("owner", "generateInvite", {"groupID": group})["invite"]["code"]
        self.rpc("member", "joinGroup", {"code": invite})
        self.checks.append("report_dedup_nonmember_and_private_rls")

        self.stage = "moderation_lifecycle"
        queue = self.moderate("queue", {})
        assert isinstance(queue, list) and len(queue) <= 100
        assert all(row["status"] == "pending" for row in queue)
        assert [row["createdAt"] for row in queue] == sorted(row["createdAt"] for row in queue)
        assert any(row["id"] == report and row["status"] == "pending" for row in queue)
        decision = {"id": report, "decision": "dismissed", "note": "Disposable dismissal"}
        reviewed = self.moderate("review", decision)
        assert reviewed["id"] == report and reviewed["status"] == "dismissed" and reviewed["reviewedAt"]
        assert self.moderate("review", decision) == reviewed, "repeat moderation is not idempotent"
        code, conflict = self.call("rest/v1/rpc/grouply_moderation", {
            "action": "review", "payload": {"id": report, "decision": "removed", "note": "Conflict"},
        }, admin=True)
        assert code == 400 and conflict.get("message") == "already_reviewed"
        dismissed = next(row for row in self.snapshot("member")["reports"] if row["id"] == report)
        assert dismissed["status"] == "dismissed" and dismissed["reviewedAt"]
        assert next(row for row in self.snapshot("member")["messages"] if row["id"] == message)["text"] == "Retained anonymous history"
        removed_report = self.rpc("member", "reportMessage", {"id": moderated, "reason": "Local removal check"})["id"]
        before = {name: self.revision(name) for name in ("owner", "member")}
        self.moderate("review", {"id": removed_report, "decision": "removed", "note": "Disposable removal"})
        for name in before:
            assert self.revision(name) > before[name], "moderation did not invalidate member snapshot"
            assert next(row for row in self.snapshot(name)["messages"] if row["id"] == moderated)["text"] == "[Pesan dihapus moderator]"
        removed = next(row for row in self.snapshot("member")["reports"] if row["id"] == removed_report)
        assert removed["status"] == "removed" and removed["reviewedAt"]
        self.checks.append("service_only_moderation_lifecycle_redaction_revision")

        self.stage = "block_revision"
        before = self.revision("member")
        self.rpc("member", "blockUser", {"id": owner})
        assert self.revision("member") > before and owner in self.snapshot("member")["blockedUserIDs"]
        before = self.revision("member")
        self.rpc("member", "unblockUser", {"id": owner})
        assert self.revision("member") > before and owner not in self.snapshot("member")["blockedUserIDs"]
        self.rpc("member", "blockUser", {"id": owner})
        self.rpc("owner", "blockUser", {"id": member})
        self.rpc("owner", "markChatRead", {"groupID": group, "messageIDs": [message, moderated]})
        self.checks.append("block_unblock_own_revision")

        self.stage = "coordinator_and_completed_history"
        due = (datetime.now(timezone.utc) + timedelta(days=7)).isoformat()
        project = self.rpc("owner", "createProject", {"groupID": group, "title": "Completed history", "dueAt": due})["id"]
        task = self.rpc("owner", "createTask", {
            "projectID": project, "title": "Retained task", "assigneeID": owner, "reviewerID": member, "dueAt": due,
        })["id"]
        self.complete_task("owner", "member", task)
        reviewed_task = self.rpc("owner", "createTask", {
            "projectID": project, "title": "Retained review", "assigneeID": member, "reviewerID": owner, "dueAt": due,
        })["id"]
        self.complete_task("member", "owner", reviewed_task)
        self.rpc("owner", "deleteAccount", {}, "coordinator_transfer_required")
        assert self.snapshot("owner")["currentUserID"] == owner
        self.rpc("owner", "transferCoordinator", {"groupID": group, "to": member})
        assert self.rpc("owner", "deleteAccount", {}) == {"deleted": True}
        self.assert_deleted("owner", group)
        remaining = self.snapshot("member")
        assert owner not in [row["id"] for row in remaining["users"]]
        assert owner not in next(row for row in remaining["groups"] if row["id"] == group)["memberIDs"]
        assert owner not in remaining["blockedUserIDs"]
        retained = next(row for row in remaining["messages"] if row["id"] == message)
        assert retained["senderID"] == "" and retained["text"] == "Retained anonymous history"
        completed = next(row for row in remaining["tasks"] if row["id"] == task)
        assert completed["status"] == "done" and completed["assigneeID"] == ""
        assert completed["submissions"][0]["authorID"] == ""
        reviewed_task = next(row for row in remaining["tasks"] if row["id"] == reviewed_task)
        assert reviewed_task["reviewerID"] == "" and reviewed_task["submissions"][0]["reviewerID"] == ""
        leaked_sections = [key for key, value in remaining.items() if owner in json.dumps(value)]
        assert not leaked_sections, "deleted identity remains in snapshot sections: " + ", ".join(leaked_sections)
        self.checks.append("delete_identity_sessions_memberships_blocks_anonymous_history")

        self.stage = "archived_assignment_and_sole_coordinator"
        solo = self.rpc("outsider", "createGroup", {"name": self.prefix + "-solo"})["id"]
        solo_invite = self.rpc("outsider", "generateInvite", {"groupID": solo})["invite"]["code"]
        solo_message = self.rpc("outsider", "sendMessage", {"groupID": solo, "clientID": str(uuid.uuid4()), "text": "Orphan history"})["id"]
        invite = self.rpc("member", "generateInvite", {"groupID": group})["invite"]["code"]
        self.rpc("outsider", "joinGroup", {"code": invite})
        project = self.rpc("member", "createProject", {"groupID": group, "title": "Archived assignment", "dueAt": due})["id"]
        task = self.rpc("member", "createTask", {
            "projectID": project, "title": "Active blocker", "assigneeID": outsider, "reviewerID": member, "dueAt": due,
        })["id"]
        self.rpc("member", "archiveProject", {"id": project})
        self.rpc("outsider", "deleteAccount", {}, "active_assignment")
        assert self.snapshot("outsider")["currentUserID"] == outsider
        self.rpc("member", "transferCoordinator", {"groupID": group, "to": outsider})
        self.rpc("member", "deleteAccount", {}, "active_assignment")
        assert self.snapshot("member")["currentUserID"] == member
        self.rpc("outsider", "transferCoordinator", {"groupID": group, "to": member})
        self.rpc("member", "restoreProject", {"id": project})
        self.complete_task("outsider", "member", task)
        assert self.rpc("outsider", "deleteAccount", {}) == {"deleted": True}
        self.assert_deleted("outsider", group)
        code, _ = self.call("rest/v1/rpc/grouply_mutate", {"action": "joinGroup", "payload": {"code": solo_invite}}, user="member")
        assert code == 400, "orphan group invitation survived deletion"
        assert all(row["id"] != solo for row in self.snapshot("member")["groups"])
        assert solo_message not in [row["id"] for row in self.snapshot("member")["messages"]]
        self.checks.append("archived_assignment_blocks_sole_coordinator_orphan_invite_denied")

    def finish_cleanup_tasks(self):
        for name in self.users:
            if "access_token" not in self.users[name]:
                continue
            code, snapshot = self.call("rest/v1/rpc/grouply_snapshot", {}, user=name)
            if code != 200:
                continue
            for task in snapshot["tasks"]:
                if task["id"] not in self.tasks or task["status"] == "done":
                    continue
                project = next(row for row in snapshot["projects"] if row["id"] == task["projectID"])
                group = next(row for row in snapshot["groups"] if row["id"] == project["groupID"])
                coordinator = next(key for key, user in self.users.items() if user["id"] == group["coordinatorID"])
                assignee = next(key for key, user in self.users.items() if user["id"] == task["assigneeID"])
                reviewer = next(key for key, user in self.users.items() if user["id"] == task["reviewerID"])
                if project["status"] == "archived":
                    self.rpc(coordinator, "restoreProject", {"id": project["id"]})
                version = task["version"]
                if task["status"] == "todo":
                    self.rpc(assignee, "startTask", {"id": task["id"], "expectedVersion": version})
                    version += 1
                if task["status"] in ("todo", "in_progress", "needs_revision"):
                    self.rpc(assignee, "submitWork", {"taskID": task["id"], "note": "Fixture cleanup", "links": [], "expectedVersion": version})
                    version += 1
                self.rpc(reviewer, "review", {"taskID": task["id"], "approve": True, "feedback": "Fixture cleanup", "expectedVersion": version})
            self.tasks.difference_update(row["id"] for row in snapshot["tasks"])

    def cleanup(self):
        failures = 0
        if self.tasks:
            try:
                self.finish_cleanup_tasks()
            except Exception:
                failures += 1
        for user_id, email in self.created.items():
            try:
                assert str(uuid.UUID(user_id)) == user_id
                assert email.startswith(self.prefix + "-") and email.endswith("@grouply.local")
                path = "auth/v1/admin/users/" + user_id
                code, user = self.call(path, admin=True, method="GET")
                if code == 404:
                    continue
                assert code == 200 and user["id"] == user_id and user["email"] == email
                name = next(key for key, account in self.users.items() if account["id"] == user_id and account["email"] == email)
                account = self.users[name]
                if "access_token" not in account:
                    code, session = self.call("auth/v1/token?grant_type=password", {
                        "email": email, "password": account["password"],
                    })
                    assert code == 200 and session["user"]["id"] == user_id
                    account["access_token"] = session["access_token"]
                code, profiles = self.call("rest/v1/profiles?select=id&id=eq." + user_id, user=name, method="GET")
                assert code == 200, "cannot establish fixture profile state"
                if profiles == []:
                    code, _ = self.call(path, admin=True, method="DELETE")
                    assert code in (200, 204, 404)
                else:
                    assert profiles == [{"id": user_id}], "unexpected fixture profile"
                    snapshot = self.snapshot(name)
                    for group in snapshot["groups"]:
                        if group["coordinatorID"] != user_id:
                            continue
                        assert set(group["memberIDs"]) <= self.created.keys(), "foreign group member prevents cleanup"
                        successors = [member for member in group["memberIDs"] if member != user_id]
                        if successors:
                            self.rpc(name, "transferCoordinator", {"groupID": group["id"], "to": successors[0]})
                    assert self.rpc(name, "deleteAccount", {}) == {"deleted": True}
                code, _ = self.call(path, admin=True, method="GET")
                assert code == 404, "fixture identity survived cleanup"
            except Exception:
                failures += 1
        return failures


def self_check():
    from unittest.mock import patch

    for url in ("https://localhost:55321", "http://localhost:54321", "http://example.org:55321",
                "http://localhost:55321/private", "http://secret@localhost:55321"):
        try:
            require_local(url)
        except AssertionError:
            pass
        else:
            raise AssertionError("nonlocal target accepted")
    verification = Verification({"API_URL": "http://127.0.0.1:55321", "ANON_KEY": "offline", "SERVICE_ROLE_KEY": "offline"})
    user_id = str(uuid.uuid4())
    email = verification.prefix + "-owned@grouply.local"
    verification.created[user_id] = email
    verification.users["owned"] = {"id": user_id, "email": email, "access_token": "offline"}
    identity = {"id": user_id, "email": email}
    with patch.object(verification, "call", side_effect=[(200, identity), (200, []), (204, None), (404, {})]) as mocked:
        assert verification.cleanup() == 0
        assert mocked.call_args_list[2].kwargs["method"] == "DELETE"
    successor = str(uuid.uuid4())
    verification.created[successor] = verification.prefix + "-successor@grouply.local"
    fixture_snapshot = {"currentUserID": user_id, "groups": [
        {"id": "group", "coordinatorID": user_id, "memberIDs": [user_id, successor]},
    ]}
    with patch.object(verification, "call", side_effect=[
        (200, identity), (200, [{"id": user_id}]), (200, fixture_snapshot),
        (200, {}), (200, {"deleted": True}), (404, {}), (404, {}),
    ]) as mocked:
        assert verification.cleanup() == 0
        mutations = [entry.args[1]["action"] for entry in mocked.call_args_list if len(entry.args) > 1 and "action" in entry.args[1]]
        assert mutations == ["transferCoordinator", "deleteAccount"]
        assert all(entry.kwargs.get("method") != "DELETE" for entry in mocked.call_args_list)
    del verification.created[successor]
    with patch.object(verification, "call", side_effect=[
        (200, identity), (200, [{"id": user_id}]),
        (200, {"currentUserID": user_id, "groups": []}), (400, {"message": "active_assignment"}),
    ]) as mocked:
        assert verification.cleanup() == 1
        assert all(entry.kwargs.get("method") != "DELETE" for entry in mocked.call_args_list)
    with patch.object(verification, "call", side_effect=[(200, identity), (403, {})]) as mocked:
        assert verification.cleanup() == 1
        assert all(entry.kwargs.get("method") != "DELETE" for entry in mocked.call_args_list)
    with patch.object(verification, "call", side_effect=[
        (200, identity), (200, [{"id": user_id}]),
        (200, {"currentUserID": user_id, "groups": [
            {"id": "group", "coordinatorID": user_id, "memberIDs": [user_id, str(uuid.uuid4())]},
        ]}),
    ]) as mocked:
        assert verification.cleanup() == 1 and mocked.call_count == 3
    with patch.object(verification, "call", return_value=(200, {"id": user_id, "email": "alex@grouply.local"})) as mocked:
        assert verification.cleanup() == 1 and mocked.call_count == 1
    with patch.object(verification, "call", side_effect=OSError("suppressed")):
        assert verification.cleanup() == 1
    failed_login = Verification({"API_URL": "http://localhost:55321", "ANON_KEY": "offline", "SERVICE_ROLE_KEY": "offline"})
    with patch.object(failed_login, "call", side_effect=[
        (201, {"id": user_id, "email": failed_login.prefix + "-owned@grouply.local"}), (400, {}),
    ]):
        try:
            failed_login.create_user("owned")
        except AssertionError:
            pass
        else:
            raise AssertionError("failed login accepted")
        assert user_id in failed_login.created, "failed-login identity lost before cleanup"
    recovered_email = failed_login.users["owned"]["email"]
    with patch.object(failed_login, "call", side_effect=[
        (200, {"id": user_id, "email": recovered_email}),
        (200, {"user": {"id": user_id}, "access_token": "offline"}),
        (200, [{"id": user_id}]), (200, {"currentUserID": user_id, "groups": []}),
        (200, {"deleted": True}), (404, {}),
    ]) as mocked:
        assert failed_login.cleanup() == 0
        assert all(entry.kwargs.get("method") != "DELETE" for entry in mocked.call_args_list)
    verification.users = {"assignee": {"id": "assignee", "access_token": "offline"},
                          "reviewer": {"id": "reviewer", "access_token": "offline"}}
    verification.tasks = {"task"}
    snapshot = {"tasks": [{"id": "task", "status": "todo", "version": 1,
                            "projectID": "project", "assigneeID": "assignee", "reviewerID": "reviewer"}],
                "projects": [{"id": "project", "groupID": "group", "status": "archived"}],
                "groups": [{"id": "group", "coordinatorID": "reviewer"}]}
    with patch.object(verification, "call", return_value=(200, snapshot)), patch.object(verification, "rpc") as mocked:
        verification.finish_cleanup_tasks()
        assert [entry.args[1] for entry in mocked.call_args_list] == ["restoreProject", "startTask", "submitWork", "review"]
        assert mocked.call_args.args[2]["expectedVersion"] == 3
        assert not verification.tasks
    print(json.dumps({"result": "PASS", "mode": "offline_self_check", "checks": ["local_guard", "unprofiled_admin_cleanup", "profiled_rpc_cleanup_and_transfer", "no_admin_fallback_after_rpc_or_profile_failure", "foreign_identity_and_group_member_refused", "cleanup_failure_counted", "failed_login_recovered_for_cleanup", "active_fixture_cleanup"]}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--run", action="store_true", help="Run only after migration readiness is confirmed")
    mode.add_argument("--self-check", action="store_true", help="Offline checks; no backend requests")
    args = parser.parse_args()
    if not __debug__:
        parser.error("Assertions are required; do not use python -O")
    if args.self_check:
        self_check()
        return 0
    verification = None
    summary = {"result": "FAIL", "mode": "live_local", "checks": [], "stage": "local_status",
               "limits": ["HTTP only; no device/WebSocket or Apple revocation proof", "Retained orphan history is not purged; parent SQL proves retention", "No direct private-schema inspection", "Sole coordinator active assignment is in another joined group", "Queue assertion requires fewer than 100 older pending reports"]}
    try:
        verification = Verification(local_status())
        verification.run()
        summary["result"] = "PASS"
    except (Exception, KeyboardInterrupt) as error:
        summary["error_type"] = type(error).__name__
        if isinstance(error, AssertionError):
            summary["assertion"] = str(error)
        summary["failure_frames"] = [{"function": frame.name, "line": frame.lineno}
                                     for frame in traceback.extract_tb(error.__traceback__)
                                     if frame.filename.endswith("/milestone_e_local.py")]
    finally:
        if verification:
            summary["checks"] = verification.checks
            summary["stage"] = verification.stage
            summary["cleanup_failures"] = verification.cleanup()
            if summary["cleanup_failures"]:
                summary["result"] = "FAIL"
        output = ROOT / "artifacts/milestone-e-local.json"
        try:
            output.parent.mkdir(exist_ok=True)
            output.write_text(json.dumps(summary, indent=2) + "\n")
        except OSError:
            summary["result"] = "FAIL"
            summary["artifact_write_failed"] = True
        print(json.dumps(summary, sort_keys=True))
    return 0 if summary["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
