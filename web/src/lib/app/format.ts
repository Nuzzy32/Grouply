import type { TaskStatus } from './types.ts';

// Label, warna, dan ikon status: sama dengan GLStatus di Flutter dan desain Grouply Web.
export const STATUS: Record<TaskStatus, { label: string; bg: string; icon: string; ring: string }> = {
	todo: { label: 'Belum dimulai', bg: 'var(--butter)', icon: 'radio_button_unchecked', ring: 'var(--ring-todo)' },
	in_progress: { label: 'Sedang dikerjakan', bg: 'var(--sky)', icon: 'autorenew', ring: 'var(--ring-progress)' },
	in_review: { label: 'Menunggu review', bg: 'var(--lavender)', icon: 'visibility', ring: 'var(--ring-review)' },
	needs_revision: { label: 'Perlu revisi', bg: 'var(--coral)', icon: 'undo', ring: 'var(--ring-revision)' },
	done: { label: 'Selesai', bg: 'var(--mint)', icon: 'check_circle', ring: 'var(--ring-done)' }
};

const DARK: Record<string, string> = {
	DED2FF: '#3A3354',
	C9F2D6: '#1F3D2B',
	D8EAF4: '#1E3442',
	F9E9BE: '#413720',
	F6CED1: '#47282B',
	ECEEEB: '#26292B',
	FFFFFF: '#1C1E20'
};

/** Warna pastel dari data ("#DED2FF") untuk kedua mode, aturan sama dengan glTint di Flutter. */
export function tint(hex: string | undefined): string {
	const raw = (hex ?? '').replace('#', '').toUpperCase();
	if (!/^[0-9A-F]{6}$/.test(raw)) return 'var(--lavender)';
	const dark =
		DARK[raw] ??
		'#' +
			[0, 2, 4]
				.map((i, k) => Math.floor(parseInt(raw.slice(i, i + 2), 16) * 0.28 + [0x1c, 0x1e, 0x20][k] * 0.72))
				.map((v) => v.toString(16).padStart(2, '0'))
				.join('');
	return `light-dark(#${raw}, ${dark})`;
}

/** Ikon grup disimpan sebagai nama SF Symbol (dipakai client iOS/Flutter). */
export function groupIcon(sf: string): string {
	if (sf.startsWith('building')) return 'apartment';
	if (sf.startsWith('person.2')) return 'group';
	return 'groups';
}

export function initials(name: string | undefined): string {
	const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
	if (!parts.length) return '?';
	return (parts.length > 1 ? parts[0][0] + parts[1][0] : parts[0].slice(0, 2)).toUpperCase();
}

export const firstName = (name: string | undefined) => (name ?? '').trim().split(/\s+/)[0] || 'kamu';

const DAY_MS = 86_400_000;
const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
/** Selisih hari kalender (0 = hari ini, 1 = besok, -1 = kemarin). */
export const dayOffset = (value: Date, now: Date) => Math.round((startOfDay(value) - startOfDay(now)) / DAY_MS);

const fmt = (opts: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat('id-ID', opts);
const timeFmt = fmt({ hour: '2-digit', minute: '2-digit', hour12: false });
const dateFmt = fmt({ day: 'numeric', month: 'short' });
const weekdayFmt = fmt({ weekday: 'short' });

export const time = (d: Date) => timeFmt.format(d).replace('.', ':');
export const shortDate = (d: Date) => dateFmt.format(d).replace('.', '');
export const weekday = (d: Date) => weekdayFmt.format(d).replace('.', '');
export const longToday = (d: Date) => fmt({ weekday: 'long', day: 'numeric', month: 'long' }).format(d);

export const isOverdue = (due: Date, status: TaskStatus, now: Date) => status !== 'done' && due < now;

/** "Terlambat · 12 Okt", "Hari ini, 23:59", "Besok, 23:59", "Sen, 12:00", atau "24 Okt". */
export function dueLabel(due: Date, status: TaskStatus, now: Date): string {
	if (isOverdue(due, status, now)) return `Terlambat · ${shortDate(due)}`;
	const n = dayOffset(due, now);
	if (n === 0) return `Hari ini, ${time(due)}`;
	if (n === 1) return `Besok, ${time(due)}`;
	if (n < 7) return `${weekday(due)}, ${time(due)}`;
	return shortDate(due);
}

/** Cap waktu kartu aktivitas: "19:02", "Kemarin", atau "Sen, 14 Okt". */
export function activityStamp(value: Date, now: Date): string {
	const n = dayOffset(value, now);
	if (n === 0) return time(value);
	if (n === -1) return 'Kemarin';
	return `${weekday(value)}, ${shortDate(value)}`;
}

/** Ikon dan warna kartu aktivitas dari kata kerjanya, sama dengan _activityStyle di Flutter. */
export function activityStyle(verb: string): { icon: string; bg: string } {
	if (verb.startsWith('mengirim')) return { icon: 'upload', bg: 'var(--lavender)' };
	if (verb.startsWith('menyetujui')) return { icon: 'check_circle', bg: 'var(--mint)' };
	if (verb.startsWith('meminta')) return { icon: 'undo', bg: 'var(--coral)' };
	if (verb.startsWith('membuat')) return { icon: 'add_task', bg: 'var(--sky)' };
	if (verb.startsWith('mengalihkan')) return { icon: 'swap_horiz', bg: 'var(--sky)' };
	return { icon: 'edit', bg: 'var(--butter)' };
}

/** Nilai <input type="date"> (yyyy-mm-dd, waktu lokal). */
export const dateInput = (d: Date) =>
	`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** Deadline jatuh pukul 23:59 waktu lokal pada hari yang dipilih, sama dengan Flutter. */
export function dueFromInput(value: string): Date | null {
	const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
	return m ? new Date(+m[1], +m[2] - 1, +m[3], 23, 59) : null;
}

/** Pecah teks pesan jadi potongan teks dan tautan https (hanya https yang dijadikan link). */
export function linkify(text: string): { text: string; href?: string }[] {
	return text
		.split(/(https:\/\/[^\s<>"']+)/)
		.filter(Boolean)
		.map((part) => (part.startsWith('https://') ? { text: part.replace('https://', ''), href: part } : { text: part }));
}

const dayFmt = new Intl.DateTimeFormat('id-ID', { weekday: 'long', day: 'numeric', month: 'long' });
/** Pemisah hari di thread: "Hari ini", "Kemarin", atau "Jumat, 16 Oktober". */
export function dayLabel(value: Date, now: Date): string {
	const n = dayOffset(value, now);
	return n === 0 ? 'Hari ini' : n === -1 ? 'Kemarin' : dayFmt.format(value);
}
