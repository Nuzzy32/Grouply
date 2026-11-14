<script lang="ts">
	import Icon from '#lib/Icon.svelte';

	let { placeholder, onsend }: { placeholder: string; onsend: (text: string) => void } = $props();
	let draft = $state('');
	let box: HTMLTextAreaElement;

	function send() {
		const text = draft.trim();
		if (!text) return;
		onsend(text);
		draft = '';
		queueMicrotask(resize);
		box.focus();
	}
	function resize() {
		box.style.height = 'auto';
		box.style.height = `${Math.min(box.scrollHeight, 120)}px`;
	}
</script>

<div class="composer">
	<textarea
		bind:this={box}
		bind:value={draft}
		oninput={resize}
		onkeydown={(e) => {
			// Enter mengirim, Shift+Enter baris baru (IME tetap boleh menyusun huruf).
			if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
				e.preventDefault();
				send();
			}
		}}
		rows="1"
		maxlength="2000"
		{placeholder}
		aria-label={placeholder}
	></textarea>
	<button class="send" class:ready={draft.trim() !== ''} onclick={send} aria-label="Kirim"><Icon name="arrow_upward" size={21} /></button>
</div>

<style>
	.composer {
		display: flex;
		align-items: flex-end;
		gap: 10px;
		padding: 6px 6px 6px 16px;
		border-radius: 24px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
	}
	textarea {
		flex: 1;
		min-width: 0;
		min-height: 36px;
		max-height: 120px;
		padding: 8px 0;
		border: none;
		outline: none;
		background: none;
		font: inherit;
		font-size: 15px;
		line-height: 1.4;
		color: var(--ink);
		resize: none;
	}
	textarea::placeholder {
		color: var(--placeholder);
	}
	.send {
		flex: none;
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 50%;
		background: var(--disabled);
		color: #fff;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: background 0.15s;
	}
	.send.ready {
		background: var(--ink);
		color: var(--on-ink);
	}
</style>
