<script lang="ts">
	import { page } from '$app/state';
	import Icon from '#lib/Icon.svelte';
	import { dateInput, dueFromInput, dueLabel, groupIcon, initials, isOverdue, STATUS, tint } from '#lib/app/format.ts';
	import { canManageTasks, PROJECT_STATUS } from '#lib/app/project.ts';
	import { flash, header, store } from '#lib/app/store.svelte.ts';
	import DueField from '#lib/app/ui/DueField.svelte';
	import Modal from '#lib/app/ui/Modal.svelte';
	import PulseRing from '#lib/app/ui/PulseRing.svelte';
	import StatusChip from '#lib/app/ui/StatusChip.svelte';
	import type { Task, TaskStatus } from '#lib/app/types.ts';

	const now = new Date();
	const snap = $derived(store.snap!);
	const me = $derived(snap.currentUserID);
	const project = $derived(snap.projects.find((p) => p.id === page.params.id));
	const group = $derived(snap.groups.find((g) => g.id === project?.groupID));
	const user = (id: string) => snap.users.find((u) => u.id === id);
	const name = (id: string) => (id === me ? 'Kamu' : (user(id)?.name ?? 'Anggota'));
	const tasks = $derived(
		snap.tasks.filter((t) => t.projectID === project?.id).sort((a, b) => a.dueAt.localeCompare(b.dueAt))
	);
	const done = $derived(tasks.filter((t) => t.status === 'done').length);
	const counts = $derived(
		Object.fromEntries(
			(Object.keys(STATUS) as TaskStatus[]).map((s) => [s, tasks.filter((t) => t.status === s).length])
		) as Record<TaskStatus, number>
	);
	const comments = (t: Task) => snap.messages.filter((m) => m.taskID === t.id && m.kind === 'text').length;
	const waitHours = (t: Task) =>
		Math.floor((now.getTime() - new Date(t.submissions.at(-1)?.createdAt ?? now).getTime()) / 3_600_000);

	// Group Pulse: memilih anggota menyorot tugasnya, bukan menilai kontribusi.
	let picked = $state('');
	const members = $derived(
		(group?.memberIDs ?? []).map((id) => {
			const mine = tasks.filter((t) => t.assigneeID === id);
			return { id, done: mine.filter((t) => t.status === 'done').length, total: mine.length };
		})
	);
	const pickedStats = $derived(members.find((m) => m.id === picked));
	const dim = (t: Task) => picked !== '' && t.assigneeID !== picked;

	let view = $state<'board' | 'list'>('board');
	const COLUMNS: [TaskStatus, string][] = [
		['todo', 'Belum dimulai'],
		['in_progress', 'Dikerjakan'],
		['in_review', 'Review'],
		['needs_revision', 'Revisi'],
		['done', 'Selesai']
	];

	// Buat tugas
	let modal = $state(false);
	let title = $state('');
	let description = $state('');
	let assignee = $state('');
	let reviewer = $state('');
	let due = $state('');
	let error = $state('');
	const lockReason = $derived.by(() => {
		if (!project) return '';
		if (project.status === 'archived') return 'Proyek ini telah diarsipkan.';
		if (project.status === 'completed') return 'Proyek ini sudah selesai. Buka kembali proyek untuk mengubah tugas.';
		if (!canManageTasks(snap, project)) return 'Hanya koordinator yang bisa membuat tugas.';
		return '';
	});
	const lateWarning = $derived(
		project && dueFromInput(due) && dueFromInput(due)! > new Date(project.dueAt)
			? `Deadline tugas melewati deadline proyek (${new Date(project.dueAt).toLocaleDateString('id-ID', { day: 'numeric', month: 'short' })}). Tetap bisa disimpan, pastikan ini disengaja.`
			: ''
	);

	function newTask() {
		const d = new Date();
		d.setDate(d.getDate() + 3);
		title = description = assignee = reviewer = error = '';
		due = dateInput(d);
		modal = true;
	}

	$effect(() => {
		if (!project || !group) return;
		header.crumbs = [
			{ label: 'Grup', href: '/app/grup' },
			{ label: group.name, href: `/app/grup/${group.id}` },
			{ label: project.title }
		];
		header.action = { label: 'Buat tugas', icon: 'add', run: newTask, locked: lockReason || undefined };
		return () => (header.action = null);
	});

	async function createTask() {
		error = '';
		const text = title.trim();
		const at = dueFromInput(due);
		const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
		if (!text) return void (error = 'Judul tugas wajib diisi.');
		if (text.length > 120) return void (error = 'Judul tugas maksimal 120 karakter.');
		if (!assignee) return void (error = 'Pilih pelaksana tugas.');
		if (!reviewer) return void (error = 'Pilih reviewer tugas.');
		if (assignee === reviewer) return void (error = 'Pelaksana dan reviewer harus orang berbeda.');
		if (!at || at < today) return void (error = 'Pilih deadline yang valid, mulai hari ini.');
		try {
			await store.mutate('createTask', {
				projectID: project!.id,
				title: text,
				description: description.trim(),
				assigneeID: assignee,
				reviewerID: reviewer,
				dueAt: at.toISOString()
			});
			modal = false;
			flash(assignee === me ? 'Tugas dibuat. Ditugaskan ke kamu.' : `Tugas dibuat. ${name(assignee)} akan diberi tahu.`);
		} catch (e) {
			error = (e as Error).message;
		}
	}
</script>

<svelte:head><title>{project?.title ?? 'Proyek'} · GROUPLY</title></svelte:head>

{#snippet pair(t: Task)}
	<span class="pair" title="{name(t.assigneeID)} → {name(t.reviewerID)}">
		<span class="av" style="--s:26px;font-size:10px" style:background={tint(user(t.assigneeID)?.tint)}>{initials(user(t.assigneeID)?.name)}</span>
		<Icon name="arrow_forward" size={14} />
		<span class="av" style="--s:26px;font-size:10px" style:background={tint(user(t.reviewerID)?.tint)}>{initials(user(t.reviewerID)?.name)}</span>
	</span>
{/snippet}

{#if !project || !group}
	<div class="missing">
		<b>Proyek tidak ditemukan</b>
		<span>Mungkin proyek ini dihapus atau kamu sudah keluar dari grupnya.</span>
		<a class="btn btn-ghost" href="/app/grup">Kembali ke Grup</a>
	</div>
{:else}
	{@const st = PROJECT_STATUS[project.status]}
	<div class="page">
		{#if project.status === 'archived'}
			<div class="banner" style="background:var(--chip)"><Icon name="inventory_2" />Proyek ini telah diarsipkan. Informasi dan riwayatnya tetap dapat dilihat.</div>
		{:else if project.status === 'completed'}
			<div class="banner" style="background:var(--mint)"><Icon name="task_alt" />Proyek ini sudah selesai. Semua tugas hanya bisa dilihat.</div>
		{/if}

		<div class="top">
			<div class="card info">
				<div class="info-head">
					<a class="group" href="/app/grup/{group.id}">
						<span class="gicon" style:background={tint(group.tint)}><Icon name={groupIcon(group.icon)} size={13} /></span>{group.name}
					</a>
					<span class="chip p-status" style:background={st.bg}><Icon name={st.icon} size={15} />{st.label}</span>
				</div>
				<h1>{project.title}</h1>
				<span class="due"><Icon name="event" size={18} />Deadline {new Date(project.dueAt).toLocaleString('id-ID', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).replace('.', ':')}</span>
				{#if project.description}<p>{project.description}</p>{/if}
				<div class="grow"></div>
				<div class="info-foot">
					<span class="stack">
						{#each group.memberIDs.slice(0, 6) as id (id)}
							<span class="av" title={user(id)?.name} style="--s:34px;font-size:11px" style:background={tint(user(id)?.tint)}>{initials(user(id)?.name)}</span>
						{/each}
					</span>
					<span>{done}/{tasks.length} tugas selesai</span>
				</div>
			</div>

			<div class="card pulse">
				<div class="pulse-head"><h2>Group Pulse</h2><span>Pilih anggota untuk menyorot tugasnya</span></div>
				{#if tasks.length}
					{#key project.id}
						<div class="ring-row">
							<div class="ring">
								<PulseRing {counts} label="{done} dari {tasks.length} disetujui" />
								<div class="ring-text">
									<b>{Math.round((done / tasks.length) * 100)}%</b>
									<span>{done} dari {tasks.length} disetujui</span>
								</div>
							</div>
							<div class="legend">
								{#each COLUMNS as [s] (s)}
									<div class="legend-row">
										<span class="dot" style:background={STATUS[s].bg} style:box-shadow="inset 0 0 0 2px {STATUS[s].ring}"><Icon name={STATUS[s].icon} size={14} /></span>
										<span class="legend-label">{STATUS[s].label}</span>
										<b>{counts[s]}</b>
									</div>
								{/each}
							</div>
						</div>
					{/key}
				{:else}
					<p class="muted">Belum ada tugas, jadi belum ada progres.</p>
				{/if}
				<div class="picker">
					{#each members as m (m.id)}
						<button class="pick" class:on={picked === m.id} aria-pressed={picked === m.id} title={user(m.id)?.name} onclick={() => (picked = picked === m.id ? '' : m.id)}>
							<span class="av big" style="--s:44px;font-size:13px" style:background={tint(user(m.id)?.tint)}>
								{initials(user(m.id)?.name)}<span class="ratio">{m.done}/{m.total}</span>
							</span>
							<span class="pick-name">{name(m.id)}</span>
						</button>
					{/each}
				</div>
				{#if pickedStats}
					<div class="picked">
						<span class="picked-head">
							<b>Tugas {name(pickedStats.id)} · {pickedStats.done} dari {pickedStats.total} selesai</b>
							<button onclick={() => (picked = '')}>Tampilkan semua</button>
						</span>
						<span class="bar"><span style:width="{pickedStats.total ? (pickedStats.done / pickedStats.total) * 100 : 0}%"></span></span>
						<small>Ringkasan pembagian tugas, bukan penilaian kontribusi.</small>
					</div>
				{/if}
			</div>
		</div>

		<div class="tasks-head">
			<h2>Tugas</h2>
			<span class="muted">{tasks.length} tugas</span>
			<div class="grow"></div>
			<div class="views" role="tablist" aria-label="Tampilan tugas">
				<button role="tab" aria-selected={view === 'board'} class:on={view === 'board'} onclick={() => (view = 'board')}><Icon name="view_kanban" size={19} />Papan</button>
				<button role="tab" aria-selected={view === 'list'} class:on={view === 'list'} onclick={() => (view = 'list')}><Icon name="view_list" size={19} />Daftar</button>
			</div>
		</div>

		{#if !tasks.length}
			<div class="card none">
				{lockReason ? 'Belum ada tugas di proyek ini.' : 'Belum ada tugas. Klik Buat tugas untuk membagi pekerjaan pertama.'}
			</div>
		{:else if view === 'board'}
			<div class="board">
				{#each COLUMNS as [s, label] (s)}
					{@const items = tasks.filter((t) => t.status === s)}
					<div class="col">
						<div class="col-head">
							<span class="dot" style:background={STATUS[s].bg} style:box-shadow="inset 0 0 0 2px {STATUS[s].ring}"><Icon name={STATUS[s].icon} size={14} /></span>
							<b>{label}</b><span class="count">{items.length}</span>
						</div>
						{#each items as t (t.id)}
							{@const late = isOverdue(new Date(t.dueAt), t.status, now)}
							<div class="task" class:dim={dim(t)}>
								{#if late}<span class="chip flag" style="background:var(--coral)"><Icon name="error" size={15} />Terlambat</span>{/if}
								{#if t.status === 'in_review' && waitHours(t) > 48}<span class="chip flag" style="background:var(--lavender)"><Icon name="pending_actions" size={15} />Menunggu {waitHours(t)} jam</span>{/if}
								<b>{t.title}</b>
								<span class="task-foot">
									{@render pair(t)}
									<span class="grow"></span>
									<span class="meta"><Icon name="schedule" size={15} />{dueLabel(new Date(t.dueAt), t.status, now)}</span>
									<span class="meta"><Icon name="chat_bubble" size={15} />{comments(t)}</span>
								</span>
							</div>
						{:else}
							<div class="col-empty">Tidak ada tugas</div>
						{/each}
					</div>
				{/each}
			</div>
		{:else}
			<div class="card list">
				<div class="tr th"><span>Tugas</span><span>Status</span><span>Pelaksana → Reviewer</span><span>Deadline</span><span class="right">Kom.</span></div>
				{#each tasks as t (t.id)}
					<div class="tr" class:dim={dim(t)}>
						<span class="t-title"><b>{t.title}</b>{#if isOverdue(new Date(t.dueAt), t.status, now)}<span class="late" title="Terlambat"><Icon name="error" size={18} /></span>{/if}</span>
						<span><StatusChip status={t.status} /></span>
						<span class="t-pair">{@render pair(t)}<span class="ellipsis">{name(t.assigneeID)} → {name(t.reviewerID)}</span></span>
						<span class="nowrap">{dueLabel(new Date(t.dueAt), t.status, now)}</span>
						<span class="right">{comments(t)}</span>
					</div>
				{/each}
			</div>
		{/if}
	</div>
{/if}

{#if modal && project && group}
	<Modal title="Buat tugas" sub="{project.title} · Deadline proyek {new Date(project.dueAt).toLocaleDateString('id-ID', { day: 'numeric', month: 'short' })}" width={620} busy={store.busy} onclose={() => (modal = false)}>
		<form id="task-form" class="form" onsubmit={(e) => (e.preventDefault(), createTask())} novalidate>
			<label class="field">
				<span class="label-row"><span>Judul <em>*</em></span><small>{title.trim().length}/120</small></span>
				<input class="input" bind:value={title} maxlength="120" placeholder="Contoh: Buat use case diagram" />
			</label>
			<label class="field">
				Deskripsi
				<textarea class="input" bind:value={description} rows="3" maxlength="2000" placeholder="Jelaskan apa yang perlu dikerjakan dan hasil yang diharapkan..."></textarea>
			</label>
			{#each [['Pelaksana', 'assignee'], ['Reviewer', 'reviewer']] as [label, role] (role)}
				<div class="field">
					<span>{label} <em>*</em></span>
					<div class="people">
						{#each group.memberIDs as id (id)}
							{@const on = role === 'assignee' ? assignee === id : reviewer === id}
							{@const blocked = role === 'reviewer' && assignee === id}
							<button
								type="button"
								class="person"
								class:on
								aria-pressed={on}
								disabled={blocked}
								title={blocked ? 'Reviewer harus berbeda dari pelaksana' : undefined}
								onclick={() => {
									if (role === 'assignee') {
										assignee = id;
										if (reviewer === id) reviewer = '';
									} else reviewer = id;
								}}
							>
								<span class="av" style="--s:30px;font-size:11px" style:background={tint(user(id)?.tint)}>{initials(user(id)?.name)}</span>{name(id)}
							</button>
						{/each}
					</div>
				</div>
			{/each}
			<div class="field">
				<span>Deadline <em>*</em></span>
				<DueField bind:value={due} />
				{#if lateWarning}<div class="notice warn"><Icon name="warning" size={18} />{lateWarning}</div>{/if}
			</div>
			{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		</form>
		{#snippet footer()}
			<button class="btn btn-ghost" type="button" disabled={store.busy} onclick={() => (modal = false)}>Batal</button>
			<button class="btn btn-primary" form="task-form" disabled={store.busy}>
				{#if store.busy}<span class="spin" aria-hidden="true"></span>{/if}{store.busy ? 'Menyimpan…' : 'Buat tugas'}
			</button>
		{/snippet}
	</Modal>
{/if}

<style>
	.page {
		padding: 24px 32px 56px;
		display: flex;
		flex-direction: column;
		gap: 20px;
	}
	.banner {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 12px 16px;
		border-radius: 18px;
		font-size: 14px;
	}
	.top {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: 20px;
		align-items: stretch;
	}
	@media (min-width: 1240px) {
		.top {
			grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr);
		}
	}
	.card {
		background: var(--surface);
		border-radius: 32px;
		min-width: 0;
		animation: up 0.25s ease both;
	}
	.info {
		padding: 24px;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.info-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
	}
	.group {
		height: 32px;
		padding: 0 6px;
		margin-left: -6px;
		border-radius: 10px;
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 14px;
		font-weight: 600;
		color: var(--text2);
	}
	.group:hover {
		background: var(--muted);
	}
	.gicon {
		width: 20px;
		height: 20px;
		border-radius: 7px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.p-status {
		height: 28px;
		padding: 0 10px 0 7px;
		gap: 4px;
		font-size: 12px;
		align-self: center;
	}
	h1 {
		margin: 0;
		font-size: 30px;
		font-weight: 700;
		letter-spacing: -0.03em;
		line-height: 1.12;
		text-wrap: pretty;
	}
	.due {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 14px;
		color: var(--text3);
	}
	.info p {
		margin: 0;
		max-width: 640px;
		font-size: 15px;
		line-height: 1.55;
		color: var(--text3);
	}
	.grow {
		flex: 1;
	}
	.info-foot {
		padding-top: 6px;
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		color: var(--text3);
	}
	.stack {
		display: flex;
		padding-right: 8px;
	}
	.stack .av {
		margin-right: -8px;
		box-shadow: 0 0 0 2.5px var(--surface);
	}
	.pulse {
		padding: 22px 24px;
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	.pulse-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 8px;
		flex-wrap: wrap;
	}
	h2 {
		margin: 0;
		font-size: 19px;
		font-weight: 700;
		letter-spacing: -0.02em;
	}
	.pulse-head span,
	.muted {
		font-size: 13px;
		color: var(--secondary);
	}
	p.muted {
		margin: 0;
		padding: 8px 0;
		font-size: 15px;
	}
	.ring-row {
		display: flex;
		align-items: center;
		gap: 22px;
		flex-wrap: wrap;
	}
	.ring {
		flex: none;
		position: relative;
		width: 132px;
		height: 132px;
	}
	.ring-text {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
	}
	.ring-text b {
		font-size: 28px;
		font-weight: 800;
		letter-spacing: -0.04em;
		font-variant-numeric: tabular-nums;
	}
	.ring-text span {
		max-width: 80px;
		font-size: 12px;
		line-height: 1.25;
		text-align: center;
		color: var(--secondary);
	}
	.legend {
		flex: 1 1 170px;
		display: flex;
		flex-direction: column;
		gap: 7px;
	}
	.legend-row {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 14px;
	}
	.legend-label {
		flex: 1;
		color: var(--text3);
	}
	.legend-row b {
		font-variant-numeric: tabular-nums;
	}
	.dot {
		flex: none;
		width: 24px;
		height: 24px;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.picker {
		display: flex;
		gap: 4px;
		overflow-x: auto;
		margin: 0 -4px;
		padding: 4px;
	}
	.pick {
		flex: none;
		width: 64px;
		border: none;
		background: none;
		padding: 4px 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 5px;
		transition: transform 0.25s cubic-bezier(0.3, 1.6, 0.5, 1);
	}
	.pick:active {
		transform: scale(0.92);
	}
	.pick.on {
		transform: scale(1.06);
	}
	.big {
		position: relative;
		transition: box-shadow 0.2s;
	}
	.pick.on .big {
		box-shadow:
			0 0 0 2.5px var(--surface),
			0 0 0 4.5px var(--ink);
	}
	.ratio {
		position: absolute;
		right: -6px;
		bottom: -4px;
		min-width: 26px;
		height: 20px;
		padding: 0 5px;
		border-radius: 10px;
		background: var(--surface);
		box-shadow: 0 0 0 1px var(--border);
		font-size: 11px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.pick-name {
		max-width: 62px;
		font-size: 13px;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.pick.on .pick-name {
		font-weight: 700;
	}
	.picked {
		padding: 12px 14px;
		border-radius: 18px;
		background: var(--muted);
		display: flex;
		flex-direction: column;
		gap: 6px;
		animation: up 0.2s ease both;
	}
	.picked-head {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.picked-head b {
		flex: 1;
		font-size: 14px;
		font-weight: 600;
	}
	.picked-head button {
		height: 32px;
		padding: 0 10px;
		border: none;
		border-radius: 16px;
		background: var(--surface);
		font-size: 13px;
		font-weight: 600;
	}
	.bar {
		height: 6px;
		border-radius: 3px;
		background: var(--surface);
		overflow: hidden;
	}
	.bar span {
		display: block;
		height: 100%;
		border-radius: 3px;
		background: var(--ink);
		transition: width 0.5s ease;
	}
	.picked small {
		font-size: 12px;
		color: var(--text2);
	}
	.tasks-head {
		padding-top: 4px;
		display: flex;
		align-items: center;
		gap: 12px;
		flex-wrap: wrap;
	}
	.tasks-head h2 {
		font-size: 22px;
	}
	.tasks-head .muted {
		font-size: 14px;
	}
	.views {
		display: flex;
		gap: 2px;
		padding: 4px;
		border-radius: 16px;
		background: var(--chip);
	}
	.views button {
		height: 36px;
		padding: 0 14px 0 10px;
		border: none;
		border-radius: 12px;
		background: transparent;
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 14px;
		font-weight: 600;
		transition: background 0.15s;
	}
	.views .on {
		background: light-dark(var(--surface), #3b3f43);
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
	}
	.board {
		display: grid;
		grid-template-columns: repeat(5, minmax(236px, 1fr));
		gap: 14px;
		overflow-x: auto;
		padding-bottom: 6px;
		align-items: start;
	}
	.col {
		background: var(--muted);
		border-radius: 24px;
		padding: 12px;
		display: flex;
		flex-direction: column;
		gap: 10px;
		min-height: 180px;
	}
	.col-head {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 4px 4px 2px;
	}
	.col-head b {
		flex: 1;
		font-size: 14px;
	}
	.count {
		min-width: 24px;
		height: 22px;
		padding: 0 7px;
		border-radius: 11px;
		background: var(--surface);
		font-size: 12px;
		font-weight: 700;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.task {
		background: var(--surface);
		border-radius: 18px;
		padding: 14px;
		display: flex;
		flex-direction: column;
		gap: 10px;
		transition: opacity 0.25s;
		animation: up 0.22s ease both;
	}
	.task b {
		font-size: 15px;
		font-weight: 600;
		line-height: 1.3;
	}
	.flag {
		height: 24px;
		padding: 0 9px 0 6px;
		font-size: 12px;
		box-shadow: inset 0 0 0 1.5px var(--ink);
	}
	.task-foot {
		display: flex;
		align-items: center;
		gap: 6px;
		flex-wrap: wrap;
	}
	.pair {
		display: flex;
		align-items: center;
		gap: 3px;
		color: var(--secondary);
	}
	.meta {
		display: flex;
		align-items: center;
		gap: 3px;
		font-size: 12px;
		color: var(--text3);
	}
	.dim {
		opacity: 0.35;
	}
	.col-empty {
		padding: 16px 8px;
		border-radius: 16px;
		border: 1.5px dashed var(--disabled);
		text-align: center;
		font-size: 13px;
		color: var(--secondary);
	}
	.none {
		padding: 28px;
		text-align: center;
		font-size: 15px;
		color: var(--secondary);
		border-radius: 24px;
	}
	.list {
		border-radius: 24px;
		padding: 4px 8px 6px;
		display: flex;
		flex-direction: column;
	}
	.tr {
		display: grid;
		grid-template-columns: minmax(0, 2fr) 170px minmax(0, 1.3fr) 130px 50px;
		gap: 16px;
		align-items: center;
		min-height: 56px;
		padding: 8px 12px;
		border-top: 1px solid var(--muted);
		font-size: 13px;
		color: var(--text3);
		transition: opacity 0.25s;
	}
	.th {
		min-height: 0;
		padding: 10px 12px;
		border-top: none;
		font-size: 12px;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--text2);
	}
	@media (max-width: 1099px) {
		.tr {
			grid-template-columns: minmax(0, 2fr) 170px 120px 50px;
		}
		.tr > :nth-child(3) {
			display: none;
		}
	}
	.t-title {
		min-width: 0;
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.t-title b {
		min-width: 0;
		font-size: 15px;
		font-weight: 600;
		color: var(--ink);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.late {
		flex: none;
		display: flex;
		color: var(--danger);
	}
	.t-pair {
		min-width: 0;
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.ellipsis {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.nowrap {
		white-space: nowrap;
	}
	.right {
		text-align: right;
	}
	.missing {
		max-width: 480px;
		margin: 48px auto;
		background: var(--surface);
		border-radius: 28px;
		padding: 32px 24px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
		text-align: center;
	}
	.missing b {
		font-size: 19px;
	}
	.missing span {
		font-size: 15px;
		color: var(--secondary);
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
	.people {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}
	.person {
		height: 40px;
		padding: 0 14px 0 4px;
		border-radius: 20px;
		border: 1.5px solid var(--ink);
		background: transparent;
		display: flex;
		align-items: center;
		gap: 7px;
		font-size: 14px;
		font-weight: 600;
		transition: background 0.15s;
	}
	.person.on {
		background: var(--ink);
		color: var(--on-ink);
	}
	.person:disabled {
		opacity: 0.35;
		cursor: not-allowed;
	}
	.notice.warn {
		display: flex;
		gap: 8px;
		align-items: flex-start;
		background: var(--butter);
	}
</style>
