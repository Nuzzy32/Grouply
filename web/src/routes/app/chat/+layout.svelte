<script lang="ts">
	import { page } from '$app/state';
	import Icon from '#lib/Icon.svelte';
	import { myGroups, splitActivity, unreadCount, userName } from '#lib/app/derive.ts';
	import { activityStamp, groupIcon, tint } from '#lib/app/format.ts';
	import { header, store } from '#lib/app/store.svelte.ts';
	import type { Message } from '#lib/app/types.ts';

	let { children } = $props();

	const now = new Date();
	const snap = $derived(store.snap!);
	let query = $state('');

	// Pratinjau sama dengan Flutter: "Nama: teks", aktivitas, atau pesan dari pengguna yang diblokir.
	function preview(m: Message | undefined) {
		if (!m) return 'Belum ada pesan. Sapa kelompokmu!';
		const name = userName(snap, m.senderID);
		if (m.kind === 'activity') {
			const a = splitActivity(m);
			return `${name} ${a.verb.toLowerCase()} ${a.title}`.trim();
		}
		if (snap.blockedUserIDs.includes(m.senderID) && m.senderID !== snap.currentUserID) return 'Pesan dari pengguna yang kamu blokir';
		return `${name}: ${m.text}`;
	}

	const rows = $derived(
		myGroups(snap)
			.map((g) => {
				const last = snap.messages.filter((m) => m.groupID === g.id && !m.taskID).at(-1);
				return { g, last, unread: unreadCount(snap, g.id) };
			})
			.sort((a, b) => (b.last?.createdAt ?? '').localeCompare(a.last?.createdAt ?? '') || a.g.name.localeCompare(b.g.name, 'id'))
	);
	const shown = $derived(rows.filter((r) => r.g.name.toLowerCase().includes(query.trim().toLowerCase())));
	const activeID = $derived(page.params.id ?? '');

	$effect(() => {
		if (!activeID) header.crumbs = [{ label: 'Chat' }];
	});
</script>

<svelte:head><title>Chat · GROUPLY</title></svelte:head>

<div class="chat">
	<section class="list" class:hide-narrow={!!activeID} aria-label="Daftar percakapan">
		<div class="list-head">
			<h1>Chat grup</h1>
			<label class="search">
				<Icon name="search" size={20} />
				<input bind:value={query} placeholder="Cari nama grup" aria-label="Cari nama grup" />
				{#if query}<button aria-label="Hapus pencarian" onclick={() => (query = '')}><Icon name="close" size={17} /></button>{/if}
			</label>
		</div>
		<div class="rows">
			{#each shown as { g, last, unread } (g.id)}
				<a class="row" class:on={g.id === activeID} href="/app/chat/{g.id}" aria-current={g.id === activeID ? 'page' : undefined}>
					<span class="icon" style:background={tint(g.tint)}><Icon name={groupIcon(g.icon)} size={24} /></span>
					<span class="text">
						<span class="line"><b class:unread={unread > 0}>{g.name}</b>{#if last}<small>{activityStamp(new Date(last.createdAt), now)}</small>{/if}</span>
						<span class="line">
							<span class="preview" class:unread={unread > 0}>{preview(last)}</span>
							{#if unread}<span class="badge" aria-label="{unread} pesan belum dibaca">{unread > 99 ? '99+' : unread}</span>{/if}
						</span>
					</span>
				</a>
			{:else}
				<div class="none">
					{#if rows.length}
						<Icon name="search_off" size={28} />
						<b>Tidak ada grup “{query.trim()}”</b>
						<span>Coba kata kunci lain.</span>
					{:else}
						<span>Belum ada chat. Chat grup dibuat otomatis saat kamu bergabung ke grup.</span>
					{/if}
				</div>
			{/each}
		</div>
	</section>
	{@render children()}
</div>

<style>
	.chat {
		height: 100%;
		display: flex;
		overflow: hidden;
	}
	.list {
		flex: none;
		width: 340px;
		display: flex;
		flex-direction: column;
		border-right: 1px solid var(--border);
	}
	@media (max-width: 899px) {
		.list {
			width: 100%;
			border-right: none;
		}
		.list.hide-narrow {
			display: none;
		}
	}
	.list-head {
		padding: 18px 16px 12px;
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	h1 {
		margin: 0;
		font-size: 22px;
		font-weight: 700;
		letter-spacing: -0.02em;
	}
	.search {
		height: 44px;
		padding: 0 4px 0 12px;
		border-radius: 14px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		gap: 8px;
		color: var(--secondary);
	}
	.search input {
		flex: 1;
		min-width: 0;
		border: none;
		outline: none;
		background: none;
		font: inherit;
		font-size: 15px;
		color: var(--ink);
	}
	.search button {
		width: 36px;
		height: 36px;
		border: none;
		border-radius: 50%;
		background: var(--muted);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.rows {
		flex: 1;
		min-height: 0;
		overflow: auto;
		padding: 0 10px 16px;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.row {
		padding: 12px;
		border-radius: 18px;
		display: flex;
		align-items: center;
		gap: 12px;
		transition: background 0.15s;
	}
	.row:hover,
	.row.on {
		background: var(--surface);
	}
	.row.on {
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
	}
	.icon {
		flex: none;
		width: 48px;
		height: 48px;
		border-radius: 18px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 3px;
	}
	.line {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.line b {
		flex: 1;
		min-width: 0;
		font-size: 15px;
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.line b.unread {
		font-weight: 800;
	}
	.line small {
		flex: none;
		font-size: 12px;
		color: var(--secondary);
	}
	.preview {
		flex: 1;
		min-width: 0;
		font-size: 13px;
		line-height: 1.35;
		color: var(--secondary);
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
		overflow-wrap: anywhere;
	}
	.preview.unread {
		font-weight: 600;
		color: var(--ink);
	}
	.badge {
		flex: none;
		min-width: 22px;
		height: 22px;
		padding: 0 7px;
		border-radius: 11px;
		background: var(--ink);
		color: var(--on-ink);
		font-size: 12px;
		font-weight: 700;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.none {
		padding: 28px 12px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		text-align: center;
		font-size: 14px;
		line-height: 1.5;
		color: var(--secondary);
	}
	.none b {
		font-size: 15px;
		color: var(--ink);
	}
</style>
