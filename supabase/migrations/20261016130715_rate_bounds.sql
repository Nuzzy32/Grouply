SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION private.mutate (
  action  text,
  payload jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare actor uuid:=auth.uid();g public.groups;p public.projects;t public.tasks;s public.submissions;inv private.invitations;mid uuid;gid uuid;pid uuid;tid uuid;uid uuid;rid uuid;result_id uuid;token text;body text;link text;link_data jsonb;old public.chat_messages;target uuid;is_coord boolean:=false;is_task boolean:=false;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor) then raise exception 'unauthorized';end if;
 if action='deleteAccount' then raise exception 'account_deletion_unavailable';end if;
 if action='createGroup' then
 insert into public.groups(name,description,course,coordinator_id) values(private.txt(payload->>'name',80),private.txt(payload->>'description',1000,false),private.txt(payload->>'course',120,false),actor) returning id into gid;
 insert into public.group_members values(gid,actor);return jsonb_build_object('id',gid);
 elsif action='updateProfile' then update public.profiles set name=private.txt(payload->>'name',80) where id=actor;return '{}'::jsonb;
 elsif action in ('blockUser','unblockUser') then
 uid:=coalesce(payload->>'id',payload->>'userID')::uuid;
 if uid=actor or not private.profile_visible(uid) or not exists(select 1 from public.profiles where id=uid) then raise exception 'forbidden';end if;
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
 if (select count(*) from public.group_members where group_id=gid)>=8 then raise exception 'group_full';end if;
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
 token:=encode(extensions.gen_random_bytes(32),'hex');insert into private.invitations(group_id,token_hash) values(gid,extensions.digest(token,'sha256')) returning * into inv;
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
 when 'markChatRead' then insert into public.chat_reads select actor,id from public.chat_messages where group_id=gid on conflict do nothing;
 else raise exception 'invalid_input';
 end case;
 insert into public.activity_events(group_id,actor_id,action,target_id) values(gid,actor,action,coalesce(tid,pid,target));
 if tid is not null and action in ('createTask','updateTask','reassignTask','submitWork','review','reopenTask') then
 body:=case action when 'createTask' then 'Membuat tugas' when 'updateTask' then 'Mengubah detail tugas' when 'reassignTask' then 'Mengalihkan tugas' when 'submitWork' then 'Mengirim hasil' when 'review' then case when (payload->>'approve')::boolean then 'Menyetujui tugas' else 'Meminta revisi' end else 'Membuka kembali tugas' end;
 insert into public.chat_messages(group_id,task_id,sender_id,content,kind) values(gid,null,actor,body||' · '||(select title from public.tasks where id=tid),'activity'),(gid,tid,actor,body,'activity');end if;
 return case when result_id is null then '{}'::jsonb else jsonb_build_object('id',result_id) end;
end$function$;

