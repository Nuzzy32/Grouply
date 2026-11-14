<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { flash } from '../store.svelte.ts';

	export type MenuItem = { label: string; sub?: string; icon: string; run: () => void; locked?: string; danger?: boolean };
	let { items, label, icon = 'more_horiz' }: { items: MenuItem[]; label: string; icon?: string } = $props();

	let open = $state(false);
	let root = $state<HTMLElement>();
	// Item bergembok tetap terlihat dan menjelaskan alasannya saat diklik (aturan desain Soft Future).
	function pick(item: MenuItem) {
		open = false;
		if (item.locked) flash(item.locked, 'err');
		else item.run();
	}
</script>

<svelte:window
	onclick={(e) => open && root && !root.contains(e.target as Node) && (open = false)}
	onkeydown={(e) => e.key === 'Escape' && open && (open = false)}
/>

<span class="wrap" bind:this={root}>
	<button class="trigger" class:on={open} aria-label={label} title={label} aria-haspopup="menu" aria-expanded={open} onclick={() => (open = !open)}>
		<Icon name={icon} size={20} />
	</button>
	{#if open}
		<span class="menu" role="menu">
			{#each items as item (item.label)}
				<button role="menuitem" class="item" class:danger={item.danger && !item.locked} class:locked={!!item.locked} onclick={() => pick(item)}>
					<Icon name={item.locked ? 'lock' : item.icon} size={19} />
					<span class="text"><b>{item.label}</b>{#if item.sub}<small>{item.sub}</small>{/if}</span>
				</button>
			{/each}
		</span>
	{/if}
</span>

<style>
	.wrap {
		position: relative;
		flex: none;
	}
	.trigger {
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 50%;
		background: var(--chip);
		display: flex;
		align-items: center;
		justify-content: center;
		transition: background 0.15s;
	}
	.trigger:hover,
	.trigger.on {
		background: var(--border);
	}
	.menu {
		position: absolute;
		right: 0;
		top: calc(100% + 6px);
		z-index: 30;
		min-width: 260px;
		padding: 6px;
		border-radius: 18px;
		background: var(--surface);
		box-shadow:
			0 20px 40px -16px rgba(0, 0, 0, 0.3),
			0 0 0 1px var(--border);
		display: flex;
		flex-direction: column;
		animation: up 0.15s ease both;
	}
	.item {
		min-height: 46px;
		padding: 8px 12px;
		border: none;
		border-radius: 12px;
		background: none;
		display: flex;
		align-items: center;
		gap: 12px;
		text-align: left;
	}
	.item:hover {
		background: var(--chip);
	}
	.text {
		display: flex;
		flex-direction: column;
	}
	.text b {
		font-size: 14px;
		font-weight: 600;
	}
	.text small {
		font-size: 12px;
		color: var(--secondary);
	}
	.danger {
		color: var(--danger);
	}
	.locked {
		opacity: 0.6;
	}
</style>
