CREATE OR REPLACE FUNCTION private.snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN RAISE EXCEPTION 'unauthorized'; END IF;
 SELECT jsonb_build_object(
 'currentUserID',actor,
 'users',coalesce((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'email','','tint',u.tint) ORDER BY u.name) FROM public.profiles u WHERE private.profile_visible(u.id)),'[]'),
 'groups',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'course',g.course,'coordinatorID',coalesce(g.coordinator_id::text,''),'tint',g.tint,'icon',g.icon,'memberIDs',(SELECT jsonb_agg(user_id ORDER BY user_id) FROM public.group_members WHERE group_id=g.id))) FROM public.groups g WHERE private.member(g.id)),'[]'),
 'projects',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'groupID',p.group_id,'title',p.title,'description',p.description,'dueAt',private.iso(p.due_at),'status',CASE WHEN p.archived_at IS NOT NULL THEN 'archived' ELSE p.status END,'previousStatus',CASE WHEN p.archived_at IS NOT NULL THEN p.status ELSE NULL END)) FROM public.projects p WHERE private.member(p.group_id)),'[]'),
 'tasks',coalesce((SELECT jsonb_agg(jsonb_build_object('id',t.id,'projectID',t.project_id,'title',t.title,'description',t.description,'assigneeID',coalesce(t.assignee_id::text,''),'reviewerID',coalesce(t.reviewer_id::text,''),'dueAt',private.iso(t.due_at),'status',t.status,'version',t.version,'submissions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'revision',s.revision,'authorID',coalesce(s.author_id::text,''),'note',s.note,'links',s.links,'createdAt',private.iso(s.created_at),'decision',r.decision,'feedback',r.feedback,'reviewerID',coalesce(r.reviewer_id::text,'')) ORDER BY s.revision) FROM public.submissions s LEFT JOIN public.reviews r ON r.submission_id=s.id WHERE s.task_id=t.id),'[]'))) FROM public.tasks t WHERE private.task_group(t.id) IS NOT NULL),'[]'),
 'messages',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'groupID',m.group_id,'taskID',m.task_id,'senderID',coalesce(m.sender_id::text,''),'text',m.content,'createdAt',private.iso(m.created_at),'kind',m.kind,'delivery','sent','targetTaskID',CASE WHEN m.kind='activity' THEN m.task_id ELSE NULL END) ORDER BY m.created_at,m.id) FROM public.chat_messages m WHERE private.member(m.group_id)),'[]'),
 'invites',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'groupID',i.group_id,'code','','createdAt',private.iso(i.created_at),'expiresAt',private.iso(i.expires_at),'maxUses',i.max_uses,'useCount',i.used_count,'revoked',i.revoked_at IS NOT NULL)) FROM private.invitations i JOIN public.groups g ON g.id=i.group_id WHERE g.coordinator_id=actor),'[]'),
 'reports',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'messageID',r.message_id,'reporterID',r.reporter_id,'reason',r.reason,'createdAt',private.iso(r.created_at),'status',r.status,'reviewedAt',private.iso(r.reviewed_at))) FROM private.content_reports r WHERE r.reporter_id=actor),'[]'),
 'blockedUserIDs',coalesce((SELECT jsonb_agg(blocked_id) FROM public.user_blocks WHERE user_id=actor),'[]'),
 'readMessageIDs',coalesce((SELECT jsonb_agg(r.message_id) FROM public.chat_reads r JOIN public.chat_messages m ON m.id=r.message_id WHERE r.user_id=actor AND m.task_id IS NULL AND private.member(m.group_id)),'[]')) INTO result;
 RETURN result;
END;
$$;
