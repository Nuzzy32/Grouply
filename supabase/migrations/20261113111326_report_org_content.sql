-- Reports for organization content (announcements, meetings, approvals), required for
-- user-generated content before store release. Reuses private.content_reports and the
-- operator flow. Lock order unchanged: profile -> groups -> organizations -> report rows -> sync.
SET local check_function_bodies = off;

-- No FK on target_id: an announcement may be withdrawn after it was reported. The excerpt
-- keeps what was reported for the operator.
ALTER TABLE private.content_reports
  ALTER COLUMN message_id DROP NOT NULL,
  ADD COLUMN target_kind text NOT NULL DEFAULT 'message'
    CHECK (target_kind IN ('message','announcement','meeting','approval')),
  ADD COLUMN target_id uuid,
  ADD COLUMN excerpt text NOT NULL DEFAULT '' CHECK (length(excerpt) <= 2000),
  ADD CONSTRAINT report_target CHECK (
    (target_kind = 'message' AND message_id IS NOT NULL AND target_id IS NULL)
    OR (target_kind <> 'message' AND message_id IS NULL AND target_id IS NOT NULL));
CREATE INDEX reports_reporter_target ON private.content_reports(reporter_id, target_kind, target_id)
  WHERE target_id IS NOT NULL;

CREATE FUNCTION private.report_content(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); kind text; tid uuid; gid uuid; org uuid; excerpt text; report_id uuid;
  n public.announcements; m public.meetings; a public.approvals;
BEGIN
  IF jsonb_typeof(payload->'kind') IS DISTINCT FROM 'string' OR jsonb_typeof(payload->'id') IS DISTINCT FROM 'string'
    OR jsonb_typeof(payload->'reason') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'invalid_input'; END IF;
  PERFORM private.txt(payload->>'reason', 1000);
  kind := payload->>'kind';
  tid := (payload->>'id')::uuid;
  IF kind = 'announcement' THEN
    SELECT * INTO n FROM public.announcements WHERE id = tid;
    IF n.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    gid := n.group_id;
    IF gid IS NULL THEN org := n.organization_id; END IF;
  ELSIF kind = 'meeting' THEN
    SELECT * INTO m FROM public.meetings WHERE id = tid;
    IF m.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    gid := m.group_id;
  ELSIF kind = 'approval' THEN
    SELECT * INTO a FROM public.approvals WHERE id = tid;
    IF a.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    gid := a.group_id; org := a.organization_id;
  ELSE
    RAISE EXCEPTION 'invalid_input';
  END IF;
  -- Same order as membership changes, so visibility cannot go stale under us.
  IF gid IS NOT NULL THEN PERFORM 1 FROM public.groups WHERE id = gid FOR UPDATE; END IF;
  IF org IS NOT NULL THEN PERFORM 1 FROM public.organizations WHERE id = org FOR NO KEY UPDATE; END IF;
  IF kind = 'announcement' THEN
    IF n.author_id = actor OR NOT EXISTS(SELECT 1 FROM private.announcement_audience(n.id) AS x(uid) WHERE x.uid = actor) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    excerpt := n.title || E'\n' || n.body;
  ELSIF kind = 'meeting' THEN
    IF NOT private.member(m.group_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
    excerpt := concat_ws(E'\n', m.title, nullif(m.place, ''), nullif(m.agenda, ''), nullif(m.minutes, ''));
  ELSE
    IF a.requester_id = actor OR NOT (
        EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = a.organization_id AND user_id = actor)
        OR EXISTS(SELECT 1 FROM public.groups WHERE id = a.group_id AND coordinator_id = actor)) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    excerpt := concat_ws(E'\n', a.title, a.note, CASE WHEN a.links <> '[]'::jsonb THEN a.links::text END);
  END IF;
  SELECT id INTO report_id FROM private.content_reports
    WHERE reporter_id = actor AND target_kind = kind AND target_id = tid ORDER BY created_at, id LIMIT 1;
  IF report_id IS NOT NULL THEN RETURN jsonb_build_object('id', report_id); END IF;
  IF (SELECT count(*) FROM private.content_reports WHERE reporter_id = actor AND created_at > now() - interval '1 minute') >= 5 THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;
  INSERT INTO private.content_reports(reporter_id, reason, target_kind, target_id, excerpt)
    VALUES (actor, private.txt(payload->>'reason', 1000), kind, tid, left(excerpt, 2000)) RETURNING id INTO report_id;
  PERFORM private.touch_users(ARRAY[actor]);
  RETURN jsonb_build_object('id', report_id);
END;
$$;
REVOKE ALL ON FUNCTION private.report_content(jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- Operator queue and review, extended to organization content.
CREATE OR REPLACE FUNCTION public.grouply_moderation(action text, payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE report private.content_reports; decision text; resolution text; target_group uuid; org uuid;
  removed constant text := '[Dihapus moderator]'; audience uuid[];
BEGIN
  IF current_setting('role',true) IS DISTINCT FROM 'service_role' OR auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF action IS NULL OR payload IS NULL OR jsonb_typeof(payload) <> 'object' THEN RAISE EXCEPTION 'invalid_input'; END IF;
  IF action = 'queue' THEN
    IF payload <> '{}'::jsonb THEN RAISE EXCEPTION 'invalid_input'; END IF;
    RETURN coalesce((SELECT jsonb_agg(to_jsonb(queued)) FROM
      (SELECT r.id, r.target_kind AS kind, coalesce(r.message_id, r.target_id) AS "targetID",
        r.message_id AS "messageID", r.reporter_id AS "reporterID", r.reason, r.created_at AS "createdAt", r.status,
        coalesce(m.group_id, n.group_id, mt.group_id, ap.group_id) AS "groupID",
        coalesce(n.organization_id, ap.organization_id, g.organization_id) AS "organizationID",
        CASE WHEN r.target_kind = 'message' THEN m.content ELSE r.excerpt END AS text
       FROM private.content_reports r
       LEFT JOIN public.chat_messages m ON m.id = r.message_id
       LEFT JOIN public.announcements n ON r.target_kind = 'announcement' AND n.id = r.target_id
       LEFT JOIN public.meetings mt ON r.target_kind = 'meeting' AND mt.id = r.target_id
       LEFT JOIN public.approvals ap ON r.target_kind = 'approval' AND ap.id = r.target_id
       LEFT JOIN public.groups g ON g.id = mt.group_id
       WHERE r.status = 'pending' ORDER BY r.created_at, r.id LIMIT 100) queued), '[]');
  ELSIF action = 'review' THEN
    IF jsonb_typeof(payload->'id') IS DISTINCT FROM 'string' OR jsonb_typeof(payload->'decision') IS DISTINCT FROM 'string'
      OR jsonb_typeof(payload->'note') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'invalid_input'; END IF;
    decision := payload->>'decision'; resolution := private.txt(payload->>'note',1000);
    IF decision NOT IN ('dismissed','removed') THEN RAISE EXCEPTION 'invalid_input'; END IF;
    SELECT * INTO report FROM private.content_reports WHERE id=(payload->>'id')::uuid;
    IF report.id IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    -- Organization content: group then organization before the report row, the order
    -- deleteAccount and every member action use.
    IF report.target_kind = 'announcement' THEN
      SELECT group_id, CASE WHEN group_id IS NULL THEN organization_id END INTO target_group, org
        FROM public.announcements WHERE id = report.target_id;
    ELSIF report.target_kind = 'meeting' THEN
      SELECT group_id INTO target_group FROM public.meetings WHERE id = report.target_id;
    ELSIF report.target_kind = 'approval' THEN
      SELECT group_id, organization_id INTO target_group, org FROM public.approvals WHERE id = report.target_id;
    END IF;
    IF report.target_kind <> 'message' THEN
      IF target_group IS NOT NULL THEN PERFORM 1 FROM public.groups WHERE id = target_group FOR UPDATE; END IF;
      IF org IS NOT NULL THEN PERFORM 1 FROM public.organizations WHERE id = org FOR NO KEY UPDATE; END IF;
    END IF;
    SELECT * INTO report FROM private.content_reports WHERE id = report.id FOR UPDATE;
    IF report.status <> 'pending' THEN
      IF report.status=decision AND report.resolution_note=resolution THEN
        RETURN jsonb_build_object('id',report.id,'status',report.status,'reviewedAt',private.iso(report.reviewed_at));
      END IF;
      RAISE EXCEPTION 'already_reviewed';
    END IF;
    UPDATE private.content_reports SET status=decision,reviewed_at=now(),resolution_note=resolution WHERE id=report.id;
    IF report.target_kind = 'message' THEN
      IF decision='removed' THEN
        UPDATE public.chat_messages SET content='[Pesan dihapus moderator]' WHERE id=report.message_id RETURNING chat_messages.group_id INTO target_group;
      ELSE
        SELECT message.group_id INTO target_group FROM public.chat_messages message WHERE message.id=report.message_id;
      END IF;
      INSERT INTO public.user_sync_state AS state(user_id)
        SELECT member.user_id FROM public.group_members member WHERE member.group_id=target_group
        UNION SELECT report.reporter_id WHERE report.reporter_id IS NOT NULL ORDER BY user_id
        ON CONFLICT(user_id) DO UPDATE SET revision=state.revision+1;
    ELSE
      IF decision = 'removed' THEN
        IF report.target_kind = 'announcement' THEN
          UPDATE public.announcements SET title = removed, body = removed WHERE id = report.target_id;
        ELSIF report.target_kind = 'meeting' THEN
          UPDATE public.meetings SET title = removed, place = '', agenda = '', minutes = removed, version = version + 1
            WHERE id = report.target_id;
        ELSE
          UPDATE public.approvals SET title = removed, note = removed, links = '[]' WHERE id = report.target_id;
        END IF;
      END IF;
      audience := ARRAY(
        SELECT x.uid FROM private.announcement_audience(report.target_id) AS x(uid) WHERE report.target_kind = 'announcement'
        UNION SELECT member.user_id FROM public.group_members member WHERE report.target_kind = 'meeting' AND member.group_id = target_group
        UNION SELECT a.requester_id FROM public.approvals a WHERE report.target_kind = 'approval' AND a.id = report.target_id
        UNION SELECT s.approver_id FROM public.approval_steps s WHERE report.target_kind = 'approval' AND s.approval_id = report.target_id
        UNION SELECT r.user_id FROM public.organization_roles r WHERE report.target_kind = 'approval' AND r.organization_id = org
        UNION SELECT g.coordinator_id FROM public.groups g WHERE report.target_kind = 'approval' AND g.id = target_group
        UNION SELECT report.reporter_id);
      PERFORM private.touch_users(audience);
    END IF;
    RETURN jsonb_build_object('id',report.id,'status',decision,'reviewedAt',private.iso(now()));
  END IF;
  RAISE EXCEPTION 'invalid_input';
EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_input';
END;
$$;

-- Copied from 20261112133033; changed: reportContent dispatch.
CREATE OR REPLACE FUNCTION private.mutate(action text, payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); message public.chat_messages; report_id uuid; owned_group public.groups;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  PERFORM 1 FROM public.profiles WHERE id = actor FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF action IS NULL OR payload IS NULL OR jsonb_typeof(payload) <> 'object' THEN RAISE EXCEPTION 'invalid_input'; END IF;
  IF action IN ('createOrganization','updateOrganization','createDivision','setOrgRole','transferKetua') THEN
    RETURN private.mutate_org(action,payload);
  END IF;
  IF action = 'reportContent' THEN RETURN private.report_content(payload); END IF;
  IF action IN ('setProjectLead','createMeeting','updateMeeting','cancelMeeting','recordMeeting','requestApproval',
      'decideApproval','cancelApproval','postAnnouncement','deleteAnnouncement','markAnnouncementRead') THEN
    RETURN private.mutate_orgwork(action,payload);
  END IF;
  IF action = 'deleteAccount' THEN
    IF payload <> '{}'::jsonb THEN RAISE EXCEPTION 'invalid_input'; END IF;
    PERFORM 1 FROM public.groups WHERE id IN
      (SELECT group_id FROM public.group_members WHERE user_id = actor)
      OR coordinator_id = actor ORDER BY id FOR UPDATE;
    -- Organizations after groups, in id order, before group_members rows fire org_membership_guard.
    PERFORM 1 FROM public.organizations WHERE id IN (SELECT organization_id FROM public.groups WHERE id IN
      (SELECT group_id FROM public.group_members WHERE user_id = actor)) ORDER BY id FOR NO KEY UPDATE;
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
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow
  OR numeric_value_out_of_range THEN RAISE EXCEPTION 'invalid_input';
END;
$$;

-- Copied from 20261112133033; changed: reports[].kind/targetID, messageID '' for organization content.
CREATE OR REPLACE FUNCTION private.snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
 SELECT jsonb_build_object(
 'currentUserID',actor,
 'users',coalesce((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'email','','tint',u.tint) ORDER BY u.name) FROM public.profiles u WHERE private.profile_visible(u.id)),'[]'),
 'groups',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'course',g.course,'coordinatorID',coalesce(g.coordinator_id::text,''),'tint',g.tint,'icon',g.icon,'organizationID',coalesce(g.organization_id::text,''),'isCommittee',g.is_committee,'memberIDs',(SELECT jsonb_agg(user_id ORDER BY user_id) FROM public.group_members WHERE group_id=g.id))) FROM public.groups g WHERE private.member(g.id)),'[]'),
 'projects',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'groupID',p.group_id,'title',p.title,'description',p.description,'dueAt',private.iso(p.due_at),'status',CASE WHEN p.archived_at IS NOT NULL THEN 'archived' ELSE p.status END,'previousStatus',CASE WHEN p.archived_at IS NOT NULL THEN p.status ELSE NULL END,'leadID',coalesce(p.lead_id::text,''))) FROM public.projects p WHERE private.member(p.group_id)),'[]'),
 'tasks',coalesce((SELECT jsonb_agg(jsonb_build_object('id',t.id,'projectID',t.project_id,'title',t.title,'description',t.description,'assigneeID',coalesce(t.assignee_id::text,''),'reviewerID',coalesce(t.reviewer_id::text,''),'dueAt',private.iso(t.due_at),'status',t.status,'version',t.version,'submissions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'revision',s.revision,'authorID',coalesce(s.author_id::text,''),'note',s.note,'links',s.links,'createdAt',private.iso(s.created_at),'decision',r.decision,'feedback',r.feedback,'reviewerID',coalesce(r.reviewer_id::text,'')) ORDER BY s.revision) FROM public.submissions s LEFT JOIN public.reviews r ON r.submission_id=s.id WHERE s.task_id=t.id),'[]'))) FROM public.tasks t WHERE private.task_group(t.id) IS NOT NULL),'[]'),
 'messages',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'groupID',m.group_id,'taskID',m.task_id,'senderID',coalesce(m.sender_id::text,''),'text',m.content,'createdAt',private.iso(m.created_at),'kind',m.kind,'delivery','sent','targetTaskID',CASE WHEN m.kind='activity' THEN m.task_id ELSE NULL END) ORDER BY m.created_at,m.id) FROM public.chat_messages m WHERE private.member(m.group_id)),'[]'),
 'invites',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'groupID',i.group_id,'code','','createdAt',private.iso(i.created_at),'expiresAt',private.iso(i.expires_at),'maxUses',i.max_uses,'useCount',i.used_count,'revoked',i.revoked_at IS NOT NULL)) FROM private.invitations i JOIN public.groups g ON g.id=i.group_id WHERE g.coordinator_id=actor),'[]'),
 'reports',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'messageID',coalesce(r.message_id::text,''),'kind',r.target_kind,'targetID',coalesce(r.target_id,r.message_id),'reporterID',r.reporter_id,'reason',r.reason,'createdAt',private.iso(r.created_at),'status',r.status,'reviewedAt',private.iso(r.reviewed_at))) FROM private.content_reports r WHERE r.reporter_id=actor),'[]'),
 'organizations',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'description',o.description,'periodLabel',o.period_label,'planActive',coalesce(o.plan_expires_at>now(),false),'planExpiresAt',private.iso(o.plan_expires_at),'seatLimit',o.seat_limit,'seatsUsed',private.org_seats(o.id),'approvals',private.org_approvals(o.id,actor),'announcements',private.org_announcements(o.id,actor),'myRole',(SELECT r.role FROM public.organization_roles r WHERE r.organization_id=o.id AND r.user_id=actor),'roles',coalesce((SELECT jsonb_agg(jsonb_build_object('userID',r.user_id,'role',r.role,'name',CASE WHEN EXISTS(SELECT 1 FROM public.user_blocks b WHERE b.user_id=actor AND b.blocked_id=r.user_id) THEN 'Anggota' ELSE p.name END) ORDER BY CASE r.role WHEN 'ketua' THEN 0 WHEN 'bph' THEN 1 ELSE 2 END,p.name,p.id) FROM public.organization_roles r JOIN public.profiles p ON p.id=r.user_id WHERE r.organization_id=o.id),'[]'),'divisions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'isCommittee',d.is_committee,'memberCount',d.members,'isMember',d.mine) ORDER BY d.name,d.id) FROM (SELECT g.id,g.name,g.is_committee,count(m.user_id) AS members,bool_or(m.user_id=actor) AS mine FROM public.groups g JOIN public.group_members m ON m.group_id=g.id WHERE g.organization_id=o.id GROUP BY g.id,g.name,g.is_committee) d),'[]')) ORDER BY o.name,o.id) FROM public.organizations o WHERE private.org_member(o.id,actor)),'[]'),
 'meetings',private.my_meetings(actor),
 'blockedUserIDs',coalesce((SELECT jsonb_agg(blocked_id) FROM public.user_blocks WHERE user_id=actor),'[]'),
 'readMessageIDs',coalesce((SELECT jsonb_agg(r.message_id) FROM public.chat_reads r JOIN public.chat_messages m ON m.id=r.message_id WHERE r.user_id=actor AND m.task_id IS NULL AND private.member(m.group_id)),'[]')) INTO result;
 RETURN result;
END;
$$;

NOTIFY pgrst, 'reload schema';
