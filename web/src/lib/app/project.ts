import type { Project, Snapshot } from './types.ts';

export const PROJECT_STATUS: Record<Project['status'], { label: string; bg: string; icon: string }> = {
	active: { label: 'Aktif', bg: 'var(--sky)', icon: 'autorenew' },
	completed: { label: 'Selesai', bg: 'var(--mint)', icon: 'task_alt' },
	archived: { label: 'Diarsipkan', bg: 'var(--chip)', icon: 'inventory_2' }
};

export function projectStats(snap: Snapshot, projectID: string) {
	const tasks = snap.tasks.filter((t) => t.projectID === projectID);
	const done = tasks.filter((t) => t.status === 'done').length;
	return { tasks, done, total: tasks.length, open: tasks.length - done };
}

/** Koordinator grup, atau koordinator sie (leadID) untuk proyek kepanitiaan, boleh mengelola tugas. */
export const canManageTasks = (snap: Snapshot, project: Project) => {
	const group = snap.groups.find((g) => g.id === project.groupID);
	return group?.coordinatorID === snap.currentUserID || project.leadID === snap.currentUserID;
};
