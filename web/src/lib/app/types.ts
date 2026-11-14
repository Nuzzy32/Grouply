// Bentuk hasil RPC grouply_snapshot (private.snapshot, migration org_plan). Hanya field yang dipakai web.
export type TaskStatus = 'todo' | 'in_progress' | 'in_review' | 'needs_revision' | 'done';

export interface User {
	id: string;
	name: string;
	tint: string;
}

export interface Group {
	id: string;
	name: string;
	description: string;
	course: string;
	coordinatorID: string;
	tint: string;
	icon: string;
	organizationID: string;
	isCommittee: boolean;
	closed: boolean;
	memberIDs: string[];
}

export interface Project {
	id: string;
	groupID: string;
	title: string;
	description: string;
	dueAt: string;
	status: 'active' | 'completed' | 'archived';
	previousStatus: 'active' | 'completed' | null;
	leadID: string;
}

export interface Submission {
	id: string;
	revision: number;
	authorID: string;
	note: string;
	links: string[];
	createdAt: string;
	decision: 'approved' | 'changes_requested' | null;
	feedback: string;
	reviewerID: string;
}

export interface Task {
	id: string;
	projectID: string;
	title: string;
	description: string;
	assigneeID: string;
	reviewerID: string;
	dueAt: string;
	status: TaskStatus;
	version: number;
	submissions: Submission[];
}

export interface Message {
	id: string;
	groupID: string;
	taskID: string | null;
	senderID: string;
	text: string;
	createdAt: string;
	kind: 'text' | 'activity';
	targetTaskID: string | null;
}

export interface Snapshot {
	currentUserID: string;
	users: User[];
	groups: Group[];
	projects: Project[];
	tasks: Task[];
	messages: Message[];
	reports: { id: string; messageID: string; kind: string; targetID: string }[];
	blockedUserIDs: string[];
	readMessageIDs: string[];
}
