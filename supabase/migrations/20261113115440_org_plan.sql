-- Organization Plan Tahap 3a (docs/DESIGN-org-tahap3.md): proker templates with plan items,
-- closed committees, period archive and handover, LPJ report data.
-- Lock order unchanged: profile -> groups (by id) -> organizations (by id, FOR NO KEY UPDATE)
-- -> report rows -> user_sync_state (by user_id).
SET local check_function_bodies = off;

CREATE TABLE public.proker_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES public.organizations(id),
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
  sections jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX proker_templates_org ON public.proker_templates(organization_id);
CREATE INDEX proker_templates_creator ON public.proker_templates(created_by);

CREATE TABLE public.project_plan_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id),
  position smallint NOT NULL CHECK (position BETWEEN 1 AND 40),
  title text NOT NULL CHECK (length(title) BETWEEN 3 AND 120),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 2000),
  due_at timestamptz NOT NULL,
  task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL,
  UNIQUE (project_id, position)
);
CREATE INDEX project_plan_items_task ON public.project_plan_items(task_id) WHERE task_id IS NOT NULL;

CREATE TABLE public.organization_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  label text NOT NULL CHECK (length(label) BETWEEN 1 AND 40),
  started_at timestamptz,
  closed_at timestamptz NOT NULL DEFAULT now(),
  closed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  UNIQUE (organization_id, label)
);
CREATE INDEX organization_periods_closer ON public.organization_periods(closed_by);

ALTER TABLE public.projects ADD COLUMN period_id uuid REFERENCES public.organization_periods(id);
CREATE INDEX projects_period ON public.projects(period_id) WHERE period_id IS NOT NULL;
ALTER TABLE public.groups ADD COLUMN closed_at timestamptz,
  ADD CONSTRAINT groups_closed_committee CHECK (closed_at IS NULL OR is_committee);

ALTER TABLE private.content_reports DROP CONSTRAINT content_reports_target_kind_check,
  ADD CONSTRAINT content_reports_target_kind_check
    CHECK (target_kind IN ('message','announcement','meeting','approval','template'));

ALTER TABLE public.proker_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_plan_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_periods ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.proker_templates, public.project_plan_items, public.organization_periods
  FROM PUBLIC, anon, authenticated;

-- One section or plan item of a template: {title, description?, offsetDays, items (sections only)}.
CREATE FUNCTION private.valid_plan_entry(e jsonb, section boolean)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE item jsonb; days numeric;
BEGIN
  IF jsonb_typeof(e) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(e) AS k(name)
      WHERE k.name NOT IN ('title','description','offsetDays','items') OR (k.name = 'items' AND NOT section)) THEN
    RETURN false;
  END IF;
  IF jsonb_typeof(e->'title') IS DISTINCT FROM 'string' OR length(btrim(e->>'title')) NOT BETWEEN 3 AND 120 THEN RETURN false; END IF;
  IF e ? 'description' AND (jsonb_typeof(e->'description') IS DISTINCT FROM 'string' OR length(e->>'description') > 2000) THEN
    RETURN false;
  END IF;
  IF jsonb_typeof(e->'offsetDays') IS DISTINCT FROM 'number' OR (e->>'offsetDays') !~ '^-?[0-9]+$' THEN RETURN false; END IF;
  days := (e->>'offsetDays')::numeric;
  IF days <> trunc(days) OR days NOT BETWEEN -365 AND 365 THEN RETURN false; END IF;
  IF section THEN
    IF jsonb_typeof(e->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(e->'items') > 40 THEN RETURN false; END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(e->'items') LOOP
      IF NOT private.valid_plan_entry(item, false) THEN RETURN false; END IF;
    END LOOP;
  END IF;
  RETURN true;
END;
$$;

CREATE FUNCTION private.valid_sections(s jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE sec jsonb; total integer := 0;
BEGIN
  IF jsonb_typeof(s) IS DISTINCT FROM 'array' OR jsonb_array_length(s) NOT BETWEEN 1 AND 20 THEN RETURN false; END IF;
  FOR sec IN SELECT value FROM jsonb_array_elements(s) LOOP
    IF NOT private.valid_plan_entry(sec, true) THEN RETURN false; END IF;
    total := total + jsonb_array_length(sec->'items');
  END LOOP;
  RETURN total <= 200;
END;
$$;

ALTER TABLE public.proker_templates ADD CONSTRAINT proker_templates_sections CHECK (private.valid_sections(sections));

-- Built-in templates: generic product content (no people, no sample records).
INSERT INTO public.proker_templates(organization_id, name, description, sections) VALUES
(NULL, 'Seminar', 'Seminar atau talkshow satu hari dengan pemateri tamu.', '[
  {"title":"Sie Acara","offsetDays":0,"items":[
    {"title":"Hubungi dan konfirmasi pemateri","offsetDays":-30},
    {"title":"Susun rundown acara","offsetDays":-21},
    {"title":"Siapkan MC dan moderator","offsetDays":-14},
    {"title":"Gladi bersih","offsetDays":-1}]},
  {"title":"Sie Publikasi","offsetDays":-1,"items":[
    {"title":"Desain poster dan materi media sosial","offsetDays":-21},
    {"title":"Buka pendaftaran peserta","offsetDays":-18},
    {"title":"Unggah publikasi berkala","offsetDays":-7},
    {"title":"Kirim pengingat ke peserta","offsetDays":-1}]},
  {"title":"Sie Dana dan Sponsor","offsetDays":-7,"items":[
    {"title":"Susun RAB dan ajukan ke bendahara","offsetDays":-35},
    {"title":"Kirim proposal sponsor","offsetDays":-28}]},
  {"title":"Sie Perlengkapan dan Konsumsi","offsetDays":0,"items":[
    {"title":"Pinjam ruangan","offsetDays":-28},
    {"title":"Pesan konsumsi","offsetDays":-7},
    {"title":"Cek sound system dan proyektor","offsetDays":-1}]},
  {"title":"Sie Dokumentasi dan LPJ","offsetDays":14,"items":[
    {"title":"Dokumentasi foto dan video acara","offsetDays":0},
    {"title":"Kumpulkan bukti pengeluaran","offsetDays":7},
    {"title":"Susun LPJ","offsetDays":14}]}
]'::jsonb),
(NULL, 'Lomba', 'Kompetisi dengan pendaftaran peserta, penjurian, dan pengumuman pemenang.', '[
  {"title":"Sie Acara dan Penjurian","offsetDays":0,"items":[
    {"title":"Susun aturan dan kriteria penilaian","offsetDays":-45},
    {"title":"Hubungi dan konfirmasi juri","offsetDays":-30},
    {"title":"Siapkan lembar penilaian","offsetDays":-7},
    {"title":"Rekap nilai dan tetapkan pemenang","offsetDays":0}]},
  {"title":"Sie Publikasi dan Pendaftaran","offsetDays":-7,"items":[
    {"title":"Desain poster lomba","offsetDays":-40},
    {"title":"Buka pendaftaran","offsetDays":-35},
    {"title":"Tutup pendaftaran dan verifikasi peserta","offsetDays":-10}]},
  {"title":"Sie Dana dan Hadiah","offsetDays":-7,"items":[
    {"title":"Susun RAB dan ajukan ke bendahara","offsetDays":-45},
    {"title":"Siapkan hadiah dan sertifikat","offsetDays":-7}]},
  {"title":"Sie Dokumentasi dan LPJ","offsetDays":14,"items":[
    {"title":"Dokumentasi acara","offsetDays":0},
    {"title":"Umumkan pemenang","offsetDays":1},
    {"title":"Susun LPJ","offsetDays":14}]}
]'::jsonb),
(NULL, 'Makrab', 'Malam keakraban atau acara menginap di luar kampus.', '[
  {"title":"Sie Acara","offsetDays":0,"items":[
    {"title":"Susun rundown dan games","offsetDays":-14},
    {"title":"Siapkan perlengkapan games","offsetDays":-3}]},
  {"title":"Sie Tempat dan Transportasi","offsetDays":-3,"items":[
    {"title":"Survei dan pesan lokasi","offsetDays":-30},
    {"title":"Pesan transportasi","offsetDays":-14},
    {"title":"Susun daftar kamar dan bus","offsetDays":-3}]},
  {"title":"Sie Konsumsi","offsetDays":-2,"items":[
    {"title":"Pilih menu dan vendor","offsetDays":-14},
    {"title":"Konfirmasi jumlah porsi","offsetDays":-2}]},
  {"title":"Sie Keamanan dan Kesehatan","offsetDays":-1,"items":[
    {"title":"Kumpulkan izin orang tua dan data kesehatan","offsetDays":-7},
    {"title":"Siapkan kotak P3K","offsetDays":-1}]},
  {"title":"Sie Dokumentasi dan LPJ","offsetDays":14,"items":[
    {"title":"Dokumentasi acara","offsetDays":0},
    {"title":"Susun LPJ","offsetDays":14}]}
]'::jsonb),
(NULL, 'Open recruitment', 'Rekrutmen anggota baru: pendaftaran, seleksi, dan pengumuman.', '[
  {"title":"Sie Publikasi","offsetDays":-14,"items":[
    {"title":"Desain poster open recruitment","offsetDays":-30},
    {"title":"Buka formulir pendaftaran","offsetDays":-28},
    {"title":"Tutup pendaftaran","offsetDays":-14}]},
  {"title":"Sie Seleksi","offsetDays":0,"items":[
    {"title":"Susun pertanyaan wawancara","offsetDays":-14},
    {"title":"Jadwalkan wawancara","offsetDays":-10},
    {"title":"Rekap hasil seleksi","offsetDays":-2}]},
  {"title":"Sie Pengumuman dan Onboarding","offsetDays":7,"items":[
    {"title":"Umumkan hasil seleksi","offsetDays":0},
    {"title":"Bagikan kode undangan divisi ke anggota baru","offsetDays":1},
    {"title":"Adakan pertemuan perdana","offsetDays":7}]}
]'::jsonb);

CREATE FUNCTION private.mutate_orgplan(action text, payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); g public.groups; o public.organizations; t public.proker_templates;
  item public.project_plan_items; p public.projects; target uuid; event_at timestamptz; sec jsonb; it jsonb;
  pos integer; new_project uuid; ids uuid[] := '{}'::uuid[]; locked uuid[]; next_label text; new_period uuid; archived integer;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;

  IF action = 'applyTemplate' THEN
    SELECT * INTO g FROM public.groups WHERE id = (payload->>'groupID')::uuid FOR UPDATE;
    IF g.id IS NULL OR NOT private.member(g.id) OR g.coordinator_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF g.organization_id IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    IF g.closed_at IS NOT NULL THEN RAISE EXCEPTION 'group_closed'; END IF;
    IF NOT private.org_active(g.organization_id) THEN RAISE EXCEPTION 'plan_inactive'; END IF;
    SELECT * INTO t FROM public.proker_templates WHERE id = (payload->>'templateID')::uuid
      AND (organization_id IS NULL OR organization_id = g.organization_id);
    IF t.id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    event_at := (payload->>'eventAt')::timestamptz;
    IF event_at IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    IF (SELECT count(*) FROM public.activity_events e WHERE e.group_id = g.id AND e.action = 'applyTemplate'
        AND e.created_at > now() - interval '1 hour') >= 5 THEN
      RAISE EXCEPTION 'rate_limited';
    END IF;
    FOR sec IN SELECT value FROM jsonb_array_elements(t.sections) WITH ORDINALITY AS s(value, n) ORDER BY s.n LOOP
      IF event_at + make_interval(days => (sec->>'offsetDays')::integer) <= now() THEN RAISE EXCEPTION 'invalid_input'; END IF;
      INSERT INTO public.projects(group_id, title, description, due_at)
        VALUES (g.id, private.txt(sec->>'title', 120), private.txt(sec->>'description', 2000, false),
          event_at + make_interval(days => (sec->>'offsetDays')::integer))
        RETURNING id INTO new_project;
      ids := ids || new_project;
      pos := 0;
      FOR it IN SELECT value FROM jsonb_array_elements(sec->'items') WITH ORDINALITY AS s(value, n) ORDER BY s.n LOOP
        pos := pos + 1;
        INSERT INTO public.project_plan_items(project_id, position, title, description, due_at)
          VALUES (new_project, pos, private.txt(it->>'title', 120), private.txt(it->>'description', 2000, false),
            event_at + make_interval(days => (it->>'offsetDays')::integer));
      END LOOP;
    END LOOP;
    INSERT INTO public.activity_events(group_id, actor_id, action, target_id) VALUES (g.id, actor, action, t.id);
    INSERT INTO public.chat_messages(group_id, sender_id, content, kind)
      VALUES (g.id, actor, 'Memakai template · ' || t.name, 'activity');
    RETURN jsonb_build_object('projectIDs', to_jsonb(ids));
  END IF;

  IF action IN ('createTemplate','deleteTemplate') THEN
    IF action = 'createTemplate' THEN
      SELECT * INTO o FROM public.organizations WHERE id = (payload->>'organizationID')::uuid FOR NO KEY UPDATE;
      IF o.id IS NULL OR NOT (
          EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = o.id AND user_id = actor AND role IN ('ketua','bph'))
          OR EXISTS(SELECT 1 FROM public.groups x JOIN public.group_members m ON m.group_id = x.id
            WHERE x.organization_id = o.id AND x.coordinator_id = actor AND m.user_id = actor)) THEN
        RAISE EXCEPTION 'forbidden';
      END IF;
      IF NOT coalesce(o.plan_expires_at > now(), false) THEN RAISE EXCEPTION 'plan_inactive'; END IF;
      IF (SELECT count(*) FROM public.proker_templates WHERE organization_id = o.id) >= 50 THEN RAISE EXCEPTION 'rate_limited'; END IF;
      IF NOT private.valid_sections(payload->'sections') THEN RAISE EXCEPTION 'invalid_input'; END IF;
      INSERT INTO public.proker_templates(organization_id, created_by, name, description, sections)
        VALUES (o.id, actor, private.txt(payload->>'name', 80), private.txt(payload->>'description', 1000, false), payload->'sections')
        RETURNING * INTO t;
      RETURN jsonb_build_object('id', t.id);
    END IF;
    SELECT * INTO t FROM public.proker_templates WHERE id = (payload->>'id')::uuid;
    IF t.id IS NULL OR t.organization_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    PERFORM 1 FROM public.organizations WHERE id = t.organization_id FOR NO KEY UPDATE;
    IF NOT private.org_member(t.organization_id, actor) OR (t.created_by IS DISTINCT FROM actor
        AND NOT EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = t.organization_id AND user_id = actor AND role = 'ketua')) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    DELETE FROM public.proker_templates WHERE id = t.id;
    RETURN '{}'::jsonb;
  END IF;

  IF action = 'deletePlanItem' THEN
    SELECT * INTO item FROM public.project_plan_items WHERE id = (payload->>'id')::uuid;
    SELECT * INTO p FROM public.projects WHERE id = item.project_id;
    SELECT * INTO g FROM public.groups WHERE id = p.group_id FOR UPDATE;
    IF g.id IS NULL OR NOT private.member(g.id) THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF g.closed_at IS NOT NULL THEN RAISE EXCEPTION 'group_closed'; END IF;
    SELECT * INTO p FROM public.projects WHERE id = p.id FOR UPDATE;
    IF g.coordinator_id IS DISTINCT FROM actor AND p.lead_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'forbidden'; END IF;
    SELECT * INTO item FROM public.project_plan_items WHERE id = item.id;
    IF item.task_id IS NOT NULL THEN RAISE EXCEPTION 'plan_item_used'; END IF;
    DELETE FROM public.project_plan_items WHERE id = item.id;
    PERFORM private.touch_users(ARRAY(SELECT user_id FROM public.group_members WHERE group_id = g.id));
    RETURN '{}'::jsonb;
  END IF;

  IF action IN ('closeCommittee','reopenCommittee','setCoordinator','removeClosedMember') THEN
    SELECT * INTO g FROM public.groups WHERE id = (payload->>'groupID')::uuid FOR UPDATE;
    IF g.id IS NULL OR g.organization_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    SELECT * INTO o FROM public.organizations WHERE id = g.organization_id FOR NO KEY UPDATE;
    IF action = 'closeCommittee' THEN
      IF NOT ((private.member(g.id) AND g.coordinator_id = actor)
          OR EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = o.id AND user_id = actor AND role = 'ketua')) THEN
        RAISE EXCEPTION 'forbidden';
      END IF;
      IF NOT g.is_committee OR g.closed_at IS NOT NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
      -- Nothing may stay open, archived projects included: otherwise members could never leave.
      IF EXISTS(SELECT 1 FROM public.tasks x JOIN public.projects q ON q.id = x.project_id WHERE q.group_id = g.id AND x.status <> 'done')
        OR EXISTS(SELECT 1 FROM public.projects q WHERE q.group_id = g.id AND q.status = 'active' AND q.archived_at IS NULL)
        OR EXISTS(SELECT 1 FROM public.approvals a WHERE a.group_id = g.id AND a.status = 'pending') THEN
        RAISE EXCEPTION 'committee_busy';
      END IF;
      UPDATE public.groups SET closed_at = now() WHERE id = g.id;
      UPDATE private.invitations SET revoked_at = now() WHERE group_id = g.id AND revoked_at IS NULL;
      UPDATE public.meetings SET status = 'cancelled', version = version + 1
        WHERE group_id = g.id AND status = 'scheduled' AND starts_at > now();
      INSERT INTO public.chat_messages(group_id, sender_id, content, kind) VALUES (g.id, actor, 'Menutup kepanitiaan', 'activity');
    ELSIF action = 'reopenCommittee' THEN
      IF NOT EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = o.id AND user_id = actor AND role = 'ketua') THEN
        RAISE EXCEPTION 'forbidden';
      END IF;
      IF g.closed_at IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
      IF NOT coalesce(o.plan_expires_at > now(), false) THEN RAISE EXCEPTION 'plan_inactive'; END IF;
      IF (SELECT count(*) FROM public.groups x WHERE x.organization_id = o.id AND x.is_committee AND x.closed_at IS NULL
          AND EXISTS(SELECT 1 FROM public.group_members m WHERE m.group_id = x.id)) >= 30 THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      UPDATE public.groups SET closed_at = NULL WHERE id = g.id;
      INSERT INTO public.chat_messages(group_id, sender_id, content, kind) VALUES (g.id, actor, 'Membuka kembali kepanitiaan', 'activity');
    ELSIF action = 'removeClosedMember' THEN
      -- Handover: frees seats held by people left only in a closed committee.
      IF NOT EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = o.id AND user_id = actor AND role = 'ketua') THEN
        RAISE EXCEPTION 'forbidden';
      END IF;
      IF g.closed_at IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
      target := (payload->>'userID')::uuid;
      IF target IS NULL OR NOT EXISTS(SELECT 1 FROM public.group_members WHERE group_id = g.id AND user_id = target) THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      IF target = g.coordinator_id THEN RAISE EXCEPTION 'coordinator_transfer_required'; END IF;
      DELETE FROM public.group_members WHERE group_id = g.id AND user_id = target;
    ELSE
      IF NOT EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = o.id AND user_id = actor AND role = 'ketua') THEN
        RAISE EXCEPTION 'forbidden';
      END IF;
      target := (payload->>'userID')::uuid;
      IF target IS NULL OR target = g.coordinator_id
        OR NOT EXISTS(SELECT 1 FROM public.group_members WHERE group_id = g.id AND user_id = target) THEN
        RAISE EXCEPTION 'invalid_input';
      END IF;
      UPDATE public.groups SET coordinator_id = target WHERE id = g.id;
      INSERT INTO public.chat_messages(group_id, sender_id, content, kind)
        VALUES (g.id, actor, 'Mengganti koordinator · ' || private.org_name(target, actor), 'activity');
    END IF;
    INSERT INTO public.activity_events(group_id, actor_id, action, target_id) VALUES (g.id, actor, action, coalesce(target, g.id));
    PERFORM private.org_touch(o.id);
    RETURN '{}'::jsonb;
  END IF;

  IF action = 'closePeriod' THEN
    -- Cheap role check first so an ordinary member cannot make us lock every group.
    IF NOT EXISTS(SELECT 1 FROM public.organization_roles
        WHERE organization_id = (payload->>'organizationID')::uuid AND user_id = actor AND role = 'ketua') THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    locked := ARRAY(SELECT x.id FROM public.groups x WHERE x.organization_id = (payload->>'organizationID')::uuid ORDER BY x.id FOR UPDATE);
    SELECT * INTO o FROM public.organizations WHERE id = (payload->>'organizationID')::uuid FOR NO KEY UPDATE;
    IF NOT EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = o.id AND user_id = actor AND role = 'ketua') THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    IF jsonb_typeof(payload->'currentLabel') IS DISTINCT FROM 'string' OR jsonb_typeof(payload->'nextLabel') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'invalid_input';
    END IF;
    IF o.period_label = '' THEN RAISE EXCEPTION 'invalid_input'; END IF;
    -- A retry after a lost response carries the old label and must not close the new period.
    IF btrim(payload->>'currentLabel') <> o.period_label THEN RAISE EXCEPTION 'stale_version'; END IF;
    next_label := private.txt(payload->>'nextLabel', 40);
    IF next_label = o.period_label THEN RAISE EXCEPTION 'invalid_input'; END IF;
    IF EXISTS(SELECT 1 FROM public.organization_periods WHERE organization_id = o.id AND label IN (o.period_label, next_label)) THEN
      RAISE EXCEPTION 'period_exists';
    END IF;
    INSERT INTO public.organization_periods(organization_id, label, started_at, closed_by)
      VALUES (o.id, o.period_label, (SELECT max(closed_at) FROM public.organization_periods WHERE organization_id = o.id), actor)
      RETURNING id INTO new_period;
    UPDATE public.projects SET archived_at = now()
      WHERE group_id = ANY(locked) AND status = 'completed' AND archived_at IS NULL;
    UPDATE public.projects q SET period_id = new_period
      WHERE q.group_id = ANY(locked) AND q.archived_at IS NOT NULL AND q.period_id IS NULL;
    GET DIAGNOSTICS archived = ROW_COUNT;
    UPDATE public.organizations SET period_label = next_label WHERE id = o.id;
    PERFORM private.org_touch(o.id);
    RETURN jsonb_build_object('periodID', new_period, 'archived', archived);
  END IF;

  RAISE EXCEPTION 'invalid_input';
END;
$$;

CREATE FUNCTION private.templates(org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid();
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT private.org_member(org_id, actor) THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'description', t.description,
      'builtIn', t.organization_id IS NULL, 'sectionCount', jsonb_array_length(t.sections),
      'itemCount', (SELECT coalesce(sum(jsonb_array_length(s->'items')), 0) FROM jsonb_array_elements(t.sections) s),
      'createdAt', private.iso(t.created_at), 'mine', coalesce(t.created_by = actor, false))
    ORDER BY t.organization_id IS NOT NULL, t.created_at, t.id)
    FROM public.proker_templates t WHERE t.organization_id IS NULL OR t.organization_id = templates.org_id), '[]');
END;
$$;

CREATE FUNCTION private.template(tid uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); t public.proker_templates;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  SELECT * INTO t FROM public.proker_templates WHERE id = tid;
  IF t.id IS NULL OR (t.organization_id IS NOT NULL AND NOT private.org_member(t.organization_id, actor))
    OR (t.organization_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.groups x JOIN public.group_members m ON m.group_id = x.id
      WHERE x.organization_id IS NOT NULL AND m.user_id = actor)) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN jsonb_build_object('id', t.id, 'name', t.name, 'description', t.description,
    'builtIn', t.organization_id IS NULL, 'sections', t.sections);
END;
$$;

CREATE FUNCTION private.org_members(org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid();
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.organization_roles r
      WHERE r.organization_id = org_members.org_id AND r.user_id = actor AND r.role = 'ketua') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('groupID', g.id, 'name', g.name, 'isCommittee', g.is_committee,
      'closed', g.closed_at IS NOT NULL, 'coordinatorID', coalesce(g.coordinator_id::text, ''),
      'members', coalesce((SELECT jsonb_agg(jsonb_build_object('id', m.user_id, 'name', private.org_name(m.user_id, actor))
          ORDER BY m.user_id) FROM public.group_members m WHERE m.group_id = g.id), '[]'))
    ORDER BY g.is_committee, g.name, g.id)
    FROM public.groups g WHERE g.organization_id = org_members.org_id), '[]');
END;
$$;

CREATE FUNCTION private.org_archive(org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid();
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.organization_roles r WHERE r.organization_id = org_archive.org_id AND r.user_id = actor) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN jsonb_build_object('periods', coalesce((SELECT jsonb_agg(jsonb_build_object('id', pr.id, 'label', pr.label,
      'startedAt', private.iso(pr.started_at), 'closedAt', private.iso(pr.closed_at),
      'projects', coalesce((SELECT jsonb_agg(jsonb_build_object('id', q.id, 'groupID', q.group_id, 'groupName', g.name,
          'title', q.title, 'dueAt', private.iso(q.due_at),
          'total', (SELECT count(*) FROM public.tasks x WHERE x.project_id = q.id),
          'done', (SELECT count(*) FROM public.tasks x WHERE x.project_id = q.id AND x.status = 'done'))
        ORDER BY g.name, q.due_at, q.id)
        FROM public.projects q JOIN public.groups g ON g.id = q.group_id WHERE q.period_id = pr.id), '[]'),
      'committees', coalesce((SELECT jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'closedAt', private.iso(g.closed_at))
          ORDER BY g.closed_at, g.id)
        FROM public.groups g WHERE g.organization_id = pr.organization_id AND g.closed_at IS NOT NULL
          AND g.closed_at <= pr.closed_at AND (pr.started_at IS NULL OR g.closed_at > pr.started_at)), '[]'))
    ORDER BY pr.closed_at DESC, pr.id)
    FROM public.organization_periods pr WHERE pr.organization_id = org_archive.org_id), '[]'));
END;
$$;

-- LPJ data for one group and one period; client renders PDF/CSV.
CREATE FUNCTION private.report(gid uuid, pid uuid, wanted uuid[])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); g public.groups; o public.organizations; pr public.organization_periods;
  full_access boolean; window_from timestamptz; window_to timestamptz; scope uuid[]; chosen uuid[]; lbl text;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  SELECT * INTO g FROM public.groups WHERE id = gid;
  IF g.id IS NULL OR g.organization_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO o FROM public.organizations WHERE id = g.organization_id;
  full_access := EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = o.id AND user_id = actor)
    OR (coalesce(g.coordinator_id = actor, false) AND private.member(g.id));
  IF pid IS NOT NULL THEN
    SELECT * INTO pr FROM public.organization_periods WHERE id = pid AND organization_id = o.id;
    IF pr.id IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
    window_from := coalesce(pr.started_at, '-infinity'); window_to := pr.closed_at; lbl := pr.label;
  ELSE
    window_from := coalesce((SELECT max(closed_at) FROM public.organization_periods WHERE organization_id = o.id), '-infinity');
    window_to := now(); lbl := o.period_label;
  END IF;
  scope := ARRAY(SELECT q.id FROM public.projects q WHERE q.group_id = g.id AND q.period_id IS NOT DISTINCT FROM pid
    AND (full_access OR (q.lead_id = actor AND private.member(g.id))) ORDER BY q.due_at DESC, q.id);
  IF NOT full_access AND cardinality(scope) = 0 THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF wanted IS NULL THEN chosen := scope[1:20];
  ELSE
    IF cardinality(wanted) > 20 OR EXISTS(SELECT 1 FROM unnest(wanted) w WHERE w <> ALL(scope)) THEN RAISE EXCEPTION 'forbidden'; END IF;
    chosen := wanted;
  END IF;
  RETURN jsonb_build_object(
    'generatedAt', private.iso(now()), 'organization', o.name, 'period', lbl,
    'group', jsonb_build_object('name', g.name, 'isCommittee', g.is_committee, 'coordinator', private.org_name(g.coordinator_id, actor)),
    'projects', coalesce((SELECT jsonb_agg(jsonb_build_object('id', q.id, 'title', q.title, 'dueAt', private.iso(q.due_at),
        'status', q.status, 'lead', CASE WHEN q.lead_id IS NULL THEN '' ELSE private.org_name(q.lead_id, actor) END,
        'tasks', coalesce((SELECT jsonb_agg(jsonb_build_object('title', x.title,
            'assignee', private.org_name(x.assignee_id, actor), 'reviewer', private.org_name(x.reviewer_id, actor),
            'status', x.status, 'dueAt', private.iso(x.due_at),
            'doneAt', private.iso((SELECT max(r.created_at) FROM public.reviews r JOIN public.submissions s ON s.id = r.submission_id
              WHERE s.task_id = x.id AND r.decision = 'approved')),
            'revisions', (SELECT greatest(count(*) - 1, 0) FROM public.submissions s WHERE s.task_id = x.id),
            'links', coalesce((SELECT s.links FROM public.submissions s WHERE s.task_id = x.id ORDER BY s.revision DESC LIMIT 1), '[]'))
          ORDER BY x.due_at, x.id) FROM public.tasks x WHERE x.project_id = q.id), '[]'))
      ORDER BY q.due_at, q.id) FROM public.projects q WHERE q.id = ANY(chosen)), '[]'),
    'meetings', coalesce((SELECT jsonb_agg(jsonb_build_object('title', m.title, 'startsAt', private.iso(m.starts_at),
        'present', (SELECT count(*) FROM public.meeting_attendance a WHERE a.meeting_id = m.id AND a.status = 'hadir'),
        'excused', (SELECT count(*) FROM public.meeting_attendance a WHERE a.meeting_id = m.id AND a.status = 'izin'),
        'minutes', left(m.minutes, 4000), 'minutesTruncated', length(m.minutes) > 4000) ORDER BY m.starts_at, m.id)
      FROM (SELECT * FROM public.meetings mm WHERE mm.group_id = g.id AND mm.status <> 'cancelled'
        AND mm.starts_at > window_from AND mm.starts_at <= window_to ORDER BY mm.starts_at, mm.id LIMIT 100) m), '[]'),
    'approvals', CASE WHEN NOT full_access THEN '[]'::jsonb ELSE coalesce((SELECT jsonb_agg(jsonb_build_object('title', a.title,
        'amount', a.amount, 'status', a.status, 'closedAt', private.iso(a.closed_at),
        'chain', (SELECT coalesce(jsonb_agg(private.org_name(s.approver_id, actor) || CASE s.decision
            WHEN 'approved' THEN ' (disetujui)' WHEN 'rejected' THEN ' (ditolak)' ELSE ' (belum)' END ORDER BY s.position), '[]')
          FROM public.approval_steps s WHERE s.approval_id = a.id)) ORDER BY a.closed_at, a.id)
      FROM public.approvals a WHERE a.group_id = g.id AND a.status IN ('approved','rejected')
        AND a.closed_at > window_from AND a.closed_at <= window_to), '[]') END,
    'totals', jsonb_build_object(
      'tasks', (SELECT count(*) FROM public.tasks x WHERE x.project_id = ANY(chosen)),
      'done', (SELECT count(*) FROM public.tasks x WHERE x.project_id = ANY(chosen) AND x.status = 'done'),
      'approvedAmount', CASE WHEN NOT full_access THEN 0 ELSE coalesce((SELECT sum(a.amount) FROM public.approvals a
        WHERE a.group_id = g.id AND a.status = 'approved' AND a.closed_at > window_from AND a.closed_at <= window_to), 0) END));
END;
$$;

REVOKE ALL ON FUNCTION private.valid_plan_entry(jsonb,boolean), private.valid_sections(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.mutate_orgplan(text,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.templates(uuid), private.template(uuid), private.org_archive(uuid), private.org_members(uuid),
  private.report(uuid,uuid,uuid[]) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.templates(uuid), private.template(uuid), private.org_archive(uuid), private.org_members(uuid),
  private.report(uuid,uuid,uuid[]) TO authenticated;

CREATE FUNCTION public.grouply_templates(org_id uuid)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$ SELECT private.templates(org_id) $$;
CREATE FUNCTION public.grouply_template(template_id uuid)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$ SELECT private.template(template_id) $$;
CREATE FUNCTION public.grouply_org_archive(org_id uuid)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$ SELECT private.org_archive(org_id) $$;
CREATE FUNCTION public.grouply_org_members(org_id uuid)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$ SELECT private.org_members(org_id) $$;
CREATE FUNCTION public.grouply_report(group_id uuid, period_id uuid DEFAULT NULL, project_ids uuid[] DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SET search_path = '' AS $$ SELECT private.report(group_id, period_id, project_ids) $$;
REVOKE ALL ON FUNCTION public.grouply_templates(uuid), public.grouply_template(uuid), public.grouply_org_archive(uuid),
  public.grouply_org_members(uuid), public.grouply_report(uuid,uuid,uuid[]) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.grouply_templates(uuid), public.grouply_template(uuid), public.grouply_org_archive(uuid),
  public.grouply_org_members(uuid), public.grouply_report(uuid,uuid,uuid[]) TO authenticated;

-- Copied from 20261112133033; changed: closed-committee allow list, restoreProject of period archives, createTask planItemID.
CREATE OR REPLACE FUNCTION private.mutate_workflow (
  action  text,
  payload jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare actor uuid:=auth.uid();g public.groups;p public.projects;t public.tasks;s public.submissions;inv private.invitations;mid uuid;gid uuid;pid uuid;tid uuid;uid uuid;rid uuid;result_id uuid;token text;body text;link text;link_data jsonb;old public.chat_messages;target uuid;is_coord boolean:=false;is_task boolean:=false;o public.organizations;uses integer;plan uuid;
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
 -- Closed committee: only chat, leaving and handover stay possible.
 if g.closed_at is not null and action not in ('sendMessage','retryMessage','markChatRead','reportMessage','leaveGroup','removeMember','transferCoordinator') then raise exception 'group_closed';end if;
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
 when 'restoreProject' then if p.archived_at is null then raise exception 'invalid_input';end if;if p.period_id is not null then raise exception 'project_read_only';end if;update public.projects set archived_at=null where id=pid;
 when 'createTask','updateTask','reassignTask' then
 if action<>'createTask' and t.status in ('in_review','done') then raise exception 'already_reviewed';end if;
 uid:=case when action='updateTask' then t.assignee_id else (payload->>'assigneeID')::uuid end;rid:=(payload->>'reviewerID')::uuid;
 if uid is null or rid is null or uid=rid or not exists(select 1 from public.group_members where group_id=gid and user_id=uid) or not exists(select 1 from public.group_members where group_id=gid and user_id=rid) then raise exception 'invalid_input';end if;
 if action='reassignTask' then update public.tasks set assignee_id=uid,reviewer_id=rid,status=case when status='needs_revision' then status else 'todo' end,version=version+1 where id=tid;
 else
 if (payload->>'dueAt')::timestamptz is null or (payload->>'dueAt')::timestamptz<=now() then raise exception 'invalid_input';end if;
 if action='createTask' then mid:=nullif(payload->>'meetingID','')::uuid;if mid is not null and not exists(select 1 from public.meetings where id=mid and group_id=gid and status<>'cancelled') then raise exception 'invalid_input';end if;plan:=nullif(payload->>'planItemID','')::uuid;if plan is not null and not exists(select 1 from public.project_plan_items where id=plan and project_id=pid) then raise exception 'invalid_input';end if;if plan is not null and exists(select 1 from public.project_plan_items where id=plan and task_id is not null) then raise exception 'plan_item_used';end if;insert into public.tasks(project_id,title,description,assignee_id,reviewer_id,due_at,meeting_id) values(pid,private.txt(payload->>'title',120),private.txt(payload->>'description',2000,false),uid,rid,(payload->>'dueAt')::timestamptz,mid) returning id into tid;result_id:=tid;if plan is not null then update public.project_plan_items set task_id=tid where id=plan;end if;
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

-- Copied from 20261112133033; changed: closed committees reject every action here.
CREATE OR REPLACE FUNCTION private.mutate_orgwork(action text, payload jsonb)
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
    IF g.closed_at IS NOT NULL THEN RAISE EXCEPTION 'group_closed'; END IF;
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
    IF g.closed_at IS NOT NULL THEN RAISE EXCEPTION 'group_closed'; END IF;
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
    IF g.closed_at IS NOT NULL THEN RAISE EXCEPTION 'group_closed'; END IF;
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
      IF g.closed_at IS NOT NULL THEN RAISE EXCEPTION 'group_closed'; END IF;
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

-- Copied from 20261112133033; changed: closed committees outside the 30 limit, closed period labels rejected.
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
    IF EXISTS(SELECT 1 FROM public.organization_periods pr WHERE pr.organization_id = org.id
        AND pr.label = private.txt(payload->>'periodLabel',40,false)) THEN RAISE EXCEPTION 'period_exists'; END IF;
    UPDATE public.organizations SET name = private.txt(payload->>'name',80),
      description = private.txt(payload->>'description',1000,false),
      period_label = private.txt(payload->>'periodLabel',40,false)
      WHERE id = org.id;
  ELSIF action = 'createDivision' THEN
    IF mine IS NULL OR mine NOT IN ('ketua','bph') THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF org.plan_expires_at IS NULL OR org.plan_expires_at <= now() THEN RAISE EXCEPTION 'plan_inactive'; END IF;
    IF (SELECT count(*) FROM public.groups g WHERE g.organization_id = org.id
        AND g.is_committee = coalesce((payload->>'committee')::boolean, false) AND g.closed_at IS NULL
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

-- Copied from 20261112133033; changed: closed committees leave the dashboard.
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
    WHERE g.organization_id = org.id AND g.closed_at IS NULL GROUP BY g.id
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

-- Copied from 20261113111326; changed: Tahap 3a dispatch.
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
  IF action IN ('applyTemplate','createTemplate','deleteTemplate','deletePlanItem','closeCommittee','reopenCommittee',
      'setCoordinator','removeClosedMember','closePeriod') THEN
    RETURN private.mutate_orgplan(action,payload);
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

-- Copied from 20261113111326; changed: closed, periodLabel, planItems, organizations[].periods.
CREATE OR REPLACE FUNCTION private.snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
 SELECT jsonb_build_object(
 'currentUserID',actor,
 'users',coalesce((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'email','','tint',u.tint) ORDER BY u.name) FROM public.profiles u WHERE private.profile_visible(u.id)),'[]'),
 'groups',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'course',g.course,'coordinatorID',coalesce(g.coordinator_id::text,''),'tint',g.tint,'icon',g.icon,'organizationID',coalesce(g.organization_id::text,''),'isCommittee',g.is_committee,'closed',g.closed_at IS NOT NULL,'memberIDs',(SELECT jsonb_agg(user_id ORDER BY user_id) FROM public.group_members WHERE group_id=g.id))) FROM public.groups g WHERE private.member(g.id)),'[]'),
 'projects',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'groupID',p.group_id,'title',p.title,'description',p.description,'dueAt',private.iso(p.due_at),'status',CASE WHEN p.archived_at IS NOT NULL THEN 'archived' ELSE p.status END,'previousStatus',CASE WHEN p.archived_at IS NOT NULL THEN p.status ELSE NULL END,'leadID',coalesce(p.lead_id::text,''),'periodLabel',coalesce((SELECT pr.label FROM public.organization_periods pr WHERE pr.id=p.period_id),''),'planItems',CASE WHEN p.status='active' AND p.archived_at IS NULL THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'position',i.position,'title',i.title,'description',i.description,'dueAt',private.iso(i.due_at)) ORDER BY i.position) FROM public.project_plan_items i WHERE i.project_id=p.id AND i.task_id IS NULL),'[]') ELSE '[]'::jsonb END)) FROM public.projects p WHERE private.member(p.group_id)),'[]'),
 'tasks',coalesce((SELECT jsonb_agg(jsonb_build_object('id',t.id,'projectID',t.project_id,'title',t.title,'description',t.description,'assigneeID',coalesce(t.assignee_id::text,''),'reviewerID',coalesce(t.reviewer_id::text,''),'dueAt',private.iso(t.due_at),'status',t.status,'version',t.version,'submissions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'revision',s.revision,'authorID',coalesce(s.author_id::text,''),'note',s.note,'links',s.links,'createdAt',private.iso(s.created_at),'decision',r.decision,'feedback',r.feedback,'reviewerID',coalesce(r.reviewer_id::text,'')) ORDER BY s.revision) FROM public.submissions s LEFT JOIN public.reviews r ON r.submission_id=s.id WHERE s.task_id=t.id),'[]'))) FROM public.tasks t WHERE private.task_group(t.id) IS NOT NULL),'[]'),
 'messages',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'groupID',m.group_id,'taskID',m.task_id,'senderID',coalesce(m.sender_id::text,''),'text',m.content,'createdAt',private.iso(m.created_at),'kind',m.kind,'delivery','sent','targetTaskID',CASE WHEN m.kind='activity' THEN m.task_id ELSE NULL END) ORDER BY m.created_at,m.id) FROM public.chat_messages m WHERE private.member(m.group_id)),'[]'),
 'invites',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'groupID',i.group_id,'code','','createdAt',private.iso(i.created_at),'expiresAt',private.iso(i.expires_at),'maxUses',i.max_uses,'useCount',i.used_count,'revoked',i.revoked_at IS NOT NULL)) FROM private.invitations i JOIN public.groups g ON g.id=i.group_id WHERE g.coordinator_id=actor),'[]'),
 'reports',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'messageID',coalesce(r.message_id::text,''),'kind',r.target_kind,'targetID',coalesce(r.target_id,r.message_id),'reporterID',r.reporter_id,'reason',r.reason,'createdAt',private.iso(r.created_at),'status',r.status,'reviewedAt',private.iso(r.reviewed_at))) FROM private.content_reports r WHERE r.reporter_id=actor),'[]'),
 'organizations',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'description',o.description,'periodLabel',o.period_label,'planActive',coalesce(o.plan_expires_at>now(),false),'planExpiresAt',private.iso(o.plan_expires_at),'seatLimit',o.seat_limit,'seatsUsed',private.org_seats(o.id),'periods',coalesce((SELECT jsonb_agg(jsonb_build_object('id',pr.id,'label',pr.label,'startedAt',private.iso(pr.started_at),'closedAt',private.iso(pr.closed_at)) ORDER BY pr.closed_at DESC,pr.id) FROM public.organization_periods pr WHERE pr.organization_id=o.id),'[]'),'approvals',private.org_approvals(o.id,actor),'announcements',private.org_announcements(o.id,actor),'myRole',(SELECT r.role FROM public.organization_roles r WHERE r.organization_id=o.id AND r.user_id=actor),'roles',coalesce((SELECT jsonb_agg(jsonb_build_object('userID',r.user_id,'role',r.role,'name',CASE WHEN EXISTS(SELECT 1 FROM public.user_blocks b WHERE b.user_id=actor AND b.blocked_id=r.user_id) THEN 'Anggota' ELSE p.name END) ORDER BY CASE r.role WHEN 'ketua' THEN 0 WHEN 'bph' THEN 1 ELSE 2 END,p.name,p.id) FROM public.organization_roles r JOIN public.profiles p ON p.id=r.user_id WHERE r.organization_id=o.id),'[]'),'divisions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'isCommittee',d.is_committee,'closed',d.closed_at IS NOT NULL,'memberCount',d.members,'isMember',d.mine) ORDER BY d.name,d.id) FROM (SELECT g.id,g.name,g.is_committee,g.closed_at,count(m.user_id) AS members,bool_or(m.user_id=actor) AS mine FROM public.groups g JOIN public.group_members m ON m.group_id=g.id WHERE g.organization_id=o.id GROUP BY g.id,g.name,g.is_committee,g.closed_at) d),'[]')) ORDER BY o.name,o.id) FROM public.organizations o WHERE private.org_member(o.id,actor)),'[]'),
 'meetings',private.my_meetings(actor),
 'blockedUserIDs',coalesce((SELECT jsonb_agg(blocked_id) FROM public.user_blocks WHERE user_id=actor),'[]'),
 'readMessageIDs',coalesce((SELECT jsonb_agg(r.message_id) FROM public.chat_reads r JOIN public.chat_messages m ON m.id=r.message_id WHERE r.user_id=actor AND m.task_id IS NULL AND private.member(m.group_id)),'[]')) INTO result;
 RETURN result;
END;
$$;

-- Copied from 20261113111326; changed: templates can be reported.
CREATE OR REPLACE FUNCTION private.report_content(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); kind text; tid uuid; gid uuid; org uuid; excerpt text; report_id uuid;
  n public.announcements; m public.meetings; a public.approvals; tp public.proker_templates;
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
  ELSIF kind = 'template' THEN
    SELECT * INTO tp FROM public.proker_templates WHERE id = tid;
    IF tp.id IS NULL OR tp.organization_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
    org := tp.organization_id;
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
  ELSIF kind = 'approval' THEN
    IF a.requester_id = actor OR NOT (
        EXISTS(SELECT 1 FROM public.organization_roles WHERE organization_id = a.organization_id AND user_id = actor)
        OR EXISTS(SELECT 1 FROM public.groups WHERE id = a.group_id AND coordinator_id = actor)) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    excerpt := concat_ws(E'\n', a.title, a.note, CASE WHEN a.links <> '[]'::jsonb THEN a.links::text END);
  ELSE
    IF tp.created_by = actor OR NOT private.org_member(tp.organization_id, actor) THEN RAISE EXCEPTION 'forbidden'; END IF;
    excerpt := tp.name || E'\n' || tp.description || E'\n' || tp.sections::text;
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

-- Copied from 20261113111326; changed: template reports (removed = template deleted).
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
        coalesce(n.organization_id, ap.organization_id, g.organization_id, pt.organization_id) AS "organizationID",
        CASE WHEN r.target_kind = 'message' THEN m.content ELSE r.excerpt END AS text
       FROM private.content_reports r
       LEFT JOIN public.chat_messages m ON m.id = r.message_id
       LEFT JOIN public.announcements n ON r.target_kind = 'announcement' AND n.id = r.target_id
       LEFT JOIN public.meetings mt ON r.target_kind = 'meeting' AND mt.id = r.target_id
       LEFT JOIN public.approvals ap ON r.target_kind = 'approval' AND ap.id = r.target_id
       LEFT JOIN public.groups g ON g.id = mt.group_id
       LEFT JOIN public.proker_templates pt ON r.target_kind = 'template' AND pt.id = r.target_id
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
    ELSIF report.target_kind = 'template' THEN
      SELECT organization_id INTO org FROM public.proker_templates WHERE id = report.target_id;
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
        ELSIF report.target_kind = 'approval' THEN
          UPDATE public.approvals SET title = removed, note = removed, links = '[]' WHERE id = report.target_id;
        ELSE
          DELETE FROM public.proker_templates WHERE id = report.target_id;
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

NOTIFY pgrst, 'reload schema';
