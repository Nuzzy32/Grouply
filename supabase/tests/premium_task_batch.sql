-- Run with psql -v ON_ERROR_STOP=1. All fixtures roll back.
BEGIN;
CREATE FUNCTION pg_temp.check(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %', label; END IF;
  RAISE NOTICE 'PASS: %', label;
END;
$$;
CREATE FUNCTION pg_temp.reject_batch(payload jsonb, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.grouply_mutate('publishTaskBatch', payload);
  RAISE EXCEPTION 'unexpected success';
EXCEPTION WHEN raise_exception THEN
  PERFORM pg_temp.check(SQLERRM = expected, expected || ' rejects batch');
END;
$$;

SELECT gen_random_uuid() AS coordinator, gen_random_uuid() AS member, gen_random_uuid() AS outsider,
  gen_random_uuid() AS org, gen_random_uuid() AS team, gen_random_uuid() AS project,
  gen_random_uuid() AS request, gen_random_uuid() AS other_request \gset
INSERT INTO auth.users(id, raw_user_meta_data) VALUES
  (:'coordinator','{"name":"Premium coordinator"}'),
  (:'member','{"name":"Premium member"}'),
  (:'outsider','{"name":"Premium outsider"}');
INSERT INTO public.organizations(id,name,seat_limit,plan_expires_at)
  VALUES (:'org','Premium fixture',10,now()+interval '30 days');
INSERT INTO public.groups(id,name,coordinator_id,organization_id)
  VALUES (:'team','Premium group',:'coordinator',:'org');
INSERT INTO public.group_members(group_id,user_id)
  VALUES (:'team',:'coordinator'),(:'team',:'member');
INSERT INTO public.projects(id,group_id,title,due_at)
  VALUES (:'project',:'team','Premium project',now()+interval '10 days');

SELECT jsonb_build_object('title','Rundown','description','Susun agenda',
  'assigneeID',:'member','reviewerID',:'coordinator','dueAt',now()+interval '1 day') AS task \gset
SELECT jsonb_build_object('projectID',:'project','requestID',:'request',
  'tasks',jsonb_build_array(:'task'::jsonb, :'task'::jsonb || '{"title":"Anggaran"}')) AS batch \gset
SELECT jsonb_set(:'batch'::jsonb,'{tasks,1,reviewerID}',to_jsonb(:'member'::text)) AS bad \gset

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', :'outsider', true);
SELECT pg_temp.reject_batch(:'batch','forbidden');
SELECT set_config('request.jwt.claim.sub', :'member', true);
SELECT pg_temp.reject_batch(:'batch','forbidden');
SELECT set_config('request.jwt.claim.sub', :'coordinator', true);
SELECT pg_temp.check((public.grouply_snapshot()->>'taskBatchAvailable')::boolean,'capability advertised');
SELECT pg_temp.reject_batch(:'bad','invalid_input');
SELECT pg_temp.check(jsonb_array_length(public.grouply_snapshot()->'tasks')=0,'last row failure rolls back first row');
SELECT public.grouply_mutate('publishTaskBatch', :'batch') AS receipt \gset
SELECT pg_temp.check(jsonb_array_length(:'receipt'::jsonb->'ids')=2,'batch creates both tasks');
SELECT pg_temp.check(public.grouply_mutate('publishTaskBatch', :'batch')=:'receipt'::jsonb,'retry returns same receipt');
SELECT pg_temp.reject_batch(:'bad','invalid_input');
SELECT pg_temp.check(jsonb_array_length(public.grouply_snapshot()->'tasks')=2,'retry creates no duplicates');

RESET ROLE;
UPDATE public.organizations SET plan_expires_at=now()-interval '1 day' WHERE id=:'org';
SET LOCAL ROLE authenticated;
SELECT pg_temp.check(public.grouply_mutate('publishTaskBatch', :'batch')=:'receipt'::jsonb,'retry after expiry returns receipt');
SELECT pg_temp.reject_batch(jsonb_set(:'batch'::jsonb,'{requestID}',to_jsonb(:'other_request'::text)),'plan_inactive');
SELECT pg_temp.check(public.grouply_mutate('createTask', :'task'::jsonb || jsonb_build_object('projectID',:'project')) ? 'id',
  'manual creation still works after expiry');
ROLLBACK;
