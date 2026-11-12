-- psql -v ON_ERROR_STOP=1; Organization Plan Tahap 2. Disposable fixtures; everything rolls back.
BEGIN;
CREATE FUNCTION pg_temp.check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',label; END IF; RAISE NOTICE 'PASS: %',label; END;
$$;
CREATE FUNCTION pg_temp.denied(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE statement;
  RAISE EXCEPTION 'unexpected success';
EXCEPTION WHEN OTHERS THEN
  IF sqlerrm NOT LIKE '%'||expected||'%' THEN RAISE EXCEPTION 'Expected %, got %',expected,sqlerrm; END IF;
  RAISE NOTICE 'PASS: rejected with %',expected;
END;
$$;
CREATE FUNCTION pg_temp.fails(action text,payload jsonb,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.grouply_mutate(action,payload);
  RAISE EXCEPTION 'unexpected success';
EXCEPTION WHEN OTHERS THEN
  IF sqlerrm NOT LIKE '%'||expected||'%' THEN RAISE EXCEPTION 'Expected % from %, got %',expected,action,sqlerrm; END IF;
  RAISE NOTICE 'PASS: % rejected with %',action,expected;
END;
$$;
CREATE FUNCTION pg_temp.actor(actor text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
END;
$$;
CREATE FUNCTION pg_temp.operator() RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true); END;
$$;
CREATE FUNCTION pg_temp.org(org text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT o FROM jsonb_array_elements(public.grouply_snapshot()->'organizations') o WHERE o->>'id'=org;
$$;
CREATE FUNCTION pg_temp.approval(org text,aid text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT a FROM jsonb_array_elements(pg_temp.org(org)->'approvals') a WHERE a->>'id'=aid;
$$;
CREATE FUNCTION pg_temp.ann(org text,nid text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT a FROM jsonb_array_elements(pg_temp.org(org)->'announcements') a WHERE a->>'id'=nid;
$$;
CREATE FUNCTION pg_temp.meeting(mid text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT m FROM jsonb_array_elements(public.grouply_snapshot()->'meetings') m WHERE m->>'id'=mid;
$$;
CREATE FUNCTION pg_temp.project(pid text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT p FROM jsonb_array_elements(public.grouply_snapshot()->'projects') p WHERE p->>'id'=pid;
$$;
CREATE FUNCTION pg_temp.revision(uid text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$
  SELECT coalesce((SELECT revision FROM public.user_sync_state WHERE user_id=uid::uuid),0);
$$;

-- e..01 ketua, 02 bph, 03 kadiv Humas, 04 staf Humas, 05 outsider, 06 pembina, 07 panitia (Acara),
-- 08 kadiv Acara, 09 leaver (Humas), 10 lead (Humas)
INSERT INTO auth.users(id,raw_user_meta_data) SELECT ('e0000000-0000-0000-0000-0000000000'||lpad(n::text,2,'0'))::uuid,
  jsonb_build_object('name','Work fixture '||n) FROM generate_series(1,10) n;
\set ketua 'e0000000-0000-0000-0000-000000000001'
\set bph 'e0000000-0000-0000-0000-000000000002'
\set kadiv 'e0000000-0000-0000-0000-000000000003'
\set staf 'e0000000-0000-0000-0000-000000000004'
\set outsider 'e0000000-0000-0000-0000-000000000005'
\set pembina 'e0000000-0000-0000-0000-000000000006'
\set panitia 'e0000000-0000-0000-0000-000000000007'
\set kadiv2 'e0000000-0000-0000-0000-000000000008'
\set leaver 'e0000000-0000-0000-0000-000000000009'
\set lead 'e0000000-0000-0000-0000-000000000010'

SET LOCAL ROLE authenticated;

-- Direct access is closed.
SELECT pg_temp.actor(:'outsider');
SELECT pg_temp.denied($q$SELECT * FROM public.meetings$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT * FROM public.meeting_attendance$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT * FROM public.approvals$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT * FROM public.approval_steps$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT * FROM public.announcements$q$,'permission denied');
SELECT pg_temp.denied($q$INSERT INTO public.announcement_reads VALUES(gen_random_uuid(),auth.uid())$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.mutate_orgwork('postAnnouncement','{}')$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.org_approvals(gen_random_uuid(),auth.uid())$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.touch_users(ARRAY[auth.uid()])$q$,'permission denied');

-- Fixture organization: BPH Inti (ketua, bph, pembina), Humas (kadiv, staf, leaver, lead), Acara (kadiv2, panitia).
SELECT pg_temp.actor(:'ketua');
SELECT x->>'id' AS org, x->>'groupID' AS bph_inti
  FROM (SELECT public.grouply_mutate('createOrganization','{"name":"BEM Kerja"}') x) s \gset
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT public.grouply_billing('activatePlan',jsonb_build_object('organizationID',:'org','seatLimit',50,'expiresAt',now()+interval '30 days'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Humas'))->>'id' AS humas \gset
SELECT public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Acara'))->>'id' AS acara \gset
SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'humas','maxUses',30))->'invite'->>'code' AS humas_code \gset
SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'acara','maxUses',30))->'invite'->>'code' AS acara_code \gset
SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'bph_inti','maxUses',30))->'invite'->>'code' AS bph_code \gset
SELECT pg_temp.actor(:'kadiv'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'staf'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'leaver'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'lead'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'kadiv2'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'acara_code'));
SELECT pg_temp.actor(:'panitia'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'acara_code'));
SELECT pg_temp.actor(:'bph'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'bph_code'));
SELECT pg_temp.actor(:'pembina'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'bph_code'));
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'humas','to',:'kadiv'));
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'acara','to',:'kadiv2'));
SELECT public.grouply_mutate('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'bph','role','bph'));
SELECT public.grouply_mutate('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'pembina','role','pembina'));
SELECT (pg_temp.org(:'org')->>'seatsUsed')::int AS seats_before \gset

-- ORG-07 committees: officers create them, members come from any division without new seats.
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('createDivision',jsonb_build_object('organizationID',:'org','name','Panitia','committee',true),'forbidden');
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.fails('createDivision',jsonb_build_object('organizationID',:'org','name','Panitia','committee','ya'),'invalid_input');
SELECT public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Panitia Seminar','committee',true))->>'id' AS com \gset
SELECT pg_temp.check((SELECT (g->>'isCommittee')::boolean FROM jsonb_array_elements(public.grouply_snapshot()->'groups') g WHERE g->>'id'=:'com'),'committee is flagged in groups');
SELECT pg_temp.check((SELECT (d->>'isCommittee')::boolean FROM jsonb_array_elements(pg_temp.org(:'org')->'divisions') d WHERE d->>'id'=:'com'),'committee is flagged in organization divisions');
SELECT pg_temp.check((SELECT NOT (d->>'isCommittee')::boolean FROM jsonb_array_elements(pg_temp.org(:'org')->'divisions') d WHERE d->>'id'=:'humas'),'divisions stay unflagged');
SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'com','maxUses',30))->'invite'->>'code' AS com_code \gset
SELECT pg_temp.actor(:'staf'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'com_code'));
SELECT pg_temp.actor(:'panitia'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'com_code'));
SELECT pg_temp.check((pg_temp.org(:'org')->>'seatsUsed')::int=:seats_before,'committee members from divisions use no new seat');
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.check((SELECT (d->>'isCommittee')::boolean FROM jsonb_array_elements(public.grouply_org_overview(:'org')->'divisions') d WHERE d->>'id'=:'com'),'dashboard flags committees');
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('createGroup','{"name":"Kelompok bebas"}')->>'id' AS plain \gset

-- Project lead (koordinator sie).
SELECT public.grouply_mutate('createProject',jsonb_build_object('groupID',:'humas','title','Publikasi','dueAt',now()+interval '20 days'))->>'id' AS proj \gset
SELECT public.grouply_mutate('createProject',jsonb_build_object('groupID',:'humas','title','Dokumentasi','dueAt',now()+interval '20 days'))->>'id' AS proj2 \gset
SELECT public.grouply_mutate('createProject',jsonb_build_object('groupID',:'plain','title','Tugas kuliah','dueAt',now()+interval '20 days'))->>'id' AS plain_proj \gset
SELECT pg_temp.fails('setProjectLead',jsonb_build_object('projectID',:'plain_proj','userID',:'kadiv'),'invalid_input');
SELECT pg_temp.fails('setProjectLead',jsonb_build_object('projectID',:'proj','userID',:'outsider'),'invalid_input');
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('setProjectLead',jsonb_build_object('projectID',:'proj','userID',:'staf'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('setProjectLead',jsonb_build_object('projectID',:'proj','userID',:'lead'));
SELECT pg_temp.check(pg_temp.project(:'proj')->>'leadID'=:'lead','snapshot carries leadID');
SELECT pg_temp.check(pg_temp.project(:'proj2')->>'leadID'='','unled project has empty leadID');
SELECT pg_temp.actor(:'lead');
SELECT public.grouply_mutate('createTask',jsonb_build_object('projectID',:'proj','title','Poster','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days'))->>'id' AS task1 \gset
SELECT pg_temp.fails('createTask',jsonb_build_object('projectID',:'proj2','title','Bukan sienya','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days'),'forbidden');
SELECT pg_temp.fails('updateProject',jsonb_build_object('projectID',:'proj','title','Diubah','dueAt',now()+interval '9 days'),'forbidden');
SELECT pg_temp.fails('generateInvite',jsonb_build_object('groupID',:'humas'),'forbidden');
SELECT public.grouply_mutate('updateTask',jsonb_build_object('id',:'task1','expectedVersion',1,'title','Poster utama','reviewerID',:'kadiv','dueAt',now()+interval '6 days'));
SELECT public.grouply_mutate('reassignTask',jsonb_build_object('id',:'task1','expectedVersion',2,'assigneeID',:'kadiv','reviewerID',:'staf'));
SELECT pg_temp.check(true,'lead creates, updates and reassigns tasks in their project');
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('setProjectLead',jsonb_build_object('projectID',:'proj','userID',null));
SELECT pg_temp.actor(:'lead');
SELECT pg_temp.fails('createTask',jsonb_build_object('projectID',:'proj','title','Setelah dicabut','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('setProjectLead',jsonb_build_object('projectID',:'proj','userID',:'lead'));
SELECT pg_temp.actor(:'lead');
SELECT public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'humas'));
SELECT pg_temp.fails('createTask',jsonb_build_object('projectID',:'proj','title','Setelah keluar','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.check(pg_temp.project(:'proj')->>'leadID'='','leaving the group clears the project lead');

-- ORG-09 meetings.
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('createMeeting',jsonb_build_object('groupID',:'humas','title','Rapat liar','startsAt',now()+interval '1 day'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('createMeeting',jsonb_build_object('groupID',:'plain','title','Rapat','startsAt',now()+interval '1 day'),'invalid_input');
SELECT pg_temp.fails('createMeeting',jsonb_build_object('groupID',:'humas','title','Rapat','startsAt',now()+interval '1 day','noteTakerID',:'outsider'),'invalid_input');
SELECT pg_temp.fails('createMeeting',jsonb_build_object('groupID',:'humas','title','Rapat','startsAt','2026-13-45'),'invalid_input');
SELECT pg_temp.fails('createMeeting',jsonb_build_object('groupID',:'humas','title','Rapat'),'invalid_input');
SELECT public.grouply_mutate('createMeeting',jsonb_build_object('groupID',:'humas','title','Rapat mingguan','startsAt',now()+interval '1 day','place','Sekre','agenda','1. Publikasi','noteTakerID',:'staf'))->>'id' AS meet1 \gset
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'messages') m WHERE m->>'groupID'=:'humas' AND m->>'kind'='activity' AND m->>'text'='Menjadwalkan rapat · Rapat mingguan'),'scheduling posts an activity message');
SELECT pg_temp.check((SELECT m->>'status'='scheduled' AND m->>'noteTakerID'=:'staf' AND (m->>'version')::int=1 AND NOT (m->>'hasMinutes')::boolean FROM (SELECT pg_temp.meeting(:'meet1') m) s),'snapshot lists the meeting');
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('recordMeeting',jsonb_build_object('id',:'meet1','expectedVersion',1,'minutes','Terlalu awal'),'invalid_input');
SELECT pg_temp.fails('updateMeeting',jsonb_build_object('id',:'meet1','expectedVersion',1,'title','x','startsAt',now()),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('updateMeeting',jsonb_build_object('id',:'meet1','expectedVersion',2,'title','Rapat mingguan','startsAt',now()-interval '1 hour','place','Sekre','noteTakerID',:'staf'),'stale_version');
SELECT public.grouply_mutate('updateMeeting',jsonb_build_object('id',:'meet1','expectedVersion',1,'title','Rapat mingguan','startsAt',now()-interval '1 hour','place','Sekre','agenda','1. Publikasi','noteTakerID',:'staf'));
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'messages') m WHERE m->>'text'='Mengubah jadwal rapat · Rapat mingguan'),'moving a meeting posts an activity message');
SELECT pg_temp.actor(:'outsider');
SELECT pg_temp.denied(format('SELECT public.grouply_meeting(%L)',:'meet1'),'forbidden');
SELECT pg_temp.check(pg_temp.meeting(:'meet1') IS NULL,'outsider snapshot has no meetings of other groups');
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('recordMeeting',jsonb_build_object('id',:'meet1','expectedVersion',2,'attendance',jsonb_build_array(jsonb_build_object('userID',:'outsider','status','hadir'))),'invalid_input');
SELECT pg_temp.fails('recordMeeting',jsonb_build_object('id',:'meet1','expectedVersion',2,'attendance',jsonb_build_array(jsonb_build_object('userID',:'staf','status','hadir'),jsonb_build_object('userID',:'staf','status','izin'))),'invalid_input');
SELECT pg_temp.fails('recordMeeting',jsonb_build_object('id',:'meet1','expectedVersion',2,'attendance',jsonb_build_array(jsonb_build_object('userID',:'staf','status','alpa'))),'invalid_input');
SELECT public.grouply_mutate('recordMeeting',jsonb_build_object('id',:'meet1','expectedVersion',2,'minutes','Poster dikejar Jumat.',
  'attendance',jsonb_build_array(jsonb_build_object('userID',:'kadiv','status','hadir'),jsonb_build_object('userID',:'staf','status','hadir'),jsonb_build_object('userID',:'leaver','status','izin'))));
SELECT pg_temp.check((SELECT m->>'status'='done' AND (m->>'present')::int=2 AND (m->>'excused')::int=1 AND (m->>'hasMinutes')::boolean AND m->>'myStatus'='hadir' FROM (SELECT pg_temp.meeting(:'meet1') m) s),'notulis records minutes and attendance');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'messages') m WHERE m->>'text'='Mencatat notulen rapat · Rapat mingguan'),'first minutes post an activity message');
SELECT pg_temp.actor(:'leaver');
SELECT public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'humas'));
SELECT pg_temp.actor(:'staf');
SELECT public.grouply_mutate('recordMeeting',jsonb_build_object('id',:'meet1','expectedVersion',3,'minutes','Revisi: poster dikejar Kamis.',
  'attendance',jsonb_build_array(jsonb_build_object('userID',:'kadiv','status','hadir'),jsonb_build_object('userID',:'staf','status','izin'))));
SELECT pg_temp.check((SELECT d->>'minutes'='Revisi: poster dikejar Kamis.' AND (d->>'version')::int=4 AND jsonb_array_length(d->'attendance')=3
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(d->'attendance') a WHERE a->>'userID'=:'leaver' AND a->>'status'='izin')
  FROM (SELECT public.grouply_meeting(:'meet1') d) s),'revising minutes keeps the attendance of members who left');
SELECT pg_temp.check((SELECT count(*)=1 FROM jsonb_array_elements(public.grouply_snapshot()->'messages') m WHERE m->>'text'='Mencatat notulen rapat · Rapat mingguan'),'revisions do not post again');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('updateMeeting',jsonb_build_object('id',:'meet1','expectedVersion',4,'title','x','startsAt',now()),'meeting_closed');
SELECT pg_temp.fails('cancelMeeting',jsonb_build_object('id',:'meet1','expectedVersion',4),'meeting_closed');
SELECT public.grouply_mutate('createMeeting',jsonb_build_object('groupID',:'humas','title','Rapat batal','startsAt',now()-interval '2 hours'))->>'id' AS meet2 \gset
SELECT public.grouply_mutate('cancelMeeting',jsonb_build_object('id',:'meet2','expectedVersion',1));
SELECT pg_temp.fails('recordMeeting',jsonb_build_object('id',:'meet2','expectedVersion',2,'minutes','x'),'meeting_closed');
SELECT public.grouply_mutate('createTask',jsonb_build_object('projectID',:'proj','title','Hasil rapat','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days','meetingID',:'meet1'))->>'id' AS meet_task \gset
SELECT pg_temp.check(pg_temp.meeting(:'meet1')->'taskIDs' @> to_jsonb(ARRAY[:'meet_task']),'tasks created from a meeting link back to it');
SELECT pg_temp.fails('createTask',jsonb_build_object('projectID',:'proj','title','Dari rapat batal','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days','meetingID',:'meet2'),'invalid_input');
SELECT pg_temp.actor(:'kadiv2');
SELECT public.grouply_mutate('createMeeting',jsonb_build_object('groupID',:'acara','title','Rapat Acara','startsAt',now()+interval '2 days'))->>'id' AS meet3 \gset
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('createTask',jsonb_build_object('projectID',:'proj','title','Rapat grup lain','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days','meetingID',:'meet3'),'invalid_input');

-- ORG-08 approvals.
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','approverIDs',jsonb_build_array(:'staf')),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','approverIDs',jsonb_build_array(:'panitia')),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','approverIDs',jsonb_build_array(:'kadiv',:'kadiv')),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','approverIDs','[]'::jsonb),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x'),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','amount',-1,'approverIDs',jsonb_build_array(:'kadiv')),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','amount','banyak','approverIDs',jsonb_build_array(:'kadiv')),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','amount',99999999999999999999,'approverIDs',jsonb_build_array(:'kadiv')),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','links',jsonb_build_array('http://contoh.id'),'approverIDs',jsonb_build_array(:'kadiv')),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'plain','title','Dana','note','x','approverIDs',jsonb_build_array(:'kadiv')),'invalid_input');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'acara','title','Dana','note','x','approverIDs',jsonb_build_array(:'kadiv2')),'forbidden');
SELECT pg_temp.revision(:'ketua') AS ketua_rev \gset
SELECT public.grouply_mutate('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana publikasi','note','Cetak 20 poster A3.','amount',750000,
  'links',jsonb_build_array('https://contoh.id/rab'),'approverIDs',jsonb_build_array(:'kadiv',:'bph',:'ketua')))->>'id' AS ap1 \gset
SELECT pg_temp.check(pg_temp.revision(:'ketua')>:ketua_rev,'a new request refreshes every officer');
SELECT pg_temp.check((SELECT a->>'status'='pending' AND (a->>'amount')::bigint=750000 AND a->>'requesterName'='Work fixture 4' AND a->>'groupName'='Humas'
  AND jsonb_array_length(a->'steps')=3 AND a->'steps'->1->>'approverID'=:'bph' AND (a->'steps'->1->>'eligible')::boolean
  FROM (SELECT pg_temp.approval(:'org',:'ap1') a) s),'requester sees the chain');
SELECT public.grouply_mutate('requestApproval',jsonb_build_object('groupID',:'humas','title','Izin pembina','note','Kegiatan malam.','approverIDs',jsonb_build_array(:'pembina')))->>'id' AS ap2 \gset
SELECT pg_temp.check(true,'pembina can be an approver');
SELECT pg_temp.actor(:'panitia');
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap1') IS NULL,'a member of another division does not see the request');
SELECT pg_temp.actor(:'kadiv2');
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap1') IS NULL,'another division coordinator does not see the request');
SELECT pg_temp.actor(:'pembina');
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap1') IS NOT NULL,'every officer sees the request');
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap1','approve',true),'forbidden');
SELECT pg_temp.actor(:'outsider');
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap1','approve',true),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap1','approve',false),'invalid_input');
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap1'),'invalid_input');
SELECT public.grouply_mutate('decideApproval',jsonb_build_object('id',:'ap1','approve',true,'note','Oke'));
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap1','approve',true),'forbidden');
-- An approver who loses the qualifying position can neither decide nor keep seeing the request.
SELECT public.grouply_mutate('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'bph','role',null));
SELECT pg_temp.check(NOT (pg_temp.approval(:'org',:'ap1')->'steps'->1->>'eligible')::boolean,'chain marks an approver who lost the role');
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap1','approve',true),'forbidden');
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap1') IS NULL,'former officer no longer sees the request');
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'bph','role','bph'));
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('decideApproval',jsonb_build_object('id',:'ap1','approve',true));
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('decideApproval',jsonb_build_object('id',:'ap1','approve',false,'note','Anggaran terlalu besar.'));
SELECT pg_temp.check((SELECT a->>'status'='rejected' AND a->>'closedAt' IS NOT NULL AND a->'steps'->2->>'decision'='rejected' AND a->'steps'->2->>'note'='Anggaran terlalu besar.'
  FROM (SELECT pg_temp.approval(:'org',:'ap1') a) s),'a rejection closes the request');
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap1','approve',true),'approval_closed');
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('cancelApproval',jsonb_build_object('id',:'ap1'),'approval_closed');
-- Coordinator handover moves the right to decide.
SELECT public.grouply_mutate('requestApproval',jsonb_build_object('groupID',:'humas','title','Konsumsi','note','Rapat besar.','approverIDs',jsonb_build_array(:'kadiv')))->>'id' AS ap3 \gset
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'humas','to',:'staf'));
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap3','approve',true),'forbidden');
SELECT pg_temp.actor(:'staf');
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'humas','to',:'kadiv'));
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('decideApproval',jsonb_build_object('id',:'ap3','approve',true));
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap3')->>'status'='approved','approving the last step approves the request');
-- Cancel, and the open-request cap.
SELECT pg_temp.actor(:'staf');
SELECT public.grouply_mutate('requestApproval',jsonb_build_object('groupID',:'humas','title','Batal','note','x','approverIDs',jsonb_build_array(:'ketua')))->>'id' AS ap4 \gset
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('cancelApproval',jsonb_build_object('id',:'ap4'),'forbidden');
SELECT pg_temp.actor(:'staf');
SELECT public.grouply_mutate('cancelApproval',jsonb_build_object('id',:'ap4'));
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap4')->>'status'='cancelled','requester cancels a pending request');
SELECT public.grouply_mutate('requestApproval',jsonb_build_object('groupID',:'humas','title','Antre '||n,'note','x','approverIDs',jsonb_build_array(:'ketua'))) FROM generate_series(1,4) n;
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Keenam','note','x','approverIDs',jsonb_build_array(:'ketua')),'rate_limited');
-- Lapse: an approver or requester who leaves the organization.
SELECT pg_temp.actor(:'pembina');
SELECT public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'bph_inti'));
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap2')->>'status'='lapsed','an approver leaving the organization lapses the request');
SELECT pg_temp.actor(:'panitia');
SELECT public.grouply_mutate('requestApproval',jsonb_build_object('groupID',:'acara','title','Sewa sound','note','Untuk malam puncak.','approverIDs',jsonb_build_array(:'kadiv2')))->>'id' AS ap5 \gset
SELECT public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'acara'));
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap5')->>'status'='pending','leaving the origin group but staying in the organization keeps the request');
SELECT public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'com'));
SELECT pg_temp.actor(:'kadiv2');
SELECT pg_temp.check(pg_temp.approval(:'org',:'ap5')->>'status'='lapsed','a requester leaving the organization lapses the request');
SELECT pg_temp.fails('decideApproval',jsonb_build_object('id',:'ap5','approve',true),'approval_closed');

-- ORG-10 announcements.
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',:'org','title','Info','body','x'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',:'org','title','Info','body','x'),'forbidden');
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',:'org','title','Info','body','  '),'invalid_input');
SELECT public.grouply_mutate('postAnnouncement',jsonb_build_object('organizationID',:'org','title','Rapat pleno','body','Semua hadir Sabtu.'))->>'id' AS ann1 \gset
RESET ROLE;
SELECT (SELECT count(DISTINCT m.user_id) FROM public.group_members m JOIN public.groups g ON g.id=m.group_id WHERE g.organization_id=:'org'::uuid) AS audience \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.check((SELECT (a->>'read')::boolean AND (a->>'readCount')::int=1 AND (a->>'audienceCount')::int=:audience FROM (SELECT pg_temp.ann(:'org',:'ann1') a) s),'author sees read counts, own post already read');
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.check((SELECT NOT (a->>'read')::boolean AND (a->>'readCount')::int=0 AND (a->>'audienceCount')::int=0 AND a->'unreadIDs'='[]'::jsonb AND a->>'authorName'='Work fixture 2'
  FROM (SELECT pg_temp.ann(:'org',:'ann1') a) s),'staff sees the post without counts or names');
SELECT pg_temp.actor(:'kadiv2');
SELECT pg_temp.check((SELECT NOT (a->'unreadIDs' @> to_jsonb(ARRAY[:'staf'])) FROM (SELECT pg_temp.ann(:'org',:'ann1') a) s),'unread names stop at the viewer''s own groups');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.check((SELECT a->'unreadIDs' @> to_jsonb(ARRAY[:'staf']) AND (a->>'readCount')::int=0 FROM (SELECT pg_temp.ann(:'org',:'ann1') a) s),'a division coordinator sees which of their members have not read');
SELECT pg_temp.actor(:'staf');
SELECT public.grouply_mutate('markAnnouncementRead',jsonb_build_object('id',:'ann1'));
SELECT public.grouply_mutate('markAnnouncementRead',jsonb_build_object('id',:'ann1'));
SELECT pg_temp.check((pg_temp.ann(:'org',:'ann1')->>'read')::boolean,'marking read is idempotent');
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.check((pg_temp.ann(:'org',:'ann1')->>'readCount')::int=2,'author sees the new read');
SELECT pg_temp.actor(:'outsider');
SELECT pg_temp.fails('markAnnouncementRead',jsonb_build_object('id',:'ann1'),'forbidden');
SELECT pg_temp.actor(:'kadiv2');
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',:'org','groupID',:'humas','title','Bukan grupku','body','x'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',gen_random_uuid(),'groupID',:'humas','title','Salah','body','x'),'invalid_input');
SELECT public.grouply_mutate('postAnnouncement',jsonb_build_object('organizationID',:'org','groupID',:'humas','title','Piket','body','Jadwal piket baru.'))->>'id' AS ann2 \gset
SELECT pg_temp.actor(:'kadiv2');
SELECT pg_temp.check(pg_temp.ann(:'org',:'ann2') IS NULL,'group posts stay inside the group');
SELECT pg_temp.fails('markAnnouncementRead',jsonb_build_object('id',:'ann2'),'forbidden');
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.check(pg_temp.ann(:'org',:'ann2')->>'groupID'=:'humas','group members receive group posts');
SELECT pg_temp.fails('deleteAnnouncement',jsonb_build_object('id',:'ann1'),'forbidden');
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('deleteAnnouncement',jsonb_build_object('id',:'ann2'),'forbidden');
SELECT public.grouply_mutate('deleteAnnouncement',jsonb_build_object('id',:'ann1'));
SELECT pg_temp.check(pg_temp.ann(:'org',:'ann1') IS NULL,'the ketua withdraws an organization-wide post');
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('postAnnouncement',jsonb_build_object('organizationID',:'org','title','Info '||n,'body','x')) FROM generate_series(1,5) n;
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',:'org','title','Keenam','body','x'),'rate_limited');

-- Expired plan: nothing new, existing work can be finished.
SELECT pg_temp.actor(:'staf');
SELECT (SELECT a->>'id' FROM jsonb_array_elements(pg_temp.org(:'org')->'approvals') a WHERE a->>'status'='pending' ORDER BY a->>'createdAt' LIMIT 1) AS open_ap \gset
SELECT (SELECT a->>'id' FROM jsonb_array_elements(pg_temp.org(:'org')->'announcements') a WHERE NOT (a->>'read')::boolean LIMIT 1) AS unread_ann \gset
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT public.grouply_billing('deactivatePlan',jsonb_build_object('organizationID',:'org'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('createMeeting',jsonb_build_object('groupID',:'humas','title','Rapat','startsAt',now()+interval '1 day'),'plan_inactive');
SELECT pg_temp.fails('setProjectLead',jsonb_build_object('projectID',:'proj','userID',:'staf'),'plan_inactive');
SELECT public.grouply_mutate('setProjectLead',jsonb_build_object('projectID',:'proj','userID',null));
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',:'org','groupID',:'humas','title','Info','body','x'),'plan_inactive');
SELECT public.grouply_mutate('recordMeeting',jsonb_build_object('id',:'meet1','expectedVersion',4,'minutes','Revisi akhir.','attendance','[]'::jsonb));
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'humas','title','Dana','note','x','approverIDs',jsonb_build_array(:'kadiv')),'plan_inactive');
SELECT public.grouply_mutate('markAnnouncementRead',jsonb_build_object('id',:'unread_ann'));
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',:'org','title','Info','body','x'),'plan_inactive');
SELECT pg_temp.fails('createDivision',jsonb_build_object('organizationID',:'org','name','Panitia baru','committee',true),'plan_inactive');
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('decideApproval',jsonb_build_object('id',:'open_ap','approve',true));
SELECT pg_temp.check(pg_temp.approval(:'org',:'open_ap')->>'status'='approved','pending requests can still be decided after the plan ends');

-- Committee limit is counted apart from divisions.
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT public.grouply_billing('activatePlan',jsonb_build_object('organizationID',:'org','seatLimit',50,'expiresAt',now()+interval '30 days'));
RESET ROLE;
WITH made AS (
  INSERT INTO public.groups(name,coordinator_id,organization_id,is_committee)
    SELECT 'Panitia '||n,:'bph'::uuid,:'org'::uuid,true FROM generate_series(1,29) n RETURNING id)
INSERT INTO public.group_members SELECT id,:'bph'::uuid FROM made;
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.fails('createDivision',jsonb_build_object('organizationID',:'org','name','Panitia ke-31','committee',true),'invalid_input');
SELECT pg_temp.check(public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Divisi baru')) ? 'id','divisions are not blocked by the committee limit');

RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.denied(format('SELECT public.grouply_meeting(%L)',:'meet1'),'permission denied');
RESET ROLE;
ROLLBACK;
