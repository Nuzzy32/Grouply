CREATE TABLE private.task_batch_receipts (
  actor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  payload_hash bytea NOT NULL,
  task_ids uuid[] NOT NULL,
  PRIMARY KEY (actor_id, project_id, request_id)
);
REVOKE ALL ON private.task_batch_receipts FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.publish_task_batch(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  actor uuid := auth.uid();
  pid uuid;
  batch_id uuid;
  batch jsonb;
  item jsonb;
  g public.groups;
  p public.projects;
  receipt private.task_batch_receipts;
  payload_hash bytea;
  ids uuid[] := ARRAY[]::uuid[];
BEGIN
  PERFORM 1 FROM public.profiles WHERE id = actor FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF jsonb_typeof(payload) IS DISTINCT FROM 'object'
    OR jsonb_typeof(payload->'tasks') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;
  pid := (payload->>'projectID')::uuid;
  batch_id := (payload->>'requestID')::uuid;
  batch := payload->'tasks';
  IF pid IS NULL OR batch_id IS NULL OR jsonb_array_length(batch) NOT BETWEEN 1 AND 20
    OR pg_catalog.octet_length(batch::text) > 180000 THEN RAISE EXCEPTION 'invalid_input'; END IF;

  SELECT * INTO g FROM public.groups
    WHERE id = (SELECT group_id FROM public.projects WHERE id = pid) FOR UPDATE;
  IF g.id IS NULL OR NOT private.member(g.id) THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO p FROM public.projects WHERE id = pid FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;

  payload_hash := extensions.digest(batch::text, 'sha256');
  SELECT * INTO receipt FROM private.task_batch_receipts r
    WHERE r.actor_id = actor AND r.project_id = pid AND r.request_id = batch_id;
  IF FOUND THEN
    IF receipt.payload_hash <> payload_hash THEN RAISE EXCEPTION 'invalid_input'; END IF;
    RETURN jsonb_build_object('ids', receipt.task_ids);
  END IF;

  IF g.coordinator_id IS DISTINCT FROM actor AND p.lead_id IS DISTINCT FROM actor THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p.status <> 'active' OR p.archived_at IS NOT NULL THEN RAISE EXCEPTION 'project_read_only'; END IF;
  PERFORM 1 FROM public.organizations
    WHERE id = g.organization_id AND plan_expires_at > clock_timestamp() FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plan_inactive'; END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(batch) LOOP
    IF jsonb_typeof(item) IS DISTINCT FROM 'object'
      OR jsonb_typeof(item->'title') IS DISTINCT FROM 'string'
      OR jsonb_typeof(item->'description') IS DISTINCT FROM 'string'
      OR jsonb_typeof(item->'assigneeID') IS DISTINCT FROM 'string'
      OR jsonb_typeof(item->'reviewerID') IS DISTINCT FROM 'string'
      OR jsonb_typeof(item->'dueAt') IS DISTINCT FROM 'string'
      OR item ? 'meetingID' THEN RAISE EXCEPTION 'invalid_input'; END IF;
    ids := array_append(ids, (private.mutate_workflow(
      'createTask', item || jsonb_build_object('projectID', pid)
    )->>'id')::uuid);
  END LOOP;
  INSERT INTO private.task_batch_receipts VALUES (actor, pid, batch_id, payload_hash, ids);
  RETURN jsonb_build_object('ids', ids);
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow
  OR numeric_value_out_of_range THEN RAISE EXCEPTION 'invalid_input';
END;
$$;
REVOKE ALL ON FUNCTION private.publish_task_batch(jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.publish_task_batch(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.grouply_mutate(action text, payload jsonb)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$
  SELECT CASE WHEN action = 'publishTaskBatch' THEN private.publish_task_batch(payload)
    ELSE private.mutate(action, payload) END
$$;

CREATE OR REPLACE FUNCTION public.grouply_snapshot()
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$
  SELECT private.snapshot() || '{"taskBatchAvailable":true}'::jsonb
$$;
