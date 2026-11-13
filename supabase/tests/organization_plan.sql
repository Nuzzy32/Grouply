-- psql -v ON_ERROR_STOP=1; Organization Plan Tahap 3a. Disposable fixtures; everything rolls back.
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
CREATE FUNCTION pg_temp.project(pid text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT p FROM jsonb_array_elements(public.grouply_snapshot()->'projects') p WHERE p->>'id'=pid;
$$;
CREATE FUNCTION pg_temp.titled(gid text,title text) RETURNS text LANGUAGE sql AS $$
  SELECT p->>'id' FROM jsonb_array_elements(public.grouply_snapshot()->'projects') p
  WHERE p->>'groupID'=gid AND p->>'title'=title ORDER BY p->>'dueAt' DESC LIMIT 1;
$$;
CREATE FUNCTION pg_temp.group_row(gid text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT g FROM jsonb_array_elements(public.grouply_snapshot()->'groups') g WHERE g->>'id'=gid;
$$;
CREATE FUNCTION pg_temp.version(tid text) RETURNS int LANGUAGE sql AS $$
  SELECT (t->>'version')::int FROM jsonb_array_elements(public.grouply_snapshot()->'tasks') t WHERE t->>'id'=tid;
$$;
CREATE FUNCTION pg_temp.finish(tid text,assignee text,reviewer text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v int;
BEGIN
  PERFORM pg_temp.actor(assignee);
  v := pg_temp.version(tid);
  PERFORM public.grouply_mutate('startTask',jsonb_build_object('id',tid,'expectedVersion',v));
  PERFORM public.grouply_mutate('submitWork',jsonb_build_object('id',tid,'expectedVersion',v+1,'note','Selesai','links',jsonb_build_array('https://contoh.id/hasil')));
  PERFORM pg_temp.actor(reviewer);
  PERFORM public.grouply_mutate('review',jsonb_build_object('id',tid,'expectedVersion',v+2,'approve',true));
END;
$$;
CREATE FUNCTION pg_temp.join_code(gid text) RETURNS text LANGUAGE sql AS $$
  SELECT public.grouply_mutate('generateInvite',jsonb_build_object('groupID',gid,'maxUses',30))->'invite'->>'code';
$$;

-- d..01 ketua, 02 bph, 03 kadiv Humas, 04 staf Humas, 05 outsider, 06 ketua pelaksana, 07 panitia, 08 lead (Humas)
INSERT INTO auth.users(id,raw_user_meta_data) SELECT ('d0000000-0000-0000-0000-0000000000'||lpad(n::text,2,'0'))::uuid,
  jsonb_build_object('name','Plan fixture '||n) FROM generate_series(1,8) n;
\set ketua 'd0000000-0000-0000-0000-000000000001'
\set bph 'd0000000-0000-0000-0000-000000000002'
\set kadiv 'd0000000-0000-0000-0000-000000000003'
\set staf 'd0000000-0000-0000-0000-000000000004'
\set outsider 'd0000000-0000-0000-0000-000000000005'
\set ketpel 'd0000000-0000-0000-0000-000000000006'
\set panitia 'd0000000-0000-0000-0000-000000000007'
\set lead 'd0000000-0000-0000-0000-000000000008'

SET LOCAL ROLE authenticated;

-- Direct access is closed.
SELECT pg_temp.actor(:'outsider');
SELECT pg_temp.denied($q$SELECT * FROM public.proker_templates$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT * FROM public.project_plan_items$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT * FROM public.organization_periods$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.mutate_orgplan('closePeriod','{}')$q$,'permission denied');
SELECT pg_temp.denied($q$SELECT private.valid_sections('[]')$q$,'permission denied');

-- Fixture: BPH Inti (ketua, bph), Humas (kadiv, staf, lead), plan active, period 2026/2027.
SELECT pg_temp.actor(:'ketua');
SELECT x->>'id' AS org, x->>'groupID' AS bph_inti
  FROM (SELECT public.grouply_mutate('createOrganization','{"name":"HIMA Rencana","periodLabel":"2026/2027"}') x) s \gset
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT public.grouply_billing('activatePlan',jsonb_build_object('organizationID',:'org','seatLimit',50,'expiresAt',now()+interval '30 days'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Humas'))->>'id' AS humas \gset
SELECT pg_temp.join_code(:'humas') AS humas_code \gset
SELECT pg_temp.join_code(:'bph_inti') AS bph_code \gset
SELECT pg_temp.actor(:'kadiv'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'staf'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'lead'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'humas_code'));
SELECT pg_temp.actor(:'bph'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'bph_code'));
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'humas','to',:'kadiv'));
SELECT public.grouply_mutate('setOrgRole',jsonb_build_object('organizationID',:'org','userID',:'bph','role','bph'));

-- ORG-12 templates.
SELECT pg_temp.actor(:'outsider');
SELECT pg_temp.denied(format('SELECT public.grouply_templates(%L)',:'org'),'forbidden');
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.check((SELECT count(*)=4 AND bool_and((t->>'builtIn')::boolean AND NOT (t->>'mine')::boolean)
  FROM jsonb_array_elements(public.grouply_templates(:'org')) t),'members see the four built-in templates');
SELECT (SELECT t->>'id' FROM jsonb_array_elements(public.grouply_templates(:'org')) t WHERE t->>'name'='Seminar') AS seminar \gset
SELECT pg_temp.check((SELECT jsonb_array_length(d->'sections')=5 AND (d->>'builtIn')::boolean FROM (SELECT public.grouply_template(:'seminar') d) s),'template detail carries its sections');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','Punyaku','sections','[{"title":"Sie A","offsetDays":0,"items":[]}]'::jsonb),'forbidden');
SELECT pg_temp.fails('deleteTemplate',jsonb_build_object('id',:'seminar'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','x','sections','[]'::jsonb),'invalid_input');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','x','sections','[{"title":"ab","offsetDays":0,"items":[]}]'::jsonb),'invalid_input');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','x','sections','[{"title":"Sie A","offsetDays":1.5,"items":[]}]'::jsonb),'invalid_input');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','x','sections','[{"title":"Sie A","offsetDays":5.0,"items":[]}]'::jsonb),'invalid_input');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','x','sections','[{"title":"Sie A","offsetDays":0,"items":[],"owner":"x"}]'::jsonb),'invalid_input');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','x','sections',
  jsonb_build_array(jsonb_build_object('title','Sie A','offsetDays',0,'items',(SELECT jsonb_agg(jsonb_build_object('title','Butir '||n,'offsetDays',-n)) FROM generate_series(1,41) n)))),'invalid_input');
SELECT public.grouply_mutate('createTemplate',jsonb_build_object('organizationID',:'org','name','Bakti sosial','description','Versi HIMA',
  'sections','[{"title":"Sie Acara","offsetDays":0,"items":[{"title":"Survei lokasi","offsetDays":-10,"description":"Bawa formulir"}]}]'::jsonb))->>'id' AS own_tpl \gset
SELECT pg_temp.check((SELECT (t->>'mine')::boolean AND NOT (t->>'builtIn')::boolean FROM jsonb_array_elements(public.grouply_templates(:'org')) t WHERE t->>'id'=:'own_tpl'),'a coordinator saves an organization template');
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('createTemplate',jsonb_build_object('organizationID',:'org','name','Sementara','sections','[{"title":"Sie Satu","offsetDays":0,"items":[]}]'::jsonb))->>'id' AS bph_tpl \gset
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('deleteTemplate',jsonb_build_object('id',:'bph_tpl'),'forbidden');
SELECT pg_temp.actor(:'ketua');
SELECT public.grouply_mutate('deleteTemplate',jsonb_build_object('id',:'bph_tpl'));
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_templates(:'org')) t WHERE t->>'id'=:'bph_tpl'),'the ketua removes an organization template');

-- applyTemplate creates sie projects and plan items, never tasks.
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('applyTemplate',jsonb_build_object('templateID',:'seminar','groupID',:'humas','eventAt',now()+interval '40 days'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('applyTemplate',jsonb_build_object('templateID',:'seminar','groupID',:'humas'),'invalid_input');
SELECT pg_temp.fails('applyTemplate',jsonb_build_object('templateID',:'seminar','groupID',:'humas','eventAt',now()+interval '3 days'),'invalid_input');
SELECT (now()+interval '40 days')::text AS event_at \gset
SELECT public.grouply_mutate('applyTemplate',jsonb_build_object('templateID',:'seminar','groupID',:'humas','eventAt',:'event_at'::timestamptz)) AS applied \gset
SELECT pg_temp.check(jsonb_array_length((:'applied'::jsonb)->'projectIDs')=5,'one project per sie');
SELECT pg_temp.titled(:'humas','Sie Acara') AS acara \gset
SELECT pg_temp.titled(:'humas','Sie Dana dan Sponsor') AS dana \gset
SELECT pg_temp.check((SELECT (p->>'dueAt')::timestamptz=:'event_at'::timestamptz-interval '7 days' AND jsonb_array_length(p->'planItems')=2
  FROM (SELECT pg_temp.project(:'dana') p) s),'sie deadline and plan items follow the event date');
SELECT pg_temp.check((SELECT bool_and(x->>'title' IS NOT NULL) AND count(*)=4 FROM jsonb_array_elements(pg_temp.project(:'acara')->'planItems') x),'plan items arrive in the snapshot');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'tasks') t WHERE t->>'projectID'=:'acara'),'applying a template creates no tasks');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'messages') m WHERE m->>'text'='Memakai template · Seminar'),'applying a template posts an activity message');
SELECT public.grouply_mutate('applyTemplate',jsonb_build_object('templateID',:'own_tpl','groupID',:'humas','eventAt',now()+interval '20 days'));
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'projects') p, jsonb_array_elements(p->'planItems') x
  WHERE p->>'groupID'=:'humas' AND x->>'title'='Survei lokasi' AND x->>'description'='Bawa formulir'),'organization templates apply the same way');
-- Rate limit: five uses per hour per group.
SELECT public.grouply_mutate('applyTemplate',jsonb_build_object('templateID',:'own_tpl','groupID',:'humas','eventAt',now()+interval '20 days')) FROM generate_series(1,3);
SELECT pg_temp.fails('applyTemplate',jsonb_build_object('templateID',:'own_tpl','groupID',:'humas','eventAt',now()+interval '20 days'),'rate_limited');

-- Plan items become tasks once, through createTask.
SELECT (SELECT x->>'id' FROM jsonb_array_elements(pg_temp.project(:'acara')->'planItems') x ORDER BY (x->>'position')::int LIMIT 1) AS item1 \gset
SELECT (SELECT x->>'id' FROM jsonb_array_elements(pg_temp.project(:'acara')->'planItems') x ORDER BY (x->>'position')::int OFFSET 1 LIMIT 1) AS item2 \gset
SELECT (SELECT x->>'id' FROM jsonb_array_elements(pg_temp.project(:'dana')->'planItems') x LIMIT 1) AS dana_item \gset
SELECT public.grouply_mutate('createTask',jsonb_build_object('projectID',:'acara','title','Hubungi pemateri','assigneeID',:'staf','reviewerID',:'kadiv',
  'dueAt',now()+interval '5 days','planItemID',:'item1'))->>'id' AS plan_task \gset
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(pg_temp.project(:'acara')->'planItems') x WHERE x->>'id'=:'item1'),'a used plan item leaves the plan');
SELECT pg_temp.fails('createTask',jsonb_build_object('projectID',:'acara','title','Lagi','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days','planItemID',:'item1'),'plan_item_used');
SELECT pg_temp.fails('createTask',jsonb_build_object('projectID',:'acara','title','Salah sie','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '5 days','planItemID',:'dana_item'),'invalid_input');
SELECT pg_temp.denied(format('SELECT public.grouply_mutate(''deletePlanItem'',%L)',jsonb_build_object('id',:'item1')),'plan_item_used');
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('deletePlanItem',jsonb_build_object('id',:'item2'),'forbidden');
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('setProjectLead',jsonb_build_object('projectID',:'dana','userID',:'lead'));
SELECT pg_temp.actor(:'lead');
SELECT public.grouply_mutate('deletePlanItem',jsonb_build_object('id',:'dana_item'));
SELECT pg_temp.check(jsonb_array_length(pg_temp.project(:'dana')->'planItems')=1,'a project lead removes a plan item');
SELECT pg_temp.fails('deletePlanItem',jsonb_build_object('id',:'item2'),'forbidden');

-- setCoordinator: the ketua replaces an unresponsive coordinator.
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('setCoordinator',jsonb_build_object('groupID',:'humas','userID',:'staf'),'forbidden');
SELECT public.grouply_mutate('createGroup','{"name":"Kelompok bebas"}')->>'id' AS plain \gset
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('setCoordinator',jsonb_build_object('groupID',:'plain','userID',:'kadiv'),'forbidden');
SELECT pg_temp.fails('setCoordinator',jsonb_build_object('groupID',:'humas','userID',:'outsider'),'invalid_input');
SELECT public.grouply_mutate('setCoordinator',jsonb_build_object('groupID',:'humas','userID',:'staf'));
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.check(pg_temp.group_row(:'humas')->>'coordinatorID'=:'staf','the ketua hands a division to a member');
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'humas','to',:'kadiv'));

-- ORG-13 committees close only when nothing is left open.
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Panitia Seminar','committee',true))->>'id' AS com \gset
SELECT pg_temp.join_code(:'com') AS com_code \gset
SELECT pg_temp.actor(:'ketpel'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'com_code'));
SELECT pg_temp.actor(:'panitia'); SELECT public.grouply_mutate('joinGroup',jsonb_build_object('code',:'com_code'));
SELECT pg_temp.actor(:'bph');
SELECT public.grouply_mutate('transferCoordinator',jsonb_build_object('groupID',:'com','to',:'ketpel'));
SELECT pg_temp.actor(:'ketpel');
SELECT public.grouply_mutate('createProject',jsonb_build_object('groupID',:'com','title','Sie Acara Seminar','dueAt',now()+interval '10 days'))->>'id' AS sie \gset
SELECT public.grouply_mutate('createTask',jsonb_build_object('projectID',:'sie','title','Rundown','assigneeID',:'panitia','reviewerID',:'ketpel','dueAt',now()+interval '5 days'))->>'id' AS sie_task \gset
SELECT public.grouply_mutate('createMeeting',jsonb_build_object('groupID',:'com','title','Rapat evaluasi','startsAt',now()+interval '3 days'))->>'id' AS future_meeting \gset
SELECT pg_temp.actor(:'panitia');
SELECT pg_temp.fails('closeCommittee',jsonb_build_object('groupID',:'com'),'forbidden');
SELECT pg_temp.actor(:'ketpel');
SELECT pg_temp.fails('closeCommittee',jsonb_build_object('groupID',:'humas'),'forbidden');
SELECT pg_temp.fails('closeCommittee',jsonb_build_object('groupID',:'com'),'committee_busy');
SELECT public.grouply_mutate('archiveProject',jsonb_build_object('projectID',:'sie'));
SELECT pg_temp.fails('closeCommittee',jsonb_build_object('groupID',:'com'),'committee_busy');
SELECT public.grouply_mutate('restoreProject',jsonb_build_object('projectID',:'sie'));
SELECT pg_temp.finish(:'sie_task',:'panitia',:'ketpel');
SELECT pg_temp.actor(:'ketpel');
SELECT public.grouply_mutate('completeProject',jsonb_build_object('projectID',:'sie'));
SELECT pg_temp.actor(:'panitia');
SELECT public.grouply_mutate('requestApproval',jsonb_build_object('groupID',:'com','title','Dana konsumsi','note','Untuk 50 orang.','amount',400000,'approverIDs',jsonb_build_array(:'ketpel')))->>'id' AS com_ap \gset
SELECT pg_temp.actor(:'ketpel');
SELECT pg_temp.fails('closeCommittee',jsonb_build_object('groupID',:'com'),'committee_busy');
SELECT public.grouply_mutate('decideApproval',jsonb_build_object('id',:'com_ap','approve',true));
SELECT public.grouply_mutate('closeCommittee',jsonb_build_object('groupID',:'com'));
SELECT pg_temp.check((pg_temp.group_row(:'com')->>'closed')::boolean,'closed flag reaches the group');
SELECT pg_temp.check((SELECT (d->>'closed')::boolean FROM jsonb_array_elements(pg_temp.org(:'org')->'divisions') d WHERE d->>'id'=:'com'),'closed flag reaches the organization list');
SELECT pg_temp.check((SELECT m->>'status'='cancelled' FROM jsonb_array_elements(public.grouply_snapshot()->'meetings') m WHERE m->>'id'=:'future_meeting'),'closing cancels upcoming meetings');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_snapshot()->'invites') i WHERE i->>'groupID'=:'com' AND NOT (i->>'revoked')::boolean),'closing revokes invitations');
-- Only chat, leaving and handover stay open.
SELECT pg_temp.fails('createProject',jsonb_build_object('groupID',:'com','title','Baru','dueAt',now()+interval '5 days'),'group_closed');
SELECT pg_temp.fails('reopenProject',jsonb_build_object('projectID',:'sie'),'group_closed');
SELECT pg_temp.fails('generateInvite',jsonb_build_object('groupID',:'com'),'group_closed');
SELECT pg_temp.fails('updateGroup',jsonb_build_object('id',:'com','name','Ganti'),'group_closed');
SELECT pg_temp.fails('setProjectLead',jsonb_build_object('projectID',:'sie','userID',null),'group_closed');
SELECT pg_temp.fails('createMeeting',jsonb_build_object('groupID',:'com','title','Rapat','startsAt',now()+interval '1 day'),'group_closed');
SELECT pg_temp.fails('postAnnouncement',jsonb_build_object('organizationID',:'org','groupID',:'com','title','Info','body','x'),'group_closed');
SELECT pg_temp.fails('applyTemplate',jsonb_build_object('templateID',:'seminar','groupID',:'com','eventAt',now()+interval '40 days'),'group_closed');
SELECT pg_temp.actor(:'panitia');
SELECT pg_temp.fails('requestApproval',jsonb_build_object('groupID',:'com','title','Lagi','note','x','approverIDs',jsonb_build_array(:'ketpel')),'group_closed');
SELECT pg_temp.fails('joinGroup',jsonb_build_object('code',:'com_code'),'group_closed');
SELECT pg_temp.check(public.grouply_mutate('sendMessage',jsonb_build_object('groupID',:'com','clientID',gen_random_uuid(),'text','Terima kasih semua')) ? 'id','chat stays open in a closed committee');
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_org_overview(:'org')->'divisions') d WHERE d->>'id'=:'com'),'closed committees leave the dashboard');
SELECT pg_temp.actor(:'ketpel');
SELECT pg_temp.fails('reopenCommittee',jsonb_build_object('groupID',:'com'),'forbidden');

-- Handover reaches groups the ketua is not in: member list and removing people left in a closed committee.
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.denied(format('SELECT public.grouply_org_members(%L)',:'org'),'forbidden');
SELECT pg_temp.fails('removeClosedMember',jsonb_build_object('groupID',:'com','userID',:'panitia'),'forbidden');
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.check((SELECT (g->>'closed')::boolean AND g->>'coordinatorID'=:'ketpel'
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(g->'members') m WHERE m->>'id'=:'panitia' AND m->>'name'='Plan fixture 7')
  FROM jsonb_array_elements(public.grouply_org_members(:'org')) g WHERE g->>'groupID'=:'com'),'the ketua lists members of groups they are not in');
SELECT pg_temp.check(EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_org_members(:'org')) g WHERE g->>'groupID'=:'humas'
  AND jsonb_array_length(g->'members')=4),'every division is listed with its members');
SELECT pg_temp.fails('removeClosedMember',jsonb_build_object('groupID',:'humas','userID',:'staf'),'invalid_input');
SELECT pg_temp.fails('removeClosedMember',jsonb_build_object('groupID',:'com','userID',:'ketpel'),'coordinator_transfer_required');
SELECT pg_temp.fails('removeClosedMember',jsonb_build_object('groupID',:'com','userID',:'outsider'),'invalid_input');
SELECT public.grouply_mutate('removeClosedMember',jsonb_build_object('groupID',:'com','userID',:'panitia'));
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_org_members(:'org')) g, jsonb_array_elements(g->'members') m
  WHERE g->>'groupID'=:'com' AND m->>'id'=:'panitia'),'the ketua frees a seat held only in a closed committee');

-- ORG-13 period close: completed work is archived and labelled, running work carries over.
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('createProject',jsonb_build_object('groupID',:'humas','title','Rilis pers','dueAt',now()+interval '9 days'))->>'id' AS done_proj \gset
SELECT public.grouply_mutate('createTask',jsonb_build_object('projectID',:'done_proj','title','Tulis rilis','assigneeID',:'staf','reviewerID',:'kadiv','dueAt',now()+interval '4 days'))->>'id' AS done_task \gset
SELECT pg_temp.finish(:'done_task',:'staf',:'kadiv');
SELECT pg_temp.actor(:'kadiv');
SELECT public.grouply_mutate('completeProject',jsonb_build_object('projectID',:'done_proj'));
SELECT public.grouply_mutate('createProject',jsonb_build_object('groupID',:'humas','title','Batal','dueAt',now()+interval '9 days'))->>'id' AS dropped \gset
SELECT public.grouply_mutate('archiveProject',jsonb_build_object('projectID',:'dropped'));
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('closePeriod',jsonb_build_object('organizationID',:'org','currentLabel','2026/2027','nextLabel','2027/2028'),'forbidden');
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('closePeriod',jsonb_build_object('organizationID',:'org','currentLabel','2025/2026','nextLabel','2027/2028'),'stale_version');
SELECT pg_temp.fails('closePeriod',jsonb_build_object('organizationID',:'org','currentLabel','2026/2027','nextLabel','  '),'invalid_input');
SELECT pg_temp.fails('closePeriod',jsonb_build_object('organizationID',:'org','currentLabel','2026/2027','nextLabel','2026/2027'),'invalid_input');
SELECT public.grouply_mutate('closePeriod',jsonb_build_object('organizationID',:'org','currentLabel','2026/2027','nextLabel','2027/2028')) AS closed \gset
SELECT (:'closed'::jsonb)->>'periodID' AS period1 \gset
SELECT pg_temp.check(((:'closed'::jsonb)->>'archived')::int=3,'completed, hand-archived and committee work get the label');
SELECT pg_temp.fails('closePeriod',jsonb_build_object('organizationID',:'org','currentLabel','2026/2027','nextLabel','2027/2028'),'stale_version');
SELECT pg_temp.check((SELECT o->>'periodLabel'='2027/2028' AND o->'periods'->0->>'label'='2026/2027' FROM (SELECT pg_temp.org(:'org') o) s),'the organization moves to the new period');
SELECT pg_temp.fails('updateOrganization',jsonb_build_object('id',:'org','name','HIMA Rencana','periodLabel','2026/2027'),'period_exists');
SELECT pg_temp.fails('closePeriod',jsonb_build_object('organizationID',:'org','currentLabel','2027/2028','nextLabel','2026/2027'),'period_exists');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.check((SELECT p->>'status'='archived' AND p->>'periodLabel'='2026/2027' FROM (SELECT pg_temp.project(:'done_proj') p) s),'completed proker is archived under the old period');
SELECT pg_temp.check(pg_temp.project(:'dropped')->>'periodLabel'='2026/2027','hand-archived proker is labelled too');
SELECT pg_temp.check((SELECT p->>'status'='active' AND p->>'periodLabel'='' FROM (SELECT pg_temp.project(:'acara') p) s),'running proker carries over');
SELECT pg_temp.fails('restoreProject',jsonb_build_object('projectID',:'dropped'),'project_read_only');

-- ORG-14 archive and report.
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.denied(format('SELECT public.grouply_org_archive(%L)',:'org'),'forbidden');
SELECT pg_temp.denied(format('SELECT public.grouply_report(%L,%L)',:'humas',:'period1'),'forbidden');
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.check((SELECT p->>'label'='2026/2027'
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(p->'projects') q WHERE q->>'id'=:'done_proj' AND (q->>'done')::int=1)
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(p->'committees') c WHERE c->>'id'=:'com')
  FROM (SELECT public.grouply_org_archive(:'org')->'periods'->0 p) s),'officers read the period archive');
SELECT pg_temp.check((SELECT r->>'period'='2026/2027' AND (r->'totals'->>'approvedAmount')::bigint=400000
  AND r->'approvals'->0->'chain'->>0 LIKE '%(disetujui)' AND jsonb_array_length(r->'meetings')=0
  FROM (SELECT public.grouply_report(:'com',:'period1') r) s),'committee report sums approved requests and skips cancelled meetings');
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.check((SELECT t->>'status'='done' AND t->>'doneAt' IS NOT NULL AND t->'links'->>0='https://contoh.id/hasil' AND t->>'assignee'='Plan fixture 4'
  AND (t->>'revisions')::int=0
  FROM (SELECT public.grouply_report(:'humas',:'period1',ARRAY[:'done_proj']::uuid[])->'projects'->0->'tasks'->0 t) s),'coordinator report carries assignee, done date and links');
SELECT pg_temp.denied(format('SELECT public.grouply_report(%L,%L,%L)',:'humas',:'period1',ARRAY[:'acara']::uuid[]),'forbidden');
SELECT public.grouply_mutate('blockUser',jsonb_build_object('id',:'staf'));
SELECT pg_temp.check(public.grouply_report(:'humas',:'period1',ARRAY[:'done_proj']::uuid[])->'projects'->0->'tasks'->0->>'assignee'='Anggota','blocked people are masked in the report');
SELECT pg_temp.actor(:'lead');
SELECT pg_temp.check((SELECT jsonb_array_length(r->'projects')=1 AND r->'projects'->0->>'id'=:'dana' AND r->'approvals'='[]'::jsonb
  FROM (SELECT public.grouply_report(:'humas') r) s),'a project lead reports only their sie and no requests');

-- Organization templates can be reported; operator removal deletes them.
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.fails('reportContent',jsonb_build_object('kind','template','id',:'seminar','reason','x'),'forbidden');
SELECT public.grouply_mutate('reportContent',jsonb_build_object('kind','template','id',:'own_tpl','reason','Isi tidak pantas'))->>'id' AS tpl_report \gset
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('reportContent',jsonb_build_object('kind','template','id',:'own_tpl','reason','Punyaku'),'forbidden');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT pg_temp.check((SELECT q->>'kind'='template' AND q->>'organizationID'=:'org' AND q->>'text' LIKE 'Bakti sosial%'
  FROM jsonb_array_elements(public.grouply_moderation('queue','{}')) q WHERE q->>'id'=:'tpl_report'),'template reports reach the operator queue');
SELECT pg_temp.check(public.grouply_moderation('review',jsonb_build_object('id',:'tpl_report','decision','removed','note','Melanggar'))->>'status'='removed','operator removes a template');
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'staf');
SELECT pg_temp.check(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.grouply_templates(:'org')) t WHERE t->>'id'=:'own_tpl'),'removed template is gone');

-- Expired plan: archive, reports and period close keep working; creating is locked.
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT public.grouply_billing('deactivatePlan',jsonb_build_object('organizationID',:'org'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'kadiv');
SELECT pg_temp.fails('applyTemplate',jsonb_build_object('templateID',:'seminar','groupID',:'humas','eventAt',now()+interval '40 days'),'plan_inactive');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','Baru','sections','[{"title":"Sie Satu","offsetDays":0,"items":[]}]'::jsonb),'plan_inactive');
SELECT pg_temp.check(public.grouply_report(:'humas',:'period1') ? 'projects','reports stay readable after the plan ends');
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('reopenCommittee',jsonb_build_object('groupID',:'com'),'plan_inactive');
SELECT pg_temp.check(public.grouply_org_archive(:'org') ? 'periods','the archive stays readable after the plan ends');
SELECT pg_temp.check(public.grouply_mutate('closePeriod',jsonb_build_object('organizationID',:'org','currentLabel','2027/2028','nextLabel','2028/2029')) ? 'periodID','a period can close after the plan ends');

-- Limits: closed committees sit outside the 30-committee limit; reopening checks it; 50 templates.
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.operator();
SELECT public.grouply_billing('activatePlan',jsonb_build_object('organizationID',:'org','seatLimit',50,'expiresAt',now()+interval '30 days'));
RESET ROLE;
WITH made AS (
  INSERT INTO public.groups(name,coordinator_id,organization_id,is_committee)
    SELECT 'Panitia '||n,:'bph'::uuid,:'org'::uuid,true FROM generate_series(1,29) n RETURNING id)
INSERT INTO public.group_members SELECT id,:'bph'::uuid FROM made;
INSERT INTO public.proker_templates(organization_id,created_by,name,sections)
  SELECT :'org'::uuid,:'bph'::uuid,'Isi '||n,'[{"title":"Sie Satu","offsetDays":0,"items":[]}]' FROM generate_series(1,50) n;
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(:'bph');
SELECT pg_temp.check(public.grouply_mutate('createDivision',jsonb_build_object('organizationID',:'org','name','Panitia ke-30','committee',true)) ? 'id','closed committees do not count toward the limit');
SELECT pg_temp.fails('createTemplate',jsonb_build_object('organizationID',:'org','name','Ke-51','sections','[{"title":"Sie Satu","offsetDays":0,"items":[]}]'::jsonb),'rate_limited');
SELECT pg_temp.actor(:'ketua');
SELECT pg_temp.fails('reopenCommittee',jsonb_build_object('groupID',:'com'),'invalid_input');

RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.denied(format('SELECT public.grouply_templates(%L)',:'org'),'permission denied');
SELECT pg_temp.denied(format('SELECT public.grouply_report(%L)',:'humas'),'permission denied');
RESET ROLE;
ROLLBACK;
