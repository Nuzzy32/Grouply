<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import Icon from '#lib/Icon.svelte';
	import { unreadCount } from '#lib/app/derive.ts';
	import { dueFromInput, groupIcon, initials, shortDate, tint } from '#lib/app/format.ts';
	import { inviteStatus, memberLock, PROJECT_STATUS, projectStats } from '#lib/app/project.ts';
	import { ask, flash, header, store } from '#lib/app/store.svelte.ts';
	import DueField from '#lib/app/ui/DueField.svelte';
	import Menu from '#lib/app/ui/Menu.svelte';
	import Modal from '#lib/app/ui/Modal.svelte';
	import type { Project } from '#lib/app/types.ts';

	const snap = $derived(store.snap!);
	const me = $derived(snap.currentUserID);
	const group = $derived(snap.groups.find((g) => g.id === page.params.id));
	const isCoord = $derived(group?.coordinatorID === me);
	const user = (id: string) => snap.users.find((u) => u.id === id);
	const projects = $derived(snap.projects.filter((p) => p.groupID === group?.id));

	type Filter = Project['status'];
	let filter = $state<Filter>('active');
	const FILTERS: [Filter, string][] = [
		['active', 'Aktif'],
		['completed', 'Selesai'],
		['archived', 'Arsip']
	];
	const shown = $derived(projects.filter((p) => p.status === filter).sort((a, b) => a.dueAt.localeCompare(b.dueAt)));
	const openTasks = $derived(
		snap.tasks.filter((t) => t.status !== 'done' && projects.some((p) => p.id === t.projectID && p.status === 'active'))
	);
	const members = $derived(
		(group?.memberIDs ?? [])
			.map((id) => ({ id, name: user(id)?.name ?? 'Anggota', active: openTasks.filter((t) => t.assigneeID === id).length }))
			.sort((a, b) => Number(b.id === group?.coordinatorID) - Number(a.id === group?.coordinatorID) || a.name.localeCompare(b.name, 'id'))
	);

	let modal = $state<'project' | 'invite' | 'settings' | null>(null);
	let title = $state('');
	let description = $state('');
	let due = $state('');
	let error = $state('');
	let inviteCode = $state('');
	let inviteID = $state('');
	// Kode mentah hanya ada di respons generateInvite; status terbaru diambil dari snapshot.
	const currentInvite = $derived(snap.invites.find((i) => i.id === inviteID));
	let groupName = $state('');
	let groupDesc = $state('');
	const nameOf = (id: string) => user(id)?.name ?? 'Anggota';

	function newProject() {
		const d = new Date();
		d.setDate(d.getDate() + 14);
		title = description = error = '';
		due = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
		modal = 'project';
	}

	$effect(() => {
		if (!group) return;
		header.crumbs = [{ label: 'Grup', href: '/app/grup' }, { label: group.name }];
		header.action = {
			label: 'Buat proyek',
			icon: 'add',
			run: newProject,
			locked: isCoord ? undefined : 'Hanya koordinator yang bisa membuat proyek.'
		};
		return () => (header.action = null);
	});

	async function saveProject() {
		error = '';
		const name = title.trim();
		const at = dueFromInput(due);
		if (name.length < 3) return void (error = 'Nama proyek minimal 3 karakter.');
		if (name.length > 60) return void (error = 'Nama proyek maksimal 60 karakter.');
		if (!at || at < new Date()) return void (error = 'Pilih deadline yang valid, mulai hari ini.');
		try {
			const { id } = await store.mutate<{ id: string }>('createProject', {
				groupID: group!.id,
				title: name,
				description: description.trim(),
				dueAt: at.toISOString()
			});
			modal = null;
			flash('Proyek dibuat. Tambahkan tugas pertama.');
			await goto(`/app/proyek/${id}`);
		} catch (e) {
			error = (e as Error).message;
		}
	}

	async function invite() {
		if (!group!.organizationID && group!.memberIDs.length >= 8) return flash('Grup sudah penuh (maksimal 8 anggota).', 'err');
		error = '';
		inviteCode = inviteID = '';
		modal = 'invite';
		try {
			const result = await store.mutate<{ invite: { id: string; code: string } }>('generateInvite', { groupID: group!.id });
			inviteCode = result.invite.code;
			inviteID = result.invite.id;
		} catch (e) {
			error = (e as Error).message;
		}
	}

	async function revoke() {
		try {
			await store.mutate('revokeInvite', { id: inviteID });
			flash(`Kode ${inviteCode.slice(0, 8)}… dinonaktifkan`, 'info');
		} catch (e) {
			flash((e as Error).message, 'err');
		}
	}

	function openSettings() {
		groupName = group!.name;
		groupDesc = group!.description;
		error = '';
		modal = 'settings';
	}

	async function saveSettings() {
		error = '';
		const name = groupName.trim();
		const desc = groupDesc.trim();
		if (!isCoord) return void (error = 'Hanya koordinator yang bisa mengubah pengaturan grup.');
		if (name.length < 3) return void (error = 'Nama grup minimal 3 karakter.');
		if (name.length > 40) return void (error = 'Nama grup maksimal 40 karakter.');
		if (desc.length > 140) return void (error = 'Deskripsi maksimal 140 karakter.');
		try {
			await store.mutate('updateGroup', { id: group!.id, name, course: group!.course, description: desc });
			modal = null;
			flash('Pengaturan grup disimpan');
		} catch (e) {
			error = (e as Error).message;
		}
	}

	async function run(action: string, payload: Record<string, unknown>, done: string, kind: 'ok' | 'info' = 'ok') {
		try {
			await store.mutate(action, payload);
			flash(done, kind);
			return true;
		} catch (e) {
			flash((e as Error).message, 'err');
			return false;
		}
	}

	async function transfer(id: string) {
		const name = nameOf(id);
		const ok = await ask({
			title: `Jadikan ${name} koordinator?`,
			text: `${name} akan bisa mengelola anggota, proyek, dan tugas. Kamu tetap jadi anggota grup.`,
			ok: 'Jadikan koordinator'
		});
		if (ok) await run('transferCoordinator', { groupID: group!.id, to: id }, `${name} sekarang koordinator`);
	}

	async function remove(id: string) {
		const name = nameOf(id);
		const lock = memberLock(snap, group!.id, id);
		if (lock) return flash(lock, 'err');
		const ok = await ask({
			title: `Keluarkan ${name}?`,
			text: `${name} tidak bisa lagi membuka proyek dan chat grup ini. Hasil kerja dan tugas yang sudah selesai tetap tercatat atas nama ${name}.`,
			ok: 'Keluarkan',
			destructive: true
		});
		if (ok) await run('removeMember', { groupID: group!.id, userID: id }, `${name} dikeluarkan dari grup`, 'info');
	}

	async function leave() {
		const g = group!;
		if (isCoord && g.memberIDs.length > 1) {
			await ask({
				title: 'Serahkan peran koordinator dulu',
				text: 'Grup harus selalu punya koordinator. Pilih anggota lain sebagai koordinator sebelum kamu keluar.',
				info: true
			});
			return;
		}
		const lock = memberLock(snap, g.id, me);
		if (lock) return flash(lock, 'err');
		const last = g.memberIDs.length === 1;
		const ok = await ask(
			last
				? {
						title: 'Kamu anggota terakhir',
						text: `Kalau kamu keluar, ${g.name} tidak punya anggota lagi dan tidak bisa dibuka siapa pun. Undangannya ikut dicabut.`,
						ok: 'Keluar & hapus grup',
						destructive: true
					}
				: {
						title: 'Keluar dari grup?',
						text: `Kamu tidak bisa lagi membuka proyek dan chat ${g.name}. Hasil kerja dan tugas yang sudah selesai tetap tercatat atas nama kamu.`,
						ok: 'Keluar',
						destructive: true
					}
		);
		if (!ok) return;
		const name = g.name;
		if (await run('leaveGroup', { id: g.id }, last ? 'Grup dihapus' : `Kamu keluar dari ${name}`, 'info')) {
			modal = null;
			await goto('/app/grup');
		}
	}

	async function copyCode() {
		try {
			await navigator.clipboard.writeText(inviteCode);
			flash('Kode undangan disalin.');
		} catch {
			flash('Salin manual: pilih kode lalu tekan Ctrl/⌘+C.', 'info');
		}
	}

	const emptyText = (f: Filter) =>
		f === 'archived'
			? 'Belum ada proyek yang diarsipkan.'
			: f === 'completed'
				? 'Belum ada proyek yang selesai.'
				: 'Tidak ada proyek aktif. Lihat tab Selesai atau Arsip.';
</script>

<svelte:head><title>{group?.name ?? 'Grup'} · GROUPLY</title></svelte:head>

{#if !group}
	<div class="missing">
		<b>Grup tidak ditemukan</b>
		<span>Mungkin kamu sudah keluar dari grup ini.</span>
		<a class="btn btn-ghost" href="/app/grup">Kembali ke Grup</a>
	</div>
{:else}
	{@const unread = unreadCount(snap, group.id)}
	<div class="page">
		<div class="col">
			<div class="hero">
				<span class="icon" style:background={tint(group.tint)}><Icon name={groupIcon(group.icon)} size={34} /></span>
				<div class="info">
					<h1>{group.name}</h1>
					<span class="course">{group.course}</span>
					{#if group.description}<p>{group.description}</p>{/if}
					<span class="summary"><Icon name="insights" size={18} />{projects.filter((p) => p.status === 'active').length} proyek aktif · {openTasks.length} tugas berjalan</span>
				</div>
				<div class="hero-actions">
					<a class="btn btn-primary chat" href="/app/chat/{group.id}">
						<Icon name="chat_bubble" size={19} />Buka chat grup
						{#if unread}<span class="badge">{unread}</span>{/if}
					</a>
					{#if !group.closed}
						<button class="settings" aria-label="Pengaturan grup" title="Pengaturan grup" onclick={openSettings}><Icon name="settings" size={20} /></button>
					{/if}
				</div>
			</div>

			<div class="section-head">
				<h2>Proyek</h2>
				<div class="filters">
					{#each FILTERS as [key, label] (key)}
						<button class="filter" class:on={filter === key} aria-pressed={filter === key} onclick={() => (filter = key)}>
							{label} · {projects.filter((p) => p.status === key).length}
						</button>
					{/each}
				</div>
			</div>

			{#if projects.length === 0}
				<div class="empty">
					<span class="empty-icon"><Icon name="folder_open" size={28} /></span>
					<b>Belum ada proyek</b>
					<span>
						{isCoord
							? 'Mulai proyek pertama untuk mengatur tugas dan kerja sama kelompokmu.'
							: 'Koordinator belum membuat proyek. Proyek baru akan muncul di sini.'}
					</span>
					{#if isCoord}<button class="btn btn-primary" onclick={newProject}>Buat proyek</button>{/if}
				</div>
			{:else if shown.length === 0}
				<p class="filter-empty">{emptyText(filter)}</p>
			{:else}
				<div class="projects">
					{#each shown as p (p.id)}
						{@const s = projectStats(snap, p.id)}
						{@const st = PROJECT_STATUS[p.status]}
						<a class="project" href="/app/proyek/{p.id}">
							<span class="p-top">
								<i style:background={tint(group.tint)}></i>
								<span class="chip p-status" style:background={st.bg}><Icon name={st.icon} size={15} />{st.label}</span>
							</span>
							<span class="p-text">
								<b>{p.title}</b>
								{#if p.description}<span>{p.description}</span>{/if}
							</span>
							<span class="p-foot">
								<span class="progress">
									<span class="bar"><span style:width="{s.total ? (s.done / s.total) * 100 : 0}%"></span></span>
									<b>{s.done}/{s.total} selesai</b>
								</span>
								<span class="due"><Icon name="event" size={16} />Deadline {shortDate(new Date(p.dueAt))} · {s.open} tugas berjalan</span>
							</span>
						</a>
					{/each}
				</div>
			{/if}
		</div>

		<aside class="members">
			<div class="m-head">
				<h2>Anggota</h2>
				<span>{group.organizationID ? `${members.length} anggota` : `${members.length} dari 8 anggota`}</span>
			</div>
			{#each members as m (m.id)}
				<div class="member">
					<span class="av" style="--s:40px;font-size:13px" style:background={tint(user(m.id)?.tint)}>{initials(m.name)}</span>
					<span class="m-text"><b>{m.id === me ? `${m.name} (kamu)` : m.name}</b><span>{m.active} tugas aktif</span></span>
					{#if m.id === group.coordinatorID}<span class="chip coord"><Icon name="shield_person" size={15} />Koordinator</span>{/if}
					{#if isCoord && m.id !== me && m.id !== group.coordinatorID}
						<Menu
							label="Aksi untuk {m.name}"
							items={[
								{ label: 'Jadikan koordinator', icon: 'shield_person', run: () => transfer(m.id) },
								{ label: 'Keluarkan dari grup', icon: 'person_remove', danger: true, run: () => remove(m.id) }
							]}
						/>
					{/if}
				</div>
			{/each}
			{#if isCoord}
				<button class="btn btn-ghost invite" onclick={invite}><Icon name="person_add" size={19} />Undang anggota</button>
			{/if}
			<button class="btn btn-text leave" onclick={leave}><Icon name="logout" size={18} />Keluar dari grup</button>
		</aside>
	</div>
{/if}

{#if modal === 'project'}
	<Modal title="Buat proyek" sub={group?.name} busy={store.busy} onclose={() => (modal = null)}>
		<form id="project-form" class="form" onsubmit={(e) => (e.preventDefault(), saveProject())} novalidate>
			<label class="field">
				<span class="label-row"><span>Nama proyek <em>*</em></span><small>{title.trim().length}/60</small></span>
				<input class="input" bind:value={title} maxlength="60" placeholder="Contoh: Aplikasi Kantin Kampus" />
			</label>
			<label class="field">
				Deskripsi
				<textarea class="input" bind:value={description} rows="3" maxlength="300" placeholder="Tujuan proyek dan hasil akhir yang diharapkan"></textarea>
			</label>
			<div class="field">
				<span>Deadline <em>*</em></span>
				<DueField bind:value={due} label="Pilih tanggal deadline proyek" />
			</div>
			{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		</form>
		{#snippet footer()}
			<button class="btn btn-ghost" type="button" disabled={store.busy} onclick={() => (modal = null)}>Batal</button>
			<button class="btn btn-primary" form="project-form" disabled={store.busy}>
				{#if store.busy}<span class="spin" aria-hidden="true"></span>{/if}{store.busy ? 'Menyimpan…' : 'Buat proyek'}
			</button>
		{/snippet}
	</Modal>
{:else if modal === 'settings' && group}
	<Modal title="Pengaturan grup" sub={group.course} busy={store.busy} onclose={() => (modal = null)}>
		<form id="settings-form" class="form" onsubmit={(e) => (e.preventDefault(), saveSettings())} novalidate>
			<label class="field">
				<span class="label-row"><span>Nama grup</span><small>{groupName.trim().length}/40</small></span>
				<input class="input" bind:value={groupName} maxlength="40" disabled={!isCoord} />
			</label>
			<label class="field">
				<span class="label-row"><span>Deskripsi</span><small>{groupDesc.trim().length}/140</small></span>
				<textarea class="input" bind:value={groupDesc} rows="3" maxlength="140" placeholder="Tujuan atau catatan singkat grup" disabled={!isCoord}></textarea>
			</label>
			{#if !isCoord}<p class="hint lock"><Icon name="lock" size={17} />Hanya koordinator yang bisa mengubah pengaturan grup.</p>{/if}
			{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		</form>
		<button class="btn btn-text leave" onclick={leave}><Icon name="logout" size={18} />Keluar dari grup</button>
		{#snippet footer()}
			<button class="btn btn-ghost" type="button" disabled={store.busy} onclick={() => (modal = null)}>{isCoord ? 'Batal' : 'Tutup'}</button>
			{#if isCoord}
				<button class="btn btn-primary" form="settings-form" disabled={store.busy}>{store.busy ? 'Menyimpan…' : 'Simpan'}</button>
			{/if}
		{/snippet}
	</Modal>
{:else if modal === 'invite'}
	<Modal title="Undang anggota" sub="Kode berlaku 7 hari dan hanya bisa dipakai sekali." busy={store.busy} onclose={() => (modal = null)}>
		{#if inviteCode}
			{@const st = currentInvite ? inviteStatus(currentInvite) : { label: 'Undangan aktif', valid: true }}
			<div class="invite-status">
				<span class="chip" style:background={st.valid ? 'var(--mint)' : 'var(--chip)'}>{st.label}</span>
				{#if currentInvite}<small>Berlaku sampai {new Date(currentInvite.expiresAt).toLocaleString('id-ID', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).replace('.', ':')} · {currentInvite.useCount}/{currentInvite.maxUses} pemakaian</small>{/if}
			</div>
			<div class="code-box" class:void={!st.valid}>
				<code>{inviteCode}</code>
				<button class="btn btn-primary" onclick={copyCode}><Icon name="content_copy" size={18} />Salin</button>
			</div>
			<p class="hint">Bagikan kode ini ke anggota. Mereka menempelkannya di Grup → Gabung dengan kode. Buat kode baru untuk tiap anggota.</p>
			{#if st.valid}<button class="btn btn-text revoke" disabled={store.busy} onclick={revoke}>Nonaktifkan kode</button>{/if}
		{:else if error}
			<div class="notice error" role="alert">{error}</div>
		{:else}
			<div class="loading"><span class="spin" aria-label="Membuat kode"></span></div>
		{/if}
	</Modal>
{/if}

<style>
	.page {
		max-width: 1360px;
		margin: 0 auto;
		padding: 28px 32px 56px;
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: 24px;
		align-items: start;
	}
	@media (min-width: 1240px) {
		.page {
			grid-template-columns: minmax(0, 1fr) 320px;
		}
	}
	.col {
		display: flex;
		flex-direction: column;
		gap: 20px;
		min-width: 0;
	}
	.hero {
		background: var(--surface);
		border-radius: 32px;
		padding: 24px;
		display: flex;
		gap: 20px;
		align-items: flex-start;
		flex-wrap: wrap;
		animation: up 0.25s ease both;
	}
	.icon {
		flex: none;
		width: 68px;
		height: 68px;
		border-radius: 24px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.info {
		flex: 1 1 280px;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	h1 {
		margin: 0;
		font-size: 28px;
		font-weight: 700;
		letter-spacing: -0.025em;
		line-height: 1.15;
	}
	.course {
		font-size: 15px;
		color: var(--secondary);
	}
	.info p {
		margin: 0;
		font-size: 15px;
		line-height: 1.5;
		color: var(--text3);
	}
	.summary {
		padding-top: 2px;
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 14px;
		color: var(--text3);
	}
	.chat {
		flex: none;
		height: 46px;
		font-size: 14px;
	}
	.hero-actions {
		flex: none;
		display: flex;
		gap: 8px;
	}
	.settings {
		width: 46px;
		height: 46px;
		border: none;
		border-radius: 50%;
		background: var(--chip);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.settings:hover {
		background: var(--border);
	}
	.leave {
		align-self: flex-start;
		margin-top: 6px;
		display: flex;
		align-items: center;
		gap: 6px;
		color: var(--danger);
	}
	.invite-status {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.invite-status small {
		font-size: 13px;
		color: var(--secondary);
	}
	.code-box.void code {
		text-decoration: line-through;
		opacity: 0.5;
	}
	.revoke {
		align-self: flex-start;
		color: var(--danger);
	}
	.hint.lock {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.badge {
		min-width: 22px;
		height: 22px;
		padding: 0 6px;
		border-radius: 11px;
		background: var(--mint);
		color: var(--ink);
		font-size: 12px;
		font-weight: 700;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.section-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		flex-wrap: wrap;
	}
	h2 {
		margin: 0;
		font-size: 22px;
		font-weight: 700;
		letter-spacing: -0.02em;
	}
	.filters {
		display: flex;
		gap: 6px;
		flex-wrap: wrap;
	}
	.filter {
		height: 40px;
		padding: 0 16px;
		border-radius: 20px;
		border: 1.5px solid var(--ink);
		background: transparent;
		font-size: 14px;
		font-weight: 600;
		transition:
			background 0.2s,
			color 0.2s;
	}
	.filter.on {
		background: var(--ink);
		color: var(--on-ink);
	}
	.projects {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
		gap: 16px;
	}
	.project {
		background: var(--surface);
		border-radius: 24px;
		padding: 18px;
		display: flex;
		flex-direction: column;
		gap: 14px;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
		transition:
			transform 0.15s,
			box-shadow 0.15s;
		animation: up 0.22s ease both;
	}
	.project:hover {
		transform: translateY(-2px);
		box-shadow: 0 12px 30px -16px rgba(0, 0, 0, 0.25);
	}
	.p-top {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	.p-top i {
		width: 12px;
		height: 12px;
		border-radius: 50%;
		box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.08);
	}
	.p-status {
		height: 28px;
		padding: 0 10px 0 7px;
		gap: 4px;
		font-size: 12px;
		align-self: center;
	}
	.p-text {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.p-text b {
		font-size: 17px;
		font-weight: 700;
		letter-spacing: -0.01em;
		line-height: 1.25;
	}
	.p-text span {
		font-size: 14px;
		line-height: 1.45;
		color: var(--secondary);
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}
	.p-foot {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.progress {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.progress b {
		font-size: 13px;
		font-weight: 600;
		white-space: nowrap;
	}
	.bar {
		flex: 1;
		height: 6px;
		border-radius: 3px;
		background: var(--muted);
		overflow: hidden;
	}
	.bar span {
		display: block;
		height: 100%;
		border-radius: 3px;
		background: var(--ink);
		transition: width 0.5s ease;
	}
	.due {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 13px;
		color: var(--text3);
	}
	.empty,
	.missing {
		background: var(--surface);
		border-radius: 28px;
		padding: 32px 24px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
		text-align: center;
	}
	.missing {
		max-width: 480px;
		margin: 48px auto;
	}
	.empty-icon {
		width: 56px;
		height: 56px;
		border-radius: 20px;
		background: var(--butter);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.empty b,
	.missing b {
		font-size: 19px;
	}
	.empty > span:not(.empty-icon),
	.missing span {
		max-width: 420px;
		font-size: 15px;
		line-height: 1.5;
		color: var(--secondary);
	}
	.filter-empty {
		margin: 0;
		padding: 28px 0;
		text-align: center;
		font-size: 15px;
		color: var(--secondary);
	}
	.members {
		background: var(--surface);
		border-radius: 28px;
		padding: 18px 20px 12px;
		display: flex;
		flex-direction: column;
		animation: up 0.25s ease both;
	}
	.m-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		padding-bottom: 6px;
	}
	.m-head h2 {
		font-size: 19px;
	}
	.m-head span {
		font-size: 13px;
		color: var(--secondary);
	}
	.member {
		min-height: 60px;
		padding: 8px 0;
		border-top: 1px solid var(--border);
		display: flex;
		align-items: center;
		gap: 12px;
	}
	.m-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.m-text b {
		font-size: 15px;
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.m-text span {
		font-size: 13px;
		color: var(--secondary);
	}
	.coord {
		height: 26px;
		padding: 0 9px 0 6px;
		font-size: 12px;
		background: var(--mint);
		align-self: center;
	}
	.invite {
		margin-top: 8px;
		height: 44px;
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
	.code-box {
		display: flex;
		gap: 10px;
		align-items: center;
		padding: 12px 12px 12px 16px;
		border-radius: 18px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
	}
	.code-box code {
		flex: 1;
		min-width: 0;
		font-family: ui-monospace, 'SF Mono', Menlo, monospace;
		font-size: 13px;
		word-break: break-all;
		user-select: all;
	}
	.hint {
		margin: 0;
		font-size: 14px;
		line-height: 1.5;
		color: var(--text2);
	}
	.loading {
		display: grid;
		place-items: center;
		padding: 24px;
	}
</style>
