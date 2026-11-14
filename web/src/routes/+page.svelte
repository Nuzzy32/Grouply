<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import ThemeToggle from '#lib/ThemeToggle.svelte';
	import { reveal } from '#lib/reveal.ts';
	import Demo from '#lib/landing/Demo.svelte';
	import Features from '#lib/landing/Features.svelte';
	import Hero from '#lib/landing/Hero.svelte';
	import Showcase from '#lib/landing/Showcase.svelte';
	import { SIGN_IN_URL, SIGN_UP_URL } from '#lib/landing/links.ts';

	const FAQ = [
		['Siapa yang bisa menyetujui tugas?', 'Hanya reviewer yang ditunjuk untuk tugas itu. Pelaksana tidak bisa menyetujui hasil kerjanya sendiri, jadi setiap tugas yang Selesai memang sudah diperiksa orang lain.'],
		['Apa bedanya chat grup dan diskusi tugas?', 'Chat grup untuk obrolan umum kelompok. Diskusi tugas menempel di satu tugas, jadi pertanyaan soal tugas itu nggak tenggelam di chat.'],
		['Bagaimana cara anggota bergabung?', 'Koordinator membuat kode undangan, lalu membagikannya. Kode berlaku 7 hari dan bisa dinonaktifkan kapan saja.'],
		['Bisa dipakai di HP dan laptop sekaligus?', 'Bisa. GROUPLY tersedia di iOS, Android, dan Web dengan data yang sama, jadi kamu bisa mulai di HP lalu lanjut review di laptop.']
	];
	const description =
		'Bagi tugas, kirim hasil, review bareng, dan pantau progres tim dalam satu tempat. Tersedia di iOS, Android, dan Web.';

	let scrolled = $state(false);
	let faq = $state(0);
</script>

<svelte:head>
	<title>GROUPLY · Kerja kelompok yang beneran jalan</title>
	<meta name="description" content={description} />
	<meta property="og:title" content="GROUPLY · Kerja kelompok yang beneran jalan" />
	<meta property="og:description" content={description} />
</svelte:head>

<svelte:window onscroll={() => (scrolled = window.scrollY > 8)} />

<header>
	<nav aria-label="Navigasi utama" class:scrolled>
		<a href="#top" class="brand"><img src="/brand.png" alt="" width="34" height="34" /><span>GROUPLY</span></a>
		<div class="links">
			<a href="#fitur">Fitur</a>
			<a href="#tampilan">Tampilan</a>
			<a href="#demo">Demo</a>
			<a href="#faq">FAQ</a>
		</div>
		<div class="auth">
			<ThemeToggle />
			<a href={SIGN_IN_URL} class="ghost">Masuk</a>
			<a href={SIGN_UP_URL} class="solid">Mulai sekarang</a>
		</div>
	</nav>
</header>

<main>
	<Hero />
	<Features />
	<Showcase />
	<Demo />

	<section id="faq" class="section" use:reveal>
		<div class="wrap faq rv">
			<div class="faq-head">
				<span class="eyebrow">FAQ</span>
				<h2 class="section-title" style="font-size:clamp(32px,4vw,48px);line-height:1.08">Pertanyaan yang sering muncul.</h2>
			</div>
			<div class="qs">
				{#each FAQ as [q, a], i (q)}
					{@const open = faq === i}
					<div class="q">
						<button aria-expanded={open} aria-controls="faq-{i}" onclick={() => (faq = open ? -1 : i)}>
							<span>{q}</span><span class="toggle"><Icon name={open ? 'remove' : 'add'} /></span>
						</button>
						<div class="answer" class:open id="faq-{i}">
							<div><p>{a}</p></div>
						</div>
					</div>
				{/each}
			</div>
		</div>
	</section>

	<section class="section" style="padding-bottom:30px" use:reveal>
		<div class="wrap cta rv" style="--t:.9s">
			<span class="glow" aria-hidden="true" style="left:-80px;top:-80px;background:#ded2ff;opacity:.35"></span>
			<span class="glow" aria-hidden="true" style="right:-60px;bottom:-100px;background:#c9f2d6;opacity:.3"></span>
			<h2>Mulai kelompok berikutnya dengan lebih tenang.</h2>
			<p>Buat grup, bagikan kode undangan, dan bagi tugas pertama dalam beberapa menit.</p>
			<div class="cta-actions">
				<a href={SIGN_UP_URL} class="light">Mulai sekarang<Icon name="arrow_forward" /></a>
				<a href="#demo" class="line">Lihat demo lagi</a>
			</div>
			<div class="cta-platforms">
				<span><Icon name="phone_iphone" size={18} />iOS</span>
				<span><Icon name="android" size={18} />Android</span>
				<span><Icon name="laptop_mac" size={18} />Web</span>
			</div>
		</div>
	</section>
</main>

<footer>
	<div class="wrap foot">
		<span class="brand small"><img src="/brand.png" alt="" width="28" height="28" /><b>GROUPLY</b></span>
		<span>© 2026 GROUPLY</span>
		<div class="foot-links">
			<!-- Belum ada halaman kebijakan publik; draf ada di docs/legal/. -->
			<a href="#top">Privasi</a>
			<a href="#top">Ketentuan</a>
			<a href="#top">Kontak</a>
		</div>
	</div>
</footer>

<style>
	main {
		overflow-x: clip;
	}
	header {
		position: fixed;
		inset: 0 0 auto;
		z-index: 50;
		display: flex;
		justify-content: center;
		padding: 14px 20px;
		pointer-events: none;
	}
	nav {
		pointer-events: auto;
		width: 100%;
		max-width: 1180px;
		height: 60px;
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 0 10px 0 14px;
		border-radius: 30px;
		background: transparent;
		backdrop-filter: blur(16px);
		-webkit-backdrop-filter: blur(16px);
		transition:
			background 0.3s,
			box-shadow 0.3s;
	}
	nav.scrolled {
		background: var(--nav-glass);
		box-shadow:
			0 10px 30px -18px rgba(0, 0, 0, 0.3),
			0 0 0 1px var(--border);
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		margin-right: auto;
		font-size: 14px;
		font-weight: 800;
		letter-spacing: 0.12em;
	}
	.brand img {
		border-radius: 11px;
	}
	.links {
		display: none;
		gap: 2px;
	}
	@media (min-width: 820px) {
		.links {
			display: flex;
		}
	}
	.auth {
		display: flex;
		gap: 6px;
		margin-left: auto;
	}
	.links a,
	.auth a {
		height: 40px;
		padding: 0 14px;
		border-radius: 20px;
		display: flex;
		align-items: center;
		font-size: 14px;
		font-weight: 600;
		white-space: nowrap;
		transition: background 0.2s;
	}
	.links a:hover,
	.auth .ghost:hover {
		background: var(--chip);
	}
	.auth a {
		height: 42px;
		border-radius: 21px;
	}
	.auth .solid {
		padding: 0 18px;
		background: var(--ink);
		color: var(--on-ink);
	}
	.auth .solid:hover {
		opacity: 0.88;
	}
	/* Desain asli meluap di HP 375px: sembunyikan wordmark, rapatkan tombol. */
	@media (max-width: 420px) {
		header {
			padding: 14px 12px;
		}
		.brand span {
			display: none;
		}
		.auth a {
			padding: 0 12px;
		}
		.auth .solid {
			padding: 0 14px;
		}
	}

	.faq {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: 40px;
	}
	@media (min-width: 960px) {
		.faq {
			grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr);
		}
	}
	.faq-head {
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	.qs {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.q {
		background: var(--surface);
		border-radius: 22px;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
	}
	.q button {
		width: 100%;
		text-align: left;
		border: none;
		background: none;
		border-radius: 22px;
		min-height: 64px;
		padding: 16px 20px;
		display: flex;
		align-items: center;
		gap: 14px;
		font-size: 17px;
		font-weight: 700;
	}
	.q button > span:first-child {
		flex: 1;
	}
	.toggle {
		flex: none;
		width: 34px;
		height: 34px;
		border-radius: 50%;
		background: var(--muted);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.answer {
		display: grid;
		grid-template-rows: 0fr;
		transition: grid-template-rows 0.35s var(--ease-out);
	}
	.answer.open {
		grid-template-rows: 1fr;
	}
	.answer > div {
		overflow: hidden;
	}
	.answer p {
		margin: 0;
		padding: 0 20px 18px;
		font-size: 15px;
		line-height: 1.6;
		color: var(--text3);
		opacity: 0;
		transition: opacity 0.35s;
	}
	.answer.open p {
		opacity: 1;
	}
	/* Jawaban tertutup tidak boleh terbaca pembaca layar atau terfokus. */
	.answer:not(.open) > div {
		visibility: hidden;
		transition: visibility 0s 0.35s;
	}

	/* CTA tetap gelap di kedua mode. */
	.cta {
		position: relative;
		overflow: hidden;
		background: #202124;
		color: #fff;
		box-shadow: 0 0 0 1px light-dark(transparent, var(--border));
		border-radius: 40px;
		padding: clamp(36px, 6vw, 80px) clamp(24px, 5vw, 64px);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 22px;
		text-align: center;
	}
	.glow {
		position: absolute;
		width: 320px;
		height: 320px;
		border-radius: 50%;
		filter: blur(110px);
	}
	.cta h2 {
		position: relative;
		margin: 0;
		max-width: 760px;
		font-size: clamp(34px, 5vw, 60px);
		font-weight: 800;
		letter-spacing: -0.045em;
		line-height: 1.04;
		text-wrap: balance;
	}
	.cta p {
		position: relative;
		margin: 0;
		max-width: 560px;
		font-size: 18px;
		line-height: 1.55;
		color: #d5d8db;
	}
	.cta-actions {
		position: relative;
		display: flex;
		gap: 10px;
		flex-wrap: wrap;
		justify-content: center;
	}
	.cta-actions a {
		height: 56px;
		padding: 0 24px;
		border-radius: 28px;
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 16px;
		font-weight: 600;
		transition:
			transform 0.2s,
			box-shadow 0.2s;
	}
	.cta-actions .light {
		padding: 0 26px;
		background: #fff;
		color: #202124;
		font-weight: 700;
	}
	.cta-actions .light:hover {
		transform: translateY(-2px);
	}
	.cta-actions .line {
		box-shadow: inset 0 0 0 1.5px rgba(255, 255, 255, 0.4);
	}
	.cta-actions .line:hover {
		box-shadow: inset 0 0 0 1.5px #fff;
	}
	.cta :focus-visible {
		outline-color: #fff;
	}
	.cta-platforms {
		position: relative;
		display: flex;
		gap: 18px;
		flex-wrap: wrap;
		justify-content: center;
		font-size: 14px;
		color: #d5d8db;
		padding-top: 6px;
	}
	.cta-platforms span {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	footer {
		padding: 30px 20px 40px;
	}
	.foot {
		display: flex;
		align-items: center;
		gap: 16px;
		flex-wrap: wrap;
		font-size: 14px;
		color: var(--secondary);
	}
	.brand.small {
		margin-right: 0;
		color: var(--ink);
		font-size: 13px;
	}
	.brand.small img {
		border-radius: 9px;
	}
	.foot-links {
		display: flex;
		gap: 4px;
		margin-left: auto;
	}
	.foot-links a {
		height: 36px;
		padding: 0 10px;
		border-radius: 18px;
		display: flex;
		align-items: center;
		color: var(--text2);
		transition: background 0.2s;
	}
	.foot-links a:hover {
		background: var(--chip);
	}
</style>
