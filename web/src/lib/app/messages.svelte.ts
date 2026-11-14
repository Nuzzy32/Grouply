import { store } from './store.svelte.ts';

export type Pending = {
	clientID: string;
	groupID: string;
	taskID: string | null;
	text: string;
	state: 'sending' | 'failed';
	error?: string;
};

/** Pesan yang belum dikonfirmasi server. clientID dipakai ulang saat dicoba lagi, jadi server tidak menggandakan. */
export const pending = $state<Pending[]>([]);

let chain: Promise<void> = Promise.resolve();
const idle = async () => {
	while (store.busy) await new Promise((r) => setTimeout(r, 80));
};

async function deliver(p: Pending) {
	await idle();
	try {
		await store.mutate('sendMessage', { groupID: p.groupID, taskID: p.taskID, text: p.text, clientID: p.clientID });
		const at = pending.findIndex((x) => x.clientID === p.clientID);
		if (at >= 0) pending.splice(at, 1);
	} catch (e) {
		const item = pending.find((x) => x.clientID === p.clientID);
		if (item) {
			item.state = 'failed';
			item.error = (e as Error).message;
		}
	}
}

/** Kirim berurutan agar tidak bertabrakan dengan mutasi lain (store hanya menjalankan satu mutasi). */
export function sendMessage(groupID: string, taskID: string | null, text: string) {
	const p: Pending = { clientID: crypto.randomUUID(), groupID, taskID, text: text.trim(), state: 'sending' };
	pending.push(p);
	chain = chain.then(() => deliver(p));
}

export function retry(clientID: string) {
	const p = pending.find((x) => x.clientID === clientID);
	if (!p) return;
	p.state = 'sending';
	chain = chain.then(() => deliver(p));
}
