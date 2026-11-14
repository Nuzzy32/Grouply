import type { Message, Snapshot } from './types.ts';

/** Pesan chat grup yang belum dibaca, aturan sama dengan _grUnread di Flutter. */
export function unreadCount(snap: Snapshot, groupID: string): number {
	const read = new Set(snap.readMessageIDs);
	return snap.messages.filter(
		(m) => m.groupID === groupID && !m.taskID && m.senderID !== snap.currentUserID && !read.has(m.id)
	).length;
}

export function myGroups(snap: Snapshot) {
	return snap.groups.filter((g) => g.memberIDs.includes(snap.currentUserID));
}

export const userName = (snap: Snapshot, id: string) =>
	id === snap.currentUserID ? 'Kamu' : (snap.users.find((u) => u.id === id)?.name ?? 'Anggota');

/** Pesan aktivitas di chat grup berbentuk "Mengirim hasil · Judul tugas". */
export function splitActivity(m: Message): { verb: string; title: string } {
	const at = m.text.indexOf(' · ');
	return at < 0 ? { verb: m.text, title: '' } : { verb: m.text.slice(0, at), title: m.text.slice(at + 3) };
}
