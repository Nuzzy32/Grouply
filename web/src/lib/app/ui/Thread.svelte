<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { splitActivity, userName } from '../derive.ts';
	import { activityStyle, dayLabel, dayOffset, initials, linkify, time, tint } from '../format.ts';
	import { retry, type Pending } from '../messages.svelte.ts';
	import type { Message, Snapshot } from '../types.ts';
	import Moderation from './Moderation.svelte';

	let {
		snap,
		messages,
		pending = [],
		activity = 'pill',
		onopentask
	}: {
		snap: Snapshot;
		messages: Message[];
		pending?: Pending[];
		activity?: 'pill' | 'card';
		/** Kartu aktivitas chat grup: cari tugas dari judulnya (pesan grup tidak membawa ID tugas). */
		onopentask?: (title: string, groupID: string) => (() => void) | null;
	} = $props();
	let menu = $state('');
	let moderate = $state<{ message: Message; mode: 'report' | 'block' } | null>(null);
	const reported = $derived(new Set(snap.reports.map((r) => r.messageID)));

	const now = new Date();
	const me = $derived(snap.currentUserID);
	const blocked = $derived(new Set(snap.blockedUserIDs));
	let revealed = $state(new Set<string>());
	const user = (id: string) => snap.users.find((u) => u.id === id);

	// Pengelompokan seperti desain: nama di pesan pertama, avatar dan jam di pesan terakhir.
	const rows = $derived(
		messages.map((m, i) => {
			const prev = messages[i - 1];
			const next = messages[i + 1];
			const at = new Date(m.createdAt);
			const sameAs = (o?: Message) =>
				!!o && o.kind === 'text' && o.senderID === m.senderID && dayOffset(new Date(o.createdAt), at) === 0;
			return {
				m,
				at,
				day: !prev || dayOffset(new Date(prev.createdAt), at) !== 0 ? dayLabel(at, now) : '',
				first: !sameAs(prev),
				last: !sameAs(next)
			};
		})
	);
	const radius = (mine: boolean, first: boolean, last: boolean) =>
		mine
			? `18px ${first ? 18 : 6}px ${last ? 18 : 6}px 18px`
			: `${first ? 18 : 6}px 18px 18px ${last ? 18 : 6}px`;
</script>

{#snippet body(text: string)}
	{#each linkify(text) as part, i (i)}
		{#if part.href}<a href={part.href} target="_blank" rel="noopener noreferrer">{part.text}</a>{:else}{part.text}{/if}
	{/each}
{/snippet}

<div class="thread">
	{#each rows as { m, at, day, first, last } (m.id)}
		{#if day}<div class="day">{day}</div>{/if}
		{#if m.kind === 'activity'}
			{@const a = splitActivity(m)}
			{@const style = activityStyle(a.verb.toLowerCase())}
			{#if activity === 'card'}
				{@const open = onopentask?.(a.title, m.groupID)}
				<div class="act-card">
					<span class="act-icon" style:background={style.bg}><Icon name={style.icon} size={17} /></span>
					<span class="act-text"><small>{userName(snap, m.senderID)} {a.verb.toLowerCase()} · {time(at)}</small><b>{a.title}</b></span>
					{#if open}<button class="outline-pill see" onclick={open}>Lihat tugas</button>{/if}
				</div>
			{:else}
				<div class="pill"><Icon name="bolt" size={16} /><span>{userName(snap, m.senderID)} {a.verb.toLowerCase()} · {time(at)}</span></div>
			{/if}
		{:else if m.senderID === me}
			<div class="mine" class:gap={first}>
				<div class="bubble own" style:border-radius={radius(true, first, last)}>{@render body(m.text)}</div>
				{#if last}<span class="meta">{time(at)} · Terkirim</span>{/if}
			</div>
		{:else}
			<div class="other" class:gap={first}>
				{#if last}
					<span class="av" style="--s:28px;font-size:10px;margin-bottom:20px" style:background={tint(user(m.senderID)?.tint)}>{initials(user(m.senderID)?.name)}</span>
				{:else}
					<span class="spacer"></span>
				{/if}
				<div class="col">
					{#if first}<span class="name">{userName(snap, m.senderID)}</span>{/if}
					<div class="bubble-row">
						{#if blocked.has(m.senderID) && !revealed.has(m.id)}
							<div class="hidden">
								Pesan dari pengguna yang kamu blokir
								<button onclick={() => (revealed = new Set([...revealed, m.id]))}>Tampilkan</button>
							</div>
						{:else}
							<div class="bubble" style:border-radius={radius(false, first, last)}>{@render body(m.text)}</div>
						{/if}
						<span class="more-wrap">
							<button class="more" class:open={menu === m.id} aria-label="Opsi pesan" aria-haspopup="menu" aria-expanded={menu === m.id} onclick={() => (menu = menu === m.id ? '' : m.id)}><Icon name="more_horiz" size={18} /></button>
							{#if menu === m.id}
								<span class="menu" role="menu">
									{#if reported.has(m.id)}
										<span class="item muted" role="menuitem" aria-disabled="true"><Icon name="flag" size={18} />Sudah kamu laporkan</span>
									{:else}
										<button class="item" role="menuitem" onclick={() => ((moderate = { message: m, mode: 'report' }), (menu = ''))}><Icon name="flag" size={18} />Laporkan pesan</button>
									{/if}
									<button class="item" role="menuitem" onclick={() => ((moderate = { message: m, mode: 'block' }), (menu = ''))}>
										<Icon name="block" size={18} />{blocked.has(m.senderID) ? 'Buka blokir' : 'Blokir'} {userName(snap, m.senderID)}
									</button>
								</span>
							{/if}
						</span>
					</div>
					{#if last}<span class="meta">{time(at)}</span>{/if}
				</div>
			</div>
		{/if}
	{/each}
	{#each pending as p (p.clientID)}
		<div class="mine gap">
			<div class="bubble own" class:sending={p.state === 'sending'}>{@render body(p.text)}</div>
			{#if p.state === 'failed'}
				<button class="retry" onclick={() => retry(p.clientID)} title={p.error}><Icon name="error" size={16} />Gagal terkirim · Coba lagi</button>
			{:else}
				<span class="meta"><span class="spin mini" aria-hidden="true"></span>Mengirim…</span>
			{/if}
		</div>
	{/each}
</div>

<svelte:window onkeydown={(e) => e.key === 'Escape' && menu && (e.stopPropagation(), (menu = ''))} />

{#if moderate}
	<Moderation message={moderate.message} mode={moderate.mode} onclose={() => (moderate = null)} />
{/if}

<style>
	.thread {
		display: flex;
		flex-direction: column;
		gap: 3px;
	}
	.day {
		align-self: center;
		margin: 14px 0 6px;
		height: 24px;
		padding: 0 12px;
		border-radius: 12px;
		background: var(--chip);
		font-size: 12px;
		font-weight: 600;
		color: var(--text2);
		display: flex;
		align-items: center;
	}
	.pill {
		align-self: center;
		max-width: 92%;
		margin: 8px 0;
		padding: 6px 12px;
		border-radius: 14px;
		background: var(--chip);
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 13px;
		font-weight: 500;
		color: var(--text3);
		text-align: center;
	}
	.act-card {
		align-self: center;
		width: 100%;
		max-width: 520px;
		margin: 8px 0;
		padding: 10px 12px;
		border-radius: 18px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		gap: 10px;
		animation: up 0.2s ease both;
	}
	.act-icon {
		flex: none;
		width: 36px;
		height: 36px;
		border-radius: 12px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.act-text {
		min-width: 0;
		display: flex;
		flex-direction: column;
		font-size: 14px;
	}
	.act-text small {
		font-size: 12px;
		color: var(--text2);
	}
	.gap {
		padding-top: 8px;
	}
	.other {
		display: flex;
		gap: 8px;
		align-items: flex-end;
		max-width: 84%;
	}
	.spacer {
		flex: none;
		width: 28px;
	}
	.col {
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 3px;
	}
	.name {
		padding-left: 4px;
		font-size: 13px;
		font-weight: 600;
		color: var(--text2);
	}
	.bubble {
		padding: 8px 12px;
		background: var(--surface);
		font-size: 15px;
		line-height: 1.4;
		box-shadow: 0 1px 1.5px rgba(0, 0, 0, 0.06);
		overflow-wrap: anywhere;
		white-space: pre-wrap;
	}
	.bubble a {
		color: var(--link);
		text-decoration: underline;
	}
	.mine {
		align-self: flex-end;
		max-width: 80%;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 3px;
		animation: up 0.2s ease both;
	}
	.own {
		background: var(--lavender);
		box-shadow: none;
		border-radius: 18px;
	}
	.sending {
		opacity: 0.6;
	}
	.meta {
		padding: 0 4px;
		font-size: 12px;
		color: var(--secondary);
		display: flex;
		align-items: center;
		gap: 4px;
	}
	.mini {
		width: 11px;
		height: 11px;
		border-width: 1.5px;
	}
	.retry {
		height: 30px;
		border: none;
		background: none;
		padding: 0 4px;
		display: flex;
		align-items: center;
		gap: 4px;
		font-size: 13px;
		font-weight: 600;
		color: var(--danger);
	}
	.bubble-row {
		display: flex;
		align-items: center;
		gap: 4px;
	}
	.more-wrap {
		position: relative;
		flex: none;
	}
	.more {
		width: 30px;
		height: 30px;
		border: none;
		border-radius: 50%;
		background: transparent;
		color: var(--secondary);
		display: flex;
		align-items: center;
		justify-content: center;
		opacity: 0;
		transition:
			opacity 0.15s,
			background 0.15s;
	}
	.bubble-row:hover .more,
	.more:focus-visible,
	.more.open {
		opacity: 1;
	}
	.more:hover,
	.more.open {
		background: var(--chip);
	}
	@media (hover: none) {
		.more {
			opacity: 1;
		}
	}
	.menu {
		position: absolute;
		left: 0;
		top: calc(100% + 4px);
		z-index: 5;
		min-width: 220px;
		padding: 6px;
		border-radius: 16px;
		background: var(--surface);
		box-shadow:
			0 20px 40px -16px rgba(0, 0, 0, 0.3),
			0 0 0 1px var(--border);
		display: flex;
		flex-direction: column;
		animation: up 0.15s ease both;
	}
	.item {
		height: 40px;
		padding: 0 12px;
		border: none;
		border-radius: 10px;
		background: none;
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 600;
		white-space: nowrap;
		text-align: left;
	}
	button.item:hover {
		background: var(--chip);
	}
	.item.muted {
		color: var(--secondary);
	}
	.see {
		margin-left: auto;
	}
	.hidden {
		padding: 8px 12px;
		border-radius: 16px;
		border: 1.5px dashed var(--disabled);
		font-size: 14px;
		color: var(--secondary);
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.hidden button {
		border: none;
		background: none;
		padding: 0;
		font-size: 14px;
		font-weight: 600;
		color: var(--link);
	}
</style>
