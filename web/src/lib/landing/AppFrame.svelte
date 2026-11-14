<script lang="ts">
	import type { Snippet } from 'svelte';
	import Icon from '#lib/Icon.svelte';

	type Nav = 'home' | 'group' | 'chat' | 'tasks';
	let {
		url,
		active,
		height = 500,
		children
	}: { url: string; active: Nav; height?: number; children: Snippet } = $props();

	const nav: [Nav, string][] = [
		['home', 'home'],
		['group', 'group'],
		['chat', 'chat_bubble'],
		['tasks', 'task_alt']
	];
</script>

<!-- Tiruan jendela browser berisi aplikasi web Grouply (dekorasi, bukan aplikasi sungguhan). -->
<div class="frame">
	<div class="bar">
		<span class="dot" style="background:#ff5f57"></span><span class="dot" style="background:#febc2e"></span><span class="dot" style="background:#28c840"></span>
		<span class="url"><Icon name="lock" size={14} />{url}</span>
	</div>
	<div class="body" style:height="{height}px">
		<div class="rail">
			<img src="/brand.png" alt="" width="30" height="30" />
			{#each nav as [key, icon] (key)}
				<span class="nav" class:on={active === key}><Icon name={icon} size={20} fill={active === key} /></span>
			{/each}
		</div>
		<div class="content">{@render children()}</div>
	</div>
</div>

<style>
	.frame {
		background: var(--surface);
		border-radius: 24px;
		box-shadow:
			0 50px 100px -40px rgba(30, 50, 45, 0.4),
			0 0 0 1px var(--border);
		overflow: hidden;
		min-width: 0;
	}
	.bar {
		height: 42px;
		display: flex;
		align-items: center;
		gap: 7px;
		padding: 0 16px;
		border-bottom: 1px solid var(--line);
		background: var(--chrome);
	}
	.dot {
		width: 11px;
		height: 11px;
		border-radius: 50%;
		/* Tombol jendela macOS: merah, kuning, hijau; sama di kedua mode. */
		box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.12);
	}
	.url {
		margin: 0 auto;
		height: 26px;
		padding: 0 14px;
		border-radius: 13px;
		background: var(--muted);
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 12px;
		color: var(--text2);
		white-space: nowrap;
		overflow: hidden;
	}
	.body {
		display: flex;
		background: var(--background);
		overflow: hidden;
		text-align: left;
	}
	.rail {
		flex: none;
		width: 60px;
		border-right: 1px solid var(--line);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		padding: 14px 0;
	}
	.rail img {
		border-radius: 10px;
		margin-bottom: 8px;
	}
	.nav {
		width: 38px;
		height: 38px;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
		transition:
			background 0.3s,
			color 0.3s;
	}
	.nav.on {
		background: var(--ink);
		color: var(--on-ink);
	}
	.content {
		flex: 1;
		min-width: 0;
		position: relative;
	}
</style>
