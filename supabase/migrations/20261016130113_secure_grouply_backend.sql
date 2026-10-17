SET local check_function_bodies = off;

CREATE SCHEMA "private";

CREATE TABLE "private"."content_reports" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "message_id"  uuid                     NOT NULL,
  "reporter_id" uuid                     NOT NULL,
  "reason"      text                     NOT NULL,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "content_reports_pkey" PRIMARY KEY (id),
  CONSTRAINT "content_reports_reason_check" CHECK (((length(reason) >= 1) AND (length(reason) <= 1000)))
);

ALTER TABLE "private"."content_reports"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "private"."invitations" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "group_id"   uuid                     NOT NULL,
  "token_hash" bytea                    NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at" timestamp with time zone NOT NULL DEFAULT (now() + '7 days'::interval),
  "max_uses"   integer                  NOT NULL DEFAULT 1,
  "used_count" integer                  NOT NULL DEFAULT 0,
  "revoked_at" timestamp with time zone,
  CONSTRAINT "invitations_max_uses_check" CHECK (((max_uses >= 1) AND (max_uses <= 7))),
  CONSTRAINT "invitations_pkey" PRIMARY KEY (id),
  CONSTRAINT "invitations_token_hash_key" UNIQUE (token_hash)
);

ALTER TABLE "private"."invitations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."activity_events" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "group_id"   uuid                     NOT NULL,
  "actor_id"   uuid                     NOT NULL,
  "action"     text                     NOT NULL,
  "target_id"  uuid,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "activity_events_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."activity_events"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."activity_events" FROM "anon";

CREATE TABLE "public"."chat_messages" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "group_id"   uuid                     NOT NULL,
  "task_id"    uuid,
  "sender_id"  uuid                     NOT NULL,
  "content"    text                     NOT NULL,
  "kind"       text                     NOT NULL DEFAULT 'text'::text,
  "client_id"  uuid,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "chat_messages_content_check" CHECK (((length(content) >= 1) AND (length(content) <= 2000))),
  CONSTRAINT "chat_messages_kind_check" CHECK ((kind = ANY (ARRAY['text'::text, 'activity'::text]))),
  CONSTRAINT "chat_messages_pkey" PRIMARY KEY (id),
  CONSTRAINT "chat_messages_sender_id_client_id_key" UNIQUE (sender_id, client_id)
);

ALTER TABLE "public"."chat_messages"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."chat_messages" FROM "anon";

CREATE TABLE "public"."chat_reads" (
  "user_id"    uuid NOT NULL,
  "message_id" uuid NOT NULL,
  CONSTRAINT "chat_reads_pkey" PRIMARY KEY (user_id, message_id)
);

ALTER TABLE "public"."chat_reads"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."chat_reads" FROM "anon";

CREATE TABLE "public"."group_members" (
  "group_id" uuid NOT NULL,
  "user_id"  uuid NOT NULL,
  CONSTRAINT "group_members_pkey" PRIMARY KEY (group_id, user_id)
);

ALTER TABLE "public"."group_members"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."group_members" FROM "anon";

CREATE TABLE "public"."groups" (
  "id"             uuid NOT NULL DEFAULT gen_random_uuid(),
  "name"           text NOT NULL,
  "description"    text NOT NULL DEFAULT ''::text,
  "course"         text NOT NULL DEFAULT ''::text,
  "coordinator_id" uuid NOT NULL,
  "tint"           text NOT NULL DEFAULT '#C9F2D6'::text,
  "icon"           text NOT NULL DEFAULT 'person.3.fill'::text,
  CONSTRAINT "groups_course_check" CHECK ((length(course) <= 120)),
  CONSTRAINT "groups_description_check" CHECK ((length(description) <= 1000)),
  CONSTRAINT "groups_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 80))),
  CONSTRAINT "groups_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."groups"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."groups" FROM "anon";

CREATE TABLE "public"."profiles" (
  "id"   uuid NOT NULL,
  "name" text NOT NULL,
  "tint" text NOT NULL DEFAULT '#D6E4FF'::text,
  CONSTRAINT "profiles_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 80))),
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."profiles"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."profiles" FROM "anon";

CREATE TABLE "public"."projects" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "group_id"    uuid                     NOT NULL,
  "title"       text                     NOT NULL,
  "description" text                     NOT NULL DEFAULT ''::text,
  "due_at"      timestamp with time zone NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'active'::text,
  "archived_at" timestamp with time zone,
  CONSTRAINT "projects_description_check" CHECK ((length(description) <= 2000)),
  CONSTRAINT "projects_pkey" PRIMARY KEY (id),
  CONSTRAINT "projects_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text]))),
  CONSTRAINT "projects_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 120)))
);

ALTER TABLE "public"."projects"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."projects" FROM "anon";

CREATE TABLE "public"."reviews" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "submission_id" uuid                     NOT NULL,
  "reviewer_id"   uuid                     NOT NULL,
  "decision"      text                     NOT NULL,
  "feedback"      text                     NOT NULL,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "reviews_check" CHECK (((decision = 'approved'::text) OR (length(feedback) > 0))),
  CONSTRAINT "reviews_decision_check" CHECK ((decision = ANY (ARRAY['approved'::text, 'changes_requested'::text]))),
  CONSTRAINT "reviews_feedback_check" CHECK ((length(feedback) <= 3000)),
  CONSTRAINT "reviews_pkey" PRIMARY KEY (id),
  CONSTRAINT "reviews_submission_id_key" UNIQUE (submission_id)
);

ALTER TABLE "public"."reviews"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."reviews" FROM "anon";

CREATE TABLE "public"."submissions" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "task_id"    uuid                     NOT NULL,
  "revision"   integer                  NOT NULL,
  "author_id"  uuid                     NOT NULL,
  "note"       text                     NOT NULL,
  "links"      jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "submissions_note_check" CHECK (((length(note) >= 1) AND (length(note) <= 5000))),
  CONSTRAINT "submissions_pkey" PRIMARY KEY (id),
  CONSTRAINT "submissions_task_id_revision_key" UNIQUE (task_id, revision)
);

ALTER TABLE "public"."submissions"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."submissions" FROM "anon";

CREATE TABLE "public"."tasks" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "project_id"  uuid                     NOT NULL,
  "title"       text                     NOT NULL,
  "description" text                     NOT NULL DEFAULT ''::text,
  "assignee_id" uuid                     NOT NULL,
  "reviewer_id" uuid                     NOT NULL,
  "due_at"      timestamp with time zone NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'todo'::text,
  "version"     integer                  NOT NULL DEFAULT 1,
  CONSTRAINT "tasks_check" CHECK ((assignee_id <> reviewer_id)),
  CONSTRAINT "tasks_description_check" CHECK ((length(description) <= 2000)),
  CONSTRAINT "tasks_pkey" PRIMARY KEY (id),
  CONSTRAINT "tasks_status_check" CHECK ((status = ANY (ARRAY['todo'::text, 'in_progress'::text, 'in_review'::text, 'needs_revision'::text, 'done'::text]))),
  CONSTRAINT "tasks_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 120))),
  CONSTRAINT "tasks_version_check" CHECK ((version > 0))
);

ALTER TABLE "public"."tasks"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."tasks" FROM "anon";

CREATE TABLE "public"."user_blocks" (
  "user_id"    uuid NOT NULL,
  "blocked_id" uuid NOT NULL,
  CONSTRAINT "user_blocks_check" CHECK ((user_id <> blocked_id)),
  CONSTRAINT "user_blocks_pkey" PRIMARY KEY (user_id, blocked_id)
);

ALTER TABLE "public"."user_blocks"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."user_blocks" FROM "anon";

CREATE OR REPLACE FUNCTION private.iso (
  value timestamp with time zone
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$select to_char(value at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')$function$;

CREATE OR REPLACE FUNCTION private.member (
  gid uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$select auth.uid() is not null and exists(select 1 from public.group_members where group_id=gid and user_id=auth.uid())$function$;

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
 if (select count(*) from public.chat_messages where sender_id=actor and group_id=gid and kind='text' and created_at>now()-interval '1 minute')>=20 then raise exception 'rate_limited';end if;
 insert into public.chat_messages(id,group_id,task_id,sender_id,content,client_id) values(mid,gid,tid,actor,private.txt(payload->>'text',2000),mid);return jsonb_build_object('id',mid);
 when 'generateInvite' then
 if (select count(*) from private.invitations where group_id=gid and created_at>now()-interval '1 minute')>=20 then raise exception 'rate_limited';end if;
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

CREATE OR REPLACE FUNCTION private.new_profile()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$begin insert into public.profiles(id,name) values(new.id,left(coalesce(nullif(btrim(new.raw_user_meta_data->>'name'),''),'Mahasiswa'),80));return new;end$function$;

CREATE OR REPLACE FUNCTION private.profile_visible (
  uid uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$select auth.uid() is not null and (uid=auth.uid() or exists(select 1 from public.group_members a join public.group_members b using(group_id) where a.user_id=auth.uid() and b.user_id=uid))$function$;

CREATE OR REPLACE FUNCTION private.snapshot()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare actor uuid:=auth.uid();result jsonb;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor) then raise exception 'unauthorized';end if;
 select jsonb_build_object(
 'currentUserID',actor,
 'users',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'email','','tint',u.tint) order by u.name) from public.profiles u where private.profile_visible(u.id)),'[]'),
 'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'course',g.course,'coordinatorID',g.coordinator_id,'tint',g.tint,'icon',g.icon,'memberIDs',(select jsonb_agg(user_id order by user_id) from public.group_members where group_id=g.id))) from public.groups g where private.member(g.id)),'[]'),
 'projects',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'groupID',p.group_id,'title',p.title,'description',p.description,'dueAt',private.iso(p.due_at),'status',case when p.archived_at is not null then 'archived' else p.status end,'previousStatus',case when p.archived_at is not null then p.status else null end)) from public.projects p where private.member(p.group_id)),'[]'),
 'tasks',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'projectID',t.project_id,'title',t.title,'description',t.description,'assigneeID',t.assignee_id,'reviewerID',t.reviewer_id,'dueAt',private.iso(t.due_at),'status',t.status,'version',t.version,'submissions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'revision',s.revision,'authorID',s.author_id,'note',s.note,'links',s.links,'createdAt',private.iso(s.created_at),'decision',r.decision,'feedback',r.feedback,'reviewerID',r.reviewer_id) order by s.revision) from public.submissions s left join public.reviews r on r.submission_id=s.id where s.task_id=t.id),'[]'))) from public.tasks t where private.task_group(t.id) is not null),'[]'),
 'messages',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'groupID',m.group_id,'taskID',m.task_id,'senderID',m.sender_id,'text',m.content,'createdAt',private.iso(m.created_at),'kind',m.kind,'delivery','sent','targetTaskID',case when m.kind='activity' then m.task_id else null end) order by m.created_at,m.id) from public.chat_messages m where private.member(m.group_id)),'[]'),
 'invites',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'groupID',i.group_id,'code','','createdAt',private.iso(i.created_at),'expiresAt',private.iso(i.expires_at),'maxUses',i.max_uses,'useCount',i.used_count,'revoked',i.revoked_at is not null)) from private.invitations i join public.groups g on g.id=i.group_id where g.coordinator_id=actor),'[]'),
 'reports',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'messageID',r.message_id,'reporterID',r.reporter_id,'reason',r.reason,'createdAt',private.iso(r.created_at))) from private.content_reports r join public.chat_messages m on m.id=r.message_id where r.reporter_id=actor and private.member(m.group_id)),'[]'),
 'blockedUserIDs',coalesce((select jsonb_agg(blocked_id) from public.user_blocks where user_id=actor),'[]'),
 'readMessageIDs',coalesce((select jsonb_agg(r.message_id) from public.chat_reads r join public.chat_messages m on m.id=r.message_id where r.user_id=actor and m.task_id is null and private.member(m.group_id)),'[]')) into result;
 return result;
end$function$;

CREATE OR REPLACE FUNCTION private.task_group (
  tid uuid
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$select p.group_id from public.tasks t join public.projects p on p.id=t.project_id where t.id=tid and private.member(p.group_id)$function$;

CREATE OR REPLACE FUNCTION private.txt (
  value      text,
  max_length integer,
  required   boolean DEFAULT true
)
  RETURNS text
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$declare result text:=btrim(coalesce(value,''));begin if length(result)>max_length or (required and length(result)=0) then raise exception 'invalid_input';end if;return result;end$function$;

CREATE OR REPLACE FUNCTION private.valid_links (
  links jsonb
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$select case when jsonb_typeof(links)<>'array' then false else jsonb_array_length(links)<=5 and not exists(select 1 from jsonb_array_elements(links) l where jsonb_typeof(l)<>'string' or length(l#>>'{}')>2048 or (l#>>'{}') !~* '^https://[^/@[:space:]]+(\.[^/@[:space:]]+|:[0-9]+)?(/[^[:space:]]*)?$' or (l#>>'{}') ~ '@') end$function$;

CREATE OR REPLACE FUNCTION public.grouply_mutate (
  action  text,
  payload jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$select private.mutate(action,payload)$function$;

REVOKE ALL ON FUNCTION "public"."grouply_mutate"(text, jsonb) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.grouply_snapshot()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$select private.snapshot()$function$;

REVOKE ALL ON FUNCTION "public"."grouply_snapshot"() FROM PUBLIC, "anon", "service_role";

ALTER TABLE "private"."content_reports"
  ADD CONSTRAINT "content_reports_message_id_fkey" FOREIGN KEY (message_id) REFERENCES public.chat_messages(id);

ALTER TABLE "public"."chat_reads"
  ADD CONSTRAINT "chat_reads_message_id_fkey" FOREIGN KEY (message_id) REFERENCES public.chat_messages(id);

ALTER TABLE "private"."invitations"
  ADD CONSTRAINT "invitations_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id);

ALTER TABLE "public"."activity_events"
  ADD CONSTRAINT "activity_events_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id);

ALTER TABLE "public"."chat_messages"
  ADD CONSTRAINT "chat_messages_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id);

ALTER TABLE "public"."group_members"
  ADD CONSTRAINT "group_members_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;

ALTER TABLE "public"."profiles"
  ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id);

ALTER TABLE "private"."content_reports"
  ADD CONSTRAINT "content_reports_reporter_id_fkey" FOREIGN KEY (reporter_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."activity_events"
  ADD CONSTRAINT "activity_events_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."chat_messages"
  ADD CONSTRAINT "chat_messages_sender_id_fkey" FOREIGN KEY (sender_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."chat_reads"
  ADD CONSTRAINT "chat_reads_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."group_members"
  ADD CONSTRAINT "group_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."groups"
  ADD CONSTRAINT "groups_coordinator_id_fkey" FOREIGN KEY (coordinator_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."projects"
  ADD CONSTRAINT "projects_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id);

ALTER TABLE "public"."reviews"
  ADD CONSTRAINT "reviews_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."submissions"
  ADD CONSTRAINT "submissions_author_id_fkey" FOREIGN KEY (author_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."reviews"
  ADD CONSTRAINT "reviews_submission_id_fkey" FOREIGN KEY (submission_id) REFERENCES public.submissions(id);

ALTER TABLE "public"."tasks"
  ADD CONSTRAINT "tasks_assignee_id_fkey" FOREIGN KEY (assignee_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."chat_messages"
  ADD CONSTRAINT "chat_messages_task_id_fkey" FOREIGN KEY (task_id) REFERENCES public.tasks(id);

ALTER TABLE "public"."submissions"
  ADD CONSTRAINT "submissions_task_id_fkey" FOREIGN KEY (task_id) REFERENCES public.tasks(id);

ALTER TABLE "public"."tasks"
  ADD CONSTRAINT "tasks_project_id_fkey" FOREIGN KEY (project_id) REFERENCES public.projects(id);

ALTER TABLE "public"."tasks"
  ADD CONSTRAINT "tasks_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."user_blocks"
  ADD CONSTRAINT "user_blocks_blocked_id_fkey" FOREIGN KEY (blocked_id) REFERENCES public.profiles(id);

ALTER TABLE "public"."user_blocks"
  ADD CONSTRAINT "user_blocks_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id);

CREATE INDEX invitations_group ON private.invitations USING btree (group_id);

CREATE INDEX reports_message ON private.content_reports USING btree (message_id);

CREATE INDEX reports_reporter ON private.content_reports USING btree (reporter_id);

CREATE INDEX blocks_target ON public.user_blocks USING btree (blocked_id);

CREATE INDEX events_actor ON public.activity_events USING btree (actor_id);

CREATE INDEX events_group ON public.activity_events USING btree (group_id);

CREATE INDEX group_members_user ON public.group_members USING btree (user_id, group_id);

CREATE INDEX messages_group ON public.chat_messages USING btree (group_id, created_at, id);

CREATE INDEX messages_task ON public.chat_messages USING btree (task_id);

CREATE INDEX projects_group ON public.projects USING btree (group_id);

CREATE INDEX reads_message ON public.chat_reads USING btree (message_id);

CREATE INDEX reviews_reviewer ON public.reviews USING btree (reviewer_id);

CREATE INDEX submissions_author ON public.submissions USING btree (author_id);

CREATE INDEX tasks_assignee ON public.tasks USING btree (assignee_id);

CREATE INDEX tasks_project ON public.tasks USING btree (project_id);

CREATE INDEX tasks_reviewer ON public.tasks USING btree (reviewer_id);

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION private.new_profile();

CREATE POLICY "event_read" ON "public"."activity_events"
  FOR SELECT
  TO "authenticated"
  USING (private.member(group_id));

CREATE POLICY "message_read" ON "public"."chat_messages"
  FOR SELECT
  TO "authenticated"
  USING (private.member(group_id));

CREATE POLICY "chat_read" ON "public"."chat_reads"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.chat_messages m
  WHERE (m.id = chat_reads.message_id)))));

CREATE POLICY "member_read" ON "public"."group_members"
  FOR SELECT
  TO "authenticated"
  USING (private.member(group_id));

CREATE POLICY "group_read" ON "public"."groups"
  FOR SELECT
  TO "authenticated"
  USING (private.member(id));

CREATE POLICY "profile_read" ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING (private.profile_visible(id));

CREATE POLICY "project_read" ON "public"."projects"
  FOR SELECT
  TO "authenticated"
  USING (private.member(group_id));

CREATE POLICY "review_read" ON "public"."reviews"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM public.submissions s
  WHERE (s.id = reviews.submission_id))));

CREATE POLICY "submission_read" ON "public"."submissions"
  FOR SELECT
  TO "authenticated"
  USING ((private.task_group(task_id) IS NOT NULL));

CREATE POLICY "task_read" ON "public"."tasks"
  FOR SELECT
  TO "authenticated"
  USING ((private.task_group(id) IS NOT NULL));

CREATE POLICY "block_read" ON "public"."user_blocks"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

REVOKE ALL ON FUNCTION "private"."iso"(timestamp WITH time zone) FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."member"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."member"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."mutate"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."mutate"(text, jsonb) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."new_profile"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."profile_visible"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."profile_visible"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."snapshot"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."snapshot"() TO "authenticated";

REVOKE ALL ON FUNCTION "private"."task_group"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."task_group"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."txt"(text, integer, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."valid_links"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."grouply_mutate"(text, jsonb) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."grouply_mutate"(text, jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."grouply_mutate"(text, jsonb) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."grouply_snapshot"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."grouply_snapshot"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."grouply_snapshot"() TO "postgres";

GRANT USAGE ON SCHEMA "private" TO "authenticated";

REVOKE ALL ON TABLE "public"."activity_events" FROM "authenticated";

GRANT SELECT ON TABLE "public"."activity_events" TO "authenticated";

REVOKE ALL ON TABLE "public"."activity_events" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."activity_events" TO "postgres";

REVOKE ALL ON TABLE "public"."activity_events" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."activity_events" TO "service_role";

REVOKE ALL ON TABLE "public"."chat_messages" FROM "authenticated";

GRANT SELECT ON TABLE "public"."chat_messages" TO "authenticated";

REVOKE ALL ON TABLE "public"."chat_messages" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."chat_messages" TO "postgres";

REVOKE ALL ON TABLE "public"."chat_messages" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."chat_messages" TO "service_role";

REVOKE ALL ON TABLE "public"."chat_reads" FROM "authenticated";

GRANT SELECT ON TABLE "public"."chat_reads" TO "authenticated";

REVOKE ALL ON TABLE "public"."chat_reads" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."chat_reads" TO "postgres";

REVOKE ALL ON TABLE "public"."chat_reads" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."chat_reads" TO "service_role";

REVOKE ALL ON TABLE "public"."group_members" FROM "authenticated";

GRANT SELECT ON TABLE "public"."group_members" TO "authenticated";

REVOKE ALL ON TABLE "public"."group_members" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."group_members" TO "postgres";

REVOKE ALL ON TABLE "public"."group_members" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."group_members" TO "service_role";

REVOKE ALL ON TABLE "public"."groups" FROM "authenticated";

GRANT SELECT ON TABLE "public"."groups" TO "authenticated";

REVOKE ALL ON TABLE "public"."groups" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."groups" TO "postgres";

REVOKE ALL ON TABLE "public"."groups" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."groups" TO "service_role";

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ON TABLE "public"."profiles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "postgres";

REVOKE ALL ON TABLE "public"."profiles" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."profiles" TO "service_role";

REVOKE ALL ON TABLE "public"."projects" FROM "authenticated";

GRANT SELECT ON TABLE "public"."projects" TO "authenticated";

REVOKE ALL ON TABLE "public"."projects" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."projects" TO "postgres";

REVOKE ALL ON TABLE "public"."projects" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."projects" TO "service_role";

REVOKE ALL ON TABLE "public"."reviews" FROM "authenticated";

GRANT SELECT ON TABLE "public"."reviews" TO "authenticated";

REVOKE ALL ON TABLE "public"."reviews" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."reviews" TO "postgres";

REVOKE ALL ON TABLE "public"."reviews" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."reviews" TO "service_role";

REVOKE ALL ON TABLE "public"."submissions" FROM "authenticated";

GRANT SELECT ON TABLE "public"."submissions" TO "authenticated";

REVOKE ALL ON TABLE "public"."submissions" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."submissions" TO "postgres";

REVOKE ALL ON TABLE "public"."submissions" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."submissions" TO "service_role";

REVOKE ALL ON TABLE "public"."tasks" FROM "authenticated";

GRANT SELECT ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ON TABLE "public"."tasks" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tasks" TO "postgres";

REVOKE ALL ON TABLE "public"."tasks" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."tasks" TO "service_role";

REVOKE ALL ON TABLE "public"."user_blocks" FROM "authenticated";

GRANT SELECT ON TABLE "public"."user_blocks" TO "authenticated";

REVOKE ALL ON TABLE "public"."user_blocks" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_blocks" TO "postgres";

REVOKE ALL ON TABLE "public"."user_blocks" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."user_blocks" TO "service_role";

ALTER TABLE "public"."submissions"
  ADD CONSTRAINT "submissions_https_links" CHECK (private.valid_links(links));

