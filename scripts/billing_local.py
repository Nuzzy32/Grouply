#!/usr/bin/env python3
"""Service-role Organization Plan billing for Grouply localhost only; never prints credentials."""
import argparse
from datetime import date
import json
import sys
import uuid

from backend_local import local_status, request
from moderation_local import Session, blocked, login, sql

# Each lock-test session wraps mutations so a server error comes back as text instead of
# aborting the transaction (psql would otherwise never print the turn marker).
TRY = ("CREATE FUNCTION pg_temp.try(action text, payload jsonb) RETURNS text LANGUAGE plpgsql AS $f$ "
       "BEGIN RETURN public.grouply_mutate(action,payload)::text; "
       "EXCEPTION WHEN OTHERS THEN RETURN 'error:'||sqlerrm; END $f$;")


def attempt(action, payload):
    return "SELECT pg_temp.try('" + action + "','" + json.dumps(payload) + "'::jsonb);"


def call(actor, request):
    # A None actor is the operator: the request is a moderation payload for grouply_moderation.
    if actor is None:
        return ("SET LOCAL ROLE service_role; SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',true); "
                "SELECT public.grouply_moderation('review','" + json.dumps(request) + "'::jsonb);")
    return login(actor) + attempt(*request)


def check_locks():
    run = uuid.uuid4().hex[:8]
    k, c1, c2, x, y, m, d, z, w, fk, fc, fr, fd, fb, fl, fq, ft, fu, fp = users = [str(uuid.uuid4()) for _ in range(19)]
    org_a, org_b, org_c, org_e, org_f = orgs = [str(uuid.uuid4()) for _ in range(5)]
    a1, a2, b1, b2, cg, e1, e2, f1 = groups = [str(uuid.uuid4()) for _ in range(8)]
    ap1, ap2, ap3, proj, notice, rep_a, rep_b, proj2, batch = [str(uuid.uuid4()) for _ in range(9)]
    listed = lambda ids: ",".join("'" + i + "'" for i in ids)
    setup = f"""
      BEGIN;
      INSERT INTO auth.users(id,raw_user_meta_data) SELECT id::uuid,'{{"name":"Billing lock fixture"}}' FROM unnest(ARRAY[{listed(users)}]) id;
      INSERT INTO public.organizations(id,name,seat_limit,plan_expires_at) VALUES
        ('{org_a}','Lock A',4,now()+interval '1 day'),('{org_b}','Lock B',0,NULL),('{org_c}','Lock C',0,NULL),('{org_e}','Lock E',0,NULL),
        ('{org_f}','Lock F',50,now()+interval '1 day');
      INSERT INTO public.groups(id,name,coordinator_id,organization_id) VALUES
        ('{a1}','A1','{c1}','{org_a}'),('{a2}','A2','{c2}','{org_a}'),('{b1}','B1','{c1}','{org_b}'),('{b2}','B2','{c2}','{org_b}'),
        ('{cg}','C1','{k}','{org_c}'),('{e1}','E1','{k}','{org_e}'),('{e2}','E2','{c1}','{org_e}'),('{f1}','F1','{fc}','{org_f}');
      INSERT INTO public.group_members VALUES
        ('{a1}','{c1}'),('{a1}','{k}'),('{a2}','{c2}'),('{b1}','{c1}'),('{b1}','{k}'),('{b2}','{c2}'),('{b2}','{k}'),
        ('{cg}','{k}'),('{cg}','{m}'),('{e1}','{k}'),('{e1}','{d}'),('{e1}','{z}'),('{e2}','{c1}'),('{e2}','{d}'),('{e2}','{w}'),
        ('{f1}','{fk}'),('{f1}','{fc}'),('{f1}','{fr}'),('{f1}','{fd}'),('{f1}','{fb}'),('{f1}','{fl}'),('{f1}','{fq}'),('{f1}','{ft}'),('{f1}','{fu}'),('{f1}','{fp}');
      INSERT INTO public.organization_roles SELECT id::uuid,'{k}','ketua' FROM unnest(ARRAY[{listed(orgs[:4])}]) id;
      INSERT INTO public.organization_roles VALUES ('{org_f}','{fk}','ketua'),('{org_f}','{fb}','bph');
      INSERT INTO public.projects(id,group_id,title,due_at,lead_id) VALUES ('{proj}','{f1}','Sie lock',now()+interval '30 days','{fl}'),
        ('{proj2}','{f1}','Sie batch',now()+interval '30 days','{fp}');
      INSERT INTO public.approvals(id,organization_id,group_id,requester_id,title,note) VALUES
        ('{ap1}','{org_f}','{f1}','{fr}','Lock 1','x'),('{ap2}','{org_f}','{f1}','{fd}','Lock 2','x'),('{ap3}','{org_f}','{f1}','{fq}','Lock 3','x');
      INSERT INTO public.approval_steps(approval_id,position,approver_id) VALUES ('{ap1}',1,'{fk}'),('{ap2}',1,'{fk}'),('{ap3}',1,'{fb}');
      INSERT INTO public.announcements(id,organization_id,group_id,author_id,title,body) VALUES ('{notice}','{org_f}','{f1}','{fc}','Lock','Isi');
      INSERT INTO private.content_reports(id,reporter_id,reason,target_kind,target_id,excerpt) VALUES
        ('{rep_a}','{ft}','Lock A','announcement','{notice}','Lock'),('{rep_b}','{fu}','Lock B','announcement','{notice}','Lock');
      INSERT INTO private.invitations(group_id,token_hash,max_uses) VALUES
        ('{a1}',extensions.digest('lock-{run}-a1','sha256'),5),('{a2}',extensions.digest('lock-{run}-a2','sha256'),5);
      COMMIT;
    """
    cleanup = f"""
      BEGIN;
      DELETE FROM public.organization_roles WHERE organization_id IN ({listed(orgs)});
      DELETE FROM public.chat_messages WHERE group_id IN ({listed(groups)});
      DELETE FROM public.activity_events WHERE group_id IN ({listed(groups)});
      DELETE FROM public.approvals WHERE organization_id IN ({listed(orgs)});
      DELETE FROM private.content_reports WHERE id IN ('{rep_a}','{rep_b}');
      DELETE FROM public.announcements WHERE organization_id IN ({listed(orgs)});
      DELETE FROM public.tasks WHERE project_id IN (SELECT id FROM public.projects WHERE group_id IN ({listed(groups)}));
      DELETE FROM public.projects WHERE group_id IN ({listed(groups)});
      DELETE FROM private.invitations WHERE group_id IN ({listed(groups)});
      DELETE FROM public.group_members WHERE group_id IN ({listed(groups)});
      DELETE FROM public.groups WHERE id IN ({listed(groups)});
      DELETE FROM public.organizations WHERE id IN ({listed(orgs)});
      DELETE FROM public.profiles WHERE id IN ({listed(users)});
      DELETE FROM auth.users WHERE id IN ({listed(users)});
      COMMIT;
    """
    scenarios = [
        # (label, holder, holder call, holder expects, waiter, waiter call, release, waiter expects, invariant SQL)
        ("concurrent joins for the last seat", x, ("joinGroup", {"code": f"lock-{run}-a1"}), '"id"',
         y, ("joinGroup", {"code": f"lock-{run}-a2"}), "COMMIT;", "error:org_full",
         f"SELECT count(DISTINCT m.user_id)=4 FROM public.group_members m JOIN public.groups g ON g.id=m.group_id WHERE g.organization_id='{org_a}';"),
        ("two coordinators remove the ketua from both divisions", c1, ("removeMember", {"groupID": b1, "userID": k}), "{}",
         c2, ("removeMember", {"groupID": b2, "userID": k}), "COMMIT;", "error:ketua_transfer_required",
         f"SELECT EXISTS(SELECT 1 FROM public.group_members WHERE group_id='{b2}' AND user_id='{k}') "
         f"AND EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id='{org_b}' AND user_id='{k}' AND role='ketua');"),
        ("setOrgRole while the target leaves their last division", m, ("leaveGroup", {"id": cg}), "{}",
         k, ("setOrgRole", {"organizationID": org_c, "userID": m, "role": "bph"}), "COMMIT;", "error:invalid_input",
         f"SELECT NOT EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id='{org_c}' AND user_id='{m}');"),
        ("removeMember then deleteAccount in the same organization", k, ("removeMember", {"groupID": e1, "userID": z}), "{}",
         d, ("deleteAccount", {}), "COMMIT;", '"deleted": true', None),
        ("setOrgRole then deleteAccount in the same organization", k, ("setOrgRole", {"organizationID": org_e, "userID": w, "role": "bph"}), "{}",
         d, ("deleteAccount", {}), "COMMIT;", '"deleted": true', None),
        ("deleteAccount then setOrgRole in the same organization", d, ("deleteAccount", {}), '"deleted": true',
         k, ("setOrgRole", {"organizationID": org_e, "userID": w, "role": "pembina"}), "ROLLBACK;", "{}", None),
        # Tahap 2: approvals and project leads.
        ("coordinator removes the requester while an approver decides", fc, ("removeMember", {"groupID": f1, "userID": fr}), "{}",
         fk, ("decideApproval", {"id": ap1, "approve": True}), "COMMIT;", "error:approval_closed",
         f"SELECT status='lapsed' FROM public.approvals WHERE id='{ap1}';"),
        ("requester deletes the account while an approver decides", fd, ("deleteAccount", {}), '"deleted": true',
         fk, ("decideApproval", {"id": ap2, "approve": True}), "COMMIT;", "error:approval_closed",
         f"SELECT status='lapsed' AND requester_id IS NULL FROM public.approvals WHERE id='{ap2}';"),
        ("ketua revokes an approver's role while they decide", fk, ("setOrgRole", {"organizationID": org_f, "userID": fb, "role": None}), "{}",
         fb, ("decideApproval", {"id": ap3, "approve": True}), "COMMIT;", "error:forbidden",
         f"SELECT a.status='pending' AND s.decision IS NULL FROM public.approvals a JOIN public.approval_steps s ON s.approval_id=a.id WHERE a.id='{ap3}';"),
        ("project lead creates a task while being removed", fc, ("removeMember", {"groupID": f1, "userID": fl}), "{}",
         fl, ("createTask", {"projectID": proj, "title": "Telat", "assigneeID": fq, "reviewerID": fc, "dueAt": "2030-01-01T00:00:00Z"}),
         "COMMIT;", "error:forbidden",
         f"SELECT NOT EXISTS(SELECT 1 FROM public.tasks WHERE project_id='{proj}') AND (SELECT lead_id IS NULL FROM public.projects WHERE id='{proj}');"),
        ("project lead publishes a task batch while being removed", fc, ("removeMember", {"groupID": f1, "userID": fp}), "{}",
         fp, ("publishTaskBatch", {"projectID": proj2, "requestID": batch, "tasks": [
             {"title": "Telat", "description": "", "assigneeID": fq, "reviewerID": fc, "dueAt": "2030-01-01T00:00:00Z"}]}),
         "COMMIT;", "error:forbidden",
         f"SELECT NOT EXISTS(SELECT 1 FROM public.tasks WHERE project_id='{proj2}') "
         f"AND NOT EXISTS(SELECT 1 FROM private.task_batch_receipts WHERE project_id='{proj2}');"),
        # Reports on organization content: operator review vs reporter account deletion, both orders.
        ("operator removes reported content while the reporter deletes the account", None,
         {"id": rep_a, "decision": "removed", "note": "Lock regression"}, '"status": "removed"',
         ft, ("deleteAccount", {}), "COMMIT;", '"deleted": true',
         f"SELECT (SELECT status='removed' FROM private.content_reports WHERE id='{rep_a}') "
         f"AND (SELECT title='[Dihapus moderator]' FROM public.announcements WHERE id='{notice}');"),
        ("reporter deletes the account while the operator reviews", fu, ("deleteAccount", {}), '"deleted": true',
         None, {"id": rep_b, "decision": "dismissed", "note": "Lock regression"}, "COMMIT;", '"status": "dismissed"',
         f"SELECT status='pending' AND reporter_id IS NULL AND reason='[Pelapor terhapus]' FROM private.content_reports WHERE id='{rep_b}';"),
    ]
    sql(setup)
    failures = []
    try:
        for label, holder, holder_call, holder_expect, waiter, waiter_call, release, waiter_expect, invariant in scenarios:
            first = second = None
            try:
                first, second = Session(), Session()
                for session in (first, second):
                    session.run(TRY)
                held = first.run(call(holder, holder_call))
                assert any(holder_expect in line for line in held), "holder got " + " ".join(held)
                waiting = second.send(call(waiter, waiter_call))
                blocked(second, first)
                first.run(release)
                got = second.receive(waiting)
                assert not any("deadlock" in line for line in got), "deadlock: " + " ".join(got)
                assert any(waiter_expect in line for line in got), "waiter got " + " ".join(got)
                second.run("ROLLBACK;")
                if invariant:
                    assert sql(invariant) == "t", "invariant broken after commit"
                print("PASS: " + label)
            except (RuntimeError, AssertionError) as error:
                failures.append(label)
                print("FAIL: " + label + ": " + str(error), file=sys.stderr)
            finally:
                for session in (first, second):
                    if session is not None:
                        session.close()
    finally:
        sql(cleanup)
        assert sql(f"SELECT count(*) FROM auth.users WHERE id IN ({listed(users)});") == "0", "Disposable lock fixtures were not cleaned"
    if failures:
        raise RuntimeError("Organization lock regressions failed: " + ", ".join(failures))
    print(f"PASS: all {len(scenarios)} organization two-session checks; disposable fixtures removed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="List organizations with seats and plan expiry")
    activate = commands.add_parser("activate", help="Activate or extend a plan")
    activate.add_argument("id", type=uuid.UUID)
    activate.add_argument("--seats", type=int, required=True, help="Seat limit, 1-500 unique people")
    activate.add_argument("--until", type=date.fromisoformat, required=True, help="Last day of the plan, YYYY-MM-DD")
    deactivate = commands.add_parser("deactivate", help="End a plan now; data stays, free limits apply")
    deactivate.add_argument("id", type=uuid.UUID)
    commands.add_parser("check-locks", help="Exercise organization lock races with disposable local fixtures")
    args = parser.parse_args()
    if args.command == "activate" and not 1 <= args.seats <= 500:
        parser.error("Seat limit must be 1-500.")
    status = local_status()
    if args.command == "check-locks":
        check_locks()
        return
    action, payload = {"list": ("list", {})}.get(args.command, (None, None))
    if args.command == "activate":
        # End of the chosen day in WIB, the users' time zone.
        action, payload = "activatePlan", {"organizationID": str(args.id), "seatLimit": args.seats,
                                           "expiresAt": args.until.isoformat() + "T23:59:59+07:00"}
    elif args.command == "deactivate":
        action, payload = "deactivatePlan", {"organizationID": str(args.id)}
    key = status["SERVICE_ROLE_KEY"]
    code, result = request(status["API_URL"], key, "rest/v1/rpc/grouply_billing",
                           {"action": action, "payload": payload}, key)
    if code != 200:
        raise RuntimeError("Local billing rejected (HTTP " + str(code) + "). No credentials printed.")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, ValueError, OSError):
        print("Billing failed. Check Grouply local status and organization ID; credentials are not logged.", file=sys.stderr)
        sys.exit(1)
