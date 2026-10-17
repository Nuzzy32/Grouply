-- Run using psql -v ON_ERROR_STOP=1. Fixtures always roll back.
begin;
create function pg_temp.check(ok boolean,label text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'FAILED: %',label;end if;raise notice 'PASS: %',label;end$$;
create function pg_temp.denied(action text,payload jsonb,expected text) returns void language plpgsql as $$begin perform public.grouply_mutate(action,payload);raise exception 'unexpected success';exception when others then if sqlerrm not like '%'||expected||'%' then raise exception 'Expected %, got %',expected,sqlerrm;end if;end$$;
insert into auth.users(id,raw_user_meta_data) values('10000000-0000-0000-0000-000000000001','{"name":"Alex"}'),('10000000-0000-0000-0000-000000000002','{"name":"Raka"}'),('10000000-0000-0000-0000-000000000003','{"name":"Nadia"}');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.grouply_mutate('createGroup','{"name":"Kelompok A"}')->>'id' as ga \gset
select public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'ga'))->'invite'->>'code' as code \gset
select pg_temp.check(length(:'code')=64,'invite uses random 256 bit token');
select pg_temp.check(not(public.grouply_snapshot()::text like '%'||:'code'||'%'),'snapshot never leaks invite token');
select public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'ga'))->'invite' as revoked_inv \gset
select public.grouply_mutate('revokeInvite',jsonb_build_object('id',(:'revoked_inv'::jsonb)->>'id'));
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select pg_temp.denied('joinGroup',jsonb_build_object('code',(:'revoked_inv'::jsonb)->>'code'),'invalid_input');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);

select pg_temp.check(not has_table_privilege('authenticated','public.tasks','INSERT'),'direct task INSERT denied');
do $$begin insert into public.groups(name,coordinator_id) values('Forged','10000000-0000-0000-0000-000000000001');raise exception 'unexpected success';exception when insufficient_privilege then raise notice 'PASS: real direct DML attempt denied';end$$;
select pg_temp.check(not has_table_privilege('authenticated','public.chat_messages','INSERT'),'forged system message denied');
select pg_temp.check(not has_function_privilege('anon','public.grouply_snapshot()','EXECUTE'),'anonymous RPC denied');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.check((select count(*)=0 from public.groups),'cross-group SELECT hidden');
select pg_temp.denied('createProject',jsonb_build_object('groupID',:'ga','title','IDOR','dueAt',now()+interval '1 day'),'forbidden');
select pg_temp.check(public.grouply_mutate('joinGroup',jsonb_build_object('code',:'code'))->>'id'=:'ga','invited member joins');
select pg_temp.check(public.grouply_mutate('joinGroup',jsonb_build_object('code',:'code'))->>'id'=:'ga','join retry idempotent');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grouply_mutate('createGroup','{"name":"Kelompok B"}')->>'id' as gb \gset
select pg_temp.denied('joinGroup',jsonb_build_object('code',:'code'),'invite_full');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select pg_temp.check((select count(*)=0 from public.groups where id=:'gb'),'second tenant never visible');
select public.grouply_mutate('createProject',jsonb_build_object('groupID',:'ga','title','Project','dueAt',now()+interval '7 days'))->>'id' as pid \gset
select public.grouply_mutate('createTask',jsonb_build_object('projectID',:'pid','title','Task','assigneeID','10000000-0000-0000-0000-000000000002','reviewerID','10000000-0000-0000-0000-000000000001','dueAt',now()+interval '2 days'))->>'id' as tid \gset
select pg_temp.denied('removeMember',jsonb_build_object('groupID',:'ga','userID','10000000-0000-0000-0000-000000000002'),'active_assignment');
select pg_temp.denied('startTask',jsonb_build_object('id',:'tid','expectedVersion',1),'forbidden');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.grouply_mutate('startTask',jsonb_build_object('id',:'tid','expectedVersion',1));
select pg_temp.denied('submitWork',jsonb_build_object('taskID',:'tid','expectedVersion',1,'note','Work','links',jsonb_build_array('https://example.com')),'stale_version');
select pg_temp.denied('submitWork',jsonb_build_object('taskID',:'tid','expectedVersion',2,'note','Work','links',jsonb_build_array('javascript:alert(1)')),'invalid_input');
select public.grouply_mutate('submitWork',jsonb_build_object('taskID',:'tid','expectedVersion',2,'note','Work','links',jsonb_build_array('https://example.com')));
select pg_temp.denied('review',jsonb_build_object('taskID',:'tid','expectedVersion',3,'approve',true),'forbidden');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select pg_temp.denied('reassignTask',jsonb_build_object('id',:'tid','expectedVersion',3,'assigneeID','10000000-0000-0000-0000-000000000001','reviewerID','10000000-0000-0000-0000-000000000002'),'already_reviewed');
select public.grouply_mutate('review',jsonb_build_object('taskID',:'tid','expectedVersion',3,'approve',false,'feedback','Perbaiki'));
select pg_temp.check((select status='needs_revision' from public.tasks where id=:'tid'),'revision requested atomically');
select public.grouply_mutate('reassignTask',jsonb_build_object('id',:'tid','expectedVersion',4,'assigneeID','10000000-0000-0000-0000-000000000002','reviewerID','10000000-0000-0000-0000-000000000001'));
select pg_temp.check((select status='needs_revision' from public.tasks where id=:'tid'),'reassign preserves needs revision');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.grouply_mutate('submitWork',jsonb_build_object('taskID',:'tid','expectedVersion',5,'note','Revisi','links','[]'::jsonb));
select pg_temp.check((select count(*)=2 from public.submissions where task_id=:'tid'),'revision history append only');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.grouply_mutate('review',jsonb_build_object('taskID',:'tid','expectedVersion',6,'approve',true));
select pg_temp.denied('review',jsonb_build_object('taskID',:'tid','expectedVersion',6,'approve',true),'stale_version');
select public.grouply_mutate('completeProject',jsonb_build_object('id',:'pid'));
select pg_temp.denied('reopenTask',jsonb_build_object('id',:'tid','expectedVersion',7),'project_read_only');
select public.grouply_mutate('archiveProject',jsonb_build_object('id',:'pid'));
select pg_temp.denied('reopenTask',jsonb_build_object('id',:'tid','expectedVersion',7),'project_read_only');
select public.grouply_mutate('restoreProject',jsonb_build_object('id',:'pid'));
select pg_temp.check((select status='completed' and archived_at is null from public.projects where id=:'pid'),'restore preserves completed status');
select public.grouply_mutate('sendMessage',jsonb_build_object('groupID',:'ga','text','Halo','clientID','20000000-0000-0000-0000-000000000001'));
select public.grouply_mutate('sendMessage',jsonb_build_object('groupID',:'ga','text','Halo','clientID','20000000-0000-0000-0000-000000000001'));
select pg_temp.check((select count(*)=1 from public.chat_messages where client_id='20000000-0000-0000-0000-000000000001'),'message retry no duplicates');
do $$declare n integer;begin for n in 2..30 loop perform public.grouply_mutate('sendMessage',jsonb_build_object('groupID',(select id from public.groups where name='Kelompok A'),'text','Rate bound fixture','clientID',('20000000-0000-0000-0000-'||lpad(n::text,12,'0'))));end loop;end$$;
select pg_temp.denied('sendMessage',jsonb_build_object('groupID',:'ga','text','Over limit','clientID','20000000-0000-0000-0000-000000000031'),'rate_limited');
select pg_temp.check(public.grouply_mutate('sendMessage',jsonb_build_object('groupID',:'ga','text','Halo','clientID','20000000-0000-0000-0000-000000000001'))->>'id'='20000000-0000-0000-0000-000000000001','retry remains idempotent at message cap');

select public.grouply_mutate('blockUser','{"id":"10000000-0000-0000-0000-000000000002"}');
select public.grouply_mutate('removeMember',jsonb_build_object('groupID',:'ga','userID','10000000-0000-0000-0000-000000000002'));
select pg_temp.check((select count(*)=0 from public.profiles where id='10000000-0000-0000-0000-000000000002'),'former member profile stays hidden');
select public.grouply_mutate('unblockUser','{"id":"10000000-0000-0000-0000-000000000002"}');
select pg_temp.check((select count(*)=0 from public.user_blocks where blocked_id='10000000-0000-0000-0000-000000000002'),'unblock succeeds after last shared membership ends');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.check((select count(*)=0 from public.chat_messages),'access revoked immediately');
select pg_temp.denied('sendMessage',jsonb_build_object('groupID',:'ga','text','retry','clientID','20000000-0000-0000-0000-000000000002'),'forbidden');
select pg_temp.check(jsonb_array_length(public.grouply_snapshot()->'groups')=0,'snapshot excludes removed group');

select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'ga'))->'invite' as expired_inv \gset
reset role;
update private.invitations set expires_at=now()-interval '1 second' where id=((:'expired_inv'::jsonb)->>'id')::uuid;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.denied('joinGroup',jsonb_build_object('code',(:'expired_inv'::jsonb)->>'code'),'invite_expired');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'ga'))->'invite'->>'code' as full_code \gset
reset role;
insert into auth.users(id,raw_user_meta_data) select ('10000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'{"name":"Capacity fixture"}' from generate_series(4,9) n;
insert into public.group_members(group_id,user_id) select :'ga'::uuid,id from auth.users where id in ('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000009');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.denied('joinGroup',jsonb_build_object('code',:'full_code'),'group_full');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$declare n integer;gid uuid:=(select id from public.groups where name='Kelompok A');begin for n in 5..10 loop perform public.grouply_mutate('generateInvite',jsonb_build_object('groupID',gid));end loop;end$$;
select pg_temp.denied('generateInvite',jsonb_build_object('groupID',:'ga'),'rate_limited');
rollback;
