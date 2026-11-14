<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { reducedMotion, reveal } from '#lib/reveal.ts';
	import AppFrame from './AppFrame.svelte';
	import { APP_URL } from './links';

	let frame = 0;
	// Parallax kartu mengambang: tulis variabel CSS langsung, tanpa re-render.
	function move(e: MouseEvent) {
		if (frame || reducedMotion()) return;
		const el = e.currentTarget as HTMLElement;
		const { clientX, clientY } = e;
		frame = requestAnimationFrame(() => {
			frame = 0;
			const r = el.getBoundingClientRect();
			el.style.setProperty('--mx', String(((clientX - r.left) / r.width - 0.5) * 2));
			el.style.setProperty('--my', String(((clientY - r.top) / r.height - 0.5) * 2));
		});
	}
	function leave(e: MouseEvent) {
		const el = e.currentTarget as HTMLElement;
		el.style.setProperty('--mx', '0');
		el.style.setProperty('--my', '0');
	}

	const columns = [
		{ label: 'Belum dimulai', dot: 'var(--ring-todo)' },
		{ label: 'Dikerjakan', dot: 'var(--ring-progress)' },
		{ label: 'Review', dot: 'var(--ring-review)' },
		{ label: 'Revisi', dot: 'var(--ring-revision)' },
		{ label: 'Selesai', dot: 'var(--ring-done)' }
	];
</script>

<!-- Parallax dekoratif, bukan kontrol. -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<section id="top" use:reveal onmousemove={move} onmouseleave={leave}>
	<div class="blobs" aria-hidden="true">
		<span class="blob" style="left:4%;top:60px;width:420px;height:420px;max-width:60%;background:var(--lavender);opacity:.6"></span>
		<span class="blob" style="right:4%;top:0;width:380px;height:380px;max-width:55%;background:var(--mint);opacity:.7"></span>
		<span class="blob" style="left:40%;top:260px;width:300px;height:300px;max-width:40%;background:var(--butter);opacity:.55"></span>
	</div>

	<div class="intro rv" style="--t:.9s">
		<a class="badge" href="#demo">
			<span class="chip" style="height:28px;padding:0 10px;font-size:12px;font-weight:700;background:var(--mint)">Baru</span>
			GROUPLY sekarang bisa dibuka di laptop<Icon name="arrow_forward" size={18} />
		</a>
		<h1>Kerja kelompok yang <span class="mark">beneran jalan.</span></h1>
		<p class="lead">
			Bagi tugas, kirim hasil, review bareng, dan pantau progres tim dalam satu tempat. Nggak perlu lagi
			ngejar anggota lewat chat.
		</p>
		<div class="ctas">
			<a class="btn-primary" href={APP_URL}>Mulai sekarang<Icon name="arrow_forward" /></a>
			<a class="btn-ghost" href="#demo">
				<span class="play"><Icon name="play_arrow" size={22} fill /></span>Lihat demo
			</a>
		</div>
		<div class="platforms">
			<span>Tersedia di</span>
			<b><Icon name="phone_iphone" size={18} />iOS</b>
			<b><Icon name="android" size={18} />Android</b>
			<b><Icon name="laptop_mac" size={18} />Web</b>
		</div>
	</div>

	<div class="stage">
		<div class="tilt">
			<AppFrame url="app.grouply.id/proyek/perpustakaan" active="group">
				<div class="project">
					<div class="crumbs">
						Grup<Icon name="chevron_right" size={14} />Basis Data · Kelompok 3<Icon
							name="chevron_right"
							size={14}
						/><b>Sistem Informasi Perpustakaan</b>
					</div>
					<div class="cards">
						<div class="card head">
							<span class="chip" style="font-size:11px;background:var(--sky)">Aktif</span>
							<span class="title">Sistem Informasi Perpustakaan</span>
							<span class="meta">Deadline Sab, 24 Okt · 23:59 · 5 anggota</span>
						</div>
						<div class="card pulse">
							<div class="ring">
								<span>29%<small>2 dari 7</small></span>
							</div>
							<div class="legend">
								<b>Group Pulse</b>
								<span><i style="background:var(--ring-done)"></i>Selesai<b>2</b></span>
								<span><i style="background:var(--ring-review)"></i>Menunggu review<b>1</b></span>
								<span><i style="background:var(--ring-todo)"></i>Belum dimulai<b>2</b></span>
							</div>
						</div>
					</div>
					<div class="board">
						{#each columns as col, i (col.label)}
							<div class="col">
								<span class="col-head"><i style="background:{col.dot}"></i>{col.label}</span>
								{#if i === 0}
									<div class="task">
										<span>Kamus data</span>
										<span class="avs">
											<span class="av" style="--s:20px;font-size:8px;background:var(--mint)">RA</span>
											<span class="av" style="--s:20px;font-size:8px;background:var(--butter)">NA</span>
										</span>
									</div>
									<div class="task">
										<span>Slide presentasi</span>
										<span class="avs">
											<span class="av" style="--s:20px;font-size:8px;background:var(--sky)">DI</span>
											<span class="av" style="--s:20px;font-size:8px;background:var(--lavender)">AL</span>
										</span>
									</div>
								{:else if i === 1}
									<div class="task"><span>Normalisasi ke 3NF</span><small>Besok, 23:59</small></div>
								{:else if i === 2}
									<div class="task focus">
										<span>Draft diagram ERD</span>
										<span class="chip" style="height:18px;padding:0 6px;font-size:9px;background:var(--lavender)">Revisi 1</span>
									</div>
								{:else if i === 3}
									<div class="task"><span>Tulis script DDL SQL</span><small>1 catatan revisi</small></div>
								{:else}
									<div class="task done"><span>Studi literatur</span></div>
									<div class="task done"><span>Narasi use case</span></div>
								{/if}
							</div>
						{/each}
					</div>
				</div>
			</AppFrame>
		</div>

		<div class="float" aria-hidden="true" style="left:-36px;top:150px;--k:-16">
			<div class="toast" style="animation-duration:6s">
				<span class="toast-icon"><Icon name="upload" /></span>
				<span class="toast-text"><small>Raka mengirim hasil · 15:20</small><b>Draft diagram ERD</b></span>
				<span class="outline-pill" style="height:30px">Lihat</span>
			</div>
		</div>
		<div class="float" aria-hidden="true" style="right:-30px;top:84px;--k:14">
			<div class="approved" style="animation-duration:7s;animation-delay:.8s">
				<Icon name="check_circle" fill />Disetujui. Tugas selesai.
			</div>
		</div>
		<div class="float" aria-hidden="true" style="right:48px;bottom:-26px;--k:9">
			<div class="bubble-row" style="animation-duration:6.5s;animation-delay:.4s">
				<span class="av" style="--s:34px;font-size:12px;background:var(--butter);box-shadow:0 0 0 3px var(--surface)">NA</span>
				<span class="bubble">Fine dipisah jadi entity sendiri ya 👌</span>
			</div>
		</div>
	</div>
</section>

<style>
	section {
		--mx: 0;
		--my: 0;
		position: relative;
		padding: 148px 20px 40px;
	}
	.blobs {
		position: absolute;
		top: 40px;
		left: 50%;
		width: min(1000px, 100%);
		height: 560px;
		transform: translateX(-50%);
		pointer-events: none;
	}
	.blob {
		position: absolute;
		border-radius: 50%;
		filter: blur(100px);
	}
	.intro {
		position: relative;
		max-width: 900px;
		margin: 0 auto;
		text-align: center;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 22px;
	}
	.badge {
		min-height: 38px;
		padding: 5px 14px 5px 5px;
		border-radius: 19px;
		background: var(--surface);
		box-shadow: 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 600;
		transition: box-shadow 0.2s;
	}
	.badge:hover {
		box-shadow: 0 0 0 1px var(--disabled);
	}
	h1 {
		margin: 0;
		font-size: clamp(44px, 7.4vw, 88px);
		font-weight: 800;
		letter-spacing: -0.05em;
		line-height: 1;
		text-wrap: balance;
	}
	.mark {
		background: linear-gradient(transparent 60%, var(--mint) 60%, var(--mint) 92%, transparent 92%);
		padding: 0 0.06em;
	}
	.lead {
		margin: 0;
		max-width: 640px;
		font-size: clamp(17px, 2vw, 20px);
		line-height: 1.55;
		color: var(--text3);
		text-wrap: pretty;
	}
	.ctas {
		display: flex;
		gap: 10px;
		flex-wrap: wrap;
		justify-content: center;
		padding-top: 4px;
	}
	.btn-primary,
	.btn-ghost {
		height: 56px;
		border-radius: 28px;
		display: flex;
		align-items: center;
		font-size: 16px;
		font-weight: 600;
		transition: transform 0.2s;
	}
	.btn-primary:hover,
	.btn-ghost:hover {
		transform: translateY(-2px);
	}
	.btn-primary {
		padding: 0 26px;
		gap: 8px;
		background: var(--ink);
		color: var(--on-ink);
		box-shadow: 0 14px 30px -12px rgba(32, 33, 36, 0.5);
	}
	.btn-ghost {
		padding: 0 22px 0 8px;
		gap: 10px;
		background: var(--surface);
		box-shadow: 0 0 0 1px var(--border);
	}
	.play {
		width: 40px;
		height: 40px;
		border-radius: 50%;
		background: var(--lavender);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.platforms {
		display: flex;
		align-items: center;
		gap: 14px;
		flex-wrap: wrap;
		justify-content: center;
		font-size: 14px;
		color: var(--text2);
	}
	.platforms b {
		display: flex;
		align-items: center;
		gap: 5px;
		font-weight: 600;
		color: var(--ink);
	}

	.stage {
		position: relative;
		max-width: 1140px;
		margin: 64px auto 0;
	}
	:global(.js) .tilt {
		opacity: 0;
		transform: perspective(1600px) rotateX(14deg) translateY(40px);
		transition:
			opacity 1.1s ease 0.15s,
			transform 1.1s var(--ease-out) 0.15s;
	}
	:global(.js) section:global(.seen) .tilt {
		opacity: 1;
		transform: perspective(1600px) rotateX(0deg);
	}

	.project {
		padding: 18px 22px;
		display: flex;
		flex-direction: column;
		gap: 14px;
		height: 100%;
	}
	.crumbs {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 12px;
		color: var(--secondary);
		white-space: nowrap;
	}
	.crumbs b {
		color: var(--ink);
	}
	.cards {
		display: flex;
		gap: 14px;
		flex-wrap: wrap;
	}
	.card {
		flex: 1 1 300px;
		background: var(--surface);
		border-radius: 20px;
		padding: 16px 18px;
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.title {
		font-size: 22px;
		font-weight: 800;
		letter-spacing: -0.03em;
		line-height: 1.15;
	}
	.meta {
		font-size: 12px;
		color: var(--secondary);
	}
	.pulse {
		padding: 14px 18px;
		display: flex;
		align-items: center;
		gap: 16px;
	}
	.ring {
		flex: none;
		width: 84px;
		height: 84px;
		border-radius: 50%;
		background: conic-gradient(
			var(--ring-done) 0 29%,
			var(--muted) 29% 30%,
			var(--ring-review) 30% 43%,
			var(--muted) 43% 44%,
			var(--ring-progress) 44% 57%,
			var(--muted) 57% 58%,
			var(--ring-revision) 58% 71%,
			var(--muted) 71% 72%,
			var(--ring-todo) 72% 99%,
			var(--muted) 99%
		);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.ring span {
		width: 60px;
		height: 60px;
		border-radius: 50%;
		background: var(--surface);
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		font-size: 17px;
		font-weight: 800;
	}
	.ring small {
		font-size: 9px;
		font-weight: 600;
		color: var(--secondary);
	}
	.legend {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: 11px;
		color: var(--text3);
	}
	.legend > b {
		font-size: 13px;
		color: var(--ink);
	}
	.legend span {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.legend span b {
		margin-left: auto;
	}
	i {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 50%;
	}
	.board {
		flex: 1;
		min-height: 0;
		display: grid;
		grid-template-columns: repeat(5, minmax(150px, 1fr));
		gap: 10px;
	}
	.col {
		background: var(--muted);
		border-radius: 16px;
		padding: 10px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.col-head {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 12px;
		font-weight: 700;
	}
	.col-head i {
		width: 10px;
		height: 10px;
	}
	.task {
		background: var(--surface);
		border-radius: 12px;
		padding: 10px;
		display: flex;
		flex-direction: column;
		gap: 6px;
		font-size: 12px;
		font-weight: 600;
	}
	.task small {
		font-size: 10px;
		font-weight: 400;
		color: var(--secondary);
	}
	.task.focus {
		box-shadow: inset 0 0 0 2px var(--ink);
	}
	.task.done {
		opacity: 0.75;
	}
	.avs {
		display: flex;
		gap: 4px;
	}

	.float {
		position: absolute;
		display: none;
		transform: translate3d(calc(var(--mx) * var(--k) * 1px), calc(var(--my) * var(--k) * 0.7px), 0);
		transition: transform 0.25s ease-out;
	}
	@media (min-width: 1100px) {
		.float {
			display: block;
		}
	}
	.float > div {
		animation: float ease-in-out infinite;
	}
	.toast {
		width: 290px;
		background: var(--surface);
		border-radius: 20px;
		padding: 12px 12px 12px 14px;
		display: flex;
		align-items: center;
		gap: 12px;
		box-shadow:
			0 24px 50px -20px rgba(0, 0, 0, 0.3),
			0 0 0 1px var(--border);
	}
	.toast-icon {
		flex: none;
		width: 40px;
		height: 40px;
		border-radius: 14px;
		background: var(--lavender);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.toast-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
		font-size: 14px;
	}
	.toast-text small {
		font-size: 12px;
		color: var(--text2);
	}
	.approved {
		background: #202124;
		color: #fff;
		border-radius: 18px;
		padding: 12px 16px;
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 600;
		box-shadow: 0 24px 50px -16px rgba(0, 0, 0, 0.45);
	}
	.approved :global(.ms) {
		color: #c9f2d6;
	}
	.bubble-row {
		display: flex;
		align-items: flex-end;
		gap: 8px;
	}
	.bubble {
		background: var(--surface);
		border-radius: 18px 18px 18px 6px;
		padding: 10px 14px;
		font-size: 14px;
		box-shadow:
			0 20px 40px -18px rgba(0, 0, 0, 0.3),
			0 0 0 1px var(--border);
	}
</style>
