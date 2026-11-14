<script lang="ts">
	import { goto } from '$app/navigation';
	import Icon from '#lib/Icon.svelte';
	import { myGroups, unreadCount } from '#lib/app/derive.ts';
	import { groupIcon, initials, tint } from '#lib/app/format.ts';
	import { flash, header, store } from '#lib/app/store.svelte.ts';
	import Modal from '#lib/app/ui/Modal.svelte';

	const snap = $derived(store.snap!);
	const me = $derived(snap.currentUserID);
	const groups = $derived(myGroups(snap).sort((a, b) => a.name.localeCompare(b.name, 'id')));
	const coordinating = $derived(groups.filter((g) => g.coordinatorID === me).length);
	const user = (id: string) => snap.users.find((u) => u.id === id);
	const activeProjects = (gid: string) => snap.projects.filter((p) => p.groupID === gid && p.status === 'active').length;

	let modal = $state<'create' | 'join' | null>(null);
	let name = $state('');
	let course = $state('');
	let code = $state('');
	let error = $state('');

	function open(kind: 'create' | 'join') {
		modal = kind;
		name = course = code = error = '';
	}

	$effect(() => {
		header.crumbs = [{ label: 'Grup' }];
		header.action = { label: 'Buat grup', icon: 'add', run: () => open('create') };
		return () => (header.action = null);
	});

	async function save() {
		error = '';
		try {
			if (modal === 'create') {
				const trimmed = name.trim();
				if (trimmed.length < 3) return void (error = 'Nama grup minimal 3 karakter.');
				if (trimmed.length > 40) return void (error = 'Nama grup maksimal 40 karakter.');
				const { id } = await store.mutate<{ id: string }>('createGroup', {
					name: trimmed,
					course: course.trim() || 'Mata kuliah belum diisi',
					description: ''
				});
				flash('Grup dibuat. Undang anggota lewat kode undangan.');
				modal = null;
				await goto(`/app/grup/${id}`);
			} else {
				// Tautan undangan juga diterima: ambil bagian setelah /invite/.
				const raw = code.trim();
				const token = raw.includes('/invite/') ? raw.split('/invite/')[1] : raw;
				if (!token) return void (error = 'Isi kode undangan.');
				const { id } = await store.mutate<{ id: string }>('joinGroup', { code: token });
				flash(`Kamu bergabung ke ${snap.groups.find((g) => g.id === id)?.name ?? 'grup'}`);
				modal = null;
				await goto(`/app/grup/${id}`);
			}
		} catch (e) {
			error = (e as Error).message;
		}
	}
</script>

<svelte:head><title>Grup · GROUPLY</title></svelte:head>

<div class="page">
	<div class="top">
		<div class="titles">
			<h1>Grup</h1>
			<p>{groups.length} grup · koordinator di {coordinating}</p>
		</div>
		<button class="btn btn-ghost" onclick={() => open('join')}><Icon name="login" size={19} />Gabung dengan kode</button>
	</div>

	{#if groups.length}
		<div class="grid">
			{#each groups as g (g.id)}
				{@const unread = unreadCount(snap, g.id)}
				<div class="card">
					<a class="cover" href="/app/grup/{g.id}" aria-label="Buka {g.name}"></a>
					<div class="head">
						<span class="icon" style:background={tint(g.tint)}><Icon name={groupIcon(g.icon)} size={27} /></span>
						<span class="names"><b>{g.name}</b><span>{g.course}</span></span>
					</div>
					<div class="members">
						<span class="stack">
							{#each g.memberIDs.slice(0, 5) as id (id)}
								<span class="av" title={user(id)?.name} style="--s:32px;font-size:11px" style:background={tint(user(id)?.tint)}>{initials(user(id)?.name)}</span>
							{/each}
						</span>
						<span class="meta">{g.memberIDs.length} anggota · {activeProjects(g.id)} proyek aktif</span>
					</div>
					<div class="foot">
						<span class="chip role" style:background={g.coordinatorID === me ? 'var(--mint)' : 'var(--chip)'}>
							{g.coordinatorID === me ? 'Koordinator' : 'Anggota'}
						</span>
						<a class="chat" href="/app/chat/{g.id}">
							<Icon name="chat_bubble" size={17} />Chat
							{#if unread}<i aria-label="{unread} pesan belum dibaca"></i>{/if}
						</a>
					</div>
				</div>
			{/each}
		</div>
	{:else}
		<div class="empty">
			<span class="empty-icon"><Icon name="groups" size={28} /></span>
			<b>Belum ada grup</b>
			<span>Buat grup untuk kelompokmu, atau gabung dengan kode undangan dari koordinator.</span>
			<div class="actions">
				<button class="btn btn-primary" onclick={() => open('create')}>Buat grup</button>
				<button class="btn btn-ghost" onclick={() => open('join')}>Gabung dengan kode</button>
			</div>
		</div>
	{/if}
</div>

{#if modal}
	<Modal
		title={modal === 'create' ? 'Buat grup' : 'Gabung grup'}
		sub={modal === 'create' ? 'Kamu jadi koordinator dan bisa mengundang hingga 7 anggota.' : 'Masukkan kode atau tautan undangan dari koordinator.'}
		busy={store.busy}
		onclose={() => (modal = null)}
	>
		<form id="group-form" class="form" onsubmit={(e) => (e.preventDefault(), save())} novalidate>
			{#if modal === 'create'}
				<label class="field">
					<span class="label-row"><span>Nama grup <em>*</em></span><small>{name.trim().length}/40</small></span>
					<input class="input" bind:value={name} maxlength="40" placeholder="Contoh: Basis Data · Kelompok 3" />
				</label>
				<label class="field">
					Mata kuliah
					<input class="input" bind:value={course} maxlength="60" placeholder="Contoh: Basis Data" />
				</label>
			{:else}
				<label class="field">
					Kode undangan <em>*</em>
					<input class="input mono" bind:value={code} placeholder="Tempel kode atau tautan undangan" autocomplete="off" spellcheck="false" />
				</label>
			{/if}
			{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		</form>
		{#snippet footer()}
			<button class="btn btn-ghost" type="button" disabled={store.busy} onclick={() => (modal = null)}>Batal</button>
			<button class="btn btn-primary" form="group-form" disabled={store.busy}>
				{#if store.busy}<span class="spin" aria-hidden="true"></span>{/if}
				{modal === 'create' ? (store.busy ? 'Menyimpan…' : 'Buat grup') : store.busy ? 'Bergabung…' : 'Gabung'}
			</button>
		{/snippet}
	</Modal>
{/if}

<style>
	.page {
		max-width: 1360px;
		margin: 0 auto;
		padding: 28px 32px 56px;
		display: flex;
		flex-direction: column;
		gap: 22px;
	}
	.top {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 16px;
		flex-wrap: wrap;
	}
	.titles {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	h1 {
		margin: 0;
		font-size: 34px;
		font-weight: 700;
		letter-spacing: -0.03em;
	}
	.titles p {
		margin: 0;
		font-size: 15px;
		color: var(--secondary);
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
		gap: 16px;
	}
	.card {
		position: relative;
		background: var(--surface);
		border-radius: 28px;
		padding: 20px;
		display: flex;
		flex-direction: column;
		gap: 16px;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
		transition:
			transform 0.15s,
			box-shadow 0.15s;
		animation: up 0.25s ease both;
	}
	.card:hover {
		transform: translateY(-2px);
		box-shadow: 0 12px 30px -16px rgba(0, 0, 0, 0.25);
	}
	/* Seluruh kartu bisa diklik, tombol Chat tetap terpisah. */
	.cover {
		position: absolute;
		inset: 0;
		border-radius: inherit;
	}
	.head {
		display: flex;
		gap: 14px;
		align-items: center;
	}
	.icon {
		flex: none;
		width: 54px;
		height: 54px;
		border-radius: 20px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.names {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.names b {
		font-size: 18px;
		font-weight: 700;
		letter-spacing: -0.015em;
	}
	.names span {
		font-size: 14px;
		color: var(--secondary);
	}
	.members {
		display: flex;
		align-items: center;
		gap: 10px;
		flex-wrap: wrap;
	}
	.stack {
		display: flex;
		padding-right: 8px;
	}
	.stack .av {
		margin-right: -8px;
		box-shadow: 0 0 0 2.5px var(--surface);
	}
	.meta {
		font-size: 14px;
		color: var(--text3);
	}
	.foot {
		display: flex;
		gap: 8px;
		align-items: center;
		justify-content: space-between;
	}
	.role {
		height: 28px;
		padding: 0 10px;
		font-size: 12px;
	}
	.chat {
		position: relative;
		height: 38px;
		padding: 0 14px 0 10px;
		border-radius: 19px;
		box-shadow: inset 0 0 0 1.5px var(--ink);
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 13px;
		font-weight: 600;
		transition: background 0.15s;
	}
	.chat:hover {
		background: var(--muted);
	}
	.chat i {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--ink);
	}
	.empty {
		background: var(--surface);
		border-radius: 28px;
		padding: 40px 24px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
		text-align: center;
	}
	.empty-icon {
		width: 56px;
		height: 56px;
		border-radius: 20px;
		background: var(--mint);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.empty b {
		font-size: 19px;
	}
	.empty > span:not(.empty-icon) {
		max-width: 420px;
		font-size: 15px;
		line-height: 1.5;
		color: var(--secondary);
	}
	.actions {
		margin-top: 6px;
		display: flex;
		gap: 8px;
		flex-wrap: wrap;
		justify-content: center;
	}
	.form {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	.label-row {
		display: flex;
		justify-content: space-between;
	}
	em {
		font-style: normal;
		color: var(--danger);
	}
	.mono {
		font-family: ui-monospace, 'SF Mono', Menlo, monospace;
		font-size: 14px;
	}
</style>
