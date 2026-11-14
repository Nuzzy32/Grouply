// Porsi kontribusi per anggota dalam satu proyek, sama dengan flutter/lib/core/contribution.dart:
// hanya tugas `done` yang dihitung, tiap tugas berbobot sama; terlambat dan revisi hanya ditampilkan.
import type { Task } from './types.ts';

export interface Contribution {
	id: string;
	done: number;
	review: number;
	active: number;
	late: number;
	percent: number;
}

/** Satu baris per anggota (plus mantan anggota yang menyelesaikan tugas), urut dari porsi terbesar.
 * Persen memakai sisa terbesar agar jumlahnya tepat 100. */
export function contributions(tasks: Task[], memberIDs: string[], now: Date): Contribution[] {
	const done = new Map<string, number>();
	for (const t of tasks) if (t.status === 'done') done.set(t.assigneeID, (done.get(t.assigneeID) ?? 0) + 1);
	const ids = [...memberIDs, ...[...done.keys()].filter((id) => !memberIDs.includes(id))];
	const total = [...done.values()].reduce((a, b) => a + b, 0);
	const exact = new Map(ids.map((id) => [id, total ? ((done.get(id) ?? 0) * 100) / total : 0]));
	const percent = new Map(ids.map((id) => [id, Math.floor(exact.get(id)!)]));
	const left = total ? 100 - [...percent.values()].reduce((a, b) => a + b, 0) : 0;
	[...ids]
		.sort((a, b) => exact.get(b)! - percent.get(b)! - (exact.get(a)! - percent.get(a)!))
		.slice(0, left)
		.forEach((id) => percent.set(id, percent.get(id)! + 1));
	const count = (id: string, test: (t: Task) => boolean) => tasks.filter((t) => t.assigneeID === id && test(t)).length;
	return ids
		.map((id) => ({
			id,
			done: done.get(id) ?? 0,
			review: count(id, (t) => t.status === 'in_review'),
			active: count(id, (t) => ['todo', 'in_progress', 'needs_revision'].includes(t.status)),
			late: count(id, (t) => t.status !== 'done' && new Date(t.dueAt) < now),
			percent: percent.get(id)!
		}))
		.sort((a, b) => b.percent - a.percent);
}
