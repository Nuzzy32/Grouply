import { goto } from '$app/navigation';

/** Drawer detail tugas dibuka lewat ?tugas=<id> di halaman mana pun, jadi tautannya bisa dibagikan. */
export function openTask(id: string) {
	const url = new URL(location.href);
	url.searchParams.set('tugas', id);
	return goto(url, { reset: false });
}

export function closeTask() {
	const url = new URL(location.href);
	url.searchParams.delete('tugas');
	return goto(url, { reset: false, replace: true });
}
