<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { dateInput, dueFromInput } from '../format.ts';

	let { value = $bindable(), label = 'Pilih tanggal deadline' }: { value: string; label?: string } = $props();

	const today = new Date();
	const plus = (days: number) => dateInput(new Date(today.getFullYear(), today.getMonth(), today.getDate() + days));
	const QUICK = [
		['Besok', plus(1)],
		['3 hari lagi', plus(3)],
		['Minggu depan', plus(7)]
	];
	const due = $derived(dueFromInput(value));
	const fmt = new Intl.DateTimeFormat('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
</script>

<div class="due">
	<div class="row">
		{#each QUICK as [text, day] (text)}
			<button type="button" class="quick" class:on={value === day} aria-pressed={value === day} onclick={() => (value = day)}>{text}</button>
		{/each}
		<label class="date">
			<Icon name="calendar_month" size={19} />
			<input type="date" bind:value min={plus(0)} aria-label={label} />
		</label>
	</div>
	<small>{due ? `${fmt.format(due)}, 23:59` : 'Belum dipilih'}</small>
</div>

<style>
	.due {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.row {
		display: flex;
		gap: 8px;
		flex-wrap: wrap;
		align-items: center;
	}
	.quick {
		height: 40px;
		padding: 0 14px;
		border-radius: 14px;
		border: 1.5px solid var(--ink);
		background: transparent;
		font-size: 14px;
		font-weight: 600;
		transition:
			background 0.15s,
			color 0.15s;
	}
	.quick.on {
		background: var(--ink);
		color: var(--on-ink);
	}
	.date {
		flex: 1 1 180px;
		height: 42px;
		padding: 0 12px;
		border-radius: 14px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.date input {
		flex: 1;
		min-width: 0;
		border: none;
		outline: none;
		background: none;
		font: inherit;
		font-size: 15px;
		color: var(--ink);
	}
	small {
		font-size: 13px;
		color: var(--secondary);
	}
</style>
