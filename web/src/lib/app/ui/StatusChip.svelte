<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { STATUS } from '../format.ts';
	import type { TaskStatus } from '../types.ts';

	let { status }: { status: TaskStatus } = $props();
</script>

<span class="chip status" style:background={STATUS[status].bg}><Icon name={STATUS[status].icon} size={15} />{STATUS[status].label}</span>

<style>
	.status {
		height: 28px;
		padding: 0 10px 0 7px;
		gap: 4px;
		font-size: 12px;
	}
</style>
