CREATE OR REPLACE FUNCTION private.mutate(action text, payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); message public.chat_messages; report_id uuid; owned_group public.groups;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  PERFORM 1 FROM public.profiles WHERE id = actor FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF action IS NULL OR payload IS NULL OR jsonb_typeof(payload) <> 'object' THEN RAISE EXCEPTION 'invalid_input'; END IF;
  IF action = 'deleteAccount' THEN
    IF payload <> '{}'::jsonb THEN RAISE EXCEPTION 'invalid_input'; END IF;
    PERFORM 1 FROM public.groups WHERE id IN
      (SELECT group_id FROM public.group_members WHERE user_id = actor)
      OR coordinator_id = actor ORDER BY id FOR UPDATE;
    IF EXISTS(SELECT 1 FROM public.groups owned JOIN public.group_members member ON member.group_id = owned.id
      WHERE owned.coordinator_id = actor AND member.user_id <> actor) THEN
      RAISE EXCEPTION 'coordinator_transfer_required';
    END IF;
    IF EXISTS(SELECT 1 FROM public.tasks WHERE status <> 'done' AND (assignee_id = actor OR reviewer_id = actor)) THEN
      RAISE EXCEPTION 'active_assignment';
    END IF;
    UPDATE private.content_reports SET reason = '[Pelapor terhapus]' WHERE reporter_id = actor;
    UPDATE public.chat_messages SET client_id = NULL WHERE sender_id = actor;
    UPDATE public.activity_events SET target_id = NULL WHERE target_id = actor;
    FOR owned_group IN SELECT * FROM public.groups WHERE coordinator_id = actor LOOP
      UPDATE private.invitations SET revoked_at = now() WHERE group_id = owned_group.id AND revoked_at IS NULL;
      UPDATE public.groups SET coordinator_id = NULL WHERE id = owned_group.id;
    END LOOP;
    DELETE FROM public.group_members WHERE user_id = actor;
    DELETE FROM public.chat_reads WHERE user_id = actor;
    DELETE FROM public.user_blocks WHERE user_id = actor OR blocked_id = actor;
    INSERT INTO public.user_sync_state AS state(user_id)
      SELECT DISTINCT member.user_id FROM public.group_members member WHERE member.group_id IN (
        SELECT group_id FROM public.chat_messages WHERE sender_id=actor
        UNION SELECT group_id FROM public.activity_events WHERE actor_id=actor
        UNION SELECT project.group_id FROM public.projects project JOIN public.tasks task ON task.project_id=project.id
          WHERE task.assignee_id=actor OR task.reviewer_id=actor
        UNION SELECT project.group_id FROM public.projects project JOIN public.tasks task ON task.project_id=project.id
          JOIN public.submissions submission ON submission.task_id=task.id
          LEFT JOIN public.reviews review ON review.submission_id=submission.id
          WHERE submission.author_id=actor OR review.reviewer_id=actor
      ) ORDER BY member.user_id
      ON CONFLICT(user_id) DO UPDATE SET revision=state.revision+1;
    DELETE FROM public.profiles WHERE id = actor;
    DELETE FROM auth.refresh_tokens WHERE user_id = actor::text;
    DELETE FROM auth.users WHERE id = actor;
    RETURN jsonb_build_object('deleted',true);
  ELSIF action = 'reportMessage' THEN
    IF jsonb_typeof(payload->'id') IS DISTINCT FROM 'string'
      OR jsonb_typeof(payload->'reason') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'invalid_input'; END IF;
    PERFORM private.txt(payload->>'reason',1000);
    SELECT * INTO message FROM public.chat_messages WHERE id = (payload->>'id')::uuid;
    IF message.id IS NULL OR message.sender_id = actor THEN RAISE EXCEPTION 'forbidden'; END IF;
    PERFORM 1 FROM public.groups WHERE id = message.group_id FOR UPDATE;
    IF NOT private.member(message.group_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
    SELECT id INTO report_id FROM private.content_reports WHERE reporter_id = actor AND message_id = message.id ORDER BY created_at,id LIMIT 1;
    IF report_id IS NOT NULL THEN RETURN jsonb_build_object('id',report_id); END IF;
    IF (SELECT count(*) FROM private.content_reports WHERE reporter_id = actor AND created_at > now() - interval '1 minute') >= 5 THEN
      RAISE EXCEPTION 'rate_limited';
    END IF;
    INSERT INTO private.content_reports(message_id,reporter_id,reason)
      VALUES(message.id,actor,private.txt(payload->>'reason',1000)) RETURNING id INTO report_id;
    INSERT INTO public.user_sync_state AS state(user_id) VALUES(actor)
      ON CONFLICT(user_id) DO UPDATE SET revision=state.revision+1;
    RETURN jsonb_build_object('id',report_id);
  END IF;
  RETURN private.mutate_workflow(action,payload);
EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_input';
END;
$$;
