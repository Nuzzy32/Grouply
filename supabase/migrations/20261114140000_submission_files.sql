-- Submission file attachments (14 November 2026): up to 3 files per submission
-- next to the HTTPS links. Files live in the private bucket `submission-files`
-- at `<task id>/<random uuid>`; only the task's assignee can upload, while the
-- task is open for submission, and only members of the task's group can read.
-- Nobody can overwrite or delete them (submissions are append-only).

ALTER TABLE public.submissions
  ADD COLUMN files jsonb NOT NULL DEFAULT '[]'::jsonb
  CONSTRAINT submissions_files_shape CHECK (jsonb_typeof(files) = 'array' AND jsonb_array_length(files) <= 3);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('submission-files', 'submission-files', false, 10485760, ARRAY[
  'application/pdf', 'image/jpeg', 'image/png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation'])
ON CONFLICT (id) DO NOTHING;

-- `<uuid>/<uuid>`, checked before any cast so a bad name is just "no".
CREATE FUNCTION private.submission_file_task(object_name text)
RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE WHEN object_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    THEN split_part(object_name, '/', 1)::uuid END
$$;

-- Upload: the assignee of an open task in an active project of their group.
-- ponytail: orphan uploads (picked, never submitted) are capped at 30 per
-- task and person but not cleaned up; add a sweep if storage cost matters.
CREATE FUNCTION private.can_upload_submission_file(object_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tasks t JOIN public.projects p ON p.id = t.project_id
    WHERE t.id = private.submission_file_task(object_name)
      AND t.assignee_id = auth.uid()
      AND t.status IN ('in_progress', 'needs_revision')
      AND p.status = 'active'
      AND private.member(p.group_id))
  AND (SELECT count(*) FROM storage.objects o
       WHERE o.bucket_id = 'submission-files' AND o.owner_id = auth.uid()::text
         AND split_part(o.name, '/', 1) = split_part(object_name, '/', 1)) < 30
$$;

CREATE FUNCTION private.can_read_submission_file(object_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.task_group(private.submission_file_task(object_name)) IS NOT NULL
$$;

REVOKE ALL ON FUNCTION private.submission_file_task(text), private.can_upload_submission_file(text),
  private.can_read_submission_file(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.submission_file_task(text), private.can_upload_submission_file(text),
  private.can_read_submission_file(text) TO authenticated;

CREATE POLICY submission_files_upload ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'submission-files' AND private.can_upload_submission_file(name));
CREATE POLICY submission_files_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'submission-files' AND private.can_read_submission_file(name));

-- submitWork with `files: [{path, name}]`: every path must be an object this
-- actor uploaded into this task's folder and not used by an earlier
-- submission; size and type come from Storage, not from the client. The
-- regular submitWork runs first (same transaction), then the files are
-- recorded on the submission it created.
CREATE FUNCTION private.submit_work_files(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  actor uuid := auth.uid(); tid uuid; f jsonb; o storage.objects;
  files jsonb := coalesce(payload->'files', '[]'::jsonb); recorded jsonb := '[]'::jsonb; result jsonb;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF jsonb_typeof(files) <> 'array' OR jsonb_array_length(files) > 3 THEN RAISE EXCEPTION 'invalid_input'; END IF;
  BEGIN
    tid := coalesce(payload->>'taskID', payload->>'id')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_input';
  END;
  FOR f IN SELECT jsonb_array_elements(files) LOOP
    IF jsonb_typeof(f) <> 'object' OR private.submission_file_task(f->>'path') IS DISTINCT FROM tid
       OR recorded @> jsonb_build_array(jsonb_build_object('path', f->>'path')) THEN
      RAISE EXCEPTION 'invalid_input';
    END IF;
    SELECT * INTO o FROM storage.objects
      WHERE bucket_id = 'submission-files' AND name = f->>'path' AND owner_id = actor::text;
    IF o.id IS NULL OR EXISTS (SELECT 1 FROM public.submissions s
                               WHERE s.task_id = tid AND s.files @> jsonb_build_array(jsonb_build_object('path', f->>'path'))) THEN
      RAISE EXCEPTION 'invalid_input';
    END IF;
    recorded := recorded || jsonb_build_array(jsonb_build_object(
      'path', o.name, 'name', private.txt(f->>'name', 200),
      'size', (o.metadata->>'size')::bigint, 'type', o.metadata->>'mimetype'));
  END LOOP;
  result := private.mutate('submitWork', payload - 'files');
  UPDATE public.submissions SET files = recorded
    WHERE id = (SELECT id FROM public.submissions WHERE task_id = tid ORDER BY revision DESC LIMIT 1)
      AND author_id = actor;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION private.submit_work_files(jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.submit_work_files(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.grouply_mutate(action text, payload jsonb)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$
  SELECT CASE WHEN action='publishTaskBatch' THEN private.publish_task_batch(payload)
    WHEN action IN ('addMeetingFollowUp','publishMeetingFollowUp','removeMeetingFollowUp') THEN private.mutate_meeting_follow_up(action,payload)
    WHEN action='submitWork' AND payload ? 'files' THEN private.submit_work_files(payload)
    ELSE private.mutate(action,payload) END
$$;

-- Files are read per task from `submissions` (RLS submission_read), so the
-- snapshot only advertises the capability.
CREATE OR REPLACE FUNCTION public.grouply_snapshot()
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$
  SELECT private.snapshot() || '{"taskBatchAvailable":true,"meetingFollowUpsAvailable":true,"submissionFilesAvailable":true}'::jsonb
$$;
