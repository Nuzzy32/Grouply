<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { activityStamp, activityStyle, dayOffset, dueLabel, firstName, initials, isOverdue, longToday, shortDate, STATUS, tint, weekday } from '#lib/app/format.ts';
	import { myGroups, splitActivity, userName } from '#lib/app/derive.ts';
	import { openTask } from '#lib/app/nav.ts';
	import { header, store } from '#lib/app/store.svelte.ts';
	import type { Task } from '#lib/app/types.ts';

	$effect(() => {
		header.crumbs = [{ label: 'Beranda' }];
	});

	const now = new Date();
	const snap = $derived(store.snap!);
	const me = $derived(snap.currentUserID);
	const user = (id: string) => snap.users.find((u) => u.id === id);
	const activeProjects = $derived(snap.projects.filter((p) => p.status === 'active'));
	const activeIDs = $derived(new Set(activeProjects.map((p) => p.id)));
	// Tugas di proyek selesai/arsip hanya-baca, jadi tidak perlu ditindaklanjuti.
	const live = $derived(snap.tasks.filter((t) => activeIDs.has(t.projectID)));
	const due = (t: Task) => new Date(t.dueAt);
	const lastSub = (t: Task) => t.submissions.at(-1);

	const attention = $derived(
		live
			.filter((t) => t.assigneeID === me && (t.status === 'needs_revision' || isOverdue(due(t), t.status, now)))
			.sort((a, b) => a.dueAt.localeCompare(b.dueAt))
	);
	const toReview = $derived(live.filter((t) => t.reviewerID === me && t.status === 'in_review'));
	const deadlines = $derived(
		live
			.filter((t) => t.assigneeID === me && t.status !== 'done' && due(t) >= now && dayOffset(due(t), now) < 7)
			.sort((a, b) => a.dueAt.localeCompare(b.dueAt))
	);
	const projects = $derived(
		activeProjects
			.map((p) => {
				const tasks = snap.tasks.filter((t) => t.projectID === p.id);
				return { p, done: tasks.filter((t) => t.status === 'done').length, total: tasks.length };
			})
			.sort((a, b) => a.p.dueAt.localeCompare(b.p.dueAt))
	);
	const activity = $derived(
		snap.messages
			.filter((m) => m.kind === 'activity' && !m.taskID)
			.slice(-5)
			.reverse()
	);
	const groupName = (id: string) => snap.groups.find((g) => g.id === id)?.name ?? '';
	const waitingHours = (t: Task) => Math.floor((now.getTime() - new Date(lastSub(t)?.createdAt ?? now).getTime()) / 3_600_000);
	const hasGroups = $derived(myGroups(snap).length > 0);
</script>

<svelte:head><title>Beranda · GROUPLY</title></svelte:head>

<div class="page">
	<div class="hello">
		<span class="date">{longToday(now)}</span>
		<h1>Halo, {firstName(user(me)?.name)}</h1>
		<p>{attention.length} perlu perhatian · {toReview.length} menunggu review kamu · {deadlines.length} deadline minggu ini</p>
	</div>

	{#if !hasGroups}
		<div class="card empty">
			<span class="empty-icon"><Icon name="groups" size={28} /></span>
			<b>Belum ada grup</b>
			<span>Buat grup atau gabung dengan kode undangan dari koordinatormu.</span>
			<a class="btn btn-primary" href="/app/grup">Buka Grup</a>
		</div>
	{/if}

	<div class="grid">
		<div class="col">
			<div class="duo">
				<section class="card tinted" style="background:var(--butter)">
					<h2>Perlu perhatian{#if attention.length}<span class="count">{attention.length}</span>{/if}</h2>
					{#each attention as t (t.id)}
						<button class="row tap" onclick={() => openTask(t.id)}>
							<span class="row-icon"><Icon name={t.status === 'needs_revision' ? 'undo' : 'error'} size={17} /></span>
							<span class="text">
								<small>
									{t.status === 'needs_revision'
										? `Revisi diminta oleh ${userName(snap, lastSub(t)?.reviewerID || t.reviewerID)}`
										: `Terlambat sejak ${shortDate(due(t))}`}
								</small>
								<b>{t.title}</b>
							</span>
						</button>
					{:else}
						<p class="none">Semua aman, tidak ada yang mendesak.</p>
					{/each}
				</section>

				<section class="card tinted" style="background:var(--lavender)">
					<h2>Menunggu review kamu{#if toReview.length}<span class="count">{toReview.length}</span>{/if}</h2>
					{#each toReview as t (t.id)}
						{@const sub = lastSub(t)}
						{@const author = user(sub?.authorID ?? t.assigneeID)}
						<button class="row tap" onclick={() => openTask(t.id)}>
							<span class="av" style="font-size:11px" style:background={tint(author?.tint)}>{initials(author?.name)}</span>
							<span class="text">
								<b>{t.title}</b>
								<small>Dari {userName(snap, sub?.authorID ?? t.assigneeID)} · revisi {sub?.revision ?? 1}</small>
							</span>
							{#if waitingHours(t) > 48}<span class="chip stale">Menunggu {waitingHours(t)} jam</span>{/if}
						</button>
					{:else}
						<p class="none">Tidak ada hasil kerja yang menunggu review kamu.</p>
					{/each}
				</section>
			</div>

			<section class="card">
				<h2>Deadline 7 hari ke depan<a class="link" href="/app/tugas">Semua tugas</a></h2>
				{#each deadlines as t (t.id)}
					<button class="row tap line" onclick={() => openTask(t.id)}>
						<span class="day">{due(t).getDate()}<small>{weekday(due(t))}</small></span>
						<span class="text grow"><b>{t.title}</b><small class="muted">{dueLabel(due(t), t.status, now)}</small></span>
						<span class="chip" style:background={STATUS[t.status].bg}>{STATUS[t.status].label}</span>
					</button>
				{:else}
					<p class="none">Tidak ada deadline 7 hari ke depan.</p>
				{/each}
			</section>
		</div>

		<div class="col">
			<section class="card">
				<h2>Proyek aktif<a class="link" href="/app/grup">Semua grup</a></h2>
				{#each projects as { p, done, total } (p.id)}
					<a class="project" href="/app/proyek/{p.id}">
						<span class="text"><b>{p.title}</b><small class="muted">{groupName(p.groupID)} · Deadline {shortDate(new Date(p.dueAt))}</small></span>
						<span class="progress">
							<span class="bar"><span style:width="{total ? (done / total) * 100 : 0}%"></span></span>
							<small>{done}/{total}</small>
						</span>
					</a>
				{:else}
					<p class="none">Belum ada proyek aktif.</p>
				{/each}
			</section>

			<section class="card">
				<h2>Aktivitas terbaru</h2>
				{#each activity as m (m.id)}
					{@const a = splitActivity(m)}
					{@const style = activityStyle(a.verb.toLowerCase())}
					<div class="row line">
						<span class="act" style:background={style.bg}><Icon name={style.icon} size={16} /></span>
						<span class="text grow">
							<small>{userName(snap, m.senderID)} {a.verb.toLowerCase()} · {activityStamp(new Date(m.createdAt), now)}</small>
							<b>{a.title || groupName(m.groupID)}</b>
						</span>
					</div>
				{:else}
					<p class="none">Belum ada aktivitas.</p>
				{/each}
			</section>
		</div>
	</div>
</div>

<style>
	.page {
		max-width: 1360px;
		margin: 0 auto;
		padding: 28px 32px 56px;
		display: flex;
		flex-direction: column;
		gap: 24px;
	}
	.hello {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.date {
		font-size: 14px;
		color: var(--secondary);
	}
	h1 {
		margin: 0;
		font-size: 34px;
		font-weight: 700;
		letter-spacing: -0.03em;
	}
	.hello p {
		margin: 4px 0 0;
		font-size: 15px;
		color: var(--text2);
	}
	.grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: 20px;
		align-items: start;
	}
	@media (min-width: 1240px) {
		.grid {
			grid-template-columns: minmax(0, 1fr) 380px;
		}
	}
	.col {
		display: flex;
		flex-direction: column;
		gap: 20px;
		min-width: 0;
	}
	.duo {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
		gap: 20px;
	}
	.card {
		background: var(--surface);
		border-radius: 24px;
		padding: 18px 20px 8px;
		display: flex;
		flex-direction: column;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
		animation: up 0.3s ease both;
	}
	.card.tinted {
		box-shadow: none;
	}
	h2 {
		margin: 0;
		padding-bottom: 8px;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		font-size: 17px;
		font-weight: 700;
	}
	.count {
		width: 26px;
		height: 26px;
		border-radius: 50%;
		background: var(--ink);
		color: var(--on-ink);
		font-size: 13px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.link {
		font-size: 14px;
		font-weight: 600;
		color: var(--link);
	}
	.row {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 11px 0;
		border-top: 1px solid color-mix(in srgb, var(--ink) 10%, transparent);
	}
	.tap {
		width: 100%;
		border-left: none;
		border-right: none;
		border-bottom: none;
		background: none;
		text-align: left;
		border-radius: 0;
		transition: opacity 0.15s;
	}
	.tap:hover b {
		text-decoration: underline;
	}
	.row.line {
		border-top-color: var(--line);
	}
	.row-icon {
		flex: none;
		width: 34px;
		height: 34px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--surface) 70%, transparent);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.text {
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.text b {
		font-size: 15px;
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.text small {
		font-size: 12px;
		font-weight: 600;
		color: var(--text2);
	}
	.text small.muted {
		font-weight: 400;
		color: var(--secondary);
	}
	.grow {
		flex: 1;
	}
	.row .chip {
		align-self: center;
	}
	.chip.stale {
		margin-left: auto;
		background: var(--surface);
		box-shadow: inset 0 0 0 1.5px var(--ink);
	}
	.day {
		flex: none;
		width: 52px;
		height: 54px;
		border-radius: 14px;
		background: var(--muted);
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		font-size: 18px;
		font-weight: 700;
		line-height: 1.1;
	}
	.day small {
		font-size: 11px;
		font-weight: 500;
		color: var(--secondary);
	}
	.project {
		border-radius: 12px;
		transition: background 0.15s;
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 12px 0;
		border-top: 1px solid var(--line);
	}
	.project:hover b {
		text-decoration: underline;
	}
	.progress {
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 12px;
		font-weight: 600;
		color: var(--secondary);
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
		transition: width 0.5s var(--ease-out);
	}
	.act {
		flex: none;
		width: 34px;
		height: 34px;
		border-radius: 12px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.none {
		margin: 0;
		padding: 12px 0 14px;
		border-top: 1px solid color-mix(in srgb, var(--ink) 10%, transparent);
		font-size: 14px;
		color: var(--text2);
	}
	.empty {
		align-items: center;
		text-align: center;
		gap: 8px;
		padding: 32px 20px;
	}
	.empty-icon {
		width: 56px;
		height: 56px;
		border-radius: 18px;
		background: var(--mint);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.empty span {
		color: var(--text2);
		font-size: 14px;
	}
	.empty .btn {
		margin-top: 8px;
	}
</style>
