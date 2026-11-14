<script lang="ts">
	import { STATUS } from '../format.ts';
	import type { TaskStatus } from '../types.ts';

	let { counts, label }: { counts: Record<TaskStatus, number>; label: string } = $props();

	// Urutan segmen sama dengan desain: selesai dulu, lalu review, dikerjakan, revisi, belum dimulai.
	const ORDER: TaskStatus[] = ['done', 'in_review', 'in_progress', 'needs_revision', 'todo'];
	const R = 52;
	const C = 2 * Math.PI * R;

	const total = $derived(ORDER.reduce((n, s) => n + counts[s], 0));
	const segments = $derived.by(() => {
		const parts = ORDER.filter((s) => counts[s] > 0);
		const gap = parts.length > 1 ? 3 : 0;
		let start = 0;
		return parts.map((s) => {
			const span = (counts[s] / total) * C;
			const seg = { s, len: Math.max(span - gap, 0.5), start };
			start += span;
			return seg;
		});
	});

	// Segmen tumbuh dari nol saat pertama tampil.
	let ready = $state(false);
	$effect(() => {
		const f = requestAnimationFrame(() => (ready = true));
		return () => cancelAnimationFrame(f);
	});
</script>

<svg viewBox="0 0 132 132" width="132" height="132" role="img" aria-label={label}>
	<circle cx="66" cy="66" r={R} fill="none" stroke="var(--muted)" stroke-width="15" />
	{#each segments as seg (seg.s)}
		<circle
			cx="66"
			cy="66"
			r={R}
			fill="none"
			stroke={STATUS[seg.s].ring}
			stroke-width="15"
			stroke-dasharray="{ready ? seg.len : 0} {C}"
			stroke-dashoffset={-seg.start}
			transform="rotate(-90 66 66)"
		/>
	{/each}
</svg>

<style>
	circle {
		transition:
			stroke-dasharray 0.8s var(--ease-out),
			stroke-dashoffset 0.8s var(--ease-out);
	}
</style>
