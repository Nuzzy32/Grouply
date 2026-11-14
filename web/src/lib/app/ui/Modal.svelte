<script lang="ts">
	import type { Snippet } from 'svelte';
	import Icon from '#lib/Icon.svelte';

	let {
		title,
		sub = '',
		width = 560,
		busy = false,
		onclose,
		children,
		footer
	}: {
		title: string;
		sub?: string;
		width?: number;
		busy?: boolean;
		onclose: () => void;
		children: Snippet;
		footer?: Snippet;
	} = $props();

	let dialog: HTMLDialogElement;
	// <dialog> bawaan: fokus terkunci di dalam, Esc menutup, latar tidak bisa diklik.
	$effect(() => {
		dialog.showModal();
	});
	const close = () => !busy && onclose();
</script>

<dialog
	bind:this={dialog}
	aria-label={title}
	style:max-width="{width}px"
	oncancel={(e) => {
		e.preventDefault();
		close();
	}}
	onclick={(e) => e.target === dialog && close()}
>
	<div class="body">
		<div class="head">
			<div class="titles">
				<h2>{title}</h2>
				{#if sub}<p>{sub}</p>{/if}
			</div>
			<button class="x" type="button" aria-label="Tutup" onclick={close}><Icon name="close" size={21} /></button>
		</div>
		{@render children()}
		{#if footer}<div class="foot">{@render footer()}</div>{/if}
	</div>
</dialog>

<style>
	dialog {
		width: calc(100% - 32px);
		max-height: calc(100dvh - 80px);
		padding: 0;
		border: none;
		border-radius: 28px;
		background: var(--background);
		color: var(--ink);
		box-shadow:
			0 40px 80px -30px rgba(0, 0, 0, 0.45),
			0 0 0 1px light-dark(transparent, var(--hairline));
		animation: pop 0.2s ease;
	}
	dialog::backdrop {
		background: light-dark(rgba(20, 22, 24, 0.34), rgba(0, 0, 0, 0.65));
		animation: fade 0.15s ease;
	}
	.body {
		padding: 24px;
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 12px;
	}
	.titles {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}
	h2 {
		margin: 0;
		font-size: 22px;
		font-weight: 700;
		letter-spacing: -0.02em;
	}
	p {
		margin: 0;
		font-size: 14px;
		color: var(--text3);
	}
	.x {
		flex: none;
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 50%;
		background: var(--chip);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.foot {
		display: flex;
		gap: 10px;
		justify-content: flex-end;
	}
	@keyframes pop {
		from {
			opacity: 0;
			transform: scale(0.97);
		}
	}
</style>
