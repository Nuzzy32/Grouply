<script lang="ts">
	import { page } from '$app/state';
	import Icon from '#lib/Icon.svelte';
	import { userName } from '#lib/app/derive.ts';
	import { groupIcon, initials, isOverdue, STATUS, tint } from '#lib/app/format.ts';
	import { pending, sendMessage } from '#lib/app/messages.svelte.ts';
	import { openTask } from '#lib/app/nav.ts';
	import { projectStats } from '#lib/app/project.ts';
	import { header, store } from '#lib/app/store.svelte.ts';
	import Composer from '#lib/app/ui/Composer.svelte';
	import Thread from '#lib/app/ui/Thread.svelte';

	const now = new Date();
	const snap = $derived(store.snap!);
	const me = $derived(snap.currentUserID);
	const group = $derived(snap.groups.find((g) => g.id === page.params.id && g.memberIDs.includes(me)));
	const messages = $derived(snap.messages.filter((m) => m.groupID === group?.id && !m.taskID));
	const mine = $derived(pending.filter((p) => p.groupID === group?.id && !p.taskID));
	const user = (id: string) => snap.users.find((u) => u.id === id);

	$effect(() => {
		if (group) header.crumbs = [{ label: 'Chat', href: '/app/chat' }, { label: group.name }];
	});

	// Gulir ke bawah saat dibuka; pesan baru ikut menggulir bila pengguna sedang di bawah.
	let scroller = $state<HTMLDivElement>();
	let sentinel = $state<HTMLDivElement>();
	let atBottom = $state(true);
	$effect(() => {
		if (!sentinel || !scroller) return;
		const io = new IntersectionObserver(([e]) => (atBottom = e.isIntersecting), { root: scroller });
		io.observe(sentinel);
		return () => io.disconnect();
	});
	let lastGroup = '';
	$effect(() => {
		const count = messages.length + mine.length;
		if (!scroller || !count) return;
		const first = lastGroup !== group?.id;
		lastGroup = group?.id ?? '';
		if (first || atBottom || mine.length) queueMicrotask(() => scroller?.scrollTo({ top: scroller.scrollHeight }));
	});

	// Tandai dibaca hanya pesan yang benar-benar terlihat: saat ujung thread tampil di layar.
	const read = $derived(new Set(snap.readMessageIDs));
	const unreadIDs = $derived(messages.filter((m) => m.senderID !== me && !read.has(m.id)).map((m) => m.id));
	let marking = false;
	let retryTick = $state(0);
	$effect(() => {
		retryTick;
		if (!group || !atBottom || !unreadIDs.length || marking || document.hidden) return;
		marking = true;
		store
			.mutate('markChatRead', { groupID: group.id, messageIDs: unreadIDs })
			.catch(() => setTimeout(() => retryTick++, 800))
			.finally(() => (marking = false));
	});

	// Pesan aktivitas di chat grup hanya membawa judul tugas; buka tugasnya bila judulnya unik di grup.
	function findTask(title: string, groupID: string) {
		const projectIDs = new Set(snap.projects.filter((p) => p.groupID === groupID).map((p) => p.id));
		const hits = snap.tasks.filter((t) => projectIDs.has(t.projectID) && t.title === title);
		return hits.length === 1 ? () => openTask(hits[0].id) : null;
	}

	let width = $state(1440);
	let showInfo = $state(true);
	const attention = $derived.by(() => {
		if (!group) return [];
		const active = new Set(snap.projects.filter((p) => p.groupID === group.id && p.status === 'active').map((p) => p.id));
		return snap.tasks.filter(
			(t) => active.has(t.projectID) && t.status !== 'done' && (t.status === 'needs_revision' || t.status === 'in_review' || isOverdue(new Date(t.dueAt), t.status, now))
		);
	});
	const projects = $derived(snap.projects.filter((p) => p.groupID === group?.id && p.status === 'active'));
</script>

<svelte:window bind:innerWidth={width} />
<svelte:head><title>{group ? `${group.name} · Chat` : 'Chat'} · GROUPLY</title></svelte:head>

{#if !group}
	<section class="missing">
		<Icon name="forum" size={36} />
		<b>Percakapan tidak ditemukan</b>
		<span>Mungkin kamu sudah keluar dari grup ini.</span>
		<a class="btn btn-ghost" href="/app/chat">Kembali ke Chat</a>
	</section>
{:else}
	<section class="convo" aria-label="Percakapan {group.name}">
		<div class="head">
			<a class="back" href="/app/chat" aria-label="Kembali ke daftar chat"><Icon name="arrow_back" size={20} /></a>
			<span class="icon" style:background={tint(group.tint)}><Icon name={groupIcon(group.icon)} size={22} /></span>
			<span class="title">
				<b>{group.name}</b>
				<small>{group.memberIDs.length} anggota · {group.memberIDs.map((id) => userName(snap, id)).join(', ')}</small>
			</span>
			<a class="open-group" href="/app/grup/{group.id}"><Icon name="group" size={18} />Buka grup</a>
			{#if width >= 1320}
				<button class="info-toggle" aria-label="Tampilkan atau sembunyikan info grup" aria-pressed={showInfo} title="Info grup" onclick={() => (showInfo = !showInfo)}>
					<Icon name={showInfo ? 'right_panel_close' : 'right_panel_open'} size={21} />
				</button>
			{/if}
		</div>
		<div class="scroller" bind:this={scroller}>
			<div class="inner">
				{#if messages.length || mine.length}
					<Thread {snap} {messages} pending={mine} activity="card" onopentask={findTask} />
				{:else}
					<div class="start"><b>Belum ada pesan</b><span>Sapa kelompokmu dan mulai diskusi di sini.</span></div>
				{/if}
				<div class="sentinel" bind:this={sentinel}></div>
			</div>
		</div>
		<div class="foot">
			<div class="inner">
				<Composer placeholder="Tulis pesan ke grup…" onsend={(text) => sendMessage(group.id, null, text)} />
				<small>Enter untuk kirim · Shift + Enter untuk baris baru</small>
			</div>
		</div>
	</section>

	{#if width >= 1320 && showInfo}
		<aside class="info" aria-label="Info grup">
			<div class="block">
				<span class="label">Perlu perhatian di grup</span>
				{#each attention as t (t.id)}
					<button class="card-btn" onclick={() => openTask(t.id)}>
						<b>{t.title}</b>
						<span class="meta">
							<span class="chip" style:background={STATUS[t.status].bg}><Icon name={STATUS[t.status].icon} size={14} />{STATUS[t.status].label}</span>
							<small>{userName(snap, t.assigneeID)}</small>
						</span>
					</button>
				{:else}
					<span class="muted">Tidak ada yang mendesak.</span>
				{/each}
			</div>
			<div class="block">
				<span class="label">Proyek aktif</span>
				{#each projects as p (p.id)}
					{@const s = projectStats(snap, p.id)}
					<a class="card-btn" href="/app/proyek/{p.id}">
						<b>{p.title}</b>
						<span class="progress"><span class="bar"><span style:width="{s.total ? (s.done / s.total) * 100 : 0}%"></span></span><small>{s.done}/{s.total}</small></span>
					</a>
				{:else}
					<span class="muted">Belum ada proyek aktif.</span>
				{/each}
			</div>
			<div class="block">
				<span class="label">Anggota</span>
				{#each group.memberIDs as id (id)}
					<div class="member">
						<span class="av" style="--s:32px;font-size:11px" style:background={tint(user(id)?.tint)}>{initials(user(id)?.name)}</span>
						<span class="m-name">{userName(snap, id)}</span>
						<small>{id === group.coordinatorID ? 'Koordinator' : 'Anggota'}</small>
					</div>
				{/each}
			</div>
		</aside>
	{/if}
{/if}

<style>
	.convo {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	.head {
		flex: none;
		height: 72px;
		padding: 0 20px;
		border-bottom: 1px solid var(--border);
		display: flex;
		align-items: center;
		gap: 12px;
	}
	.back {
		display: none;
		width: 40px;
		height: 40px;
		border-radius: 50%;
		align-items: center;
		justify-content: center;
	}
	@media (max-width: 899px) {
		.back {
			display: flex;
		}
	}
	.icon {
		flex: none;
		width: 42px;
		height: 42px;
		border-radius: 16px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.title {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	.title b {
		font-size: 16px;
		font-weight: 700;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.title small {
		font-size: 13px;
		color: var(--secondary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.open-group {
		flex: none;
		height: 40px;
		padding: 0 14px 0 10px;
		border-radius: 20px;
		box-shadow: inset 0 0 0 1.5px var(--ink);
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 13px;
		font-weight: 600;
		transition: background 0.15s;
	}
	.open-group:hover {
		background: var(--muted);
	}
	.info-toggle {
		flex: none;
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 50%;
		background: var(--surface);
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.scroller {
		flex: 1;
		min-height: 0;
		overflow: auto;
		padding: 8px 24px 16px;
	}
	.inner {
		max-width: 780px;
		margin: 0 auto;
		display: flex;
		flex-direction: column;
	}
	.sentinel {
		height: 1px;
	}
	.start {
		padding: 48px 12px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		text-align: center;
	}
	.start b {
		font-size: 16px;
	}
	.start span {
		font-size: 14px;
		color: var(--secondary);
	}
	.foot {
		flex: none;
		padding: 12px 24px 18px;
		border-top: 1px solid var(--border);
	}
	.foot .inner {
		gap: 6px;
	}
	.foot small {
		padding-left: 16px;
		font-size: 12px;
		color: var(--secondary);
	}
	.info {
		flex: none;
		width: 300px;
		border-left: 1px solid var(--border);
		overflow: auto;
		padding: 18px 16px 24px;
		display: flex;
		flex-direction: column;
		gap: 20px;
		animation: fade 0.2s ease;
	}
	.block {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.label {
		font-size: 12px;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--text2);
	}
	.card-btn {
		text-align: left;
		border: none;
		background: var(--surface);
		border-radius: 16px;
		padding: 10px 12px;
		display: flex;
		flex-direction: column;
		gap: 6px;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
		transition: box-shadow 0.15s;
	}
	.card-btn:hover {
		box-shadow: 0 8px 20px -12px rgba(0, 0, 0, 0.3);
	}
	.card-btn b {
		font-size: 14px;
		font-weight: 600;
		line-height: 1.3;
	}
	.meta {
		display: flex;
		align-items: center;
		gap: 6px;
		flex-wrap: wrap;
	}
	.meta .chip {
		height: 24px;
		padding: 0 8px 0 6px;
		font-size: 12px;
		align-self: center;
	}
	.meta small,
	.member small,
	.muted {
		font-size: 12px;
		color: var(--secondary);
	}
	.muted {
		font-size: 14px;
	}
	.progress {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.progress small {
		font-size: 12px;
		font-weight: 600;
	}
	.bar {
		flex: 1;
		height: 5px;
		border-radius: 3px;
		background: var(--muted);
		overflow: hidden;
	}
	.bar span {
		display: block;
		height: 100%;
		background: var(--ink);
	}
	.member {
		min-height: 40px;
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.m-name {
		flex: 1;
		font-size: 14px;
		font-weight: 500;
	}
	.missing {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 8px;
		color: var(--secondary);
		text-align: center;
		padding: 16px;
	}
	.missing b {
		font-size: 17px;
		color: var(--ink);
	}
</style>
