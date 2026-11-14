<script lang="ts">
	import Icon from '#lib/Icon.svelte';

	// Default ikut sistem; setelah diklik, pilihan disimpan dan dibaca skrip di app.html.
	let dark = $state(false);

	$effect(() => {
		const root = document.documentElement;
		const media = matchMedia('(prefers-color-scheme: dark)');
		const sync = () => (dark = root.dataset.theme ? root.dataset.theme === 'dark' : media.matches);
		sync();
		media.addEventListener('change', sync);
		return () => media.removeEventListener('change', sync);
	});

	function toggle() {
		dark = !dark;
		const theme = dark ? 'dark' : 'light';
		document.documentElement.dataset.theme = theme;
		document.querySelectorAll<HTMLMetaElement>('meta[name=theme-color]').forEach((m) => {
			m.content = dark ? '#121314' : '#F8F9F7';
		});
		try {
			localStorage.setItem('grouply-theme', theme);
		} catch {
			// Penyimpanan diblokir: tema tetap berlaku sampai halaman ditutup.
		}
	}
</script>

<button class="toggle" onclick={toggle} aria-label={dark ? 'Ganti ke mode terang' : 'Ganti ke mode gelap'}>
	<Icon name={dark ? 'light_mode' : 'dark_mode'} size={20} />
</button>

<style>
	.toggle {
		flex: none;
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 50%;
		background: transparent;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: background 0.2s;
	}
	.toggle:hover {
		background: var(--chip);
	}
</style>
