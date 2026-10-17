-- psql -v ON_ERROR_STOP=1; disposable fixtures and every mutation roll back.
BEGIN;
CREATE FUNCTION pg_temp.check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',label; END IF; RAISE NOTICE 'PASS: %',label; END;
$$;
CREATE FUNCTION pg_temp.denied(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE statement;
  RAISE EXCEPTION 'unexpected success';
EXCEPTION WHEN OTHERS THEN
  IF sqlerrm NOT LIKE '%'||expected||'%' THEN RAISE EXCEPTION 'Expected %, got %',expected,sqlerrm; END IF;
  RAISE NOTICE 'PASS: rejected with %',expected;
END;
$$;
CREATE FUNCTION pg_temp.actor(actor text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','user_metadata',jsonb_build_object('role','service_role'))::text,true);
END;
$$;

INSERT INTO auth.users(id,raw_user_meta_data) VALUES
 ('e0000000-0000-0000-0000-000000000001','{"name":"Deletion fixture"}'),
 ('e0000000-0000-0000-0000-000000000002','{"name":"Coordinator fixture"}'),
 ('e0000000-0000-0000-0000-000000000003','{"name":"Outsider fixture"}');
INSERT INTO public.groups(id,name,coordinator_id) VALUES
 ('e1000000-0000-0000-0000-000000000001','Shared fixture','e0000000-0000-0000-0000-000000000002'),
 ('e1000000-0000-0000-0000-000000000002','Sole fixture','e0000000-0000-0000-0000-000000000001');
INSERT INTO public.group_members VALUES
 ('e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001'),
 ('e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002'),
 ('e1000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000001');
INSERT INTO private.invitations(group_id,token_hash) VALUES('e1000000-0000-0000-0000-000000000002',extensions.digest('milestone-e-fixture','sha256'));
INSERT INTO public.projects(id,group_id,title,due_at,archived_at) VALUES
 ('e3000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','Shared work',now()+interval '1 day',now());
INSERT INTO public.tasks(id,project_id,title,assignee_id,reviewer_id,due_at,status) VALUES
 ('e4000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','Shared task','e0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002',now()+interval '1 day','todo');
INSERT INTO public.submissions(id,task_id,revision,author_id,note) VALUES
 ('e5000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'e0000000-0000-0000-0000-000000000001','Shared submission');
INSERT INTO public.reviews(submission_id,reviewer_id,decision,feedback) VALUES
 ('e5000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002','approved','Shared feedback');
INSERT INTO public.tasks(id,project_id,title,assignee_id,reviewer_id,due_at,status) VALUES
 ('e4000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000001','Reviewed history','e0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000001',now()+interval '1 day','done');
INSERT INTO public.submissions(id,task_id,revision,author_id,note) VALUES
 ('e5000000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000002',1,'e0000000-0000-0000-0000-000000000002','Other member work');
INSERT INTO public.reviews(submission_id,reviewer_id,decision,feedback) VALUES
 ('e5000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000001','approved','Retained review');
INSERT INTO public.chat_messages(id,group_id,sender_id,content) VALUES
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002','Reported message'),
 ('e2000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','Shared history');
INSERT INTO public.chat_messages(group_id,sender_id,content)
 SELECT 'e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002','Rate fixture '||series FROM generate_series(1,6) series;
INSERT INTO public.chat_reads VALUES('e0000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001');
INSERT INTO public.activity_events(group_id,actor_id,action,target_id) VALUES
 ('e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','fixture','e0000000-0000-0000-0000-000000000001');
INSERT INTO auth.sessions(id,user_id) VALUES('e6000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001');
INSERT INTO auth.refresh_tokens(user_id,token,session_id) VALUES
 ('e0000000-0000-0000-0000-000000000001','milestone-e-disposable-token','e6000000-0000-0000-0000-000000000001'),
 ('e0000000-0000-0000-0000-000000000001','milestone-e-legacy-token',NULL);

SET LOCAL ROLE authenticated;
SELECT pg_temp.actor('e0000000-0000-0000-0000-000000000003');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('reportMessage','{"id":"e2000000-0000-0000-0000-000000000001","reason":"Not my group"}')$q$,'forbidden');
SELECT pg_temp.denied($q$SELECT public.grouply_moderation('queue','{}')$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.mutate_workflow('deleteAccount','{}')$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT * FROM private.content_reports$q$,'permission denied');
SELECT pg_temp.actor('e0000000-0000-0000-0000-000000000002');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('deleteAccount','{}')$q$,'coordinator_transfer_required');
SELECT pg_temp.actor('e0000000-0000-0000-0000-000000000001');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('reportMessage','{"id":"e2000000-0000-0000-0000-000000000002","reason":"Own message"}')$q$,'forbidden');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('deleteAccount','{}')$q$,'active_assignment');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('deleteAccount','{"id":"e0000000-0000-0000-0000-000000000002"}')$q$,'invalid_input');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('deleteAccount','[]')$q$,'invalid_input');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('reportMessage','{"id":"bad","reason":"Reason"}')$q$,'invalid_input');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('reportMessage','{"id":"e2000000-0000-0000-0000-000000000001","reason":{}}')$q$,'invalid_input');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('reportMessage','{"id":"e2000000-0000-0000-0000-000000000001","reason":"  "}')$q$,'invalid_input');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('reportMessage',jsonb_build_object('id','e2000000-0000-0000-0000-000000000001','reason',repeat('x',1001)))$q$,'invalid_input');
SELECT revision AS report_revision FROM public.user_sync_state WHERE user_id=auth.uid() \gset
SELECT public.grouply_mutate('reportMessage','{"id":"e2000000-0000-0000-0000-000000000001","reason":"Review this"}')->>'id' AS report_id \gset
SELECT pg_temp.check((SELECT revision>:report_revision FROM public.user_sync_state WHERE user_id=auth.uid()),'report creation invalidates own sessions');
SELECT pg_temp.check(public.grouply_mutate('reportMessage','{"id":"e2000000-0000-0000-0000-000000000001","reason":"Duplicate"}')->>'id'=:'report_id','report deduplicates retries');
SELECT public.grouply_mutate('reportMessage',jsonb_build_object('id',id,'reason','Rate test')) FROM public.chat_messages WHERE content LIKE 'Rate fixture%' ORDER BY id LIMIT 4;
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('reportMessage',jsonb_build_object('id',id,'reason','Limited')) FROM public.chat_messages WHERE content LIKE 'Rate fixture%' AND id::text NOT IN (SELECT jsonb_array_elements(public.grouply_snapshot()->'reports')->>'messageID') LIMIT 1$q$,'rate_limited');
SELECT revision AS block_revision FROM public.user_sync_state WHERE user_id=auth.uid() \gset
SELECT public.grouply_mutate('blockUser','{"id":"e0000000-0000-0000-0000-000000000002"}');
SELECT pg_temp.check((SELECT revision>:block_revision FROM public.user_sync_state WHERE user_id=auth.uid()),'block invalidates own other sessions');
SELECT revision AS unblock_revision FROM public.user_sync_state WHERE user_id=auth.uid() \gset
SELECT public.grouply_mutate('unblockUser','{"id":"e0000000-0000-0000-0000-000000000002"}');
SELECT pg_temp.check((SELECT revision>:unblock_revision FROM public.user_sync_state WHERE user_id=auth.uid()),'unblock invalidates own other sessions');

RESET ROLE;
SELECT pg_temp.check(EXISTS(SELECT 1 FROM auth.users WHERE id='e0000000-0000-0000-0000-000000000001')
 AND EXISTS(SELECT 1 FROM public.group_members WHERE group_id='e1000000-0000-0000-0000-000000000001' AND user_id='e0000000-0000-0000-0000-000000000001'),'failed deletion leaves account and membership unchanged');
UPDATE public.tasks SET assignee_id='e0000000-0000-0000-0000-000000000002',reviewer_id='e0000000-0000-0000-0000-000000000001' WHERE id='e4000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('deleteAccount','{}')$q$,'active_assignment');
RESET ROLE;
UPDATE public.tasks SET status='done' WHERE id='e4000000-0000-0000-0000-000000000001';
UPDATE public.tasks SET assignee_id='e0000000-0000-0000-0000-000000000001',reviewer_id='e0000000-0000-0000-0000-000000000002' WHERE id='e4000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor('e0000000-0000-0000-0000-000000000001');
SELECT public.grouply_mutate('leaveGroup','{"id":"e1000000-0000-0000-0000-000000000001"}');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'reports') report WHERE report->>'id'=:'report_id'),'own report remains after leaving group');
SELECT pg_temp.check(jsonb_array_length(public.grouply_snapshot()->'messages')=0,'former member sees no shared content');
SELECT revision AS reporter_revision FROM public.user_sync_state WHERE user_id=auth.uid() \gset
SELECT report->>'id' AS dismiss_id FROM jsonb_array_elements(public.grouply_snapshot()->'reports') report WHERE report->>'id'<>:'report_id' LIMIT 1 \gset

RESET ROLE;
SELECT revision AS member_revision FROM public.user_sync_state WHERE user_id='e0000000-0000-0000-0000-000000000002' \gset
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_moderation('queue','{}')) report WHERE report->>'id'=:'report_id'),'service moderator queue exposes pending report');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('deleteAccount','{}')$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT public.grouply_moderation('review','{"id":"bad","decision":"removed","note":"Test"}')$q$,'invalid_input');
SELECT pg_temp.denied($q$SELECT public.grouply_moderation('review','{"id":"e2000000-0000-0000-0000-000000000001","decision":"bogus","note":"Test"}')$q$,'invalid_input');
SELECT pg_temp.denied($q$SELECT public.grouply_moderation('review','{"id":"e2000000-0000-0000-0000-000000000001","decision":"removed","note":null}')$q$,'invalid_input');
SELECT pg_temp.check(public.grouply_moderation('review',jsonb_build_object('id',:'report_id','decision','removed','note','Local resolution'))->>'status'='removed','service moderator resolves report');
SELECT pg_temp.check(public.grouply_moderation('review',jsonb_build_object('id',:'dismiss_id','decision','dismissed','note','No action needed'))->>'status'='dismissed','service moderator dismisses without deleting message');
SELECT pg_temp.check(public.grouply_moderation('review',jsonb_build_object('id',:'report_id','decision','removed','note','Local resolution'))->>'status'='removed','moderation review retry idempotent');
SELECT pg_temp.denied(format('SELECT public.grouply_moderation(''review'',%L)',jsonb_build_object('id',:'report_id','decision','dismissed','note','Changed')),'already_reviewed');
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor('e0000000-0000-0000-0000-000000000001');
SELECT pg_temp.check((SELECT revision>:reporter_revision FROM public.user_sync_state WHERE user_id=auth.uid()),'moderation notifies former-member reporter');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'reports') report WHERE report->>'id'=:'report_id' AND report->>'status'='removed' AND report->>'reviewedAt' IS NOT NULL),'reporter receives resolution metadata only');
SELECT public.grouply_mutate('deleteAccount','{}');
SELECT pg_temp.denied($q$SELECT public.grouply_snapshot()$q$,'unauthorized');
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('createGroup','{"name":"Stale JWT"}')$q$,'unauthorized');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM public.profiles),'deleted JWT cannot read even own profile');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM public.groups) AND NOT EXISTS(SELECT 1 FROM public.tasks) AND NOT EXISTS(SELECT 1 FROM public.chat_messages),'deleted JWT has no RLS shared access');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM public.user_blocks) AND NOT EXISTS(SELECT 1 FROM public.user_sync_state) AND NOT EXISTS(SELECT 1 FROM public.chat_reads),'deleted JWT has no own personal rows');
SELECT pg_temp.actor('e0000000-0000-0000-0000-000000000002');
SELECT pg_temp.check((SELECT revision>:member_revision FROM public.user_sync_state WHERE user_id=auth.uid()),'moderation and deletion invalidate remaining member');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'messages') message WHERE message->>'id'='e2000000-0000-0000-0000-000000000002' AND message->>'senderID'='' AND message->>'text'='Shared history'),'remaining member retains anonymized chat');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'tasks') task WHERE task->>'assigneeID'='' AND task->'submissions'->0->>'authorID'=''),'snapshot IDs remain nonoptional empty strings');
SELECT pg_temp.check((SELECT content='[Pesan dihapus moderator]' FROM public.chat_messages WHERE id='e2000000-0000-0000-0000-000000000001'),'moderator redacts without deleting shared message');

RESET ROLE;
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM auth.users WHERE id='e0000000-0000-0000-0000-000000000001'),'Auth user deleted');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM auth.sessions WHERE user_id='e0000000-0000-0000-0000-000000000001'),'Auth sessions deleted');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM auth.refresh_tokens WHERE user_id='e0000000-0000-0000-0000-000000000001'),'current and legacy refresh tokens deleted');
SELECT pg_temp.check((SELECT coordinator_id IS NULL FROM public.groups WHERE id='e1000000-0000-0000-0000-000000000002') AND NOT EXISTS(SELECT 1 FROM public.group_members WHERE group_id='e1000000-0000-0000-0000-000000000002'),'sole group retained unowned without data loss');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM private.invitations WHERE group_id='e1000000-0000-0000-0000-000000000002' AND revoked_at IS NULL),'orphan invitations revoked');
SELECT pg_temp.check((SELECT author_id IS NULL AND note='Shared submission' FROM public.submissions WHERE id='e5000000-0000-0000-0000-000000000001'),'shared submission remains anonymized');
SELECT pg_temp.check((SELECT reviewer_id IS NULL AND feedback='Retained review' FROM public.reviews WHERE submission_id='e5000000-0000-0000-0000-000000000002'),'shared review remains anonymized');
SELECT pg_temp.check((SELECT actor_id IS NULL AND target_id IS NULL FROM public.activity_events WHERE action='fixture'),'activity identity anonymized');
SELECT pg_temp.check((SELECT reporter_id IS NULL AND reason='[Pelapor terhapus]' AND resolution_note='Local resolution' FROM private.content_reports WHERE id=:'report_id'),'report identity scrubbed, resolution retained');
SELECT pg_temp.denied($q$UPDATE public.tasks SET status='in_progress' WHERE id='e4000000-0000-0000-0000-000000000001'$q$,'tasks_active_owners');
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims','{"role":"anon"}',true);
SELECT pg_temp.denied($q$SELECT public.grouply_mutate('deleteAccount','{}')$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT public.grouply_moderation('queue','{}')$q$,'permission denied');
ROLLBACK;
