-- Organization Plan Tahap 1 (docs/DESIGN-org-tahap1.md).
-- An organization groups existing `groups` as divisions; Kadiv = group coordinator.
-- Lock order on every path: profile -> groups (by id) -> organizations (by id, FOR NO KEY UPDATE)
-- -> user_sync_state (by user_id). Invitation rows are only touched under their group lock.
SET local check_function_bodies = off;

CREATE TABLE public.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
  period_label text NOT NULL DEFAULT '' CHECK (length(period_label) <= 40),
  seat_limit integer NOT NULL DEFAULT 0 CHECK (seat_limit BETWEEN 0 AND 500),
  plan_expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.organization_roles (
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('ketua','bph','pembina')),
  PRIMARY KEY (organization_id, user_id)
);
CREATE UNIQUE INDEX organization_one_ketua ON public.organization_roles(organization_id) WHERE role = 'ketua';
CREATE INDEX organization_roles_user ON public.organization_roles(user_id);
-- No policies: only SECURITY DEFINER RPCs read or write these tables.
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_roles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.organizations, public.organization_roles FROM PUBLIC, anon, authenticated;

ALTER TABLE public.groups ADD COLUMN organization_id uuid REFERENCES public.organizations(id);
CREATE INDEX groups_organization ON public.groups(organization_id) WHERE organization_id IS NOT NULL;

-- Multi-use invites for organization divisions; the per-group limit is enforced in generateInvite.
ALTER TABLE private.invitations DROP CONSTRAINT invitations_max_uses_check,
  ADD CONSTRAINT invitations_max_uses_check CHECK (max_uses BETWEEN 1 AND 200);

CREATE FUNCTION private.org_seats(org uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT count(DISTINCT m.user_id)::integer FROM public.group_members m
    JOIN public.groups g ON g.id = m.group_id WHERE g.organization_id = org;
$$;

CREATE FUNCTION private.org_member(org uuid, uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS(SELECT 1 FROM public.group_members m JOIN public.groups g ON g.id = m.group_id
    WHERE g.organization_id = org AND m.user_id = uid);
$$;

-- Caller must already hold the organization row lock.
CREATE FUNCTION private.org_touch(org uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO public.user_sync_state AS state(user_id)
    SELECT DISTINCT m.user_id FROM public.group_members m JOIN public.groups g ON g.id = m.group_id
    WHERE g.organization_id = org ORDER BY m.user_id
  ON CONFLICT(user_id) DO UPDATE SET revision = state.revision + 1;
$$;

-- Keeps "every role holder belongs to a division". Named to fire before membership_sync
-- (same-event triggers run in name order), so the organization lock precedes sync-row locks.
CREATE FUNCTION private.org_membership_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE org uuid; held text;
BEGIN
  SELECT organization_id INTO org FROM public.groups WHERE id = OLD.group_id;
  IF org IS NULL THEN RETURN NULL; END IF;
  -- Serialize with every membership/role change in this organization, then re-read.
  PERFORM 1 FROM public.organizations WHERE id = org FOR NO KEY UPDATE;
  IF private.org_member(org, OLD.user_id) THEN RETURN NULL; END IF;
  SELECT role INTO held FROM public.organization_roles WHERE organization_id = org AND user_id = OLD.user_id;
  IF held IS NULL THEN RETURN NULL; END IF;
  IF held = 'ketua' AND private.org_seats(org) > 0 THEN RAISE EXCEPTION 'ketua_transfer_required'; END IF;
  IF held <> 'ketua' AND OLD.user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'org_role_holder'; END IF;
  DELETE FROM public.organization_roles WHERE organization_id = org AND user_id = OLD.user_id;
  RETURN NULL;
END;
$$;
CREATE TRIGGER group_members_org_guard AFTER DELETE ON public.group_members
FOR EACH ROW EXECUTE FUNCTION private.org_membership_guard();

CREATE FUNCTION private.mutate_org(action text, payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); org public.organizations; mine text; target uuid; new_role text; gid uuid;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF action = 'createOrganization' THEN
    -- The caller's profile row lock (private.mutate) serializes this count per user.
    IF (SELECT count(*) FROM public.organization_roles WHERE user_id = actor AND role = 'ketua') >= 3 THEN
      RAISE EXCEPTION 'rate_limited';
    END IF;
    INSERT INTO public.organizations(name, description, period_label)
      VALUES (private.txt(payload->>'name',80), private.txt(payload->>'description',1000,false),
        private.txt(payload->>'periodLabel',40,false))
      RETURNING * INTO org;
    INSERT INTO public.groups(name, coordinator_id, organization_id)
      VALUES (private.txt(coalesce(nullif(btrim(payload->>'divisionName'),''),'BPH Inti'),80), actor, org.id)
      RETURNING id INTO gid;
    INSERT INTO public.group_members VALUES (gid, actor);
    INSERT INTO public.organization_roles VALUES (org.id, actor, 'ketua');
    RETURN jsonb_build_object('id', org.id, 'groupID', gid);
  END IF;

  SELECT * INTO org FROM public.organizations
    WHERE id = coalesce(payload->>'organizationID', payload->>'id')::uuid FOR NO KEY UPDATE;
  IF org.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  -- Read after the lock, so a concurrent leave cannot make these checks stale.
  SELECT role INTO mine FROM public.organization_roles WHERE organization_id = org.id AND user_id = actor;
  IF action = 'updateOrganization' THEN
    IF mine IS DISTINCT FROM 'ketua' THEN RAISE EXCEPTION 'forbidden'; END IF;
    UPDATE public.organizations SET name = private.txt(payload->>'name',80),
      description = private.txt(payload->>'description',1000,false),
      period_label = private.txt(payload->>'periodLabel',40,false)
      WHERE id = org.id;
  ELSIF action = 'createDivision' THEN
    IF mine IS NULL OR mine NOT IN ('ketua','bph') THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF org.plan_expires_at IS NULL OR org.plan_expires_at <= now() THEN RAISE EXCEPTION 'plan_inactive'; END IF;
    IF (SELECT count(*) FROM public.groups g WHERE g.organization_id = org.id
        AND EXISTS(SELECT 1 FROM public.group_members m WHERE m.group_id = g.id)) >= 30 THEN
      RAISE EXCEPTION 'invalid_input';
    END IF;
    INSERT INTO public.groups(name, description, coordinator_id, organization_id)
      VALUES (private.txt(payload->>'name',80), private.txt(payload->>'description',1000,false), actor, org.id)
      RETURNING id INTO gid;
    INSERT INTO public.group_members VALUES (gid, actor);
  ELSIF action IN ('setOrgRole','transferKetua') THEN
    IF mine IS DISTINCT FROM 'ketua' THEN RAISE EXCEPTION 'forbidden'; END IF;
    target := (payload->>'userID')::uuid;
    IF target IS NULL OR target = actor OR NOT private.org_member(org.id, target) THEN
      RAISE EXCEPTION 'invalid_input';
    END IF;
    IF action = 'setOrgRole' THEN
      new_role := payload->>'role'; -- missing or JSON null removes the role
      IF new_role IS NOT NULL AND new_role NOT IN ('bph','pembina') THEN RAISE EXCEPTION 'invalid_input'; END IF;
      IF new_role IS NULL THEN
        DELETE FROM public.organization_roles WHERE organization_id = org.id AND user_id = target;
      ELSE
        INSERT INTO public.organization_roles VALUES (org.id, target, new_role)
          ON CONFLICT (organization_id, user_id) DO UPDATE SET role = excluded.role;
      END IF;
    ELSE
      -- ponytail: anti-spam limit only; two orgs handing ketua to one person at once can reach 4.
      IF (SELECT count(*) FROM public.organization_roles WHERE user_id = target AND role = 'ketua') >= 3 THEN
        RAISE EXCEPTION 'rate_limited';
      END IF;
      -- Demote first: the one-ketua unique index cannot be deferred.
      UPDATE public.organization_roles SET role = 'bph' WHERE organization_id = org.id AND user_id = actor;
      INSERT INTO public.organization_roles VALUES (org.id, target, 'ketua')
        ON CONFLICT (organization_id, user_id) DO UPDATE SET role = 'ketua';
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_input';
  END IF;
  PERFORM private.org_touch(org.id);
  RETURN CASE WHEN gid IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('id', gid) END;
END;
$$;

REVOKE ALL ON FUNCTION private.org_seats(uuid), private.org_member(uuid,uuid), private.org_touch(uuid),
  private.org_membership_guard(), private.mutate_org(text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.org_overview(org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); org public.organizations; result jsonb;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  SELECT * INTO org FROM public.organizations WHERE id = org_id;
  IF org.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.organization_roles r
      WHERE r.organization_id = org.id AND r.user_id = actor) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF org.plan_expires_at IS NULL OR org.plan_expires_at <= now() THEN RAISE EXCEPTION 'plan_inactive'; END IF;
  -- Same markers as the Flutter client: idle = open task whose latest submission or
  -- thread message is older than 48 hours.
  WITH division AS (
    SELECT g.id, g.name, g.coordinator_id, count(m.user_id) AS members
    FROM public.groups g JOIN public.group_members m ON m.group_id = g.id
    WHERE g.organization_id = org.id GROUP BY g.id
  ), work AS (
    SELECT t.id, t.title, t.status, t.due_at, t.assignee_id, p.id AS project_id, p.group_id, s.last_sub,
      greatest(s.last_sub, (SELECT max(c.created_at) FROM public.chat_messages c WHERE c.task_id = t.id)) AS last_act
    FROM division d
    JOIN public.projects p ON p.group_id = d.id AND p.status = 'active' AND p.archived_at IS NULL
    JOIN public.tasks t ON t.project_id = p.id
    LEFT JOIN LATERAL (SELECT max(x.created_at) AS last_sub FROM public.submissions x WHERE x.task_id = t.id) s ON true
  ), flagged AS (
    SELECT w.*,
      (w.status <> 'done' AND w.due_at < now()) AS overdue,
      coalesce(w.status = 'in_review' AND w.last_sub < now() - interval '48 hours', false) AS review_pending,
      coalesce(w.status IN ('todo','in_progress','needs_revision') AND w.last_act < now() - interval '48 hours', false) AS idle
    FROM work w
  ), project_stats AS (
    SELECT p.id, p.group_id, p.title, p.due_at, count(f.id) AS total,
      count(*) FILTER (WHERE f.status = 'done') AS done,
      count(*) FILTER (WHERE f.status = 'in_review') AS in_review,
      count(*) FILTER (WHERE f.overdue) AS overdue,
      count(*) FILTER (WHERE f.idle) AS idle,
      count(*) FILTER (WHERE f.review_pending) AS review_pending
    FROM division d
    JOIN public.projects p ON p.group_id = d.id AND p.status = 'active' AND p.archived_at IS NULL
    LEFT JOIN flagged f ON f.project_id = p.id
    GROUP BY p.id
  ), attention AS (
    SELECT f.id, f.title, f.group_id, f.project_id, f.assignee_id, f.status, f.due_at,
      CASE WHEN f.overdue THEN 0 WHEN f.review_pending THEN 1 ELSE 2 END AS rank,
      CASE WHEN f.overdue THEN 'overdue' WHEN f.review_pending THEN 'review_pending' ELSE 'idle' END AS reason,
      CASE WHEN f.overdue THEN f.due_at END AS sort_due,
      floor(extract(epoch FROM now() - CASE WHEN f.overdue THEN f.due_at
        WHEN f.review_pending THEN f.last_sub ELSE f.last_act END) / 3600)::integer AS hours
    FROM flagged f WHERE f.overdue OR f.review_pending OR f.idle
    ORDER BY rank, sort_due, hours DESC, f.id LIMIT 50
  )
  SELECT jsonb_build_object(
    'generatedAt', private.iso(now()),
    'divisions', coalesce((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name,
        'coordinatorID', coalesce(d.coordinator_id::text, ''), 'memberCount', d.members,
        'projects', coalesce((SELECT jsonb_agg(jsonb_build_object('id', ps.id, 'title', ps.title,
            'dueAt', private.iso(ps.due_at), 'total', ps.total, 'done', ps.done, 'inReview', ps.in_review,
            'overdue', ps.overdue, 'idle', ps.idle, 'reviewPending', ps.review_pending)
          ORDER BY ps.due_at, ps.id) FROM project_stats ps WHERE ps.group_id = d.id), '[]'))
      ORDER BY d.name, d.id) FROM division d), '[]'),
    'attention', coalesce((SELECT jsonb_agg(jsonb_build_object('taskID', a.id, 'title', a.title,
        'divisionID', a.group_id, 'projectID', a.project_id, 'assigneeID', coalesce(a.assignee_id::text, ''),
        'status', a.status, 'dueAt', private.iso(a.due_at), 'reason', a.reason, 'hours', a.hours)
      ORDER BY a.rank, a.sort_due, a.hours DESC, a.id) FROM attention a), '[]'),
    'users', coalesce((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'tint', p.tint,
        'name', CASE WHEN EXISTS(SELECT 1 FROM public.user_blocks b WHERE b.user_id = actor AND b.blocked_id = p.id)
          THEN 'Anggota' ELSE p.name END) ORDER BY p.name, p.id)
      FROM public.profiles p WHERE p.id IN (SELECT coordinator_id FROM division UNION SELECT assignee_id FROM attention)), '[]')
  ) INTO result;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION private.org_overview(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.org_overview(uuid) TO authenticated;

CREATE FUNCTION public.grouply_org_overview(org_id uuid)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$ SELECT private.org_overview(org_id) $$;
REVOKE ALL ON FUNCTION public.grouply_org_overview(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.grouply_org_overview(uuid) TO authenticated;

-- Operator-only plan activation (no payment gateway in Tahap 1). Mirrors grouply_moderation.
CREATE FUNCTION public.grouply_billing(action text, payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE org public.organizations; seats integer; expires timestamptz;
BEGIN
  IF current_setting('role',true) IS DISTINCT FROM 'service_role' OR auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF action IS NULL OR payload IS NULL OR jsonb_typeof(payload) <> 'object' THEN RAISE EXCEPTION 'invalid_input'; END IF;
  IF action = 'list' THEN
    IF payload <> '{}'::jsonb THEN RAISE EXCEPTION 'invalid_input'; END IF;
    RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'periodLabel', o.period_label,
        'seatLimit', o.seat_limit, 'seatsUsed', private.org_seats(o.id),
        'planExpiresAt', private.iso(o.plan_expires_at), 'createdAt', private.iso(o.created_at))
      ORDER BY o.created_at, o.id) FROM public.organizations o), '[]');
  END IF;
  SELECT * INTO org FROM public.organizations WHERE id = (payload->>'organizationID')::uuid FOR NO KEY UPDATE;
  IF org.id IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
  IF action = 'activatePlan' THEN
    seats := (payload->>'seatLimit')::integer;
    expires := (payload->>'expiresAt')::timestamptz;
    IF seats IS NULL OR seats < 1 OR seats > 500 OR expires IS NULL OR expires <= now() THEN
      RAISE EXCEPTION 'invalid_input';
    END IF;
    UPDATE public.organizations SET seat_limit = seats, plan_expires_at = expires WHERE id = org.id RETURNING * INTO org;
  ELSIF action = 'deactivatePlan' THEN
    UPDATE public.organizations SET plan_expires_at = CASE WHEN plan_expires_at > now() THEN now() ELSE plan_expires_at END
      WHERE id = org.id RETURNING * INTO org;
  ELSE
    RAISE EXCEPTION 'invalid_input';
  END IF;
  PERFORM private.org_touch(org.id);
  RETURN jsonb_build_object('id', org.id, 'seatLimit', org.seat_limit, 'seatsUsed', private.org_seats(org.id),
    'planExpiresAt', private.iso(org.plan_expires_at));
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow
  OR numeric_value_out_of_range THEN RAISE EXCEPTION 'invalid_input';
END;
$$;
REVOKE ALL ON FUNCTION public.grouply_billing(text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grouply_billing(text,jsonb) TO service_role;

-- Copied from 20261017040000 (renamed to mutate_workflow in 050000); changed: joinGroup capacity, generateInvite maxUses.
CREATE OR REPLACE FUNCTION private.mutate_workflow (
  action  text,
  payload jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare actor uuid:=auth.uid();g public.groups;p public.projects;t public.tasks;s public.submissions;inv private.invitations;mid uuid;gid uuid;pid uuid;tid uuid;uid uuid;rid uuid;result_id uuid;token text;body text;link text;link_data jsonb;old public.chat_messages;target uuid;is_coord boolean:=false;is_task boolean:=false;o public.organizations;uses integer;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor) then raise exception 'unauthorized';end if;
 if action='deleteAccount' then raise exception 'account_deletion_unavailable';end if;
 if action='createGroup' then
 insert into public.groups(name,description,course,coordinator_id) values(private.txt(payload->>'name',80),private.txt(payload->>'description',1000,false),private.txt(payload->>'course',120,false),actor) returning id into gid;
 insert into public.group_members values(gid,actor);return jsonb_build_object('id',gid);
 elsif action='updateProfile' then update public.profiles set name=private.txt(payload->>'name',80) where id=actor;return '{}'::jsonb;
 elsif action in ('blockUser','unblockUser') then
 uid:=coalesce(payload->>'id',payload->>'userID')::uuid;
 if uid is null or uid=actor then raise exception 'forbidden';end if;
 if action='blockUser' and (not private.profile_visible(uid) or not exists(select 1 from public.profiles where id=uid)) then raise exception 'forbidden';end if;
 if action='blockUser' then insert into public.user_blocks values(actor,uid) on conflict do nothing;else delete from public.user_blocks where user_id=actor and blocked_id=uid;end if;return '{}'::jsonb;
 elsif action='joinGroup' then
 select * into inv from private.invitations where token_hash=extensions.digest(btrim(payload->>'code'),'sha256');
 if inv.id is null then raise exception 'invalid_input';end if;gid:=inv.group_id;
 else
 if action in ('createProject','generateInvite','transferCoordinator','removeMember','sendMessage','retryMessage','markChatRead') then gid:=(payload->>'groupID')::uuid;
 elsif action in ('updateGroup','leaveGroup') then gid:=(payload->>'id')::uuid;
 elsif action='revokeInvite' then select group_id into gid from private.invitations where id=(payload->>'id')::uuid;
 elsif action='reportMessage' then select group_id into gid from public.chat_messages where id=(payload->>'id')::uuid;
 elsif action in ('createTask','updateProject','completeProject','reopenProject','archiveProject','restoreProject') then
 pid:=coalesce(payload->>'projectID',payload->>'id')::uuid;select group_id into gid from public.projects where id=pid;
 else
 is_task:=true;tid:=coalesce(payload->>'taskID',payload->>'id')::uuid;
 select q.group_id into gid from public.tasks x join public.projects q on q.id=x.project_id where x.id=tid;
 end if;
 end if;
 -- One group lock serializes assignment, membership, invitations and task transitions.
 select * into g from public.groups where id=gid for update;
 if g.id is null then raise exception 'forbidden';end if;
 if action='joinGroup' then
 select * into inv from private.invitations where id=inv.id for update;
 if inv.revoked_at is not null then raise exception 'invalid_input';end if;
 if inv.expires_at<=now() then raise exception 'invite_expired';end if;
 if private.member(gid) then return jsonb_build_object('id',gid);end if;
 if inv.used_count>=inv.max_uses then raise exception 'invite_full';end if;
 -- Divisions of an active organization: seats are per unique person, serialized on the
 -- organization row (group -> organization lock order).
 if g.organization_id is not null then select * into o from public.organizations where id=g.organization_id for no key update;end if;
 if o.id is not null and o.plan_expires_at>now() then
 if not private.org_member(o.id,actor) and private.org_seats(o.id)>=o.seat_limit then raise exception 'org_full';end if;
 if (select count(*) from public.group_members where group_id=gid)>=200 then raise exception 'group_full';end if;
 else
 -- Free limits. A multi-use invite left over from an expired plan acts single-use.
 if inv.used_count>=1 then raise exception 'invite_full';end if;
 if (select count(*) from public.group_members where group_id=gid)>=8 then raise exception 'group_full';end if;
 end if;
 insert into public.group_members values(gid,actor);update private.invitations set used_count=used_count+1 where id=inv.id;
 return jsonb_build_object('id',gid);
 end if;
 if not private.member(gid) then raise exception 'forbidden';end if;is_coord:=g.coordinator_id=actor;
 if is_task then
 select * into t from public.tasks where id=tid for update;pid:=t.project_id;
 end if;
 if pid is not null then
 select * into p from public.projects where id=pid for update;
 if action not in ('completeProject','reopenProject','archiveProject','restoreProject') and (p.archived_at is not null or p.status<>'active') then raise exception 'project_read_only';end if;
 end if;
 if is_task and (payload->>'expectedVersion' is null or (payload->>'expectedVersion')::integer<>t.version) then raise exception 'stale_version';end if;
 if action in ('updateGroup','createProject','updateProject','createTask','updateTask','reassignTask','reopenTask','completeProject','reopenProject','archiveProject','restoreProject','generateInvite','revokeInvite','transferCoordinator','removeMember') and not is_coord then raise exception 'forbidden';end if;
 case action
 when 'updateGroup' then update public.groups set name=private.txt(payload->>'name',80),description=private.txt(payload->>'description',1000,false),course=private.txt(payload->>'course',120,false) where id=gid;
 when 'createProject','updateProject' then
 if (payload->>'dueAt')::timestamptz is null or (payload->>'dueAt')::timestamptz<=now() then raise exception 'invalid_input';end if;
 if action='createProject' then insert into public.projects(group_id,title,description,due_at) values(gid,private.txt(payload->>'title',120),private.txt(payload->>'description',2000,false),(payload->>'dueAt')::timestamptz) returning id into result_id;
 else update public.projects set title=private.txt(payload->>'title',120),description=private.txt(payload->>'description',2000,false),due_at=(payload->>'dueAt')::timestamptz where id=pid;end if;
 when 'completeProject' then
 if p.archived_at is not null or p.status<>'active' or not exists(select 1 from public.tasks where project_id=pid) or exists(select 1 from public.tasks where project_id=pid and status<>'done') then raise exception 'project_read_only';end if;
 update public.projects set status='completed' where id=pid;
 when 'reopenProject' then if p.archived_at is not null or p.status<>'completed' then raise exception 'project_read_only';end if;update public.projects set status='active' where id=pid;
 when 'archiveProject' then if p.archived_at is not null then raise exception 'project_read_only';end if;update public.projects set archived_at=now() where id=pid;
 when 'restoreProject' then if p.archived_at is null then raise exception 'invalid_input';end if;update public.projects set archived_at=null where id=pid;
 when 'createTask','updateTask','reassignTask' then
 if action<>'createTask' and t.status in ('in_review','done') then raise exception 'already_reviewed';end if;
 uid:=case when action='updateTask' then t.assignee_id else (payload->>'assigneeID')::uuid end;rid:=(payload->>'reviewerID')::uuid;
 if uid is null or rid is null or uid=rid or not exists(select 1 from public.group_members where group_id=gid and user_id=uid) or not exists(select 1 from public.group_members where group_id=gid and user_id=rid) then raise exception 'invalid_input';end if;
 if action='reassignTask' then update public.tasks set assignee_id=uid,reviewer_id=rid,status=case when status='needs_revision' then status else 'todo' end,version=version+1 where id=tid;
 else
 if (payload->>'dueAt')::timestamptz is null or (payload->>'dueAt')::timestamptz<=now() then raise exception 'invalid_input';end if;
 if action='createTask' then insert into public.tasks(project_id,title,description,assignee_id,reviewer_id,due_at) values(pid,private.txt(payload->>'title',120),private.txt(payload->>'description',2000,false),uid,rid,(payload->>'dueAt')::timestamptz) returning id into tid;result_id:=tid;
 else update public.tasks set title=private.txt(payload->>'title',120),description=private.txt(payload->>'description',2000,false),reviewer_id=rid,due_at=(payload->>'dueAt')::timestamptz,version=version+1 where id=tid;end if;end if;
 when 'startTask' then
 if t.assignee_id<>actor or t.status not in ('todo','needs_revision') then raise exception 'forbidden';end if;
 update public.tasks set status='in_progress',version=version+1 where id=tid;
 when 'reopenTask' then
 if t.status<>'done' then raise exception 'invalid_input';end if;update public.tasks set status='in_progress',version=version+1 where id=tid;
 when 'submitWork' then
 if t.assignee_id<>actor or t.status not in ('in_progress','needs_revision') then raise exception 'forbidden';end if;
 body:=private.txt(payload->>'note',5000);link_data:=coalesce(payload->'links','[]'::jsonb);
 if jsonb_typeof(link_data)<>'array' or jsonb_array_length(link_data)>5 then raise exception 'invalid_input';end if;
 for link in select jsonb_array_elements_text(link_data) loop if length(link)>2048 or link !~* '^https://[^/@[:space:]]+(\.[^/@[:space:]]+|:[0-9]+)?(/[^[:space:]]*)?$' or link ~ '@' then raise exception 'invalid_input';end if;end loop;
 insert into public.submissions(task_id,revision,author_id,note,links) values(tid,(select count(*)+1 from public.submissions where task_id=tid),actor,body,link_data);
 update public.tasks set status='in_review',version=version+1 where id=tid;
 when 'review' then
 select * into s from public.submissions where task_id=tid order by revision desc limit 1;
 if t.status<>'in_review' or t.reviewer_id<>actor or s.id is null or s.author_id=actor then raise exception 'forbidden';end if;
 body:=private.txt(payload->>'feedback',3000,not coalesce((payload->>'approve')::boolean,false));
 insert into public.reviews(submission_id,reviewer_id,decision,feedback) values(s.id,actor,case when coalesce((payload->>'approve')::boolean,false) then 'approved' else 'changes_requested' end,body);
 update public.tasks set status=case when (payload->>'approve')::boolean then 'done' else 'needs_revision' end,version=version+1 where id=tid;
 when 'sendMessage','retryMessage' then
 tid:=nullif(payload->>'taskID','')::uuid;
 if tid is not null then select q.* into p from public.tasks x join public.projects q on q.id=x.project_id where x.id=tid and q.group_id=gid;
 if p.id is null then raise exception 'forbidden';end if;if p.status<>'active' or p.archived_at is not null then raise exception 'project_read_only';end if;end if;
 mid:=(payload->>'clientID')::uuid;if mid is null then raise exception 'invalid_input';end if;
 select * into old from public.chat_messages where sender_id=actor and client_id=mid;
 if old.id is not null then if old.group_id<>gid or old.task_id is distinct from tid then raise exception 'invalid_input';end if;return jsonb_build_object('id',old.id);end if;
 if (select count(*) from public.chat_messages where sender_id=actor and group_id=gid and kind='text' and created_at>now()-interval '1 minute')>=30 then raise exception 'rate_limited';end if;
 insert into public.chat_messages(id,group_id,task_id,sender_id,content,client_id) values(mid,gid,tid,actor,private.txt(payload->>'text',2000),mid);return jsonb_build_object('id',mid);
 when 'generateInvite' then
 if (select count(*) from private.invitations where group_id=gid and created_at>now()-interval '1 minute')>=10 then raise exception 'rate_limited';end if;
 uses:=coalesce((payload->>'maxUses')::integer,1);
 if uses<>1 and (uses<1 or uses>200 or not exists(select 1 from public.organizations where id=g.organization_id and plan_expires_at>now())) then raise exception 'invalid_input';end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');insert into private.invitations(group_id,token_hash,max_uses) values(gid,extensions.digest(token,'sha256'),uses) returning * into inv;
 return jsonb_build_object('id',inv.id,'invite',jsonb_build_object('id',inv.id,'groupID',gid,'code',token,'createdAt',private.iso(inv.created_at),'expiresAt',private.iso(inv.expires_at),'maxUses',inv.max_uses,'useCount',inv.used_count,'revoked',false));
 when 'revokeInvite' then update private.invitations set revoked_at=now() where id=(payload->>'id')::uuid;
 when 'transferCoordinator' then
 target:=coalesce(payload->>'to',payload->>'userID')::uuid;
 if target=actor or not exists(select 1 from public.group_members where group_id=gid and user_id=target) then raise exception 'invalid_input';end if;update public.groups set coordinator_id=target where id=gid;
 when 'removeMember','leaveGroup' then
 target:=case when action='leaveGroup' then actor else (payload->>'userID')::uuid end;
 if target=g.coordinator_id then raise exception 'coordinator_transfer_required';end if;
 if not exists(select 1 from public.group_members where group_id=gid and user_id=target) then raise exception 'forbidden';end if;
 if exists(select 1 from public.tasks x join public.projects q on q.id=x.project_id where q.group_id=gid and x.status<>'done' and (x.assignee_id=target or x.reviewer_id=target)) then raise exception 'active_assignment';end if;
 delete from public.group_members where group_id=gid and user_id=target;
 when 'reportMessage' then
 if (select count(*) from private.content_reports where reporter_id=actor and created_at>now()-interval '1 minute')>=5 then raise exception 'rate_limited';end if;
 insert into private.content_reports(message_id,reporter_id,reason) values((payload->>'id')::uuid,actor,private.txt(payload->>'reason',1000));
 when 'markChatRead' then
 if payload ? 'messageIDs' then
 if jsonb_typeof(payload->'messageIDs') <> 'array' then raise exception 'invalid_input';end if;
 if exists(select 1 from jsonb_array_elements(payload->'messageIDs') item where jsonb_typeof(item)<>'string' or (item#>>'{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'invalid_input';end if;
 insert into public.chat_reads select actor,id from public.chat_messages where group_id=gid and task_id is null and id in (select value::uuid from jsonb_array_elements_text(payload->'messageIDs')) on conflict do nothing;
 else
 insert into public.chat_reads select actor,id from public.chat_messages where group_id=gid on conflict do nothing;
 end if;
 else raise exception 'invalid_input';
 end case;
 insert into public.activity_events(group_id,actor_id,action,target_id) values(gid,actor,action,coalesce(tid,pid,target));
 if tid is not null and action in ('createTask','updateTask','reassignTask','submitWork','review','reopenTask') then
 body:=case action when 'createTask' then 'Membuat tugas' when 'updateTask' then 'Mengubah detail tugas' when 'reassignTask' then 'Mengalihkan tugas' when 'submitWork' then 'Mengirim hasil' when 'review' then case when (payload->>'approve')::boolean then 'Menyetujui tugas' else 'Meminta revisi' end else 'Membuka kembali tugas' end;
 insert into public.chat_messages(group_id,task_id,sender_id,content,kind) values(gid,null,actor,body||' · '||(select title from public.tasks where id=tid),'activity'),(gid,tid,actor,body,'activity');end if;
 return case when result_id is null then '{}'::jsonb else jsonb_build_object('id',result_id) end;
end$function$;

-- Copied from 20261017060000; changed: organization dispatch, deleteAccount organization locks.
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
EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_input';
END;
$$;

-- Copied from 20261017070000; changed: groups.organizationID, organizations.
CREATE OR REPLACE FUNCTION private.snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
 SELECT jsonb_build_object(
 'currentUserID',actor,
 'users',coalesce((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'email','','tint',u.tint) ORDER BY u.name) FROM public.profiles u WHERE private.profile_visible(u.id)),'[]'),
 'groups',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'course',g.course,'coordinatorID',coalesce(g.coordinator_id::text,''),'tint',g.tint,'icon',g.icon,'organizationID',coalesce(g.organization_id::text,''),'memberIDs',(SELECT jsonb_agg(user_id ORDER BY user_id) FROM public.group_members WHERE group_id=g.id))) FROM public.groups g WHERE private.member(g.id)),'[]'),
 'projects',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'groupID',p.group_id,'title',p.title,'description',p.description,'dueAt',private.iso(p.due_at),'status',CASE WHEN p.archived_at IS NOT NULL THEN 'archived' ELSE p.status END,'previousStatus',CASE WHEN p.archived_at IS NOT NULL THEN p.status ELSE NULL END)) FROM public.projects p WHERE private.member(p.group_id)),'[]'),
 'tasks',coalesce((SELECT jsonb_agg(jsonb_build_object('id',t.id,'projectID',t.project_id,'title',t.title,'description',t.description,'assigneeID',coalesce(t.assignee_id::text,''),'reviewerID',coalesce(t.reviewer_id::text,''),'dueAt',private.iso(t.due_at),'status',t.status,'version',t.version,'submissions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'revision',s.revision,'authorID',coalesce(s.author_id::text,''),'note',s.note,'links',s.links,'createdAt',private.iso(s.created_at),'decision',r.decision,'feedback',r.feedback,'reviewerID',coalesce(r.reviewer_id::text,'')) ORDER BY s.revision) FROM public.submissions s LEFT JOIN public.reviews r ON r.submission_id=s.id WHERE s.task_id=t.id),'[]'))) FROM public.tasks t WHERE private.task_group(t.id) IS NOT NULL),'[]'),
 'messages',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'groupID',m.group_id,'taskID',m.task_id,'senderID',coalesce(m.sender_id::text,''),'text',m.content,'createdAt',private.iso(m.created_at),'kind',m.kind,'delivery','sent','targetTaskID',CASE WHEN m.kind='activity' THEN m.task_id ELSE NULL END) ORDER BY m.created_at,m.id) FROM public.chat_messages m WHERE private.member(m.group_id)),'[]'),
 'invites',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'groupID',i.group_id,'code','','createdAt',private.iso(i.created_at),'expiresAt',private.iso(i.expires_at),'maxUses',i.max_uses,'useCount',i.used_count,'revoked',i.revoked_at IS NOT NULL)) FROM private.invitations i JOIN public.groups g ON g.id=i.group_id WHERE g.coordinator_id=actor),'[]'),
 'reports',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'messageID',r.message_id,'reporterID',r.reporter_id,'reason',r.reason,'createdAt',private.iso(r.created_at),'status',r.status,'reviewedAt',private.iso(r.reviewed_at))) FROM private.content_reports r WHERE r.reporter_id=actor),'[]'),
 'organizations',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'description',o.description,'periodLabel',o.period_label,'planActive',coalesce(o.plan_expires_at>now(),false),'planExpiresAt',private.iso(o.plan_expires_at),'seatLimit',o.seat_limit,'seatsUsed',private.org_seats(o.id),'myRole',(SELECT r.role FROM public.organization_roles r WHERE r.organization_id=o.id AND r.user_id=actor),'roles',coalesce((SELECT jsonb_agg(jsonb_build_object('userID',r.user_id,'role',r.role,'name',CASE WHEN EXISTS(SELECT 1 FROM public.user_blocks b WHERE b.user_id=actor AND b.blocked_id=r.user_id) THEN 'Anggota' ELSE p.name END) ORDER BY CASE r.role WHEN 'ketua' THEN 0 WHEN 'bph' THEN 1 ELSE 2 END,p.name,p.id) FROM public.organization_roles r JOIN public.profiles p ON p.id=r.user_id WHERE r.organization_id=o.id),'[]'),'divisions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'memberCount',d.members,'isMember',d.mine) ORDER BY d.name,d.id) FROM (SELECT g.id,g.name,count(m.user_id) AS members,bool_or(m.user_id=actor) AS mine FROM public.groups g JOIN public.group_members m ON m.group_id=g.id WHERE g.organization_id=o.id GROUP BY g.id,g.name) d),'[]')) ORDER BY o.name,o.id) FROM public.organizations o WHERE private.org_member(o.id,actor)),'[]'),
 'blockedUserIDs',coalesce((SELECT jsonb_agg(blocked_id) FROM public.user_blocks WHERE user_id=actor),'[]'),
 'readMessageIDs',coalesce((SELECT jsonb_agg(r.message_id) FROM public.chat_reads r JOIN public.chat_messages m ON m.id=r.message_id WHERE r.user_id=actor AND m.task_id IS NULL AND private.member(m.group_id)),'[]')) INTO result;
 RETURN result;
END;
$$;

NOTIFY pgrst, 'reload schema';
