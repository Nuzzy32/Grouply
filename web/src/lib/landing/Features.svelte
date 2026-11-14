<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { reveal } from '#lib/reveal.ts';

	const pulse = [
		{ ini: 'AL', name: 'Alex', bg: 'var(--lavender)', ratio: '0/2', me: true },
		{ ini: 'RA', name: 'Raka', bg: 'var(--mint)', ratio: '0/2' },
		{ ini: 'NA', name: 'Nadia', bg: 'var(--butter)', ratio: '1/1' },
		{ ini: 'DI', name: 'Dimas', bg: 'var(--sky)', ratio: '0/1' }
	];
</script>

<section id="fitur" class="section" style="padding-top:110px" use:reveal>
	<div class="wrap stack">
		<div class="head rv">
			<span class="eyebrow">Fitur</span>
			<h2 class="section-title">Semua yang dibutuhkan kelompok, tanpa drama.</h2>
		</div>
		<div class="bento">
			<div class="tile wide rv" style="--d:.08s;background:var(--mint);--tint:#2f3a33">
				<div class="copy">
					<h3>Satu tugas, satu pelaksana, satu reviewer.</h3>
					<p>
						Setiap tugas jelas siapa yang mengerjakan, siapa yang memeriksa, dan kapan deadline-nya. Nggak
						ada lagi "ini tugas siapa, ya?"
					</p>
				</div>
				<div class="mock" style="flex:1 1 280px;padding:16px;gap:12px">
					<span class="chip" style="height:26px;padding:0 10px 0 7px;font-size:12px;gap:4px;background:var(--sky)"
						><Icon name="autorenew" size={15} />Sedang dikerjakan</span
					>
					<b style="font-size:16px">Normalisasi tabel ke 3NF</b>
					<span class="people">
						<span class="av" style="font-size:11px;background:var(--lavender)">AL</span>
						<span class="muted-icon"><Icon name="arrow_forward" size={16} /></span>
						<span class="av" style="font-size:11px;background:var(--butter)">NA</span>
						Alex → Nadia
						<span class="due"><Icon name="schedule" size={16} />Besok</span>
					</span>
				</div>
			</div>

			<div class="tile col rv" style="--d:.16s;background:var(--lavender);--tint:#36304a">
				<div class="copy">
					<h3>Selesai artinya sudah direview.</h3>
					<p>Tugas baru Selesai setelah reviewer menyetujui. Setiap revisi tercatat.</p>
				</div>
				<div class="revs">
					<div class="rev faded">
						<b>Revisi 1</b>
						<span class="chip" style="height:24px;padding:0 9px 0 6px;font-size:11px;background:var(--coral)"
							><Icon name="undo" size={14} />Perlu revisi</span
						>
					</div>
					<div class="rev lifted">
						<b>Revisi 2</b>
						<span class="chip" style="height:24px;padding:0 9px 0 6px;font-size:11px;background:var(--mint)"
							><Icon name="check_circle" size={14} />Disetujui</span
						>
					</div>
				</div>
			</div>

			<div class="tile col rv" style="--d:.24s;background:var(--sky);--tint:#2c3a42">
				<div class="copy">
					<h3>Chat yang nyambung ke tugas.</h3>
					<p>Kiriman dan review otomatis muncul di chat grup. Klik sekali, tugasnya langsung terbuka.</p>
				</div>
				<div class="activity">
					<span class="act-icon"><Icon name="check_circle" size={18} /></span>
					<span class="act-text"><small>Alex menyetujui · 16:00</small><b>Rekrut 5 partisipan</b></span>
					<span class="outline-pill">Lihat tugas</span>
				</div>
			</div>

			<div class="tile wide rv" style="--d:.32s;background:var(--butter);--tint:#4a3f22">
				<div class="copy">
					<h3>Group Pulse: progres tim, bukan ranking.</h3>
					<p>
						Lihat berapa tugas yang selesai, menunggu review, atau belum dimulai. Klik anggota untuk melihat
						tugasnya, tanpa papan peringkat.
					</p>
				</div>
				<div class="mock" style="flex:1 1 300px;padding:16px 18px;gap:14px">
					<div class="members">
						{#each pulse as m (m.ini)}
							<span class="member" class:me={m.me}>
								<span class="av" style="--s:42px;font-size:13px;position:relative;background:{m.bg}"
									>{m.ini}<span class="ratio">{m.ratio}</span></span
								>{m.name}
							</span>
						{/each}
					</div>
					<div class="mine">
						<b>Tugasmu · 0 dari 2 selesai</b>
						<span class="track"><span style="width:12%"></span></span>
					</div>
				</div>
			</div>
		</div>
	</div>
</section>

<style>
	.stack {
		display: flex;
		flex-direction: column;
		gap: 44px;
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: 14px;
		max-width: 720px;
	}
	.bento {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: 16px;
	}
	@media (min-width: 960px) {
		.bento {
			grid-template-columns: repeat(3, minmax(0, 1fr));
		}
		.wide {
			grid-column: span 2;
		}
	}
	.tile {
		border-radius: 32px;
		padding: 30px;
		display: flex;
		gap: 20px;
		color: var(--ink);
	}
	.wide {
		gap: 28px;
		flex-wrap: wrap;
		align-items: center;
	}
	.col {
		flex-direction: column;
	}
	@media (prefers-color-scheme: dark) {
		.tile {
			--tint: var(--text2) !important;
		}
	}
	.copy {
		flex: 1 1 260px;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.col .copy {
		flex: none;
	}
	h3 {
		margin: 0;
		font-size: 24px;
		font-weight: 800;
		letter-spacing: -0.025em;
		line-height: 1.15;
	}
	p {
		margin: 0;
		font-size: 16px;
		line-height: 1.55;
		color: var(--tint);
	}
	.mock {
		background: var(--surface);
		border-radius: 22px;
		display: flex;
		flex-direction: column;
		box-shadow: 0 20px 40px -24px rgba(0, 0, 0, 0.3);
	}
	.people {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 13px;
		color: var(--text3);
	}
	.muted-icon {
		display: flex;
		color: var(--secondary);
	}
	.due {
		margin-left: auto;
		display: flex;
		align-items: center;
		gap: 4px;
	}
	.revs {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.rev {
		border-radius: 16px;
		padding: 10px 12px;
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 13px;
	}
	.rev .chip {
		margin-left: auto;
		align-self: center;
	}
	.faded {
		background: color-mix(in srgb, var(--surface) 70%, transparent);
	}
	.lifted {
		background: var(--surface);
		box-shadow: 0 14px 30px -18px rgba(0, 0, 0, 0.35);
	}
	.activity {
		background: var(--surface);
		border-radius: 18px;
		padding: 10px 10px 10px 12px;
		display: flex;
		align-items: center;
		gap: 10px;
		box-shadow: 0 14px 30px -18px rgba(0, 0, 0, 0.35);
	}
	.act-icon {
		flex: none;
		width: 34px;
		height: 34px;
		border-radius: 12px;
		background: var(--mint);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.act-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		font-size: 13px;
	}
	.act-text small {
		font-size: 11px;
		color: var(--text2);
	}
	.members {
		display: flex;
		justify-content: space-between;
		gap: 6px;
	}
	.member {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		font-size: 12px;
	}
	.member.me {
		font-weight: 600;
	}
	.member.me .av {
		box-shadow:
			0 0 0 2.5px var(--surface),
			0 0 0 4.5px var(--ink);
	}
	.ratio {
		position: absolute;
		right: -8px;
		bottom: -4px;
		height: 18px;
		padding: 0 5px;
		border-radius: 9px;
		background: var(--surface);
		box-shadow: 0 0 0 1px var(--border);
		font-size: 10px;
		font-weight: 400;
		display: flex;
		align-items: center;
	}
	.mine {
		background: var(--muted);
		border-radius: 14px;
		padding: 10px 12px;
		display: flex;
		flex-direction: column;
		gap: 6px;
		font-size: 13px;
	}
	.mine b {
		font-weight: 600;
	}
	.track {
		height: 6px;
		border-radius: 3px;
		background: var(--surface);
		overflow: hidden;
	}
	.track span {
		display: block;
		height: 100%;
		background: var(--ink);
		border-radius: 3px;
	}
</style>
