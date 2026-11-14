-- Run with psql -v ON_ERROR_STOP=1. All fixtures roll back.
BEGIN;
CREATE FUNCTION pg_temp.check(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %', label; END IF;
  RAISE NOTICE 'PASS: %', label;
END;
$$;
CREATE FUNCTION pg_temp.reject(action text, payload jsonb, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.grouply_mutate(action, payload);
  RAISE EXCEPTION 'unexpected success';
EXCEPTION WHEN raise_exception THEN
  PERFORM pg_temp.check(SQLERRM = expected, action || ' rejects with ' || expected);
END;
$$;

SELECT gen_random_uuid() AS coordinator, gen_random_uuid() AS member, gen_random_uuid() AS outsider,
  gen_random_uuid() AS org, gen_random_uuid() AS team, gen_random_uuid() AS project,
  gen_random_uuid() AS meeting, gen_random_uuid() AS point, gen_random_uuid() AS dead_point \gset
INSERT INTO auth.users(id, raw_user_meta_data) VALUES
  (:'coordinator','{"name":"Follow-up coordinator"}'),
  (:'member','{"name":"Follow-up member"}'),
  (:'outsider','{"name":"Follow-up outsider"}');
INSERT INTO public.organizations(id,name,seat_limit,plan_expires_at)
  VALUES (:'org','Follow-up fixture',10,now()+interval '30 days');
INSERT INTO public.groups(id,name,coordinator_id,organization_id)
  VALUES (:'team','Follow-up group',:'coordinator',:'org');
INSERT INTO public.group_members(group_id,user_id) VALUES (:'team',:'coordinator'),(:'team',:'member');
INSERT INTO public.projects(id,group_id,title,due_at) VALUES (:'project',:'team','Follow-up project',now()+interval '10 days');
INSERT INTO public.meetings(id,group_id,title,starts_at,status)
  VALUES (:'meeting',:'team','Rapat evaluasi',now()-interval '1 day','done');

SELECT jsonb_build_object('meetingID',:'meeting','requestID',:'point','title','Kirim undangan',
  'assigneeID',:'member','dueAt',now()+interval '3 days') AS add \gset
SELECT jsonb_build_object('meetingID',:'meeting','followUpID',:'point','projectID',:'project',
  'reviewerID',:'coordinator') AS publish \gset

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', :'outsider', true);
SELECT pg_temp.reject('addMeetingFollowUp', :'add', 'forbidden');
SELECT set_config('request.jwt.claim.sub', :'member', true);
SELECT pg_temp.reject('addMeetingFollowUp', :'add', 'forbidden');
SELECT set_config('request.jwt.claim.sub', :'coordinator', true);
SELECT pg_temp.check((public.grouply_snapshot()->>'meetingFollowUpsAvailable')::boolean, 'capability advertised');
SELECT pg_temp.reject('addMeetingFollowUp', jsonb_set(:'add'::jsonb,'{meetingID}','"bukan-uuid"'), 'invalid_input');
SELECT pg_temp.check(public.grouply_mutate('addMeetingFollowUp', :'add')->>'id' = :'point', 'coordinator adds a point');
SELECT pg_temp.check(public.grouply_mutate('addMeetingFollowUp', :'add')->>'id' = :'point', 'same request is idempotent');
SELECT pg_temp.reject('addMeetingFollowUp', jsonb_set(:'add'::jsonb,'{title}','"Judul lain"'), 'invalid_input');
SELECT pg_temp.check(jsonb_array_length(public.grouply_meeting(:'meeting')->'followUps') = 1, 'detail lists one point');

SELECT public.grouply_mutate('publishMeetingFollowUp', :'publish')->>'id' AS task \gset
SELECT pg_temp.check(public.grouply_mutate('publishMeetingFollowUp', :'publish')->>'id' = :'task', 'publish retry returns the same task');
SELECT pg_temp.check((SELECT meeting_id FROM public.tasks WHERE id = :'task') = :'meeting', 'task links to the meeting');
SELECT pg_temp.reject('removeMeetingFollowUp',
  jsonb_build_object('meetingID',:'meeting','followUpID',:'point'), 'invalid_input');

-- A point whose assignee left can never be published; it can be removed, idempotently, even after expiry.
SELECT public.grouply_mutate('addMeetingFollowUp',
  jsonb_set(jsonb_set(:'add'::jsonb,'{requestID}',to_jsonb(:'dead_point'::text)),'{title}','"Sewa ruangan"'));
RESET ROLE;
DELETE FROM public.group_members WHERE group_id = :'team' AND user_id = :'member';
UPDATE public.organizations SET plan_expires_at = now() - interval '1 day' WHERE id = :'org';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', :'outsider', true);
SELECT pg_temp.reject('removeMeetingFollowUp',
  jsonb_build_object('meetingID',:'meeting','followUpID',:'dead_point'), 'forbidden');
SELECT set_config('request.jwt.claim.sub', :'coordinator', true);
SELECT public.grouply_mutate('removeMeetingFollowUp', jsonb_build_object('meetingID',:'meeting','followUpID',:'dead_point'));
SELECT pg_temp.check(public.grouply_mutate('removeMeetingFollowUp',
  jsonb_build_object('meetingID',:'meeting','followUpID',:'dead_point'))->>'id' = :'dead_point', 'remove is idempotent');
SELECT pg_temp.check(jsonb_array_length(public.grouply_meeting(:'meeting')->'followUps') = 1, 'only the published point remains');
SELECT pg_temp.reject('addMeetingFollowUp',
  jsonb_set(jsonb_set(:'add'::jsonb,'{requestID}',to_jsonb(gen_random_uuid()::text)),
    '{assigneeID}',to_jsonb(:'coordinator'::text)), 'plan_inactive');
ROLLBACK;
