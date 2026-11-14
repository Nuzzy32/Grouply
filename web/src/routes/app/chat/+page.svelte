<script lang="ts">
	import Icon from '#lib/Icon.svelte';
</script>

<section class="empty" aria-label="Percakapan">
	<Icon name="forum" size={36} />
	Pilih percakapan di sebelah kiri.
</section>

<style>
	.empty {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 8px;
		font-size: 15px;
		color: var(--secondary);
	}
	@media (max-width: 899px) {
		.empty {
			display: none;
		}
	}
</style>
