<script lang="ts">
	import { untrack } from 'svelte';
	import { userName } from '../derive.ts';
	import { flash, store } from '../store.svelte.ts';
	import type { Message } from '../types.ts';
	import Modal from './Modal.svelte';

	// Alasan dan teks sama dengan ChatReportSheet di Flutter.
	const REASONS = ['Pelecehan', 'Spam', 'Konten tidak pantas', 'Lainnya'];

	let { message, mode, onclose }: { message: Message; mode: 'report' | 'block'; onclose: () => void } = $props();

	// Nilai tetap selama dialog terbuka; induk bisa melepas `message` begitu dialog ditutup.
	const { id: messageID, senderID, text } = untrack(() => message);
	const snap = $derived(store.snap!);
	const name = $derived(userName(snap, senderID));
	const blocked = $derived(snap.blockedUserIDs.includes(senderID));
	let reason = $state('');
	let details = $state('');
	let error = $state('');

	async function report() {
		error = '';
		const extra = details.trim();
		if (!reason) return void (error = 'Pilih alasan laporan.');
		if (reason === 'Lainnya' && !extra) return void (error = 'Ceritakan singkat alasannya.');
		try {
			await store.mutate('reportMessage', { id: messageID, reason: extra ? `${reason} — ${extra}` : reason });
			onclose();
			flash('Laporan terkirim. Terima kasih sudah menjaga grup tetap nyaman.', 'info');
		} catch (e) {
			error = (e as Error).message;
		}
	}

	async function toggleBlock() {
		error = '';
		// Simpan dulu: setelah onclose() induk melepas pesan ini, dan status blokir berubah setelah mutasi.
		const who = name;
		const was = blocked;
		try {
			await store.mutate(was ? 'unblockUser' : 'blockUser', { id: senderID });
			onclose();
			flash(was ? `${who} tidak lagi diblokir` : `${who} diblokir`, 'info');
		} catch (e) {
			error = (e as Error).message;
		}
	}
</script>

{#if mode === 'report'}
	<Modal title="Laporkan pesan" sub="Laporan bersifat privat. {name} tidak diberi tahu siapa pelapornya." busy={store.busy} {onclose}>
		<blockquote>{text}</blockquote>
		<fieldset>
			<legend>Alasan</legend>
			{#each REASONS as r (r)}
				<label class="reason" class:on={reason === r}><input type="radio" name="reason" value={r} bind:group={reason} />{r}</label>
			{/each}
		</fieldset>
		<label class="field">
			Ceritakan singkat {reason === 'Lainnya' ? '' : '(opsional)'}
			<textarea class="input" bind:value={details} rows="2" maxlength="400"></textarea>
		</label>
		{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		{#snippet footer()}
			<button class="btn btn-ghost" disabled={store.busy} onclick={onclose}>Batal</button>
			<button class="btn btn-primary" disabled={store.busy} onclick={report}>{store.busy ? 'Mengirim…' : 'Kirim laporan'}</button>
		{/snippet}
	</Modal>
{:else}
	<Modal title={blocked ? `Buka blokir ${name}?` : `Blokir ${name}?`} busy={store.busy} {onclose}>
		<p>
			{blocked
				? `Pesan ${name} di chat dan diskusi akan tampil lagi untukmu.`
				: `Pesan ${name} di chat dan diskusi akan disembunyikan untukmu. ${name} tetap anggota grup, tugas bersama tetap berjalan, dan ${name} tidak diberi tahu.`}
		</p>
		{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		{#snippet footer()}
			<button class="btn btn-ghost" disabled={store.busy} onclick={onclose}>Batal</button>
			<button class="btn {blocked ? 'btn-primary' : 'danger'}" disabled={store.busy} onclick={toggleBlock}>{blocked ? 'Buka blokir' : 'Blokir'}</button>
		{/snippet}
	</Modal>
{/if}

<style>
	blockquote {
		margin: 0;
		padding: 12px 14px;
		border-radius: 16px;
		background: var(--surface);
		font-size: 14px;
		line-height: 1.45;
		color: var(--text3);
		overflow-wrap: anywhere;
		max-height: 120px;
		overflow: auto;
	}
	fieldset {
		margin: 0;
		padding: 0;
		border: none;
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 8px;
	}
	legend {
		padding: 0 0 8px;
		font-size: 14px;
		font-weight: 600;
	}
	.reason {
		height: 46px;
		padding: 0 14px;
		border-radius: 14px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 600;
		cursor: pointer;
	}
	.reason.on {
		box-shadow: inset 0 0 0 2px var(--ink);
	}
	.reason input {
		accent-color: var(--ink);
	}
	p {
		margin: 0;
		font-size: 15px;
		line-height: 1.5;
		color: var(--text3);
	}
	.danger {
		background: var(--danger);
		color: light-dark(#fff, #1a1b1d);
	}
</style>
