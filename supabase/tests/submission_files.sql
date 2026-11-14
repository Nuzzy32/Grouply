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
-- Uploads go through the storage.objects RLS policy, like the Storage API.
CREATE FUNCTION pg_temp.upload(object_name text, mime text DEFAULT 'application/pdf') RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO storage.objects(bucket_id, name, owner_id, metadata)
  VALUES ('submission-files', object_name, current_setting('request.jwt.claim.sub'),
          jsonb_build_object('size', 2048, 'mimetype', mime));
  RETURN true;
EXCEPTION WHEN insufficient_privilege THEN RETURN false;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.check(boolean,text), pg_temp.reject(text,jsonb,text), pg_temp.upload(text,text) TO authenticated;

SELECT gen_random_uuid() AS coordinator, gen_random_uuid() AS member, gen_random_uuid() AS outsider,
  gen_random_uuid() AS team, gen_random_uuid() AS project, gen_random_uuid() AS task, gen_random_uuid() AS other_task \gset
SELECT :'task' || '/' || gen_random_uuid() AS file1, :'task' || '/' || gen_random_uuid() AS file2,
  :'other_task' || '/' || gen_random_uuid() AS foreign_file, :'task' || '/' || gen_random_uuid() AS outsider_file \gset
INSERT INTO auth.users(id, raw_user_meta_data) VALUES
  (:'coordinator','{"name":"Files coordinator"}'), (:'member','{"name":"Files member"}'), (:'outsider','{"name":"Files outsider"}');
INSERT INTO public.groups(id,name,coordinator_id) VALUES (:'team','Files group',:'coordinator');
INSERT INTO public.group_members(group_id,user_id) VALUES (:'team',:'coordinator'),(:'team',:'member');
INSERT INTO public.projects(id,group_id,title,due_at) VALUES (:'project',:'team','Files project',now()+interval '10 days');
INSERT INTO public.tasks(id,project_id,title,assignee_id,reviewer_id,due_at,status) VALUES
  (:'task',:'project','Kirim ERD',:'member',:'coordinator',now()+interval '3 days','in_progress'),
  (:'other_task',:'project','Tugas lain',:'member',:'coordinator',now()+interval '3 days','in_progress');

SET LOCAL ROLE authenticated;

-- Upload rules
SELECT set_config('request.jwt.claim.sub', :'outsider', true);
SELECT pg_temp.check(NOT pg_temp.upload(:'outsider_file'), 'outsider cannot upload');
SELECT set_config('request.jwt.claim.sub', :'coordinator', true);
SELECT pg_temp.check(NOT pg_temp.upload(:'task' || '/' || gen_random_uuid()), 'reviewer cannot upload to someone else''s task');
SELECT set_config('request.jwt.claim.sub', :'member', true);
SELECT pg_temp.check(NOT pg_temp.upload(:'task' || '/../x.pdf'), 'malformed path rejected');
SELECT pg_temp.check(pg_temp.upload(:'file1'), 'assignee uploads to own open task');
SELECT pg_temp.check(pg_temp.upload(:'file2', 'image/png'), 'assignee uploads a second file');
SELECT pg_temp.check(pg_temp.upload(:'foreign_file'), 'assignee uploads to another own task');

-- Read rules
SELECT pg_temp.check((SELECT count(*) FROM storage.objects WHERE name = :'file1') = 1, 'assignee reads the file');
SELECT set_config('request.jwt.claim.sub', :'coordinator', true);
SELECT pg_temp.check((SELECT count(*) FROM storage.objects WHERE name = :'file1') = 1, 'group member reads the file');
UPDATE storage.objects SET metadata = '{}' WHERE name = :'file1';
-- Storage also blocks direct deletes with a trigger; without a delete policy the row stays either way.
SELECT set_config('test.file1', :'file1', true);
DO $$ BEGIN DELETE FROM storage.objects WHERE name = current_setting('test.file1'); EXCEPTION WHEN others THEN NULL; END $$;
SELECT set_config('request.jwt.claim.sub', :'outsider', true);
SELECT pg_temp.check((SELECT count(*) FROM storage.objects WHERE bucket_id = 'submission-files') = 0, 'outsider reads nothing');

-- submitWork with files
SELECT set_config('request.jwt.claim.sub', :'member', true);
SELECT jsonb_build_object('taskID',:'task','expectedVersion',1,'note','ERD terlampir','links','[]'::jsonb) AS base \gset
SELECT pg_temp.reject('submitWork', :'base'::jsonb || jsonb_build_object('files', jsonb_build_array(
  jsonb_build_object('path',:'foreign_file','name','x.pdf'))), 'invalid_input');
SELECT pg_temp.reject('submitWork', :'base'::jsonb || jsonb_build_object('files', jsonb_build_array(
  jsonb_build_object('path',:'task' || '/' || gen_random_uuid(),'name','hilang.pdf'))), 'invalid_input');
SELECT pg_temp.reject('submitWork', :'base'::jsonb || jsonb_build_object('files', jsonb_build_array(
  jsonb_build_object('path',:'file1','name','a.pdf'), jsonb_build_object('path',:'file1','name','b.pdf'))), 'invalid_input');
SELECT pg_temp.reject('submitWork', :'base'::jsonb || jsonb_build_object('files', jsonb_build_array(
  jsonb_build_object('path',:'file1','name','a'),jsonb_build_object('path',:'file2','name','b'),
  jsonb_build_object('path',:'file1','name','c'),jsonb_build_object('path',:'file2','name','d'))), 'invalid_input');
SELECT public.grouply_mutate('submitWork', :'base'::jsonb || jsonb_build_object('files', jsonb_build_array(
  jsonb_build_object('path',:'file1','name','ERD.pdf'), jsonb_build_object('path',:'file2','name','Diagram.png'))));
SELECT pg_temp.check((SELECT status FROM public.tasks WHERE id = :'task') = 'in_review', 'submission moves the task to review');
SELECT pg_temp.check((SELECT files FROM public.submissions WHERE task_id = :'task') = jsonb_build_array(
  jsonb_build_object('path',:'file1','name','ERD.pdf','size',2048,'type','application/pdf'),
  jsonb_build_object('path',:'file2','name','Diagram.png','size',2048,'type','image/png')), 'files recorded with Storage size and type');
SELECT pg_temp.check(NOT pg_temp.upload(:'task' || '/' || gen_random_uuid()), 'no uploads while in review');
SELECT pg_temp.check((public.grouply_snapshot()->>'submissionFilesAvailable')::boolean, 'capability advertised');

-- A revision cannot reuse an earlier submission's file.
SELECT set_config('request.jwt.claim.sub', :'coordinator', true);
SELECT public.grouply_mutate('review', jsonb_build_object('taskID',:'task','expectedVersion',2,'approve',false,'feedback','Tambah atribut'));
SELECT set_config('request.jwt.claim.sub', :'member', true);
SELECT pg_temp.reject('submitWork', jsonb_set(:'base'::jsonb,'{expectedVersion}','3') || jsonb_build_object('files', jsonb_build_array(
  jsonb_build_object('path',:'file1','name','ERD.pdf'))), 'invalid_input');
-- Without files the plain submitWork path still works.
SELECT public.grouply_mutate('submitWork', jsonb_set(:'base'::jsonb,'{expectedVersion}','3'));
SELECT pg_temp.check((SELECT files FROM public.submissions WHERE task_id = :'task' AND revision = 2) = '[]'::jsonb, 'link-only revision has no files');

RESET ROLE;
SELECT pg_temp.check((SELECT count(*) FROM storage.objects WHERE name = :'file1' AND metadata ? 'size') = 1, 'nobody could edit or delete the file');
ROLLBACK;
