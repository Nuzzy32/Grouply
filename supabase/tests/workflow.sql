-- Run using psql -v ON_ERROR_STOP=1. Fixtures always roll back.
begin;
create function pg_temp.check(ok boolean,label text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'FAILED: %',label;end if;raise notice 'PASS: %',label;end$$;
create function pg_temp.denied(action text,payload jsonb,expected text) returns void language plpgsql as $$begin perform public.grouply_mutate(action,payload);raise exception 'unexpected success';exception when others then if sqlerrm not like '%'||expected||'%' then raise exception 'Expected %, got %',expected,sqlerrm;end if;end$$;
select pg_temp.check((select pubinsert and pubupdate and not pubdelete and not pubtruncate and not puballtables from pg_publication where pubname='supabase_realtime'),'Realtime publishes INSERT/UPDATE only, never unprotected DELETE');
select pg_temp.check((select array_agg(tablename::text order by tablename)=array['chat_messages','chat_reads','user_sync_state'] from pg_publication_tables where pubname='supabase_realtime' and schemaname='public'),'Realtime contains only messages, reads, and own-user invalidation');
select pg_temp.check(not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname<>'public'),'Realtime excludes private tables');
select pg_temp.check(not exists(select 1 from (values ('chat_messages'),('chat_reads'),('user_sync_state')) tables(name) cross join (values ('INSERT'),('UPDATE'),('DELETE')) privileges(name) where has_table_privilege('authenticated','public.'||tables.name,privileges.name)),'Realtime tables deny every direct client write');
select pg_temp.check(not exists(select 1 from (values ('chat_messages'),('chat_reads'),('user_sync_state')) tables(name) where has_table_privilege('anon','public.'||tables.name,'SELECT')),'anonymous users cannot read Realtime payload tables');
select pg_temp.check((select array_agg(column_name::text order by ordinal_position)=array['user_id','revision'] from information_schema.columns where table_schema='public' and table_name='user_sync_state'),'membership invalidation contains only owner ID and revision, no group or message payload');
select pg_temp.check(not has_function_privilege('authenticated','private.invalidate_membership()','EXECUTE'),'client cannot invoke membership invalidation trigger');
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
select revision as before_join_revision from public.user_sync_state where user_id=auth.uid() \gset
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.check((select count(*)=0 from public.groups),'cross-group SELECT hidden');
select pg_temp.denied('createProject',jsonb_build_object('groupID',:'ga','title','IDOR','dueAt',now()+interval '1 day'),'forbidden');
select pg_temp.check(public.grouply_mutate('joinGroup',jsonb_build_object('code',:'code'))->>'id'=:'ga','invited member joins');
select pg_temp.check((select count(*)=1 and bool_and(user_id=auth.uid()) from public.user_sync_state),'membership invalidation visible only to its owner');
select pg_temp.check(public.grouply_mutate('joinGroup',jsonb_build_object('code',:'code'))->>'id'=:'ga','join retry idempotent');
select revision as before_leave_revision from public.user_sync_state where user_id=auth.uid() \gset
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select pg_temp.check((select revision>:'before_join_revision'::bigint from public.user_sync_state where user_id=auth.uid()),'existing member receives join invalidation');
select revision as after_join_revision from public.user_sync_state where user_id=auth.uid() \gset
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.grouply_mutate('leaveGroup',jsonb_build_object('id',:'ga'));
select pg_temp.check((select revision>:'before_leave_revision'::bigint from public.user_sync_state where user_id=auth.uid()),'voluntary leave invalidates former member');
select revision as before_rejoin_revision from public.user_sync_state where user_id=auth.uid() \gset
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select pg_temp.check((select revision>:'after_join_revision'::bigint from public.user_sync_state where user_id=auth.uid()),'existing member receives leave invalidation');
select public.grouply_mutate('generateInvite',jsonb_build_object('groupID',:'ga'))->'invite'->>'code' as rejoin_code \gset
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.grouply_mutate('joinGroup',jsonb_build_object('code',:'rejoin_code'));
select pg_temp.check((select revision>:'before_rejoin_revision'::bigint from public.user_sync_state where user_id=auth.uid()),'rejoin updates existing sync row');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grouply_mutate('createGroup','{"name":"Kelompok B"}')->>'id' as gb \gset
select public.grouply_mutate('sendMessage',jsonb_build_object('groupID',:'gb','text','Other tenant','clientID','30000000-0000-0000-0000-000000000001'));
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
select public.grouply_mutate('markChatRead',jsonb_build_object('groupID',:'ga','messageIDs',jsonb_build_array('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',gen_random_uuid(),(select id from public.chat_messages where task_id is not null limit 1))));
select pg_temp.check((select count(*)=1 from public.chat_reads),'observed group-chat IDs only; duplicate, task, missing, and other-tenant IDs ignored');
select pg_temp.check(not exists(select 1 from public.chat_reads where message_id='20000000-0000-0000-0000-000000000002'),'unobserved incoming message remains unread');
select public.grouply_mutate('markChatRead',jsonb_build_object('groupID',:'ga','messageIDs','[]'::jsonb));
select pg_temp.check((select count(*)=1 from public.chat_reads),'empty observation does not mark messages read');
select pg_temp.denied('markChatRead',jsonb_build_object('groupID',:'ga','messageIDs',null),'invalid_input');
select pg_temp.denied('markChatRead',jsonb_build_object('groupID',:'ga','messageIDs','not-an-array'),'invalid_input');
select pg_temp.denied('markChatRead',jsonb_build_object('groupID',:'ga','messageIDs',jsonb_build_array(null)),'invalid_input');
select pg_temp.denied('markChatRead',jsonb_build_object('groupID',:'ga','messageIDs',jsonb_build_array(42)),'invalid_input');
select pg_temp.denied('markChatRead',jsonb_build_object('groupID',:'ga','messageIDs',jsonb_build_array('not-a-uuid')),'invalid_input');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.check((select count(*)=0 from public.chat_reads),'read markers are hidden from other members');
select public.grouply_mutate('markChatRead',jsonb_build_object('groupID',:'ga'));
select pg_temp.check((select count(*)=(select count(*) from public.chat_messages where group_id=:'ga') from public.chat_reads),'omitted messageIDs preserves existing mark-all behavior');
select revision as removed_revision from public.user_sync_state where user_id=auth.uid() \gset
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select revision as coordinator_revision from public.user_sync_state where user_id=auth.uid() \gset

select public.grouply_mutate('blockUser','{"id":"10000000-0000-0000-0000-000000000002"}');
select public.grouply_mutate('removeMember',jsonb_build_object('groupID',:'ga','userID','10000000-0000-0000-0000-000000000002'));
select pg_temp.check((select revision>:'coordinator_revision'::bigint from public.user_sync_state where user_id=auth.uid()),'remaining members receive membership invalidation');
select pg_temp.check((select count(*)=0 from public.profiles where id='10000000-0000-0000-0000-000000000002'),'former member profile stays hidden');
select public.grouply_mutate('unblockUser','{"id":"10000000-0000-0000-0000-000000000002"}');
select pg_temp.check((select count(*)=0 from public.user_blocks where blocked_id='10000000-0000-0000-0000-000000000002'),'unblock succeeds after last shared membership ends');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.check((select count(*)=0 from public.chat_messages),'access revoked immediately');
select pg_temp.check((select count(*)=0 from public.chat_reads),'removed member cannot read previous read markers');
select pg_temp.check((select count(*)=1 and bool_and(revision>:'removed_revision'::bigint) from public.user_sync_state),'removed member receives own payload-free invalidation after losing access');
select pg_temp.denied('markChatRead',jsonb_build_object('groupID',:'ga','messageIDs',jsonb_build_array('20000000-0000-0000-0000-000000000001')),'forbidden');
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
do $$declare n integer;gid uuid:=(select id from public.groups where name='Kelompok A');begin for n in 6..10 loop perform public.grouply_mutate('generateInvite',jsonb_build_object('groupID',gid));end loop;end$$;
select pg_temp.denied('generateInvite',jsonb_build_object('groupID',:'ga'),'rate_limited');
rollback;
