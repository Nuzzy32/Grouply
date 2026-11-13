-- Organization Plan Tahap 2 (docs/DESIGN-org-tahap2.md): committees, project leads, meetings,
-- multi-step approvals, announcements. Lock order unchanged on every path:
-- profile -> groups (by id) -> organizations (by id, FOR NO KEY UPDATE) -> user_sync_state (by user_id).
SET local check_function_bodies = off;

ALTER TABLE public.groups
  ADD COLUMN is_committee boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT groups_committee_in_org CHECK (NOT is_committee OR organization_id IS NOT NULL);

ALTER TABLE public.projects ADD COLUMN lead_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
CREATE INDEX projects_lead ON public.projects(lead_id) WHERE lead_id IS NOT NULL;

CREATE TABLE public.meetings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id),
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  note_taker_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  title text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
  starts_at timestamptz NOT NULL,
  place text NOT NULL DEFAULT '' CHECK (length(place) <= 200),
  agenda text NOT NULL DEFAULT '' CHECK (length(agenda) <= 5000),
  minutes text NOT NULL DEFAULT '' CHECK (length(minutes) <= 20000),
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','done','cancelled')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX meetings_group ON public.meetings(group_id, starts_at);
CREATE INDEX meetings_created_by ON public.meetings(created_by);
CREATE INDEX meetings_note_taker ON public.meetings(note_taker_id);

CREATE TABLE public.meeting_attendance (
  meeting_id uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('hadir','izin')),
  PRIMARY KEY (meeting_id, user_id)
);
CREATE INDEX meeting_attendance_user ON public.meeting_attendance(user_id);

ALTER TABLE public.tasks ADD COLUMN meeting_id uuid REFERENCES public.meetings(id) ON DELETE SET NULL;
CREATE INDEX tasks_meeting ON public.tasks(meeting_id) WHERE meeting_id IS NOT NULL;

CREATE TABLE public.approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  group_id uuid NOT NULL REFERENCES public.groups(id),
  requester_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  title text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
  note text NOT NULL CHECK (length(note) BETWEEN 1 AND 2000),
  amount bigint CHECK (amount BETWEEN 0 AND 999999999999),
  links jsonb NOT NULL DEFAULT '[]' CHECK (private.valid_links(links)),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled','lapsed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  CHECK ((status = 'pending') = (closed_at IS NULL))
);
CREATE INDEX approvals_org ON public.approvals(organization_id, status, created_at DESC);
CREATE INDEX approvals_group ON public.approvals(group_id);
CREATE INDEX approvals_requester ON public.approvals(requester_id);

CREATE TABLE public.approval_steps (
  approval_id uuid NOT NULL REFERENCES public.approvals(id) ON DELETE CASCADE,
  position smallint NOT NULL CHECK (position BETWEEN 1 AND 5),
  approver_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  decision text CHECK (decision IN ('approved','rejected')),
  note text NOT NULL DEFAULT '' CHECK (length(note) <= 1000),
  decided_at timestamptz,
  PRIMARY KEY (approval_id, position),
  UNIQUE (approval_id, approver_id),
  CHECK ((decision IS NULL) = (decided_at IS NULL)),
  CHECK (decision IS DISTINCT FROM 'rejected' OR length(note) > 0)
);
CREATE INDEX approval_steps_approver ON public.approval_steps(approver_id);

CREATE TABLE public.announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  group_id uuid REFERENCES public.groups(id),
  author_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  title text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
  body text NOT NULL CHECK (length(body) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX announcements_org ON public.announcements(organization_id, created_at DESC);
CREATE INDEX announcements_group ON public.announcements(group_id) WHERE group_id IS NOT NULL;
CREATE INDEX announcements_author ON public.announcements(author_id);

CREATE TABLE public.announcement_reads (
  announcement_id uuid NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (announcement_id, user_id)
);
CREATE INDEX announcement_reads_user ON public.announcement_reads(user_id);

-- No policies: only SECURITY DEFINER RPCs read or write these tables.
ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcement_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.meetings, public.meeting_attendance, public.approvals, public.approval_steps,
  public.announcements, public.announcement_reads FROM PUBLIC, anon, authenticated;

CREATE FUNCTION private.org_active(org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce((SELECT plan_expires_at > now() FROM public.organizations WHERE id = org), false);
$$;

-- Bumps sync rows in user_id order (callers already hold their group/organization locks).
CREATE FUNCTION private.touch_users(ids uuid[])
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO public.user_sync_state AS state(user_id)
    SELECT DISTINCT u FROM unnest(ids) AS u WHERE u IS NOT NULL ORDER BY u
  ON CONFLICT(user_id) DO UPDATE SET revision = state.revision + 1;
$$;

-- Display name for organization-level lists; users only carries people who share a group.
CREATE FUNCTION private.org_name(uid uuid, viewer uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT CASE WHEN uid IS NULL THEN 'Anggota terhapus'
    WHEN EXISTS(SELECT 1 FROM public.user_blocks b WHERE b.user_id = viewer AND b.blocked_id = uid) THEN 'Anggota'
    ELSE coalesce((SELECT name FROM public.profiles WHERE id = uid), 'Anggota terhapus') END;
$$;

-- An approver may decide only while still an officer or the origin group's coordinator.
CREATE FUNCTION private.approval_eligible(org uuid, gid uuid, uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT uid IS NOT NULL AND (
    EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = org AND user_id = uid)
    OR EXISTS(SELECT 1 FROM public.groups WHERE id = gid AND coordinator_id = uid));
$$;

CREATE FUNCTION private.approval_touch(aid uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.touch_users(ARRAY(
    SELECT a.requester_id FROM public.approvals a WHERE a.id = aid
    UNION SELECT s.approver_id FROM public.approval_steps s WHERE s.approval_id = aid
    UNION SELECT r.user_id FROM public.approvals a JOIN public.organization_roles r ON r.organization_id = a.organization_id WHERE a.id = aid
    UNION SELECT g.coordinator_id FROM public.approvals a JOIN public.groups g ON g.id = a.group_id WHERE a.id = aid));
$$;

-- Current recipients: every member of the organization, or of the target group.
CREATE FUNCTION private.announcement_audience(aid uuid)
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT DISTINCT m.user_id FROM public.announcements n
    JOIN public.groups g ON g.organization_id = n.organization_id AND (n.group_id IS NULL OR g.id = n.group_id)
    JOIN public.group_members m ON m.group_id = g.id
  WHERE n.id = aid;
$$;

CREATE FUNCTION private.org_approvals(org uuid, viewer uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH visible AS (
    SELECT a.* FROM public.approvals a JOIN public.groups g ON g.id = a.group_id
    WHERE a.organization_id = org AND (a.requester_id = viewer OR g.coordinator_id = viewer
      OR EXISTS(SELECT 1 FROM public.organization_roles r WHERE r.organization_id = org AND r.user_id = viewer))
  ), picked AS (
    (SELECT * FROM visible WHERE status = 'pending' ORDER BY created_at, id LIMIT 100)
    UNION ALL
    (SELECT * FROM visible WHERE status <> 'pending' ORDER BY closed_at DESC, id LIMIT 30)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'groupID', a.group_id, 'groupName', g.name,
      'title', a.title, 'note', a.note, 'amount', a.amount, 'links', a.links, 'status', a.status,
      'createdAt', private.iso(a.created_at), 'closedAt', private.iso(a.closed_at),
      'requesterID', coalesce(a.requester_id::text, ''), 'requesterName', private.org_name(a.requester_id, viewer),
      'steps', coalesce((SELECT jsonb_agg(jsonb_build_object('position', s.position, 'approverID', coalesce(s.approver_id::text, ''),
          'name', private.org_name(s.approver_id, viewer),
          'eligible', private.approval_eligible(a.organization_id, a.group_id, s.approver_id),
          'decision', s.decision, 'note', s.note, 'decidedAt', private.iso(s.decided_at)) ORDER BY s.position)
        FROM public.approval_steps s WHERE s.approval_id = a.id), '[]'))
    ORDER BY a.status <> 'pending', a.created_at DESC, a.id), '[]')
  FROM picked a JOIN public.groups g ON g.id = a.group_id;
$$;

CREATE FUNCTION private.org_announcements(org uuid, viewer uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH mine AS (
    SELECT EXISTS(SELECT 1 FROM public.organization_roles r WHERE r.organization_id = org AND r.user_id = viewer) AS officer,
      EXISTS(SELECT 1 FROM public.groups g WHERE g.organization_id = org AND g.coordinator_id = viewer) AS coord
  ), picked AS (
    SELECT n.* FROM public.announcements n
    WHERE n.organization_id = org AND (n.group_id IS NULL
      OR EXISTS(SELECT 1 FROM public.group_members m WHERE m.group_id = n.group_id AND m.user_id = viewer))
    ORDER BY n.created_at DESC, n.id LIMIT 30
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'groupID', coalesce(n.group_id::text, ''),
      'title', n.title, 'body', n.body, 'createdAt', private.iso(n.created_at),
      'authorID', coalesce(n.author_id::text, ''), 'authorName', private.org_name(n.author_id, viewer),
      'read', EXISTS(SELECT 1 FROM public.announcement_reads r WHERE r.announcement_id = n.id AND r.user_id = viewer),
      'readCount', CASE WHEN coalesce(n.author_id = viewer, false) OR mine.officer THEN
          (SELECT count(*) FROM private.announcement_audience(n.id) AS x(uid)
            JOIN public.announcement_reads r ON r.announcement_id = n.id AND r.user_id = x.uid) ELSE 0 END,
      'audienceCount', CASE WHEN coalesce(n.author_id = viewer, false) OR mine.officer THEN
          (SELECT count(*) FROM private.announcement_audience(n.id)) ELSE 0 END,
      'unreadIDs', CASE WHEN coalesce(n.author_id = viewer, false) OR mine.officer OR mine.coord THEN
          coalesce((SELECT jsonb_agg(x.uid ORDER BY x.uid) FROM private.announcement_audience(n.id) AS x(uid)
            WHERE x.uid <> viewer
              AND NOT EXISTS(SELECT 1 FROM public.announcement_reads r WHERE r.announcement_id = n.id AND r.user_id = x.uid)
              AND EXISTS(SELECT 1 FROM public.group_members a JOIN public.group_members b ON b.group_id = a.group_id
                WHERE a.user_id = viewer AND b.user_id = x.uid)), '[]') ELSE '[]' END)
    ORDER BY n.created_at DESC, n.id), '[]')
  FROM picked n, mine;
$$;

-- Recent and upcoming meetings of the viewer's groups; older ones capped at 100.
CREATE FUNCTION private.my_meetings(viewer uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH mine AS (
    SELECT m.* FROM public.meetings m
    WHERE EXISTS(SELECT 1 FROM public.group_members x WHERE x.group_id = m.group_id AND x.user_id = viewer)
  ), picked AS (
    (SELECT * FROM mine WHERE starts_at >= now() - interval '30 days')
    UNION ALL
    (SELECT * FROM mine WHERE starts_at < now() - interval '30 days' ORDER BY starts_at DESC, id LIMIT 100)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'groupID', m.group_id, 'title', m.title,
      'startsAt', private.iso(m.starts_at), 'place', m.place, 'status', m.status, 'version', m.version,
      'createdBy', coalesce(m.created_by::text, ''), 'noteTakerID', coalesce(m.note_taker_id::text, ''),
      'hasMinutes', m.minutes <> '',
      'present', (SELECT count(*) FROM public.meeting_attendance a WHERE a.meeting_id = m.id AND a.status = 'hadir'),
      'excused', (SELECT count(*) FROM public.meeting_attendance a WHERE a.meeting_id = m.id AND a.status = 'izin'),
      'myStatus', coalesce((SELECT a.status FROM public.meeting_attendance a WHERE a.meeting_id = m.id AND a.user_id = viewer), ''),
      'taskIDs', coalesce((SELECT jsonb_agg(t.id ORDER BY t.id) FROM public.tasks t WHERE t.meeting_id = m.id), '[]'))
    ORDER BY m.starts_at, m.id), '[]')
  FROM picked m;
$$;

CREATE FUNCTION private.meeting_detail(mid uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); m public.meetings;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  SELECT * INTO m FROM public.meetings WHERE id = mid;
  IF m.id IS NULL OR NOT private.member(m.group_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN jsonb_build_object('id', m.id, 'version', m.version, 'agenda', m.agenda, 'minutes', m.minutes,
    'attendance', coalesce((SELECT jsonb_agg(jsonb_build_object('userID', a.user_id, 'status', a.status) ORDER BY a.user_id)
      FROM public.meeting_attendance a WHERE a.meeting_id = m.id), '[]'));
END;
$$;
REVOKE ALL ON FUNCTION private.meeting_detail(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.meeting_detail(uuid) TO authenticated;

CREATE FUNCTION public.grouply_meeting(meeting_id uuid)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$ SELECT private.meeting_detail(meeting_id) $$;
REVOKE ALL ON FUNCTION public.grouply_meeting(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.grouply_meeting(uuid) TO authenticated;

CREATE FUNCTION private.mutate_orgwork(action text, payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); g public.groups; o public.organizations; p public.projects; m public.meetings;
  a public.approvals; n public.announcements; gid uuid; target uuid; result_id uuid; link_data jsonb; att jsonb;
  ids uuid[]; pos integer; amt bigint; approve boolean; body text;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;

  IF action = 'setProjectLead' THEN
    SELECT group_id INTO gid FROM public.projects WHERE id = (payload->>'projectID')::uuid;
    SELECT * INTO g FROM public.groups WHERE id = gid FOR UPDATE;
    IF g.id IS NULL OR NOT private.member(g.id) OR g.coordinator_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF g.organization_id IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    SELECT * INTO p FROM public.projects WHERE id = (payload->>'projectID')::uuid FOR UPDATE;
    target := nullif(payload->>'userID', '')::uuid;
    IF target IS NOT NULL THEN
      IF NOT private.org_active(g.organization_id) THEN RAISE EXCEPTION 'plan_inactive'; END IF;
      IF p.archived_at IS NOT NULL OR p.status <> 'active' THEN RAISE EXCEPTION 'project_read_only'; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.group_members WHERE group_id = g.id AND user_id = target) THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
    END IF;
    UPDATE public.projects SET lead_id = target WHERE id = p.id;
    INSERT INTO public.activity_events(group_id, actor_id, action, target_id) VALUES (g.id, actor, action, p.id);
    IF target IS NOT NULL THEN
      INSERT INTO public.chat_messages(group_id, sender_id, content, kind)
        VALUES (g.id, actor, 'Menunjuk koordinator sie · ' || p.title, 'activity');
    END IF;
    RETURN '{}'::jsonb;
  END IF;

  IF action IN ('createMeeting','updateMeeting','cancelMeeting','recordMeeting') THEN
    IF action = 'createMeeting' THEN gid := (payload->>'groupID')::uuid;
    ELSE SELECT group_id INTO gid FROM public.meetings WHERE id = (payload->>'id')::uuid; END IF;
    SELECT * INTO g FROM public.groups WHERE id = gid FOR UPDATE;
    IF g.id IS NULL OR NOT private.member(g.id) THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF action <> 'createMeeting' THEN
      SELECT * INTO m FROM public.meetings WHERE id = (payload->>'id')::uuid FOR UPDATE;
    END IF;
    IF g.coordinator_id IS DISTINCT FROM actor
        AND NOT coalesce(action = 'recordMeeting' AND m.note_taker_id = actor, false) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    IF action = 'createMeeting' THEN
      IF g.organization_id IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
      IF NOT private.org_active(g.organization_id) THEN RAISE EXCEPTION 'plan_inactive'; END IF;
    ELSIF (action IN ('updateMeeting','cancelMeeting') AND m.status <> 'scheduled')
        OR (action = 'recordMeeting' AND m.status = 'cancelled') THEN
      RAISE EXCEPTION 'meeting_closed';
    ELSIF payload->>'expectedVersion' IS NULL OR (payload->>'expectedVersion')::integer <> m.version THEN
      RAISE EXCEPTION 'stale_version';
    END IF;
    IF (SELECT count(*) FROM public.activity_events e WHERE e.group_id = g.id
        AND e.action IN ('createMeeting','updateMeeting','cancelMeeting','recordMeeting')
        AND e.created_at > now() - interval '1 hour') >= 30 THEN
      RAISE EXCEPTION 'rate_limited';
    END IF;
    IF action IN ('createMeeting','updateMeeting') THEN
      target := nullif(payload->>'noteTakerID', '')::uuid;
      IF target IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.group_members WHERE group_id = g.id AND user_id = target) THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      IF (payload->>'startsAt')::timestamptz IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
      IF action = 'createMeeting' THEN
        INSERT INTO public.meetings(group_id, created_by, note_taker_id, title, starts_at, place, agenda)
          VALUES (g.id, actor, target, private.txt(payload->>'title', 120), (payload->>'startsAt')::timestamptz,
            private.txt(payload->>'place', 200, false), private.txt(payload->>'agenda', 5000, false))
          RETURNING * INTO m;
        result_id := m.id;
        body := 'Menjadwalkan rapat';
      ELSE
        -- Only changes members act on post to chat (activity messages count as unread).
        IF m.starts_at <> (payload->>'startsAt')::timestamptz OR m.place <> private.txt(payload->>'place', 200, false) THEN
          body := 'Mengubah jadwal rapat';
        END IF;
        UPDATE public.meetings SET title = private.txt(payload->>'title', 120),
          starts_at = (payload->>'startsAt')::timestamptz, place = private.txt(payload->>'place', 200, false),
          agenda = private.txt(payload->>'agenda', 5000, false), note_taker_id = target, version = version + 1
          WHERE id = m.id RETURNING * INTO m;
      END IF;
    ELSIF action = 'cancelMeeting' THEN
      UPDATE public.meetings SET status = 'cancelled', version = version + 1 WHERE id = m.id RETURNING * INTO m;
      body := 'Membatalkan rapat';
    ELSE
      IF m.starts_at > now() THEN RAISE EXCEPTION 'invalid_input'; END IF;
      att := coalesce(payload->'attendance', '[]'::jsonb);
      IF jsonb_typeof(att) <> 'array' OR jsonb_array_length(att) > 500
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(att) AS e(v) WHERE jsonb_typeof(e.v) <> 'object'
          OR jsonb_typeof(e.v->'userID') IS DISTINCT FROM 'string'
          OR (e.v->>'status') IS NULL OR (e.v->>'status') NOT IN ('hadir','izin')) THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      IF (SELECT count(*) <> count(DISTINCT (e.v->>'userID')::uuid) FROM jsonb_array_elements(att) AS e(v)) THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      -- New entries must be current members; rows of people who already left stay as recorded.
      IF EXISTS(SELECT 1 FROM jsonb_array_elements(att) AS e(v)
          WHERE NOT EXISTS(SELECT 1 FROM public.group_members x WHERE x.group_id = g.id AND x.user_id = (e.v->>'userID')::uuid)
            AND NOT EXISTS(SELECT 1 FROM public.meeting_attendance y WHERE y.meeting_id = m.id AND y.user_id = (e.v->>'userID')::uuid)) THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      DELETE FROM public.meeting_attendance y WHERE y.meeting_id = m.id
        AND EXISTS(SELECT 1 FROM public.group_members x WHERE x.group_id = g.id AND x.user_id = y.user_id);
      INSERT INTO public.meeting_attendance(meeting_id, user_id, status)
        SELECT m.id, (e.v->>'userID')::uuid, e.v->>'status' FROM jsonb_array_elements(att) AS e(v)
        ON CONFLICT (meeting_id, user_id) DO UPDATE SET status = excluded.status;
      IF m.status = 'scheduled' THEN body := 'Mencatat notulen rapat'; END IF;
      UPDATE public.meetings SET minutes = private.txt(payload->>'minutes', 20000, false), status = 'done',
        version = version + 1 WHERE id = m.id RETURNING * INTO m;
    END IF;
    INSERT INTO public.activity_events(group_id, actor_id, action, target_id) VALUES (g.id, actor, action, m.id);
    IF body IS NOT NULL THEN
      INSERT INTO public.chat_messages(group_id, sender_id, content, kind) VALUES (g.id, actor, body || ' · ' || m.title, 'activity');
    END IF;
    RETURN CASE WHEN result_id IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('id', result_id) END;
  END IF;

  IF action IN ('requestApproval','decideApproval','cancelApproval') THEN
    IF action = 'requestApproval' THEN gid := (payload->>'groupID')::uuid;
    ELSE SELECT group_id INTO gid FROM public.approvals WHERE id = (payload->>'id')::uuid; END IF;
    -- Origin group before organization: serializes with transferCoordinator and membership changes.
    SELECT * INTO g FROM public.groups WHERE id = gid FOR UPDATE;
    IF g.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF g.organization_id IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    SELECT * INTO o FROM public.organizations WHERE id = g.organization_id FOR NO KEY UPDATE;
    IF action = 'requestApproval' THEN
      IF NOT private.member(g.id) THEN RAISE EXCEPTION 'forbidden'; END IF;
      IF NOT coalesce(o.plan_expires_at > now(), false) THEN RAISE EXCEPTION 'plan_inactive'; END IF;
      IF (SELECT count(*) FROM public.approvals WHERE requester_id = actor AND status = 'pending') >= 5 THEN
        RAISE EXCEPTION 'rate_limited';
      END IF;
      link_data := coalesce(payload->'links', '[]'::jsonb);
      IF NOT private.valid_links(link_data) THEN RAISE EXCEPTION 'invalid_input'; END IF;
      amt := nullif(payload->>'amount', '')::bigint;
      IF amt < 0 OR amt > 999999999999 THEN RAISE EXCEPTION 'invalid_input'; END IF;
      IF jsonb_typeof(payload->'approverIDs') IS DISTINCT FROM 'array'
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'approverIDs') AS e(v) WHERE jsonb_typeof(e.v) <> 'string') THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      ids := ARRAY(SELECT (e.v #>> '{}')::uuid FROM jsonb_array_elements(payload->'approverIDs') WITH ORDINALITY AS e(v, i) ORDER BY e.i);
      IF cardinality(ids) NOT BETWEEN 1 AND 5 OR actor = ANY(ids)
        OR cardinality(ids) <> (SELECT count(DISTINCT x) FROM unnest(ids) AS x)
        OR EXISTS(SELECT 1 FROM unnest(ids) AS x WHERE NOT private.approval_eligible(o.id, g.id, x)) THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      INSERT INTO public.approvals(organization_id, group_id, requester_id, title, note, amount, links)
        VALUES (o.id, g.id, actor, private.txt(payload->>'title', 120), private.txt(payload->>'note', 2000), amt, link_data)
        RETURNING * INTO a;
      INSERT INTO public.approval_steps(approval_id, position, approver_id)
        SELECT a.id, u.i, u.x FROM unnest(ids) WITH ORDINALITY AS u(x, i);
      result_id := a.id;
    ELSE
      SELECT * INTO a FROM public.approvals WHERE id = (payload->>'id')::uuid;
      IF action = 'cancelApproval' THEN
        IF a.requester_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'forbidden'; END IF;
        IF a.status <> 'pending' THEN RAISE EXCEPTION 'approval_closed'; END IF;
        UPDATE public.approvals SET status = 'cancelled', closed_at = now() WHERE id = a.id;
      ELSE
        IF NOT EXISTS(SELECT 1 FROM public.approval_steps WHERE approval_id = a.id AND approver_id = actor) THEN
          RAISE EXCEPTION 'forbidden';
        END IF;
        IF a.status <> 'pending' THEN RAISE EXCEPTION 'approval_closed'; END IF;
        SELECT min(s.position) INTO pos FROM public.approval_steps s WHERE s.approval_id = a.id AND s.decision IS NULL;
        IF NOT EXISTS(SELECT 1 FROM public.approval_steps s WHERE s.approval_id = a.id AND s.position = pos AND s.approver_id = actor)
          OR NOT private.approval_eligible(o.id, g.id, actor) THEN
          RAISE EXCEPTION 'forbidden';
        END IF;
        approve := (payload->>'approve')::boolean;
        IF approve IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
        body := private.txt(payload->>'note', 1000, NOT approve);
        UPDATE public.approval_steps s SET decision = CASE WHEN approve THEN 'approved' ELSE 'rejected' END,
          note = body, decided_at = now() WHERE s.approval_id = a.id AND s.position = pos;
        IF NOT approve THEN
          UPDATE public.approvals SET status = 'rejected', closed_at = now() WHERE id = a.id;
        ELSIF NOT EXISTS(SELECT 1 FROM public.approval_steps s WHERE s.approval_id = a.id AND s.decision IS NULL) THEN
          UPDATE public.approvals SET status = 'approved', closed_at = now() WHERE id = a.id;
        END IF;
      END IF;
    END IF;
    PERFORM private.approval_touch(a.id);
    RETURN CASE WHEN result_id IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('id', result_id) END;
  END IF;

  IF action = 'postAnnouncement' THEN
    gid := nullif(payload->>'groupID', '')::uuid;
    IF gid IS NOT NULL THEN
      SELECT * INTO g FROM public.groups WHERE id = gid FOR UPDATE;
      IF g.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
      IF g.organization_id IS DISTINCT FROM (payload->>'organizationID')::uuid THEN RAISE EXCEPTION 'invalid_input'; END IF;
      IF NOT private.member(g.id) OR g.coordinator_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'forbidden'; END IF;
      IF NOT private.org_active(g.organization_id) THEN RAISE EXCEPTION 'plan_inactive'; END IF;
      IF (SELECT count(*) FROM public.announcements WHERE group_id = g.id AND created_at > now() - interval '1 hour') >= 10 THEN
        RAISE EXCEPTION 'rate_limited';
      END IF;
    ELSE
      SELECT * INTO o FROM public.organizations WHERE id = (payload->>'organizationID')::uuid FOR NO KEY UPDATE;
      IF o.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.organization_roles
          WHERE organization_id = o.id AND user_id = actor AND role IN ('ketua','bph')) THEN
        RAISE EXCEPTION 'forbidden';
      END IF;
      IF NOT coalesce(o.plan_expires_at > now(), false) THEN RAISE EXCEPTION 'plan_inactive'; END IF;
      IF (SELECT count(*) FROM public.announcements WHERE organization_id = o.id AND group_id IS NULL
          AND created_at > now() - interval '1 hour') >= 5 THEN
        RAISE EXCEPTION 'rate_limited';
      END IF;
    END IF;
    INSERT INTO public.announcements(organization_id, group_id, author_id, title, body)
      VALUES (coalesce(g.organization_id, o.id), gid, actor, private.txt(payload->>'title', 120), private.txt(payload->>'body', 2000))
      RETURNING * INTO n;
    INSERT INTO public.announcement_reads(announcement_id, user_id) VALUES (n.id, actor);
    IF gid IS NULL THEN PERFORM private.org_touch(n.organization_id);
    ELSE PERFORM private.touch_users(ARRAY(SELECT user_id FROM public.group_members WHERE group_id = gid)); END IF;
    RETURN jsonb_build_object('id', n.id);
  END IF;

  IF action = 'deleteAnnouncement' THEN
    SELECT * INTO n FROM public.announcements WHERE id = (payload->>'id')::uuid;
    IF n.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF n.group_id IS NOT NULL THEN
      PERFORM 1 FROM public.groups WHERE id = n.group_id FOR UPDATE;
      IF n.author_id IS DISTINCT FROM actor OR NOT private.member(n.group_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
      ids := ARRAY(SELECT user_id FROM public.group_members WHERE group_id = n.group_id);
    ELSE
      PERFORM 1 FROM public.organizations WHERE id = n.organization_id FOR NO KEY UPDATE;
      IF NOT private.org_member(n.organization_id, actor) OR (n.author_id IS DISTINCT FROM actor
          AND NOT EXISTS(SELECT 1 FROM public.organization_roles
            WHERE organization_id = n.organization_id AND user_id = actor AND role = 'ketua')) THEN
        RAISE EXCEPTION 'forbidden';
      END IF;
    END IF;
    DELETE FROM public.announcements WHERE id = n.id;
    IF n.group_id IS NULL THEN PERFORM private.org_touch(n.organization_id); ELSE PERFORM private.touch_users(ids); END IF;
    RETURN '{}'::jsonb;
  END IF;

  IF action = 'markAnnouncementRead' THEN
    SELECT * INTO n FROM public.announcements WHERE id = (payload->>'id')::uuid;
    IF n.id IS NULL OR NOT EXISTS(SELECT 1 FROM private.announcement_audience(n.id) AS x(uid) WHERE x.uid = actor) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    INSERT INTO public.announcement_reads(announcement_id, user_id) VALUES (n.id, actor) ON CONFLICT DO NOTHING;
    IF FOUND THEN PERFORM private.touch_users(ARRAY[actor]); END IF;
    RETURN '{}'::jsonb;
  END IF;

  RAISE EXCEPTION 'invalid_input';
END;
$$;

-- Extends Tahap 1: clears project lead / note taker in the group being left, and lapses pending
-- approvals of someone who leaves the organization. Runs under the organization lock.
CREATE OR REPLACE FUNCTION private.org_membership_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE org uuid; held text;
BEGIN
  SELECT organization_id INTO org FROM public.groups WHERE id = OLD.group_id;
  IF org IS NULL THEN RETURN NULL; END IF;
  UPDATE public.projects SET lead_id = NULL WHERE group_id = OLD.group_id AND lead_id = OLD.user_id;
  UPDATE public.meetings SET note_taker_id = NULL WHERE group_id = OLD.group_id AND note_taker_id = OLD.user_id;
  -- Serialize with every membership/role change in this organization, then re-read.
  PERFORM 1 FROM public.organizations WHERE id = org FOR NO KEY UPDATE;
  IF private.org_member(org, OLD.user_id) THEN RETURN NULL; END IF;
  SELECT role INTO held FROM public.organization_roles WHERE organization_id = org AND user_id = OLD.user_id;
  IF held = 'ketua' AND private.org_seats(org) > 0 THEN RAISE EXCEPTION 'ketua_transfer_required'; END IF;
  IF held <> 'ketua' AND OLD.user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'org_role_holder'; END IF;
  DELETE FROM public.organization_roles WHERE organization_id = org AND user_id = OLD.user_id;
  -- No sync bump here (one sync batch per transaction); others see the change on their next snapshot.
  UPDATE public.approvals a SET status = 'lapsed', closed_at = now()
    WHERE a.organization_id = org AND a.status = 'pending' AND (a.requester_id = OLD.user_id
      OR EXISTS(SELECT 1 FROM public.approval_steps s WHERE s.approval_id = a.id AND s.approver_id = OLD.user_id AND s.decision IS NULL));
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION private.org_active(uuid), private.touch_users(uuid[]), private.org_name(uuid,uuid),
  private.approval_eligible(uuid,uuid,uuid), private.approval_touch(uuid), private.announcement_audience(uuid),
  private.org_approvals(uuid,uuid), private.org_announcements(uuid,uuid), private.my_meetings(uuid),
  private.mutate_orgwork(text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

-- Copied from 20261112071535; changed: createDivision committee flag and separate 30-committee limit.
CREATE OR REPLACE FUNCTION private.mutate_org(action text, payload jsonb)
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
        AND g.is_committee = coalesce((payload->>'committee')::boolean, false)
        AND EXISTS(SELECT 1 FROM public.group_members m WHERE m.group_id = g.id)) >= 30 THEN
      RAISE EXCEPTION 'invalid_input';
    END IF;
    INSERT INTO public.groups(name, description, coordinator_id, organization_id, is_committee)
      VALUES (private.txt(payload->>'name',80), private.txt(payload->>'description',1000,false), actor, org.id,
        coalesce((payload->>'committee')::boolean, false))
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

-- Copied from 20261112071535; changed: divisions[].isCommittee.
CREATE OR REPLACE FUNCTION private.org_overview(org_id uuid)
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
    SELECT g.id, g.name, g.coordinator_id, g.is_committee, count(m.user_id) AS members
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
    'divisions', coalesce((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'isCommittee', d.is_committee,
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

-- Copied from 20261112071535; changed: project lead may run task actions, createTask meetingID.
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
 if action in ('updateGroup','createProject','updateProject','createTask','updateTask','reassignTask','reopenTask','completeProject','reopenProject','archiveProject','restoreProject','generateInvite','revokeInvite','transferCoordinator','removeMember') and not is_coord and not coalesce(action in ('createTask','updateTask','reassignTask','reopenTask') and p.lead_id=actor,false) then raise exception 'forbidden';end if;
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
 if action='createTask' then mid:=nullif(payload->>'meetingID','')::uuid;if mid is not null and not exists(select 1 from public.meetings where id=mid and group_id=gid and status<>'cancelled') then raise exception 'invalid_input';end if;insert into public.tasks(project_id,title,description,assignee_id,reviewer_id,due_at,meeting_id) values(pid,private.txt(payload->>'title',120),private.txt(payload->>'description',2000,false),uid,rid,(payload->>'dueAt')::timestamptz,mid) returning id into tid;result_id:=tid;
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

-- Copied from 20261112071535; changed: Tahap 2 dispatch, date/number format errors -> invalid_input.
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

-- Copied from 20261112071535; changed: isCommittee, leadID, meetings, organizations[].approvals/announcements.
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
 'reports',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'messageID',r.message_id,'reporterID',r.reporter_id,'reason',r.reason,'createdAt',private.iso(r.created_at),'status',r.status,'reviewedAt',private.iso(r.reviewed_at))) FROM private.content_reports r WHERE r.reporter_id=actor),'[]'),
 'organizations',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'description',o.description,'periodLabel',o.period_label,'planActive',coalesce(o.plan_expires_at>now(),false),'planExpiresAt',private.iso(o.plan_expires_at),'seatLimit',o.seat_limit,'seatsUsed',private.org_seats(o.id),'approvals',private.org_approvals(o.id,actor),'announcements',private.org_announcements(o.id,actor),'myRole',(SELECT r.role FROM public.organization_roles r WHERE r.organization_id=o.id AND r.user_id=actor),'roles',coalesce((SELECT jsonb_agg(jsonb_build_object('userID',r.user_id,'role',r.role,'name',CASE WHEN EXISTS(SELECT 1 FROM public.user_blocks b WHERE b.user_id=actor AND b.blocked_id=r.user_id) THEN 'Anggota' ELSE p.name END) ORDER BY CASE r.role WHEN 'ketua' THEN 0 WHEN 'bph' THEN 1 ELSE 2 END,p.name,p.id) FROM public.organization_roles r JOIN public.profiles p ON p.id=r.user_id WHERE r.organization_id=o.id),'[]'),'divisions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'isCommittee',d.is_committee,'memberCount',d.members,'isMember',d.mine) ORDER BY d.name,d.id) FROM (SELECT g.id,g.name,g.is_committee,count(m.user_id) AS members,bool_or(m.user_id=actor) AS mine FROM public.groups g JOIN public.group_members m ON m.group_id=g.id WHERE g.organization_id=o.id GROUP BY g.id,g.name,g.is_committee) d),'[]')) ORDER BY o.name,o.id) FROM public.organizations o WHERE private.org_member(o.id,actor)),'[]'),
 'meetings',private.my_meetings(actor),
 'blockedUserIDs',coalesce((SELECT jsonb_agg(blocked_id) FROM public.user_blocks WHERE user_id=actor),'[]'),
 'readMessageIDs',coalesce((SELECT jsonb_agg(r.message_id) FROM public.chat_reads r JOIN public.chat_messages m ON m.id=r.message_id WHERE r.user_id=actor AND m.task_id IS NULL AND private.member(m.group_id)),'[]')) INTO result;
 RETURN result;
END;
$$;

NOTIFY pgrst, 'reload schema';
