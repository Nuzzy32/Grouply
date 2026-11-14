<script lang="ts">
	// Nama ikon harus ada di daftar icon_names di app.html.
	let { name, size = 20, fill = false }: { name: string; size?: number; fill?: boolean } = $props();
</script>

<span class="ms" class:fill aria-hidden="true" style:font-size="{size}px">{name}</span>

<style>
	.ms {
		flex: none;
		display: inline-block;
		width: 1em;
		overflow: hidden;
		font-family: 'Material Symbols Rounded';
		font-weight: normal;
		font-style: normal;
		line-height: 1;
		letter-spacing: normal;
		text-transform: none;
		white-space: nowrap;
		direction: ltr;
		font-feature-settings: 'liga';
		user-select: none;
	}
	.fill {
		font-variation-settings: 'FILL' 1;
	}
</style>
