<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import Icon from '#lib/Icon.svelte';
	import ThemeToggle from '#lib/ThemeToggle.svelte';
	import { groupIcon, initials, tint } from '#lib/app/format.ts';
	import { myGroups, unreadCount } from '#lib/app/derive.ts';
	import { confirmState, flash, header, store, toast } from '#lib/app/store.svelte.ts';
	import Modal from '#lib/app/ui/Modal.svelte';
	import Search from '#lib/app/ui/Search.svelte';
	import TaskDrawer from '#lib/app/ui/TaskDrawer.svelte';
	import '#lib/app/app.css';

	let { children } = $props();

	store.init();
	$effect(() => {
		if (store.ready && !store.userID) void goto('/masuk', { replace: true });
	});

	let width = $state(1440);
	const compact = $derived(width < 1100);
	let menu = $state(false);
	let searching = $state(false);
	const mac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform);
	let signOutError = $state('');

	const me = $derived(store.snap?.users.find((u) => u.id === store.userID));
	const groups = $derived(store.snap ? myGroups(store.snap) : []);
	const unread = $derived(store.snap ? groups.reduce((n, g) => n + unreadCount(store.snap!, g.id), 0) : 0);

	const NAV = [
		{ href: '/app', label: 'Beranda', icon: 'home' },
		{ href: '/app/grup', label: 'Grup', icon: 'group' },
		{ href: '/app/chat', label: 'Chat', icon: 'chat_bubble' },
		{ href: '/app/tugas', label: 'Tugas Saya', icon: 'task_alt' }
	];
	const active = (href: string) =>
		href === '/app' ? page.url.pathname === '/app' : page.url.pathname.startsWith(href);

	let toastVisible = $state(false);
	$effect(() => {
		if (!toast.id) return;
		toastVisible = true;
		const t = setTimeout(() => (toastVisible = false), 2800);
		return () => clearTimeout(t);
	});

	async function signOut() {
		menu = false;
		try {
			await store.signOut();
		} catch (e) {
			signOutError = (e as Error).message;
		}
	}
</script>

<svelte:window
	bind:innerWidth={width}
	onkeydown={(e) => {
		if (e.key === 'Escape') menu = false;
		// ⌘K / Ctrl+K membuka pencarian dari mana pun.
		if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k' && store.snap) {
			e.preventDefault();
			searching = !searching;
		}
	}}
/>

{#if !store.ready || (store.userID && !store.snap && !store.error)}
	<div class="center"><span class="spin" aria-label="Memuat"></span></div>
{:else if store.error && !store.snap}
	<div class="center">
		<div class="notice error" role="alert">{store.error}</div>
		<div class="row">
			<button class="btn btn-ghost" onclick={() => location.reload()}>Coba lagi</button>
			<button class="btn btn-ghost" onclick={signOut}>Keluar</button>
		</div>
	</div>
{:else if store.snap}
	<div class="shell">
		<aside class:compact>
			<a href="/app" class="brand" aria-label="Beranda GROUPLY"><img src="/brand.png" alt="" width="36" height="36" />{#if !compact}<span>GROUPLY</span>{/if}</a>

			<button class="search" onclick={() => (searching = true)} aria-label="Cari tugas, proyek, atau grup" title={compact ? 'Cari (⌘K)' : undefined}>
				<Icon name="search" size={20} />
				{#if !compact}<span>Cari tugas, proyek…</span><kbd>{mac ? '⌘K' : 'Ctrl K'}</kbd>{/if}
			</button>

			<nav aria-label="Navigasi aplikasi">
				{#each NAV as item (item.href)}
					{@const on = active(item.href)}
					<a href={item.href} class="nav" class:on aria-current={on ? 'page' : undefined} title={compact ? item.label : undefined}>
						<Icon name={item.icon} size={22} fill={on} />
						{#if !compact}<span>{item.label}</span>{/if}
						{#if item.icon === 'chat_bubble' && unread > 0}
							{#if compact}<i class="dot" aria-label="{unread} pesan belum dibaca"></i>{:else}<b class="badge" aria-label="{unread} pesan belum dibaca">{unread > 99 ? '99+' : unread}</b>{/if}
						{/if}
					</a>
				{/each}
			</nav>

			{#if !compact && groups.length}
				<div class="mine">
					<span class="label">Grup saya</span>
					{#each groups as g (g.id)}
						<a href="/app/grup/{g.id}" class="group" class:on={page.url.pathname === `/app/grup/${g.id}`}>
							<span class="gicon" style:background={tint(g.tint)}><Icon name={groupIcon(g.icon)} size={16} /></span>
							<span class="gname">{g.name}</span>
							{#if unreadCount(store.snap, g.id)}<i class="dot" aria-label="Ada pesan belum dibaca"></i>{/if}
						</a>
					{/each}
				</div>
			{/if}

			<div class="account">
				{#if menu}
					<div class="menu" role="menu">
						<a role="menuitem" class="item" href="/app/profil" onclick={() => (menu = false)}><Icon name="person" size={18} />Profil dan akun</a>
						<button role="menuitem" class="item" onclick={signOut}><Icon name="logout" size={18} />Keluar</button>
					</div>
				{/if}
				<button class="who" onclick={() => (menu = !menu)} aria-expanded={menu} aria-haspopup="menu">
					<span class="av" style="--s:40px;font-size:13px" style:background={tint(me?.tint)}>{initials(me?.name)}</span>
					{#if !compact}<span class="name">{me?.name ?? 'Akun'}</span><Icon name="expand_less" size={18} />{/if}
				</button>
			</div>
		</aside>

		<div class="main">
			<header>
				<ol class="crumbs">
					{#each header.crumbs as c, i (i)}
						<li class:last={i === header.crumbs.length - 1}>
							{#if i > 0}<Icon name="chevron_right" size={16} />{/if}
							{#if c.href && i < header.crumbs.length - 1}<a href={c.href}>{c.label}</a>{:else}<span>{c.label}</span>{/if}
						</li>
					{/each}
				</ol>
				{#if header.action}
					{@const a = header.action}
					<button class="action" class:locked={!!a.locked} onclick={() => (a.locked ? flash(a.locked, 'err') : a.run())}>
						<Icon name={a.locked ? 'lock' : a.icon} size={19} />{a.label}
					</button>
				{/if}
				<ThemeToggle />
			</header>
			{#if signOutError}<div class="notice error banner" role="alert">{signOutError}</div>{/if}
			<div class="content">{@render children()}</div>
		</div>
	</div>
	{@const taskID = page.url.searchParams.get('tugas')}
	{#if taskID}
		{#key taskID}<TaskDrawer {taskID} />{/key}
	{/if}
	{#if searching}<Search onclose={() => (searching = false)} />{/if}
	{#if confirmState.ask}
		{@const a = confirmState.ask}
		<Modal title={a.title} width={460} onclose={() => confirmState.resolve(false)}>
			<p class="confirm-text">{a.text}</p>
			{#snippet footer()}
				{#if a.info}
					<button class="btn btn-primary" onclick={() => confirmState.resolve(false)}>Mengerti</button>
				{:else}
					<button class="btn btn-ghost" onclick={() => confirmState.resolve(false)}>Batal</button>
					<button class="btn {a.destructive ? 'btn-danger' : 'btn-primary'}" onclick={() => confirmState.resolve(true)}>{a.ok ?? 'Lanjutkan'}</button>
				{/if}
			{/snippet}
		</Modal>
	{/if}
	{#if toastVisible}
		{#key toast.id}
			<div class="toast {toast.kind}" role="status">
				<Icon name={toast.kind === 'err' ? 'error' : toast.kind === 'info' ? 'info' : 'check_circle'} size={20} fill />
				{toast.text}
			</div>
		{/key}
	{/if}
{/if}

<style>
	.center {
		min-height: 100dvh;
		display: grid;
		place-content: center;
		justify-items: center;
		gap: 16px;
		padding: 16px;
	}
	.row {
		display: flex;
		gap: 8px;
	}
	.shell {
		height: 100dvh;
		display: flex;
		overflow: hidden;
	}
	aside {
		flex: none;
		width: 264px;
		padding: 18px 12px;
		display: flex;
		flex-direction: column;
		gap: 16px;
		border-right: 1px solid var(--border);
		transition: width 0.2s;
		overflow-y: auto;
	}
	aside.compact {
		width: 76px;
		align-items: center;
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 0 6px;
		font-size: 14px;
		font-weight: 800;
		letter-spacing: 0.12em;
	}
	.brand img {
		border-radius: 11px;
	}
	.search {
		height: 42px;
		padding: 0 8px 0 12px;
		border: none;
		border-radius: 14px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 14px;
		color: var(--secondary);
		text-align: left;
	}
	.search span {
		flex: 1;
	}
	.compact .search {
		width: 46px;
		padding: 0;
		justify-content: center;
	}
	kbd {
		padding: 2px 6px;
		border-radius: 6px;
		background: var(--muted);
		font-family: inherit;
		font-size: 11px;
		font-weight: 600;
		color: var(--text2);
	}
	nav {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.nav {
		position: relative;
		height: 46px;
		padding: 0 14px;
		border-radius: 23px;
		display: flex;
		align-items: center;
		gap: 12px;
		font-size: 15px;
		font-weight: 600;
		transition: background 0.15s;
	}
	.compact .nav {
		width: 46px;
		padding: 0;
		justify-content: center;
	}
	.nav:hover {
		background: var(--chip);
	}
	.nav.on {
		background: var(--ink);
		color: var(--on-ink);
	}
	.badge {
		margin-left: auto;
		min-width: 24px;
		height: 22px;
		padding: 0 7px;
		border-radius: 11px;
		background: var(--mint);
		color: var(--ink);
		font-size: 12px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.dot {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--ring-done);
	}
	.compact .nav .dot {
		position: absolute;
		top: 8px;
		right: 8px;
		width: 10px;
		height: 10px;
		box-shadow: 0 0 0 2px var(--background);
	}
	.mine {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-height: 0;
	}
	.label {
		padding: 8px 12px 6px;
		font-size: 12px;
		font-weight: 700;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--secondary);
	}
	.group {
		height: 42px;
		padding: 0 10px;
		border-radius: 14px;
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 500;
		transition: background 0.15s;
	}
	.group:hover,
	.group.on {
		background: var(--chip);
	}
	.gicon {
		flex: none;
		width: 28px;
		height: 28px;
		border-radius: 10px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.gname {
		flex: 1;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.account {
		position: relative;
		margin-top: auto;
	}
	.who {
		width: 100%;
		border: none;
		background: none;
		padding: 6px;
		border-radius: 20px;
		display: flex;
		align-items: center;
		gap: 10px;
		text-align: left;
		transition: background 0.15s;
	}
	.who:hover {
		background: var(--chip);
	}
	.name {
		flex: 1;
		min-width: 0;
		font-size: 14px;
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.menu {
		position: absolute;
		left: 0;
		bottom: calc(100% + 8px);
		min-width: 200px;
		padding: 6px;
		border-radius: 18px;
		background: var(--surface);
		box-shadow:
			0 20px 40px -16px rgba(0, 0, 0, 0.3),
			0 0 0 1px var(--border);
		animation: up 0.18s ease both;
		z-index: 10;
	}
	.item {
		width: 100%;
		height: 42px;
		border: none;
		background: none;
		border-radius: 12px;
		padding: 0 12px;
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 600;
	}
	.item:hover {
		background: var(--chip);
	}
	.main {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	header {
		flex: none;
		height: 64px;
		padding: 0 24px 0 20px;
		display: flex;
		align-items: center;
		gap: 12px;
		border-bottom: 1px solid var(--border);
	}
	.crumbs {
		flex: 1;
		min-width: 0;
		margin: 0;
		padding: 0;
		list-style: none;
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 15px;
		font-weight: 500;
		color: var(--secondary);
	}
	.crumbs li {
		display: flex;
		align-items: center;
		gap: 6px;
		min-width: 0;
	}
	.crumbs span,
	.crumbs a {
		max-width: 340px;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.crumbs a:hover {
		color: var(--ink);
	}
	.crumbs .last {
		font-size: 16px;
		font-weight: 700;
		color: var(--ink);
	}
	.confirm-text {
		margin: 0;
		font-size: 15px;
		line-height: 1.55;
		color: var(--text3);
	}
	.action {
		flex: none;
		height: 42px;
		padding: 0 18px 0 14px;
		border: none;
		border-radius: 21px;
		background: var(--ink);
		color: var(--on-ink);
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 14px;
		font-weight: 600;
		transition: opacity 0.15s;
	}
	.action:hover {
		opacity: 0.88;
	}
	.action.locked {
		opacity: 0.55;
	}
	.toast {
		position: fixed;
		left: 50%;
		bottom: 28px;
		z-index: 100;
		max-width: calc(100% - 32px);
		transform: translateX(-50%);
		padding: 12px 18px 12px 14px;
		border-radius: 18px;
		background: #202124;
		color: #fff;
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 600;
		box-shadow: 0 20px 40px -16px rgba(0, 0, 0, 0.45);
		animation: toast-in 0.2s ease both;
	}
	.toast :global(.ms) {
		color: #c9f2d6;
	}
	.toast.err :global(.ms) {
		color: #f6ced1;
	}
	.toast.info :global(.ms) {
		color: #d8eaf4;
	}
	@keyframes toast-in {
		from {
			opacity: 0;
			transform: translate(-50%, 6px);
		}
	}
	.banner {
		margin: 12px 24px 0;
	}
	.content {
		flex: 1;
		overflow: auto;
		animation: fade 0.25s ease;
	}
</style>
