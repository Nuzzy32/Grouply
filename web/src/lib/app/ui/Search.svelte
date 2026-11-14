<script lang="ts">
	import { goto } from '$app/navigation';
	import Icon from '#lib/Icon.svelte';
	import { myGroups } from '../derive.ts';
	import { groupIcon, STATUS, tint } from '../format.ts';
	import { openTask } from '../nav.ts';
	import { store } from '../store.svelte.ts';

	let { onclose }: { onclose: () => void } = $props();

	const snap = $derived(store.snap!);
	const me = $derived(snap.currentUserID);
	let query = $state('');
	const q = $derived(query.trim().toLowerCase());
	const groups = $derived(myGroups(snap));
	const groupName = (id: string) => snap.groups.find((g) => g.id === id)?.name ?? '';
	const project = (id: string) => snap.projects.find((p) => p.id === id);
	const live = $derived(snap.tasks.filter((t) => project(t.projectID)?.status !== 'archived'));

	// Sama dengan desain: tanpa kata kunci tampilkan tugasmu yang terbuka dan proyek aktif.
	const tasks = $derived(
		(q ? live.filter((t) => t.title.toLowerCase().includes(q)) : live.filter((t) => (t.assigneeID === me || t.reviewerID === me) && t.status !== 'done')).slice(0, 6)
	);
	const projects = $derived(snap.projects.filter((p) => (q ? p.title.toLowerCase().includes(q) : p.status === 'active')).slice(0, 4));
	const groupHits = $derived(groups.filter((g) => !q || g.name.toLowerCase().includes(q)));

	type Hit = () => void;
	const go = (fn: () => unknown): Hit => () => {
		onclose();
		void fn();
	};
	const first = $derived<Hit | null>(
		tasks[0] ? go(() => openTask(tasks[0].id)) : projects[0] ? go(() => goto(`/app/proyek/${projects[0].id}`)) : groupHits[0] ? go(() => goto(`/app/grup/${groupHits[0].id}`)) : null
	);

	let dialog: HTMLDialogElement;
	$effect(() => {
		dialog.showModal();
	});
</script>

<dialog
	bind:this={dialog}
	aria-label="Pencarian"
	oncancel={(e) => (e.preventDefault(), onclose())}
	onclick={(e) => e.target === dialog && onclose()}
>
	<div class="box">
		<label class="bar">
			<Icon name="search" size={22} />
			<!-- svelte-ignore a11y_autofocus -->
			<input
				bind:value={query}
				autofocus
				placeholder="Cari tugas, proyek, atau grup"
				aria-label="Cari"
				onkeydown={(e) => {
					if (e.key === 'Enter' && first) {
						e.preventDefault();
						first();
					}
				}}
			/>
			<kbd>Esc</kbd>
		</label>
		<div class="results">
			{#if tasks.length}
				<span class="label">{q ? 'Tugas' : 'Tugasmu yang terbuka'}</span>
				{#each tasks as t (t.id)}
					<button class="hit" onclick={go(() => openTask(t.id))}>
						<span class="hit-icon round" style:background={STATUS[t.status].bg}><Icon name={STATUS[t.status].icon} size={17} /></span>
						<span class="hit-text"><b>{t.title}</b><small>{project(t.projectID)?.title} · {STATUS[t.status].label}</small></span>
					</button>
				{/each}
			{/if}
			{#if projects.length}
				<span class="label">Proyek</span>
				{#each projects as p (p.id)}
					<button class="hit" onclick={go(() => goto(`/app/proyek/${p.id}`))}>
						<span class="hit-icon" style:background={tint(snap.groups.find((g) => g.id === p.groupID)?.tint)}><Icon name="folder" size={17} /></span>
						<span class="hit-text"><b>{p.title}</b><small>{groupName(p.groupID)}</small></span>
					</button>
				{/each}
			{/if}
			{#if groupHits.length}
				<span class="label">Grup</span>
				{#each groupHits as g (g.id)}
					<button class="hit" onclick={go(() => goto(`/app/grup/${g.id}`))}>
						<span class="hit-icon" style:background={tint(g.tint)}><Icon name={groupIcon(g.icon)} size={17} /></span>
						<span class="hit-text"><b>{g.name}</b><small>{g.course}</small></span>
					</button>
				{/each}
			{/if}
			{#if !tasks.length && !projects.length && !groupHits.length}
				<div class="none">
					<Icon name="search_off" size={30} />
					<b>Tidak ada hasil untuk “{query.trim()}”</b>
					<span>Coba kata kunci lain.</span>
				</div>
			{/if}
		</div>
		<div class="foot"><span>Enter buka hasil pertama</span><span>Esc tutup</span></div>
	</div>
</dialog>

<style>
	dialog {
		width: calc(100% - 32px);
		max-width: 640px;
		max-height: calc(100dvh - 16vh);
		margin: 12vh auto auto;
		padding: 0;
		border: none;
		border-radius: 24px;
		background: var(--surface);
		color: var(--ink);
		box-shadow:
			0 40px 80px -30px rgba(0, 0, 0, 0.45),
			0 0 0 1px light-dark(transparent, var(--hairline));
		overflow: hidden;
		animation: pop 0.18s ease;
	}
	dialog::backdrop {
		background: light-dark(rgba(20, 22, 24, 0.34), rgba(0, 0, 0, 0.65));
		animation: fade 0.15s ease;
	}
	.box {
		max-height: inherit;
		display: flex;
		flex-direction: column;
	}
	.bar {
		flex: none;
		height: 60px;
		padding: 0 16px;
		border-bottom: 1px solid var(--border);
		display: flex;
		align-items: center;
		gap: 10px;
		color: var(--secondary);
	}
	.bar input {
		flex: 1;
		min-width: 0;
		border: none;
		outline: none;
		background: none;
		font: inherit;
		font-size: 17px;
		color: var(--ink);
	}
	kbd,
	.foot span {
		font-family: inherit;
	}
	kbd {
		padding: 3px 7px;
		border-radius: 6px;
		background: var(--muted);
		font-size: 12px;
		font-weight: 600;
		color: var(--text2);
	}
	.results {
		flex: 1;
		min-height: 0;
		overflow: auto;
		padding: 8px 8px 12px;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.label {
		padding: 10px 10px 4px;
		font-size: 12px;
		font-weight: 700;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--text2);
	}
	.hit {
		min-height: 50px;
		padding: 6px 10px;
		border: none;
		border-radius: 14px;
		background: none;
		display: flex;
		align-items: center;
		gap: 12px;
		text-align: left;
		transition: background 0.12s;
	}
	.hit:hover,
	.hit:focus-visible {
		background: var(--muted);
	}
	.hit-icon {
		flex: none;
		width: 30px;
		height: 30px;
		border-radius: 10px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.hit-icon.round {
		border-radius: 50%;
	}
	.hit-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	.hit-text b {
		font-size: 15px;
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.hit-text small {
		font-size: 13px;
		color: var(--secondary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.none {
		padding: 32px 12px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		text-align: center;
		color: var(--secondary);
	}
	.none b {
		font-size: 15px;
		color: var(--ink);
	}
	.none span {
		font-size: 13px;
	}
	.foot {
		flex: none;
		padding: 10px 16px;
		border-top: 1px solid var(--border);
		display: flex;
		gap: 16px;
		font-size: 12px;
		color: var(--secondary);
	}
	@keyframes pop {
		from {
			opacity: 0;
			transform: scale(0.97);
		}
	}
</style>
