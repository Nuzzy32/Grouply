<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { dayOffset, isOverdue } from '#lib/app/format.ts';
	import { header, store } from '#lib/app/store.svelte.ts';
	import TaskTable from '#lib/app/ui/TaskTable.svelte';
	import type { Task } from '#lib/app/types.ts';

	$effect(() => {
		header.crumbs = [{ label: 'Tugas Saya' }];
	});

	const now = new Date();
	const snap = $derived(store.snap!);
	const me = $derived(snap.currentUserID);
	// Tugas di proyek arsip disembunyikan; proyek selesai tetap tampil di Selesai.
	const visible = $derived(new Set(snap.projects.filter((p) => p.status !== 'archived').map((p) => p.id)));
	const byDue = (a: Task, b: Task) => a.dueAt.localeCompare(b.dueAt);
	const live = $derived(snap.tasks.filter((t) => visible.has(t.projectID)).sort(byDue));
	const mine = $derived(live.filter((t) => t.assigneeID === me));
	const toReview = $derived(live.filter((t) => t.reviewerID === me && t.status === 'in_review'));

	// Pembagian seksi sama dengan desain (myTasksVals).
	const overdue = (t: Task) => isOverdue(new Date(t.dueAt), t.status, now);
	const soonDue = (t: Task) => !overdue(t) && t.status !== 'done' && dayOffset(new Date(t.dueAt), now) <= 2;
	const action = $derived([...mine.filter((t) => t.status === 'needs_revision' || (overdue(t) && t.status !== 'in_review')), ...toReview]);
	const soon = $derived(mine.filter((t) => !action.includes(t) && soonDue(t) && t.status !== 'in_review'));
	const rest = $derived(mine.filter((t) => !action.includes(t) && !soon.includes(t) && t.status !== 'done'));
	const done = $derived(mine.filter((t) => t.status === 'done'));
	const active = $derived(mine.filter((t) => t.status === 'in_progress'));

	type Filter = 'all' | 'review' | 'active' | 'done';
	let filter = $state<Filter>('all');
	const FILTERS = $derived<[Filter, string, number][]>([
		['all', 'Semua', mine.length + toReview.length],
		['review', 'Perlu review', toReview.length],
		['active', 'Dikerjakan', active.length],
		['done', 'Selesai', done.length]
	]);
	const none = $derived(!mine.length && !toReview.length);
	const sections = $derived.by((): [string, Task[]][] => {
		if (filter === 'all')
			return (
				[
					['Perlu tindakan', action],
					['Segera', soon],
					['Sedang berjalan', rest],
					['Selesai', done]
				] as [string, Task[]][]
			).filter(([, items]) => items.length);
		const label = FILTERS.find(([k]) => k === filter)![1];
		return [[label, filter === 'review' ? toReview : filter === 'active' ? active : done]];
	});
</script>

<svelte:head><title>Tugas Saya · GROUPLY</title></svelte:head>

<div class="page">
	<div class="top">
		<div class="titles">
			<h1>Tugas Saya</h1>
			<p>{none ? 'Belum ada tugas untukmu' : `${mine.length - done.length} terbuka · ${toReview.length} menunggu review kamu`}</p>
		</div>
		<div class="filters">
			{#each FILTERS as [key, label, n] (key)}
				<button class="filter" class:on={filter === key} aria-pressed={filter === key} onclick={() => (filter = key)}>
					{label}<span class="n">{n}</span>
				</button>
			{/each}
		</div>
	</div>

	{#if none}
		<div class="empty">
			<span class="empty-icon"><Icon name="task_alt" size={28} /></span>
			<b>Belum ada tugas</b>
			<span>Saat koordinator membagi tugas atau ada hasil kerja yang perlu kamu review, semuanya muncul di sini.</span>
		</div>
	{:else}
		{#each sections as [title, items] (title)}
			<section class="section">
				<div class="sec-head"><h2>{title}</h2><span>{items.length}</span></div>
				{#if items.length}
					<TaskTable {snap} tasks={items} showProject />
				{:else}
					<div class="sec-empty">Tidak ada tugas di kategori ini.</div>
				{/if}
			</section>
		{/each}
	{/if}
</div>

<style>
	.page {
		max-width: 1360px;
		margin: 0 auto;
		padding: 28px 32px 56px;
		display: flex;
		flex-direction: column;
		gap: 20px;
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
	.filters {
		display: flex;
		gap: 8px;
		flex-wrap: wrap;
	}
	.filter {
		height: 42px;
		padding: 0 6px 0 16px;
		border-radius: 21px;
		border: 1.5px solid var(--ink);
		background: var(--surface);
		display: flex;
		align-items: center;
		gap: 8px;
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
	.n {
		min-width: 28px;
		height: 28px;
		padding: 0 8px;
		border-radius: 14px;
		background: var(--muted);
		color: var(--ink);
		font-size: 13px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.filter.on .n {
		background: var(--mint);
	}
	.section {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.sec-head {
		padding-left: 4px;
		display: flex;
		align-items: center;
		gap: 8px;
	}
	h2 {
		margin: 0;
		font-size: 13px;
		font-weight: 700;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--text2);
	}
	.sec-head span {
		font-size: 13px;
		color: var(--secondary);
	}
	.sec-empty {
		background: var(--surface);
		border-radius: 24px;
		padding: 26px;
		text-align: center;
		font-size: 15px;
		color: var(--secondary);
	}
	.empty {
		background: var(--surface);
		border-radius: 28px;
		padding: 36px 24px;
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
		background: var(--sky);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.empty b {
		font-size: 19px;
	}
	.empty > span:not(.empty-icon) {
		max-width: 440px;
		font-size: 15px;
		line-height: 1.5;
		color: var(--secondary);
	}
</style>
