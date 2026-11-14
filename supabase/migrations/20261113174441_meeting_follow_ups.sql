CREATE TABLE private.meeting_follow_ups (
  id uuid PRIMARY KEY,
  meeting_id uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  title text NOT NULL,
  assignee_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  due_at timestamptz NOT NULL,
  task_id uuid REFERENCES public.tasks(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX meeting_follow_ups_meeting ON private.meeting_follow_ups(meeting_id);
REVOKE ALL ON private.meeting_follow_ups FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.mutate_meeting_follow_up(action text, payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  actor uuid := auth.uid();
  mid uuid;
  fid uuid;
  g public.groups;
  m public.meetings;
  p public.projects;
  f private.meeting_follow_ups;
  title text;
  assignee uuid;
  due timestamptz;
  tid uuid;
BEGIN
  PERFORM 1 FROM public.profiles WHERE id=actor FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF action IS NULL OR action NOT IN ('addMeetingFollowUp','publishMeetingFollowUp','removeMeetingFollowUp')
    THEN RAISE EXCEPTION 'invalid_input'; END IF;
  -- Cast in the body, not DECLARE, so the handler below maps bad input to invalid_input.
  mid := (payload->>'meetingID')::uuid;
  SELECT * INTO g FROM public.groups
    WHERE id=(SELECT group_id FROM public.meetings WHERE id=mid) FOR UPDATE;
  IF g.id IS NULL OR NOT private.member(g.id) THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO m FROM public.meetings WHERE id=mid FOR UPDATE;

  -- Removal is cleanup for points that can no longer be published (assignee left,
  -- due date passed), so it works after the plan expires and is idempotent.
  IF action='removeMeetingFollowUp' THEN
    IF g.coordinator_id IS DISTINCT FROM actor AND m.note_taker_id IS DISTINCT FROM actor
      THEN RAISE EXCEPTION 'forbidden'; END IF;
    fid := (payload->>'followUpID')::uuid;
    IF fid IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    SELECT * INTO f FROM private.meeting_follow_ups WHERE id=fid AND meeting_id=mid;
    IF NOT FOUND THEN RETURN jsonb_build_object('id',fid); END IF;
    IF f.task_id IS NOT NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    DELETE FROM private.meeting_follow_ups WHERE id=fid;
    UPDATE public.meetings SET version=version+1 WHERE id=mid;
    PERFORM private.touch_users(ARRAY(SELECT user_id FROM public.group_members WHERE group_id=g.id));
    RETURN jsonb_build_object('id',fid);
  END IF;

  IF action='addMeetingFollowUp' THEN
    fid := (payload->>'requestID')::uuid;
    assignee := (payload->>'assigneeID')::uuid;
    due := (payload->>'dueAt')::timestamptz;
    IF fid IS NULL OR assignee IS NULL OR due IS NULL
      OR jsonb_typeof(payload->'title') IS DISTINCT FROM 'string'
      THEN RAISE EXCEPTION 'invalid_input'; END IF;
    title := private.txt(payload->>'title',120);
    SELECT * INTO f FROM private.meeting_follow_ups WHERE id=fid;
    IF FOUND THEN
      IF f.meeting_id=mid AND f.actor_id=actor AND f.title=title
        AND f.assignee_id=assignee AND f.due_at=due THEN RETURN jsonb_build_object('id',fid); END IF;
      RAISE EXCEPTION 'invalid_input';
    END IF;
    IF g.coordinator_id IS DISTINCT FROM actor AND m.note_taker_id IS DISTINCT FROM actor
      THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF due<=now() OR NOT EXISTS(SELECT 1 FROM public.group_members WHERE group_id=g.id AND user_id=assignee)
      THEN RAISE EXCEPTION 'invalid_input'; END IF;
    IF (SELECT count(*) FROM private.meeting_follow_ups WHERE meeting_id=mid)>=50
      THEN RAISE EXCEPTION 'rate_limited'; END IF;
  ELSE
    fid := (payload->>'followUpID')::uuid;
    SELECT * INTO f FROM private.meeting_follow_ups WHERE id=fid AND meeting_id=mid;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid_input'; END IF;
    IF f.task_id IS NOT NULL THEN RETURN jsonb_build_object('id',f.task_id); END IF;
    SELECT * INTO p FROM public.projects WHERE id=(payload->>'projectID')::uuid AND group_id=g.id FOR UPDATE;
    IF p.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  END IF;

  IF m.status <> 'done' THEN RAISE EXCEPTION 'meeting_closed'; END IF;
  PERFORM 1 FROM public.organizations
    WHERE id=g.organization_id AND plan_expires_at>clock_timestamp() FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plan_inactive'; END IF;

  IF action='addMeetingFollowUp' THEN
    INSERT INTO private.meeting_follow_ups(id,meeting_id,actor_id,title,assignee_id,due_at)
      VALUES(fid,mid,actor,title,assignee,due);
  ELSE
    tid := (private.mutate_workflow('createTask',jsonb_build_object(
      'projectID',p.id,'meetingID',mid,'title',f.title,'description','',
      'assigneeID',f.assignee_id,'reviewerID',payload->>'reviewerID','dueAt',f.due_at
    ))->>'id')::uuid;
    UPDATE private.meeting_follow_ups SET task_id=tid WHERE id=fid;
  END IF;
  UPDATE public.meetings SET version=version+1 WHERE id=mid;
  PERFORM private.touch_users(ARRAY(SELECT user_id FROM public.group_members WHERE group_id=g.id));
  RETURN jsonb_build_object('id',coalesce(tid,fid));
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow
  OR unique_violation THEN RAISE EXCEPTION 'invalid_input';
END;
$$;
REVOKE ALL ON FUNCTION private.mutate_meeting_follow_up(text,jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.mutate_meeting_follow_up(text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.grouply_mutate(action text, payload jsonb)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$
  SELECT CASE WHEN action='publishTaskBatch' THEN private.publish_task_batch(payload)
    WHEN action IN ('addMeetingFollowUp','publishMeetingFollowUp','removeMeetingFollowUp') THEN private.mutate_meeting_follow_up(action,payload)
    ELSE private.mutate(action,payload) END
$$;

CREATE OR REPLACE FUNCTION private.meeting_detail(mid uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); m public.meetings;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  SELECT * INTO m FROM public.meetings WHERE id=mid;
  IF m.id IS NULL OR NOT private.member(m.group_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN jsonb_build_object('id',m.id,'version',m.version,'agenda',m.agenda,'minutes',m.minutes,
    'attendance',coalesce((SELECT jsonb_agg(jsonb_build_object('userID',a.user_id,'status',a.status) ORDER BY a.user_id)
      FROM public.meeting_attendance a WHERE a.meeting_id=mid),'[]'),
    'followUps',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,
      'assigneeID',f.assignee_id,'dueAt',private.iso(f.due_at),'taskID',f.task_id) ORDER BY f.created_at,f.id)
      FROM private.meeting_follow_ups f WHERE f.meeting_id=mid),'[]'));
END;
$$;

CREATE OR REPLACE FUNCTION public.grouply_snapshot()
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$
  SELECT private.snapshot() || '{"taskBatchAvailable":true,"meetingFollowUpsAvailable":true}'::jsonb
$$;
