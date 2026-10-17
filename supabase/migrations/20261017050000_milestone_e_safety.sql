DO $$
DECLARE identity record;
BEGIN
  FOR identity IN SELECT * FROM (VALUES
    ('public','activity_events','actor_id'), ('public','chat_messages','sender_id'),
    ('public','groups','coordinator_id'), ('public','tasks','assignee_id'),
    ('public','tasks','reviewer_id'), ('public','submissions','author_id'),
    ('public','reviews','reviewer_id'), ('private','content_reports','reporter_id')
  ) AS identities(schema_name, table_name, column_name)
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I DROP NOT NULL', identity.schema_name, identity.table_name, identity.column_name);
    EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I', identity.schema_name, identity.table_name, identity.table_name || '_' || identity.column_name || '_fkey');
    EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.profiles(id) ON DELETE SET NULL', identity.schema_name, identity.table_name, identity.table_name || '_' || identity.column_name || '_fkey', identity.column_name);
  END LOOP;
END;
$$;

ALTER TABLE public.tasks ADD CONSTRAINT tasks_active_owners
  CHECK (status = 'done' OR (assignee_id IS NOT NULL AND reviewer_id IS NOT NULL));

ALTER TABLE private.content_reports
  ADD COLUMN status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','dismissed','removed')),
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN resolution_note text CHECK (length(resolution_note) BETWEEN 1 AND 1000),
  ADD CONSTRAINT report_resolution CHECK ((status = 'pending' AND reviewed_at IS NULL AND resolution_note IS NULL)
    OR (status <> 'pending' AND reviewed_at IS NOT NULL AND resolution_note IS NOT NULL));

CREATE INDEX reports_reporter_message ON private.content_reports(reporter_id,message_id);
CREATE INDEX reports_pending ON private.content_reports(created_at,id) WHERE status = 'pending';

CREATE OR REPLACE FUNCTION private.profile_visible(uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id = auth.uid()) AND
    (uid = auth.uid() OR EXISTS(SELECT 1 FROM public.group_members actor
      JOIN public.group_members target USING(group_id) WHERE actor.user_id = auth.uid() AND target.user_id = uid));
$$;

CREATE FUNCTION private.blocks_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid;
BEGIN
  actor := CASE WHEN TG_OP = 'DELETE' THEN OLD.user_id ELSE NEW.user_id END;
  INSERT INTO public.user_sync_state AS state(user_id) VALUES(actor)
    ON CONFLICT(user_id) DO UPDATE SET revision = state.revision + 1;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.blocks_changed() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER blocks_sync AFTER INSERT OR DELETE ON public.user_blocks
  FOR EACH ROW EXECUTE FUNCTION private.blocks_changed();

ALTER FUNCTION private.mutate(text,jsonb) RENAME TO mutate_workflow;
REVOKE ALL ON FUNCTION private.mutate_workflow(text,jsonb) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.mutate(action text, payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); message public.chat_messages; report_id uuid; owned_group public.groups;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  PERFORM 1 FROM public.profiles WHERE id = actor FOR UPDATE;
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
    UPDATE private.content_reports SET reason = '[Pelapor terhapus]' WHERE reporter_id = actor;
    UPDATE public.chat_messages SET client_id = NULL WHERE sender_id = actor;
    UPDATE public.activity_events SET target_id = NULL WHERE target_id = actor;
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
REVOKE ALL ON FUNCTION private.mutate(text,jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.mutate(text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION private.snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
 SELECT jsonb_build_object(
 'currentUserID',actor,
 'users',coalesce((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'email','','tint',u.tint) ORDER BY u.name) FROM public.profiles u WHERE private.profile_visible(u.id)),'[]'),
 'groups',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'course',g.course,'coordinatorID',coalesce(g.coordinator_id::text,''),'tint',g.tint,'icon',g.icon,'memberIDs',(SELECT jsonb_agg(user_id ORDER BY user_id) FROM public.group_members WHERE group_id=g.id))) FROM public.groups g WHERE private.member(g.id)),'[]'),
 'projects',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'groupID',p.group_id,'title',p.title,'description',p.description,'dueAt',private.iso(p.due_at),'status',CASE WHEN p.archived_at IS NOT NULL THEN 'archived' ELSE p.status END,'previousStatus',CASE WHEN p.archived_at IS NOT NULL THEN p.status ELSE NULL END)) FROM public.projects p WHERE private.member(p.group_id)),'[]'),
 'tasks',coalesce((SELECT jsonb_agg(jsonb_build_object('id',t.id,'projectID',t.project_id,'title',t.title,'description',t.description,'assigneeID',coalesce(t.assignee_id::text,''),'reviewerID',coalesce(t.reviewer_id::text,''),'dueAt',private.iso(t.due_at),'status',t.status,'version',t.version,'submissions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'revision',s.revision,'authorID',coalesce(s.author_id::text,''),'note',s.note,'links',s.links,'createdAt',private.iso(s.created_at),'decision',r.decision,'feedback',r.feedback,'reviewerID',r.reviewer_id) ORDER BY s.revision) FROM public.submissions s LEFT JOIN public.reviews r ON r.submission_id=s.id WHERE s.task_id=t.id),'[]'))) FROM public.tasks t WHERE private.task_group(t.id) IS NOT NULL),'[]'),
 'messages',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'groupID',m.group_id,'taskID',m.task_id,'senderID',coalesce(m.sender_id::text,''),'text',m.content,'createdAt',private.iso(m.created_at),'kind',m.kind,'delivery','sent','targetTaskID',CASE WHEN m.kind='activity' THEN m.task_id ELSE NULL END) ORDER BY m.created_at,m.id) FROM public.chat_messages m WHERE private.member(m.group_id)),'[]'),
 'invites',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'groupID',i.group_id,'code','','createdAt',private.iso(i.created_at),'expiresAt',private.iso(i.expires_at),'maxUses',i.max_uses,'useCount',i.used_count,'revoked',i.revoked_at IS NOT NULL)) FROM private.invitations i JOIN public.groups g ON g.id=i.group_id WHERE g.coordinator_id=actor),'[]'),
 'reports',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'messageID',r.message_id,'reporterID',r.reporter_id,'reason',r.reason,'createdAt',private.iso(r.created_at),'status',r.status,'reviewedAt',private.iso(r.reviewed_at))) FROM private.content_reports r WHERE r.reporter_id=actor),'[]'),
 'blockedUserIDs',coalesce((SELECT jsonb_agg(blocked_id) FROM public.user_blocks WHERE user_id=actor),'[]'),
 'readMessageIDs',coalesce((SELECT jsonb_agg(r.message_id) FROM public.chat_reads r JOIN public.chat_messages m ON m.id=r.message_id WHERE r.user_id=actor AND m.task_id IS NULL AND private.member(m.group_id)),'[]')) INTO result;
 RETURN result;
END;
$$;

CREATE FUNCTION public.grouply_moderation(action text, payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE report private.content_reports; decision text; resolution text; target_group uuid;
BEGIN
  IF current_setting('role',true) IS DISTINCT FROM 'service_role' OR auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF action IS NULL OR payload IS NULL OR jsonb_typeof(payload) <> 'object' THEN RAISE EXCEPTION 'invalid_input'; END IF;
  IF action = 'queue' THEN
    IF payload <> '{}'::jsonb THEN RAISE EXCEPTION 'invalid_input'; END IF;
    RETURN coalesce((SELECT jsonb_agg(to_jsonb(queued)) FROM
      (SELECT r.id,r.message_id AS "messageID",r.reporter_id AS "reporterID",r.reason,r.created_at AS "createdAt",
        r.status,m.group_id AS "groupID",m.content AS text FROM private.content_reports r
        JOIN public.chat_messages m ON m.id=r.message_id WHERE r.status='pending' ORDER BY r.created_at,r.id LIMIT 100) queued),'[]');
  ELSIF action = 'review' THEN
    IF jsonb_typeof(payload->'id') IS DISTINCT FROM 'string' OR jsonb_typeof(payload->'decision') IS DISTINCT FROM 'string'
      OR jsonb_typeof(payload->'note') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'invalid_input'; END IF;
    decision := payload->>'decision'; resolution := private.txt(payload->>'note',1000);
    IF decision NOT IN ('dismissed','removed') THEN RAISE EXCEPTION 'invalid_input'; END IF;
    SELECT * INTO report FROM private.content_reports WHERE id=(payload->>'id')::uuid FOR UPDATE;
    IF report.id IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    IF report.status <> 'pending' THEN
      IF report.status=decision AND report.resolution_note=resolution THEN
        RETURN jsonb_build_object('id',report.id,'status',report.status,'reviewedAt',private.iso(report.reviewed_at));
      END IF;
      RAISE EXCEPTION 'already_reviewed';
    END IF;
    UPDATE private.content_reports SET status=decision,reviewed_at=now(),resolution_note=resolution WHERE id=report.id;
    IF decision='removed' THEN
      UPDATE public.chat_messages SET content='[Pesan dihapus moderator]' WHERE id=report.message_id RETURNING chat_messages.group_id INTO target_group;
    ELSE
      SELECT message.group_id INTO target_group FROM public.chat_messages message WHERE message.id=report.message_id;
    END IF;
    INSERT INTO public.user_sync_state AS state(user_id)
      SELECT member.user_id FROM public.group_members member WHERE member.group_id=target_group
      UNION SELECT report.reporter_id WHERE report.reporter_id IS NOT NULL ORDER BY user_id
      ON CONFLICT(user_id) DO UPDATE SET revision=state.revision+1;
    RETURN jsonb_build_object('id',report.id,'status',decision,'reviewedAt',private.iso(now()));
  END IF;
  RAISE EXCEPTION 'invalid_input';
EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_input';
END;
$$;
REVOKE ALL ON FUNCTION public.grouply_moderation(text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grouply_moderation(text,jsonb) TO service_role;
NOTIFY pgrst, 'reload schema';
