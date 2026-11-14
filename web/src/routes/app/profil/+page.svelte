<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { myGroups } from '#lib/app/derive.ts';
	import { initials, tint } from '#lib/app/format.ts';
	import { flash, header, store } from '#lib/app/store.svelte.ts';
	import Modal from '#lib/app/ui/Modal.svelte';

	$effect(() => {
		header.crumbs = [{ label: 'Profil dan akun' }];
	});

	const snap = $derived(store.snap!);
	const me = $derived(snap.users.find((u) => u.id === snap.currentUserID));
	const groups = $derived(myGroups(snap));

	let editing = $state(false);
	let name = $state('');
	let error = $state('');

	async function saveName() {
		error = '';
		const value = name.trim();
		const length = [...value].length;
		if (length < 2) return void (error = 'Nama minimal 2 karakter.');
		if (length > 30) return void (error = 'Nama maksimal 30 karakter.');
		try {
			await store.mutate('updateProfile', { name: value });
			editing = false;
			flash('Nama diperbarui di semua grup');
		} catch (e) {
			error = (e as Error).message;
		}
	}

	async function unblock(id: string, who: string) {
		try {
			await store.mutate('unblockUser', { id });
			flash(`${who} tidak lagi diblokir`, 'info');
		} catch (e) {
			flash((e as Error).message, 'err');
		}
	}
	const blockedName = (id: string) => snap.users.find((u) => u.id === id)?.name ?? 'Pengguna';

	// Hapus akun: syarat dari server (coordinator_transfer_required, active_assignment) ditampilkan lebih dulu.
	let deleting = $state(false);
	let confirmText = $state('');
	let deleteError = $state('');
	const coordinatorOf = $derived(groups.filter((g) => g.coordinatorID === snap.currentUserID && g.memberIDs.length > 1));
	const unfinished = $derived(
		snap.tasks.filter((t) => t.status !== 'done' && (t.assigneeID === snap.currentUserID || t.reviewerID === snap.currentUserID))
	);

	async function deleteAccount() {
		deleteError = '';
		if (confirmText.trim().toUpperCase() !== 'HAPUS') return void (deleteError = 'Ketik HAPUS untuk konfirmasi.');
		try {
			await store.deleteAccount();
			flash('Akun dihapus.', 'info');
		} catch (e) {
			const failure = e as Error & { code?: string };
			deleteError =
				failure.code === 'coordinator_transfer_required'
					? 'Serahkan peran koordinator dulu sebelum menghapus akun.'
					: failure.code === 'active_assignment'
						? 'Alihkan semua tugas aktif dan peran reviewer sebelum menghapus akun.'
						: failure.message;
		}
	}
</script>

<svelte:head><title>Profil · GROUPLY</title></svelte:head>

<div class="page">
	<section class="card hero">
		<span class="av" style="--s:72px;font-size:24px" style:background={tint(me?.tint)}>{initials(me?.name)}</span>
		<div class="who">
			{#if editing}
				<form class="edit" onsubmit={(e) => (e.preventDefault(), saveName())} novalidate>
					<label class="field">
						<span class="label-row"><span>Nama tampilan</span><small>{[...name.trim()].length}/30</small></span>
						<!-- svelte-ignore a11y_autofocus -->
						<input class="input" bind:value={name} maxlength="30" autofocus />
					</label>
					{#if error}<div class="notice error" role="alert">{error}</div>{/if}
					<div class="row">
						<button type="button" class="btn btn-ghost" onclick={() => (editing = false)}>Batal</button>
						<button class="btn btn-primary" disabled={store.busy}>{store.busy ? 'Menyimpan…' : 'Simpan'}</button>
					</div>
				</form>
			{:else}
				<h1>{me?.name}</h1>
				<p>{groups.length} grup · nama ini terlihat oleh anggota grupmu</p>
				<button class="btn btn-ghost small" onclick={() => ((name = me?.name ?? ''), (error = ''), (editing = true))}><Icon name="edit" size={18} />Ubah nama</button>
			{/if}
		</div>
	</section>

	<section class="card">
		<h2>Pengguna diblokir</h2>
		<p class="muted">Pesan mereka di chat dan diskusi disembunyikan untukmu. Mereka tidak diberi tahu.</p>
		{#each snap.blockedUserIDs as id (id)}
			<div class="blocked">
				<span class="av" style="--s:36px;font-size:12px" style:background={tint(snap.users.find((u) => u.id === id)?.tint)}>{initials(blockedName(id))}</span>
				<b>{blockedName(id)}</b>
				<button class="btn btn-ghost small" disabled={store.busy} onclick={() => unblock(id, blockedName(id))}>Buka blokir</button>
			</div>
		{:else}
			<p class="none">Tidak ada pengguna yang kamu blokir.</p>
		{/each}
	</section>

	<section class="card danger-zone">
		<h2>Hapus akun</h2>
		<ul>
			<li>Akun login dan profil di server akan dihapus permanen.</li>
			<li>Hasil kerja dan pesanmu di grup tetap ada, ditampilkan sebagai “Pengguna terhapus”.</li>
			<li>Alihkan peran pelaksana/reviewer pada semua tugas yang belum selesai terlebih dahulu, termasuk di proyek arsip. Tidak ada pengalihan otomatis.</li>
			<li>Jika kamu satu-satunya anggota, grup kehilangan akses anggota dan undangannya dinonaktifkan. Riwayat kerja tetap disimpan tanpa identitas akunmu.</li>
		</ul>
		<button class="btn danger" onclick={() => ((confirmText = ''), (deleteError = ''), (deleting = true))}><Icon name="delete" size={19} />Hapus akun</button>
	</section>
</div>

{#if deleting}
	<Modal title="Hapus akun?" sub="Tindakan ini tidak bisa dibatalkan." busy={store.busy} onclose={() => (deleting = false)}>
		{#if coordinatorOf.length}
			<div class="notice warn"><Icon name="warning" size={18} />Serahkan peran koordinator dulu di: {coordinatorOf.map((g) => g.name).join(', ')}.</div>
		{/if}
		{#if unfinished.length}
			<div class="notice warn">
				<Icon name="warning" size={18} />Masih ada {unfinished.length} tugas yang belum selesai dengan kamu sebagai pelaksana atau reviewer. Minta koordinator membuka kembali proyek bila perlu, lalu alihkan tugasnya.
			</div>
		{/if}
		<label class="field">
			<span>Ketik <b>HAPUS</b> untuk konfirmasi</span>
			<input class="input" bind:value={confirmText} autocomplete="off" />
		</label>
		{#if deleteError}<div class="notice error" role="alert">{deleteError}</div>{/if}
		{#snippet footer()}
			<button class="btn btn-ghost" disabled={store.busy} onclick={() => (deleting = false)}>Batal</button>
			<button class="btn danger" disabled={store.busy || !!coordinatorOf.length || !!unfinished.length} onclick={deleteAccount}>
				{store.busy ? 'Menghapus…' : 'Hapus akun'}
			</button>
		{/snippet}
	</Modal>
{/if}

<style>
	.page {
		max-width: 760px;
		margin: 0 auto;
		padding: 28px 32px 56px;
		display: flex;
		flex-direction: column;
		gap: 20px;
	}
	.card {
		background: var(--surface);
		border-radius: 28px;
		padding: 22px 24px;
		display: flex;
		flex-direction: column;
		gap: 10px;
		animation: up 0.25s ease both;
	}
	.hero {
		flex-direction: row;
		align-items: flex-start;
		gap: 20px;
	}
	.who {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 6px;
	}
	h1 {
		margin: 0;
		font-size: 28px;
		font-weight: 700;
		letter-spacing: -0.025em;
	}
	.who p,
	.muted {
		margin: 0;
		font-size: 14px;
		color: var(--secondary);
	}
	h2 {
		margin: 0;
		font-size: 19px;
		font-weight: 700;
		letter-spacing: -0.02em;
	}
	.small {
		height: 40px;
		padding: 0 14px;
		font-size: 14px;
		margin-top: 6px;
	}
	.edit {
		width: 100%;
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.label-row {
		display: flex;
		justify-content: space-between;
	}
	.row {
		display: flex;
		gap: 8px;
		justify-content: flex-end;
	}
	.blocked {
		padding: 10px 0;
		border-top: 1px solid var(--border);
		display: flex;
		align-items: center;
		gap: 12px;
	}
	.blocked b {
		flex: 1;
		font-size: 15px;
		font-weight: 600;
	}
	.blocked .small {
		margin: 0;
	}
	.none {
		margin: 0;
		padding: 12px 0 4px;
		border-top: 1px solid var(--border);
		font-size: 14px;
		color: var(--text2);
	}
	ul {
		margin: 0;
		padding-left: 20px;
		display: flex;
		flex-direction: column;
		gap: 6px;
		font-size: 14px;
		line-height: 1.5;
		color: var(--text3);
	}
	.danger-zone .btn {
		align-self: flex-start;
		margin-top: 6px;
	}
	.danger {
		background: var(--danger);
		color: light-dark(#fff, #1a1b1d);
	}
	.notice.warn {
		display: flex;
		gap: 8px;
		align-items: flex-start;
		background: var(--butter);
	}
</style>
