<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { userName } from '../derive.ts';
	import { dueLabel, initials, isOverdue, tint } from '../format.ts';
	import { openTask } from '../nav.ts';
	import type { Snapshot, Task } from '../types.ts';
	import StatusChip from './StatusChip.svelte';

	let {
		snap,
		tasks,
		showProject = false,
		dim
	}: { snap: Snapshot; tasks: Task[]; showProject?: boolean; dim?: (t: Task) => boolean } = $props();

	const now = new Date();
	const user = (id: string) => snap.users.find((u) => u.id === id);
	const project = (id: string) => snap.projects.find((p) => p.id === id);
	const comments = (t: Task) => snap.messages.filter((m) => m.taskID === t.id && m.kind === 'text').length;
	const waitHours = (t: Task) =>
		Math.floor((now.getTime() - new Date(t.submissions.at(-1)?.createdAt ?? now).getTime()) / 3_600_000);
</script>

<div class="table" class:with-project={showProject}>
	<div class="tr th">
		<span>Tugas</span>{#if showProject}<span>Proyek</span>{/if}<span>Status</span><span class="pair-col">Pelaksana → Reviewer</span><span>Deadline</span><span class="right">Kom.</span>
	</div>
	{#each tasks as t (t.id)}
		<button class="tr" class:dim={dim?.(t)} onclick={() => openTask(t.id)}>
			<span class="title">
				<b>{t.title}</b>
				{#if isOverdue(new Date(t.dueAt), t.status, now)}<span class="chip flag" style="background:var(--coral)"><Icon name="error" size={14} />Terlambat</span>{/if}
				{#if t.status === 'in_review' && waitHours(t) > 48}<span class="chip flag" style="background:var(--lavender)"><Icon name="pending_actions" size={14} />Menunggu {waitHours(t)} jam</span>{/if}
			</span>
			{#if showProject}<span class="muted ellipsis">{project(t.projectID)?.title}</span>{/if}
			<span><StatusChip status={t.status} /></span>
			<span class="pair pair-col">
				<span class="av" style="--s:26px;font-size:10px" style:background={tint(user(t.assigneeID)?.tint)}>{initials(user(t.assigneeID)?.name)}</span>
				<Icon name="arrow_forward" size={14} />
				<span class="av" style="--s:26px;font-size:10px" style:background={tint(user(t.reviewerID)?.tint)}>{initials(user(t.reviewerID)?.name)}</span>
				<span class="ellipsis">{userName(snap, t.assigneeID)} → {userName(snap, t.reviewerID)}</span>
			</span>
			<span class="nowrap">{dueLabel(new Date(t.dueAt), t.status, now)}</span>
			<span class="right">{comments(t)}</span>
		</button>
	{/each}
</div>

<style>
	.table {
		--cols: minmax(0, 2fr) 170px minmax(0, 1.3fr) 130px 50px;
		background: var(--surface);
		border-radius: 24px;
		padding: 4px 8px 6px;
		display: flex;
		flex-direction: column;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
		animation: up 0.25s ease both;
	}
	.with-project {
		--cols: minmax(0, 2fr) minmax(0, 1fr) 170px minmax(0, 1.3fr) 130px 50px;
	}
	.tr {
		display: grid;
		grid-template-columns: var(--cols);
		gap: 16px;
		align-items: center;
		min-height: 58px;
		padding: 8px 12px;
		border: none;
		border-top: 1px solid var(--muted);
		border-radius: 14px;
		background: transparent;
		text-align: left;
		font-size: 13px;
		color: var(--text3);
		transition:
			opacity 0.25s,
			background 0.15s;
	}
	button.tr:hover {
		background: var(--background);
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
	/* Layar ringkas: kolom pasangan disembunyikan, seperti desain. */
	@media (max-width: 1099px) {
		.table {
			--cols: minmax(0, 2fr) 170px 120px 50px;
		}
		.with-project {
			--cols: minmax(0, 2fr) minmax(0, 1fr) 170px 120px 50px;
		}
		.pair-col {
			display: none !important;
		}
	}
	.title {
		min-width: 0;
		display: flex;
		align-items: center;
		gap: 8px;
		flex-wrap: wrap;
	}
	.title b {
		min-width: 0;
		font-size: 15px;
		font-weight: 600;
		color: var(--ink);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.flag {
		height: 22px;
		padding: 0 8px 0 5px;
		font-size: 11px;
		box-shadow: inset 0 0 0 1.5px var(--ink);
		align-self: center;
	}
	.muted {
		font-size: 14px;
		color: var(--secondary);
	}
	.pair {
		min-width: 0;
		display: flex;
		align-items: center;
		gap: 4px;
		color: var(--secondary);
	}
	.pair .ellipsis {
		padding-left: 4px;
		color: var(--text3);
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
	.dim {
		opacity: 0.35;
	}
</style>
