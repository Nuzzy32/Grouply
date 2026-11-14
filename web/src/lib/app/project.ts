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

/** Anggota tidak bisa keluar/dikeluarkan selama masih memegang tugas di grup (sama dengan memberLock Flutter). */
export function memberLock(snap: Snapshot, groupID: string, userID: string): string {
	const projectIDs = new Set(snap.projects.filter((p) => p.groupID === groupID).map((p) => p.id));
	const held = snap.tasks.filter((t) => projectIDs.has(t.projectID) && (t.assigneeID === userID || t.reviewerID === userID));
	if (held.some((t) => t.status === 'in_review')) return 'Selesaikan review anggota ini sebelum keluar atau menghapus anggota.';
	if (held.some((t) => t.status !== 'done')) return 'Alihkan tugas aktif anggota ini terlebih dahulu.';
	return '';
}

/** Status undangan, urutan sama dengan _grInviteStatus di Flutter. */
export function inviteStatus(inv: { revoked: boolean; expiresAt: string; useCount: number; maxUses: number }) {
	if (inv.revoked) return { label: 'Undangan tidak berlaku', valid: false };
	if (new Date(inv.expiresAt) < new Date()) return { label: 'Undangan kedaluwarsa', valid: false };
	if (inv.useCount >= inv.maxUses) return { label: 'Undangan tidak berlaku · sudah dipakai', valid: false };
	return { label: 'Undangan aktif', valid: true };
}
