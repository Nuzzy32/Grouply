-- psql -v ON_ERROR_STOP=1; Organization Plan Tahap 1. Disposable fixtures; everything rolls back.
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
-- Test-only peek at the closed roles table.
CREATE FUNCTION pg_temp.has_role(org text,uid text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT role FROM public.organization_roles WHERE organization_id=org::uuid AND user_id=uid::uuid;
$$;

-- f..01 ketua, 02 bph, 03 kadiv, 04 staf, 05 outsider, 06 joiner, 07 solo founder, 08 pembina
INSERT INTO auth.users(id,raw_user_meta_data) SELECT ('f0000000-0000-0000-0000-00000000000'||n)::uuid,
  jsonb_build_object('name','Org fixture '||n) FROM generate_series(1,8) n;
\set ketua 'f0000000-0000-0000-0000-000000000001'
\set bph 'f0000000-0000-0000-0000-000000000002'
\set kadiv 'f0000000-0000-0000-0000-000000000003'
\set staf 'f0000000-0000-0000-0000-000000000004'
\set outsider 'f0000000-0000-0000-0000-000000000005'
\set joiner 'f0000000-0000-0000-0000-000000000006'
\set solo 'f0000000-0000-0000-0000-000000000007'
\set pembina 'f0000000-0000-0000-0000-000000000008'

SET LOCAL ROLE authenticated;

-- Direct access is closed; only the RPCs reach the new tables and helpers.
SELECT pg_temp.actor(:'outsider');
SELECT pg_temp.denied($q$SELECT * FROM public.organizations$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT * FROM public.organization_roles$q$,'permission denied');
SELECT pg_temp.denied($q$INSERT INTO public.organization_roles VALUES(gen_random_uuid(),auth.uid(),'ketua')$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.mutate_org('createOrganization','{"name":"x"}')$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.org_seats(gen_random_uuid())$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.org_touch(gen_random_uuid())$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT public.grouply_billing('list','{}')$q$,'permission denied');

-- createOrganization: founder becomes ketua and coordinator of the first division.
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('createOrganization','{"name":"  "}','invalid_input');
SELECT x->>'id' AS org, x->>'groupID' AS bph_inti
  FROM (SELECT public.grouply_mutate('createOrganization','{"name":"BEM Uji","periodLabel":"2026/2027"}') x) s \gset
SELECT pg_temp.check(pg_temp.has_role(:'org',:'ketua')='ketua','founder is ketua');
SELECT pg_temp.check((SELECT g->>'name'='BPH Inti' AND g->>'organizationID'=:'org' AND g->>'coordinatorID'=:'ketua'
  FROM jsonb_array_elements(public.grouply_snapshot()->'groups') g WHERE g->>'id'=:'bph_inti'),'first division defaults to BPH Inti');
SELECT pg_temp.check((SELECT o->>'myRole'='ketua' AND (o->>'planActive')::boolean=false AND (o->>'seatsUsed')::int=1
  FROM jsonb_array_elements(public.grouply_snapshot()->'organizations') o WHERE o->>'id'=:'org'),'snapshot shows inactive org and own role');

-- Inactive plan: free limits only.
SELECT pg_temp.fails('createDivision',jsonb_build_object('organizationID',:'org','name','Humas'),'plan_inactive');
SELECT pg_temp.fails('generateInvite',jsonb_build_object('groupID',:'bph_inti','maxUses',10),'invalid_input');
SELECT pg_temp.denied(format('SELECT public.grouply_org_overview(%L)',:'org'),'plan_inactive');

-- Operator activates the plan.
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT pg_temp.denied(format('SELECT public.grouply_billing(''activatePlan'',%L)',jsonb_build_object('organizationID',:'org','seatLimit',0,'expiresAt',now()+interval '30 days')),'invalid_input');
SELECT pg_temp.denied(format('SELECT public.grouply_billing(''activatePlan'',%L)',jsonb_build_object('organizationID',:'org','seatLimit',5,'expiresAt','not a date')),'invalid_input');
SELECT pg_temp.denied(format('SELECT public.grouply_billing(''activatePlan'',%L)',jsonb_build_object('organizationID',:'org','seatLimit',5,'expiresAt',now()-interval '1 day')),'invalid_input');
SELECT pg_temp.check((public.grouply_billing('activatePlan',jsonb_build_object('organizationID',:'org','seatLimit',5,'expiresAt',now()+interval '30 days'))->>'seatLimit')::int=5,'operator activates plan');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_billing('list','{}')) o WHERE o->>'id'=:'org'),'operator lists organizations');
SET LOCAL ROLE authenticated;

-- Divisions, multi-use invites, seats.
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Humas'))->>'id' AS humas \gset
SELECT pg_temp.fails('generateInvite',jsonb_build_object('groupID',:'humas','maxUses',201),'invalid_input');
SELECT pg_temp.fails('generateInvite',jsonb_build_object('groupID',:'humas','maxUses','banyak'),'invalid_input');
SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'humas','maxUses',30))->'invite'->>'code' AS humas_code \gset
SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'bph_inti','maxUses',10))->'invite'->>'code' AS bph_code \gset
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'staf');
SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'bph_code'));
SELECT pg_temp.actor(:'pembina');
SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'bph_code'));
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'humas','to',:'kadiv'));
SELECT pg_temp.check((SELECT (o->>'seatsUsed')::int=5 FROM jsonb_array_elements(public.grouply_snapshot()->'organizations') o WHERE o->>'id'=:'org'),'five unique people use five seats');
SELECT pg_temp.actor(:'joiner');
SELECT pg_temp.fails('joinGroup',jsonb_build_object('code',:'humas_code'),'org_full');
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.check((SELECT (o->>'seatsUsed')::int=5 FROM jsonb_array_elements(public.grouply_snapshot()->'organizations') o WHERE o->>'id'=:'org'),'joining a second division uses no new seat');

-- Roles: only the ketua manages them.
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'staf','role','bph'),'forbidden');
SELECT pg_temp.fails('updateOrganization',jsonb_build_object('id',:'org','name','Diambil alih'),'forbidden');
SELECT pg_temp.fails('createDivision',jsonb_build_object('organizationID',:'org','name','Liar'),'forbidden');
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'bph','role','ketua'),'invalid_input');
SELECT pg_temp.fails('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'outsider','role','bph'),'invalid_input');
SELECT pg_temp.fails('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'ketua','role','bph'),'invalid_input');
RESET ROLE;
SELECT revision AS staf_revision FROM public.user_sync_state WHERE user_id=:'staf' \gset
SET LOCAL ROLE authenticated;
SELECT public.grouply_mutate('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'bph','role','bph'));
SELECT public.grouply_mutate('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'pembina','role','pembina'));
RESET ROLE;
SELECT pg_temp.check((SELECT revision>:staf_revision FROM public.user_sync_state WHERE user_id=:'staf'),'role change refreshes every org member');
SET LOCAL ROLE authenticated;
SELECT public.grouply_mutate('updateOrganization',jsonb_build_object('id',:'org','name','BEM Uji Baru','description','','periodLabel','2026/2027'));
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Acara'))->>'id' AS acara \gset

-- Staff snapshot: officer names and other divisions' names/counts only.
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.check((SELECT o->>'name'='BEM Uji Baru' AND o->'myRole'='null'::jsonb
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(o->'roles') r WHERE r->>'userID'=:'bph' AND r->>'role'='bph' AND r->>'name'='Org fixture 2')
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(o->'divisions') d WHERE d->>'id'=:'acara' AND (d->>'isMember')::boolean=false AND (d->>'memberCount')::int=1)
  FROM jsonb_array_elements(public.grouply_snapshot()->'organizations') o),'staff sees officers and division summary');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'groups') g WHERE g->>'id'=:'acara'),'staff snapshot excludes other divisions');
SELECT pg_temp.denied(format('SELECT public.grouply_org_overview(%L)',:'org'),'forbidden');
SELECT pg_temp.actor(:'outsider');
SELECT pg_temp.check(jsonb_array_length(public.grouply_snapshot()->'organizations')=0,'outsider sees no organization');
SELECT pg_temp.denied(format('SELECT public.grouply_org_overview(%L)',:'org'),'forbidden');

-- Overview markers match the Flutter definitions.
RESET ROLE;
INSERT INTO public.projects(id,group_id,title,due_at) VALUES('f3000000-0000-0000-0000-000000000001',:'humas','Seminar',now()+interval '20 days');
INSERT INTO public.projects(id,group_id,title,due_at,archived_at) VALUES('f3000000-0000-0000-0000-000000000002',:'humas','Arsip',now()+interval '20 days',now());
INSERT INTO public.tasks(id,project_id,title,assignee_id,reviewer_id,due_at,status) VALUES
 ('f4000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001','Terlambat',:'staf',:'kadiv',now()-interval '5 hours','todo'),
 ('f4000000-0000-0000-0000-000000000002','f3000000-0000-0000-0000-000000000001','Mandek',:'staf',:'kadiv',now()+interval '5 days','in_progress'),
 ('f4000000-0000-0000-0000-000000000003','f3000000-0000-0000-0000-000000000001','Review lama',:'staf',:'kadiv',now()+interval '5 days','in_review'),
 ('f4000000-0000-0000-0000-000000000004','f3000000-0000-0000-0000-000000000001','Selesai',:'staf',:'kadiv',now()-interval '5 days','done'),
 ('f4000000-0000-0000-0000-000000000005','f3000000-0000-0000-0000-000000000001','Baru',:'staf',:'kadiv',now()+interval '5 days','todo'),
 ('f4000000-0000-0000-0000-000000000006','f3000000-0000-0000-0000-000000000002','Diarsipkan',:'staf',:'kadiv',now()-interval '5 days','todo');
INSERT INTO public.chat_messages(group_id,task_id,sender_id,content,kind,created_at) VALUES
 (:'humas','f4000000-0000-0000-0000-000000000001',:'kadiv','Membuat tugas','activity',now()),
 (:'humas','f4000000-0000-0000-0000-000000000002',:'kadiv','Membuat tugas','activity',now()-interval '3 days'),
 (:'humas','f4000000-0000-0000-0000-000000000003',:'kadiv','Membuat tugas','activity',now()-interval '4 days'),
 (:'humas','f4000000-0000-0000-0000-000000000005',:'kadiv','Membuat tugas','activity',now()-interval '1 hour');
INSERT INTO public.submissions(task_id,revision,author_id,note,created_at) VALUES
 ('f4000000-0000-0000-0000-000000000003',1,:'staf','Draf',now()-interval '3 days');
INSERT INTO public.user_blocks VALUES(:'pembina',:'staf');
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'pembina');
SELECT public.grouply_org_overview(:'org') AS overview \gset
SELECT pg_temp.check((SELECT (p->>'total')::int=5 AND (p->>'done')::int=1 AND (p->>'inReview')::int=1 AND (p->>'overdue')::int=1
  AND (p->>'idle')::int=1 AND (p->>'reviewPending')::int=1
  FROM jsonb_array_elements(:'overview'::jsonb->'divisions') d, jsonb_array_elements(d->'projects') p WHERE p->>'title'='Seminar'),'project counts');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(:'overview'::jsonb->'divisions') d, jsonb_array_elements(d->'projects') p WHERE p->>'title'='Arsip'),'archived projects excluded');
SELECT pg_temp.check((SELECT array_agg(a->>'reason' ORDER BY n)=ARRAY['overdue','review_pending','idle']
  FROM jsonb_array_elements(:'overview'::jsonb->'attention') WITH ORDINALITY AS t(a,n)),'attention ordered overdue, review, idle');
SELECT pg_temp.check((SELECT (a->>'hours')::int BETWEEN 71 AND 72 FROM jsonb_array_elements(:'overview'::jsonb->'attention') a WHERE a->>'reason'='idle'),'idle hours since last activity');
SELECT pg_temp.check((SELECT u->>'name'='Anggota' FROM jsonb_array_elements(:'overview'::jsonb->'users') u WHERE u->>'id'=:'staf'),'blocked assignee shown as Anggota');
SELECT pg_temp.check((SELECT u->>'name'='Org fixture 3' FROM jsonb_array_elements(:'overview'::jsonb->'users') u WHERE u->>'id'=:'kadiv'),'coordinator named for officers');

-- Membership guard keeps every role holder inside a division.
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('removeMember',jsonb_build_object('groupID',:'humas','userID',:'bph'));
SELECT pg_temp.check(pg_temp.has_role(:'org',:'bph')='bph','leaving a non-last division keeps the role');
SELECT pg_temp.actor(:'ketua');
-- bph still has Acara, so this is not their last division.
SELECT public.grouply_mutate('removeMember',jsonb_build_object('groupID',:'bph_inti','userID',:'bph'));
SELECT pg_temp.check(pg_temp.has_role(:'org',:'bph')='bph','removal from a non-last division keeps the role');
SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'bph_inti','maxUses',5))->'invite'->>'code' AS back_code \gset
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'back_code'));
SELECT pg_temp.actor(:'ketua');
-- pembina's only division: a coordinator cannot silently strip the role.
SELECT pg_temp.fails('removeMember',jsonb_build_object('groupID',:'bph_inti','userID',:'pembina'),'org_role_holder');
SELECT pg_temp.actor(:'pembina');
SELECT public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'bph_inti'));
SELECT pg_temp.check(pg_temp.has_role(:'org',:'pembina') IS NULL,'officer leaving last division drops the role');
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'humas'));
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'bph_inti','to',:'bph'));
SELECT pg_temp.fails('leaveGroup',jsonb_build_object('id',:'bph_inti'),'ketua_transfer_required');
SELECT pg_temp.fails('transferKetua',jsonb_build_object('organizationID',:'org','userID',:'outsider'),'invalid_input');
SELECT pg_temp.fails('transferKetua',jsonb_build_object('organizationID',:'org','userID',:'ketua'),'invalid_input');
SELECT public.grouply_mutate('transferKetua',jsonb_build_object('organizationID',:'org','userID',:'bph'));
SELECT pg_temp.check(pg_temp.has_role(:'org',:'bph')='ketua' AND pg_temp.has_role(:'org',:'ketua')='bph','ketua handed over, old ketua becomes bph');
SELECT public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'bph_inti'));
SELECT pg_temp.check(pg_temp.has_role(:'org',:'ketua') IS NULL,'former ketua leaves cleanly');

-- Account deletion: blocked for a ketua with members, allowed for a sole founder.
SELECT pg_temp.actor(:'joiner');
SELECT x->>'id' AS org2, x->>'groupID' AS org2_bph FROM (SELECT public.grouply_mutate('createOrganization','{"name":"Dua"}') x) s \gset
SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'org2_bph'))->'invite'->>'code' AS org2_code \gset
SELECT pg_temp.actor(:'outsider');
SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'org2_code'));
SELECT pg_temp.actor(:'joiner');
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'org2_bph','to',:'outsider'));
SELECT pg_temp.fails('deleteAccount','{}','ketua_transfer_required');
SELECT pg_temp.actor(:'solo');
SELECT public.grouply_mutate('createOrganization','{"name":"Solo 1"}');
SELECT public.grouply_mutate('createOrganization','{"name":"Solo 2"}');
SELECT public.grouply_mutate('createOrganization','{"name":"Solo 3"}');
SELECT pg_temp.fails('createOrganization','{"name":"Solo 4"}','rate_limited');
SELECT public.grouply_mutate('deleteAccount','{}');
RESET ROLE;
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM auth.users WHERE id=:'solo')
  AND NOT EXISTS(SELECT 1 FROM public.organization_roles WHERE user_id=:'solo'),'sole founder can delete account');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM auth.users WHERE id=:'joiner') AND pg_temp.has_role(:'org2',:'joiner')='ketua','blocked deletion changes nothing');

-- Division limit counts only populated divisions.
INSERT INTO public.groups(id,name,coordinator_id,organization_id)
  SELECT gen_random_uuid(),'Isi '||n,:'bph',:'org' FROM generate_series(1,26) n;
INSERT INTO public.group_members SELECT id,:'bph' FROM public.groups WHERE name LIKE 'Isi %' AND organization_id=:'org';
INSERT INTO public.groups(name,coordinator_id,organization_id) VALUES('Kosong',NULL,:'org');
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'bph');
-- 29 populated + 1 empty: the empty one does not count, so the 30th still fits.
SELECT pg_temp.check(public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Ke-30')) ? 'id','empty division not counted');
SELECT pg_temp.fails('createDivision',jsonb_build_object('organizationID',:'org','name','Ke-31'),'invalid_input');

-- Expired plan: back to free limits, leftover multi-use invites act single-use.
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT public.grouply_billing('deactivatePlan',jsonb_build_object('organizationID',:'org'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'pembina');
SELECT pg_temp.fails('joinGroup',jsonb_build_object('code',:'humas_code'),'invite_full');
SELECT pg_temp.denied(format('SELECT public.grouply_org_overview(%L)',:'org'),'forbidden');
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.denied(format('SELECT public.grouply_org_overview(%L)',:'org'),'plan_inactive');
SELECT pg_temp.fails('createDivision',jsonb_build_object('organizationID',:'org','name','Telat'),'plan_inactive');
SELECT pg_temp.check((SELECT (o->>'planActive')::boolean=false FROM jsonb_array_elements(public.grouply_snapshot()->'organizations') o WHERE o->>'id'=:'org'),'snapshot shows expired plan');

-- Plain groups behave as before.
SELECT public.grouply_mutate('createGroup','{"name":"Kelompok biasa"}')->>'id' AS plain \gset
SELECT pg_temp.fails('generateInvite',jsonb_build_object('groupID',:'plain','maxUses',2),'invalid_input');
SELECT pg_temp.check((public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'plain'))->'invite'->>'maxUses')::int=1,'plain group invites stay single-use');

RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.denied(format('SELECT public.grouply_org_overview(%L)',:'org'),'permission denied');
SELECT pg_temp.denied($q$SELECT public.grouply_billing('list','{}')$q$,'permission denied');
RESET ROLE;
ROLLBACK;
