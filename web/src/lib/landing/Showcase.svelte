<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { reducedMotion, reveal } from '#lib/reveal.ts';
	import AppFrame from './AppFrame.svelte';

	const TABS = [
		{
			icon: 'home',
			title: 'Beranda yang tahu prioritasmu',
			text: 'Revisi yang diminta, review yang menunggu, dan deadline minggu ini selalu muncul paling atas.',
			url: 'beranda'
		},
		{
			icon: 'chat_bubble',
			title: 'Chat grup yang terhubung ke tugas',
			text: 'Kiriman, review, dan revisi muncul sebagai kartu aktivitas di chat. Satu klik untuk buka tugasnya.',
			url: 'chat/basis-data-k3'
		},
		{
			icon: 'rate_review',
			title: 'Review dengan riwayat lengkap',
			text: 'Reviewer menyetujui atau meminta revisi dengan catatan. Setiap revisi tersimpan rapi.',
			url: 'tugas/draft-erd'
		},
		{
			icon: 'task_alt',
			title: 'Semua tugasmu di satu tabel',
			text: 'Lintas grup dan proyek, dikelompokkan dari yang perlu tindakan sampai yang sudah selesai.',
			url: 'tugas-saya'
		}
	];
	const RAIL = ['home', 'chat', 'tasks', 'tasks'] as const;

	let tab = $state(0);
	let cyc = $state(0); // memulai ulang bilah progres saat tab dipilih ulang
	let manual = $state(false);
	let seen = $state(false);
	let rm = $state(false);
	const auto = $derived(seen && !manual && !rm);

	$effect(() => {
		if (!auto) return;
		tab; // jadwalkan ulang setiap pergantian tab
		const t = setTimeout(() => {
			tab = (tab + 1) % TABS.length;
			cyc++;
		}, 6000);
		return () => clearTimeout(t);
	});

	function pick(i: number) {
		tab = i;
		manual = true;
		cyc++;
	}
</script>

<section
	id="tampilan"
	class="section"
	use:reveal={() => {
		rm = reducedMotion();
		seen = true;
	}}
>
	<div class="wrap stack">
		<div class="head rv">
			<span class="eyebrow">Tampilan produk</span>
			<h2 class="section-title">Satu tempat untuk seluruh kerja kelompok.</h2>
		</div>
		<div class="grid rv" style="--t:.9s;--d:.1s">
			<div role="tablist" aria-label="Tampilan produk" class="tabs">
				{#each TABS as t, i (t.url)}
					{@const on = tab === i}
					<button
						role="tab"
						id="tab-{i}"
						aria-selected={on}
						aria-controls="tab-panel"
						class="tab"
						class:on
						onclick={() => pick(i)}
					>
						<span class="tab-icon"><Icon name={t.icon} size={21} /></span>
						<span class="tab-copy">
							<span class="tab-title">{t.title}</span>
							<span class="expand"><span><span class="tab-text">{t.text}</span></span></span>
							{#if on && auto}
								<span class="prog">
									{#key cyc}<span></span>{/key}
								</span>
							{/if}
						</span>
					</button>
				{/each}
			</div>

			<div id="tab-panel" role="tabpanel" aria-labelledby="tab-{tab}">
				<AppFrame url="app.grouply.id/{TABS[tab].url}" active={RAIL[tab]} height={480}>
					{#if tab === 0}
						<div class="screen pad">
							<div class="hello"><small>Jumat, 16 Oktober</small><b>Halo, Alex</b></div>
							<div class="duo">
								<div class="panel" style="background:var(--butter);animation:up .5s ease .05s both">
									<span class="panel-head">Perlu perhatian<span class="count">2</span></span>
									<span class="item">
										<span class="item-icon"><Icon name="undo" size={16} /></span>
										<span class="item-text"><small>Revisi diminta oleh Dimas</small>Tulis script DDL SQL</span>
									</span>
									<span class="item">
										<span class="item-icon"><Icon name="error" size={16} /></span>
										<span class="item-text"><small>Terlambat sejak 15 Okt</small>Script wawancara</span>
									</span>
								</div>
								<div class="panel" style="background:var(--lavender);animation:up .5s ease .12s both">
									<span class="panel-head">Menunggu review kamu<span class="count">1</span></span>
									<span class="item">
										<span class="av" style="font-size:10px;background:var(--mint)">RA</span>
										<span class="item-text" style="gap:3px"
											>Draft diagram ERD<span
												class="chip"
												style="height:20px;padding:0 7px;background:var(--surface);box-shadow:inset 0 0 0 1.5px var(--ink)"
												>Menunggu 52 jam</span
											></span
										>
									</span>
								</div>
							</div>
							<div class="panel plain" style="animation:up .5s ease .2s both">
								<span class="panel-head">Deadline 7 hari ke depan</span>
								{#each [['17', 'Sab', 'Normalisasi tabel ke 3NF', 'Besok, 23:59', 'Sedang dikerjakan', 'var(--sky)'], ['21', 'Rab', 'Ringkasan temuan sesi 1', 'Rab, 23:59', 'Belum dimulai', 'var(--butter)']] as [d, day, title, due, label, bg] (title)}
									<span class="item">
										<span class="date">{d}<small>{day}</small></span>
										<span class="item-text grow">{title}<small class="after">{due}</small></span>
										<span class="chip" style="background:{bg}">{label}</span>
									</span>
								{/each}
							</div>
						</div>
					{:else if tab === 1}
						<div class="screen row">
							<div class="chats">
								<b>Chat grup</b>
								<span class="room on">
									<span class="room-icon" style="background:var(--mint)"><Icon name="database" size={17} /></span>
									<span class="room-text"><b>Basis Data · K3</b><small>Nadia: Nanti malam call…</small></span>
								</span>
								<span class="room">
									<span class="room-icon" style="background:var(--lavender)"><Icon name="interests" size={17} /></span>
									<span class="room-text"><b style="font-weight:600">UI/UX Research</b><small>Nadia: Sesi 1 lancar…</small></span>
								</span>
							</div>
							<div class="thread">
								<span class="chip today">Hari ini</span>
								<div class="act-card" style="animation:up .5s ease .05s both">
									<span class="act-icon" style="background:var(--coral)"><Icon name="undo" size={16} /></span>
									<span class="item-text grow"><small>Dimas meminta revisi · 08:40</small>Tulis script DDL SQL</span>
									<span class="outline-pill" style="height:26px;padding:0 9px;font-size:10px">Lihat tugas</span>
								</div>
								<div class="msg" style="animation:up .5s ease .15s both">
									<span class="av" style="--s:24px;font-size:9px;background:var(--sky)">DI</span>
									<span class="bubble">Lex, cek feedback-ku di tugas DDL ya. Minor kok.</span>
								</div>
								<div class="mine" style="animation:up .5s ease .25s both">Oke, nanti malam aku benerin.</div>
								<div class="msg" style="animation:up .5s ease .35s both">
									<span class="av" style="--s:24px;font-size:9px;background:var(--coral)">SI</span>
									<span class="bubble">Template slide aku taruh sini: <u>canva.com/design/perpus-k3</u></span>
								</div>
								<div class="composer">
									Tulis pesan ke grup…<span class="send"><Icon name="arrow_upward" size={17} /></span>
								</div>
							</div>
						</div>
					{:else if tab === 2}
						<div class="screen row">
							<div class="ghost">
								<span style="height:16px;width:50%;background:var(--border)"></span>
								<span style="height:80px"></span>
								<span style="height:60px"></span>
								<span style="height:60px"></span>
							</div>
							<div class="sheet" style="animation:up .5s ease both">
								<span class="chip" style="height:24px;padding:0 9px 0 6px;font-size:11px;background:var(--lavender)"
									><Icon name="visibility" size={14} />Menunggu review</span
								>
								<b class="sheet-title">Draft diagram ERD</b>
								<span class="segments"><span>Ringkasan</span><span class="on">Hasil kerja</span><span>Diskusi</span></span>
								<div class="submission">
									<span class="sub-head">
										<span class="item-text"><b>Revisi 1</b><small class="after">Raka · Rab 14 Okt, 15:20</small></span>
										<span class="chip" style="background:var(--lavender)">Menunggu review</span>
									</span>
									<span class="note"
										>ERD v1 dengan 9 entity. Relasi Member–Loan 1:N. Tolong cek apakah Fine perlu jadi entity
										sendiri.</span
									>
									<span class="link"><Icon name="link" size={15} />drive.google.com/file/d/erd-v1</span>
								</div>
								<div class="actions">
									<span class="outline"><Icon name="undo" size={16} />Minta revisi</span>
									<span class="solid"><Icon name="check_circle" size={16} />Setujui</span>
								</div>
							</div>
						</div>
					{:else}
						<div class="screen pad" style="gap:12px">
							<div class="tasks-head">
								<b>Tugas Saya</b>
								<span class="filters"
									><span class="chip filter on">Semua · 5</span><span class="chip filter">Perlu review · 1</span></span
								>
							</div>
							{#each [['PERLU TINDAKAN', [['Tulis script DDL SQL', 'Perpustakaan', 'Perlu revisi', 'var(--coral)', 'Sen, 12:00'], ['Draft diagram ERD', 'Perpustakaan', 'Menunggu review', 'var(--lavender)', 'Min, 23:59']]], ['SEDANG BERJALAN', [['Normalisasi tabel ke 3NF', 'Perpustakaan', 'Dikerjakan', 'var(--sky)', 'Besok'], ['Ringkasan temuan sesi 1', 'Usability Test', 'Belum dimulai', 'var(--butter)', '21 Okt']]]] as const as [group, rows], g (group)}
								<span class="group-label">{group}</span>
								<div class="table">
									{#each rows as [title, project, status, bg, due], i (title)}
										<span class="tr" style="animation:up .45s ease {0.05 + (g * 2 + i) * 0.075}s both">
											<b>{title}</b><span class="dim">{project}</span><span class="chip" style="background:{bg}"
												>{status}</span
											><span>{due}</span>
										</span>
									{/each}
								</div>
							{/each}
						</div>
					{/if}
				</AppFrame>
			</div>
		</div>
	</div>
</section>

<style>
	.stack {
		display: flex;
		flex-direction: column;
		gap: 40px;
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: 14px;
		max-width: 720px;
	}
	.grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: 28px;
		align-items: start;
	}
	@media (min-width: 960px) {
		.grid {
			grid-template-columns: minmax(0, 380px) minmax(0, 1fr);
		}
	}
	.tabs {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.tab {
		text-align: left;
		border: none;
		background: transparent;
		border-radius: 22px;
		padding: 16px 18px;
		display: flex;
		gap: 14px;
		transition:
			background 0.3s,
			box-shadow 0.3s;
	}
	.tab:hover,
	.tab.on {
		background: var(--surface);
	}
	.tab.on {
		box-shadow:
			0 18px 40px -24px rgba(0, 0, 0, 0.3),
			0 0 0 1px var(--border);
	}
	.tab-icon {
		flex: none;
		width: 42px;
		height: 42px;
		border-radius: 14px;
		background: var(--chip);
		display: flex;
		align-items: center;
		justify-content: center;
		transition:
			background 0.3s,
			color 0.3s;
	}
	.on .tab-icon {
		background: var(--ink);
		color: var(--on-ink);
	}
	.tab-copy {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	.tab-title {
		font-size: 17px;
		font-weight: 700;
		letter-spacing: -0.01em;
		line-height: 1.3;
		padding-top: 9px;
	}
	.expand {
		display: grid;
		grid-template-rows: 0fr;
		transition: grid-template-rows 0.4s var(--ease-out);
	}
	.on .expand {
		grid-template-rows: 1fr;
	}
	.expand > span {
		overflow: hidden;
	}
	.tab-text {
		display: block;
		padding-top: 6px;
		font-size: 15px;
		line-height: 1.5;
		color: var(--text3);
		opacity: 0;
		transition: opacity 0.4s;
	}
	.on .tab-text {
		opacity: 1;
	}
	.prog {
		display: block;
		height: 3px;
		margin-top: 12px;
		border-radius: 2px;
		background: var(--chip);
		overflow: hidden;
	}
	.prog span {
		display: block;
		height: 100%;
		background: var(--ink);
		border-radius: 2px;
		animation: prog 6s linear forwards;
	}

	.screen {
		position: absolute;
		inset: 0;
		display: flex;
		animation: fade 0.45s ease;
	}
	.pad {
		padding: 18px 20px;
		flex-direction: column;
		gap: 14px;
	}
	.hello {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.hello small {
		font-size: 12px;
		color: var(--secondary);
	}
	.hello b {
		font-size: 24px;
		font-weight: 800;
		letter-spacing: -0.03em;
	}
	.duo {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: 12px;
	}
	.panel {
		border-radius: 20px;
		padding: 14px 16px 6px;
		display: flex;
		flex-direction: column;
	}
	.panel.plain {
		background: var(--surface);
		padding: 12px 16px 4px;
	}
	.panel-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		font-size: 15px;
		font-weight: 700;
		padding-bottom: 4px;
	}
	.count {
		width: 24px;
		height: 24px;
		border-radius: 50%;
		background: var(--ink);
		color: var(--on-ink);
		font-size: 12px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.item {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 9px 0;
		border-top: 1px solid color-mix(in srgb, var(--ink) 10%, transparent);
	}
	.plain .item {
		gap: 12px;
		border-top-color: var(--line);
	}
	.item-icon {
		flex: none;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--surface) 70%, transparent);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.item-text {
		min-width: 0;
		display: flex;
		flex-direction: column;
		font-size: 13px;
		font-weight: 600;
	}
	.item-text small {
		order: -1;
		font-size: 11px;
		font-weight: 600;
		color: var(--text2);
	}
	.item-text small.after {
		order: 0;
		font-weight: 400;
		color: var(--secondary);
	}
	.grow {
		flex: 1;
	}
	.item .chip {
		align-self: center;
	}
	.date {
		flex: none;
		width: 40px;
		height: 42px;
		border-radius: 12px;
		background: var(--muted);
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		font-size: 15px;
		font-weight: 700;
		line-height: 1;
	}
	.date small {
		font-size: 9px;
		color: var(--secondary);
	}

	.row {
		flex-direction: row;
	}
	.chats {
		flex: none;
		width: 200px;
		border-right: 1px solid var(--line);
		padding: 14px 8px;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.chats > b {
		font-size: 15px;
		padding: 0 6px 8px;
	}
	.room {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px;
		border-radius: 14px;
	}
	.room.on {
		background: var(--surface);
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
	}
	.room-icon {
		flex: none;
		width: 32px;
		height: 32px;
		border-radius: 12px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.room-text {
		min-width: 0;
		display: flex;
		flex-direction: column;
		font-size: 12px;
	}
	.room-text b,
	.room-text small {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.room-text small {
		font-size: 10px;
		color: var(--secondary);
	}
	.thread {
		flex: 1;
		min-width: 0;
		padding: 14px 18px;
		display: flex;
		flex-direction: column;
		gap: 8px;
		justify-content: flex-end;
	}
	.today {
		align-self: center;
		background: var(--chip);
		color: var(--text2);
	}
	.act-card {
		align-self: center;
		width: 100%;
		max-width: 400px;
		background: var(--surface);
		border-radius: 16px;
		box-shadow: inset 0 0 0 1px var(--border);
		padding: 10px;
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.act-card .item-text {
		font-size: 12px;
		font-weight: 700;
	}
	.act-card .item-text small {
		font-size: 10px;
		font-weight: 400;
	}
	.act-icon {
		flex: none;
		width: 32px;
		height: 32px;
		border-radius: 11px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.msg {
		display: flex;
		gap: 6px;
		align-items: flex-end;
		max-width: 75%;
	}
	.bubble,
	.mine {
		border-radius: 16px 16px 16px 6px;
		padding: 7px 11px;
		font-size: 12px;
	}
	.bubble {
		background: var(--surface);
		box-shadow: 0 1px 1.5px rgba(0, 0, 0, 0.06);
	}
	.bubble u {
		color: var(--link);
	}
	.mine {
		align-self: flex-end;
		max-width: 70%;
		background: var(--lavender);
		border-radius: 16px 16px 6px 16px;
	}
	.composer {
		margin-top: 6px;
		height: 38px;
		border-radius: 19px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		padding: 0 4px 0 14px;
		font-size: 12px;
		color: var(--placeholder);
	}
	.send {
		margin-left: auto;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		background: var(--disabled);
		color: #fff;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.ghost {
		flex: 1;
		min-width: 0;
		padding: 16px;
		display: flex;
		flex-direction: column;
		gap: 8px;
		opacity: 0.45;
	}
	.ghost span {
		border-radius: 16px;
		background: var(--surface);
	}
	.sheet {
		flex: none;
		width: min(380px, 100%);
		background: var(--background);
		border-left: 1px solid var(--border);
		box-shadow: -24px 0 40px -24px rgba(0, 0, 0, 0.25);
		padding: 16px 18px;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.sheet-title {
		font-size: 20px;
		font-weight: 800;
		letter-spacing: -0.02em;
	}
	.segments {
		display: flex;
		background: var(--chip);
		border-radius: 12px;
		padding: 3px;
		gap: 2px;
		font-size: 11px;
		font-weight: 600;
	}
	.segments span {
		flex: 1;
		height: 28px;
		border-radius: 9px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.segments .on {
		background: var(--surface);
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
	}
	.submission {
		background: var(--surface);
		border-radius: 16px;
		padding: 12px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.sub-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}
	.sub-head small {
		font-size: 10px !important;
	}
	.note {
		font-size: 12px;
		line-height: 1.45;
	}
	.link {
		height: 32px;
		border-radius: 10px;
		background: var(--muted);
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 0 10px;
		font-size: 11px;
		font-weight: 500;
	}
	.actions {
		margin-top: auto;
		display: flex;
		gap: 8px;
	}
	.actions span {
		flex: 1;
		height: 40px;
		border-radius: 13px;
		font-size: 12px;
		font-weight: 600;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 5px;
	}
	.outline {
		box-shadow: inset 0 0 0 1.5px var(--ink);
		background: var(--surface);
	}
	.solid {
		background: var(--ink);
		color: var(--on-ink);
	}

	.tasks-head {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 10px;
		flex-wrap: wrap;
	}
	.tasks-head > b {
		font-size: 22px;
		font-weight: 800;
		letter-spacing: -0.03em;
	}
	.filters {
		display: flex;
		gap: 6px;
	}
	.filter {
		height: 28px;
		padding: 0 10px;
		font-size: 11px;
		box-shadow: inset 0 0 0 1.5px var(--ink);
	}
	.filter.on {
		background: var(--ink);
		color: var(--on-ink);
		box-shadow: none;
	}
	.group-label {
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.05em;
		color: var(--text2);
	}
	.table {
		background: var(--surface);
		border-radius: 16px;
		padding: 2px 10px;
		display: flex;
		flex-direction: column;
		font-size: 12px;
	}
	.tr {
		display: grid;
		grid-template-columns: minmax(0, 1.6fr) minmax(0, 1fr) 120px 80px;
		gap: 10px;
		align-items: center;
		min-height: 42px;
	}
	.tr + .tr {
		border-top: 1px solid var(--muted);
	}
	.tr b,
	.dim {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.dim {
		color: var(--secondary);
	}
	.tr .chip {
		align-self: center;
		justify-self: start;
	}
</style>
