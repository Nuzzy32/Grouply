<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { reducedMotion, reveal } from '#lib/reveal.ts';

	type Status = 'todo' | 'in_progress' | 'in_review' | 'needs_revision' | 'done';
	const ST: Record<Status, { label: string; bg: string; icon: string; dot: string }> = {
		todo: { label: 'Belum dimulai', bg: 'var(--butter)', icon: 'radio_button_unchecked', dot: 'var(--ring-todo)' },
		in_progress: { label: 'Sedang dikerjakan', bg: 'var(--sky)', icon: 'autorenew', dot: 'var(--ring-progress)' },
		in_review: { label: 'Menunggu review', bg: 'var(--lavender)', icon: 'visibility', dot: 'var(--ring-review)' },
		needs_revision: { label: 'Perlu revisi', bg: 'var(--coral)', icon: 'undo', dot: 'var(--ring-revision)' },
		done: { label: 'Selesai', bg: 'var(--mint)', icon: 'check_circle', dot: 'var(--ring-done)' }
	};
	const COLS: [Status, string][] = [
		['todo', 'Belum dimulai'],
		['in_progress', 'Dikerjakan'],
		['in_review', 'Review'],
		['needs_revision', 'Revisi'],
		['done', 'Selesai']
	];
	const OTHERS = [
		[['Slide presentasi', 'DI', 'var(--sky)']],
		[['Normalisasi ke 3NF', 'AL', 'var(--lavender)']],
		[],
		[],
		[
			['Studi literatur', 'NA', 'var(--butter)'],
			['Narasi use case', 'SI', 'var(--coral)']
		]
	];

	type Feed =
		| { act: true; icon: string; bg: string; who: string; text: string; time: string }
		| { act: false; ini: string; bg: string; text: string };
	const A = (icon: string, bg: string, who: string, text: string, time: string): Feed => ({ act: true, icon, bg, who, text, time });
	const M = (ini: string, bg: string, text: string): Feed => ({ act: false, ini, bg, text });

	const STEPS: { col: number; st: Status; label: string; sub: string; meta: string; feed: Feed[] }[] = [
		{ col: 0, st: 'todo', label: 'Alex membuat tugas', sub: 'Raka jadi pelaksana, Nadia jadi reviewer, deadline hari Minggu.', meta: 'Raka → Nadia · Minggu', feed: [A('add_task', 'var(--sky)', 'Alex', 'membuat tugas untuk Raka', '09:12')] },
		{ col: 1, st: 'in_progress', label: 'Raka mulai mengerjakan', sub: 'Statusnya langsung berubah, jadi seluruh tim tahu tugas ini sedang jalan.', meta: 'Dikerjakan Raka', feed: [M('RA', 'var(--mint)', 'Siap, aku kerjain malam ini.')] },
		{ col: 2, st: 'in_review', label: 'Raka mengirim hasil', sub: 'Catatan dan link Drive terkirim. Nadia diberi tahu untuk mereview.', meta: 'Revisi 1 · menunggu Nadia', feed: [A('upload', 'var(--lavender)', 'Raka', 'mengirim hasil', '20:40')] },
		{ col: 3, st: 'needs_revision', label: 'Nadia meminta revisi', sub: 'Catatan revisi tersimpan di tugas, nggak tenggelam di chat.', meta: 'Catatan: pisahkan entity Fine', feed: [A('undo', 'var(--coral)', 'Nadia', 'meminta revisi', '21:05'), M('NA', 'var(--butter)', 'Fine dipisah jadi entity sendiri ya, sisanya udah oke.')] },
		{ col: 2, st: 'in_review', label: 'Raka mengirim revisi 2', sub: 'Revisi pertama tetap ada di riwayat. Nadia mereview lagi.', meta: 'Revisi 2 · menunggu Nadia', feed: [A('upload', 'var(--lavender)', 'Raka', 'mengirim revisi 2', '22:18')] },
		{ col: 4, st: 'done', label: 'Nadia menyetujui', sub: 'Tugas baru dianggap Selesai setelah disetujui reviewer. Progres tim ikut naik.', meta: 'Disetujui Nadia', feed: [A('check_circle', 'var(--mint)', 'Nadia', 'menyetujui', '22:30')] }
	];
	const LAST = STEPS.length - 1;
	const STEP_MS = 2400;

	let step = $state(0);
	let playing = $state(false);
	let started = false;

	const cur = $derived(STEPS[step]);
	const info = $derived(ST[cur.st]);
	const feed = $derived(
		STEPS.slice(0, step + 1)
			.flatMap((s, i) => s.feed.map((f, j) => ({ ...f, id: `${i}-${j}` })))
			.slice(-5)
	);
	const done = $derived(2 + (step === LAST ? 1 : 0));
	const pct = $derived(`${Math.round((done / 6) * 100)}%`);

	$effect(() => {
		if (!playing) return;
		step; // jadwalkan ulang setiap langkah
		const t = setTimeout(() => {
			if (step >= LAST) playing = false;
			else {
				step++;
				playing = step < LAST;
			}
		}, STEP_MS);
		return () => clearTimeout(t);
	});

	function go(i: number) {
		step = i;
		playing = false;
		started = true;
	}
	function toggle() {
		started = true;
		if (playing) playing = false;
		else {
			if (step === LAST) step = 0;
			playing = true;
		}
	}
</script>

<section
	id="demo"
	class="section"
	use:reveal={() => {
		if (!started && !reducedMotion()) {
			started = true;
			playing = true;
		}
	}}
>
	<div class="wrap card rv" style="--t:.9s">
		<div class="top">
			<div class="head">
				<span class="eyebrow">Demo produk</span>
				<h2 class="section-title" style="font-size:clamp(30px,4vw,48px);line-height:1.08">
					Ikuti satu tugas dari dibuat sampai disetujui.
				</h2>
			</div>
			<div class="controls">
				<button class="round" aria-label="Langkah sebelumnya" disabled={step === 0} onclick={() => go(Math.max(0, step - 1))}>
					<Icon name="chevron_left" size={22} />
				</button>
				<button class="play" onclick={toggle}>
					<Icon name={playing ? 'pause' : step === LAST ? 'replay' : 'play_arrow'} size={22} fill />
					{playing ? 'Jeda' : step === LAST ? 'Putar ulang' : 'Putar'}
				</button>
				<button class="round" aria-label="Langkah berikutnya" disabled={step === LAST} onclick={() => go(Math.min(LAST, step + 1))}>
					<Icon name="chevron_right" size={22} />
				</button>
			</div>
		</div>

		<div class="caption">
			<span class="num">Langkah {step + 1} dari {STEPS.length}</span>
			<span class="label" aria-live="polite">{cur.label}</span>
			<span class="sub">{cur.sub}</span>
		</div>

		<div class="stage">
			<div class="scroll">
				<div class="board-wrap">
					<div class="board">
						{#each COLS as [key, label], i (key)}
							<div class="col">
								<span class="col-head"><i style="background:{ST[key].dot}"></i>{label}</span>
								<div class="slot" class:here={cur.col === i}></div>
								{#each OTHERS[i] as [t, ini, bg] (t)}
									<div class="other">
										<span>{t}</span>
										<span class="av" style="--s:22px;font-size:9px;background:{bg}">{ini}</span>
									</div>
								{/each}
							</div>
						{/each}
					</div>
					<div class="mover" style:left="calc({cur.col} * ((100% - 40px) / 5 + 10px))">
						<div class="task" class:done={cur.st === 'done'}>
							{#key step}
								<span class="pulse" class:on={step === LAST} aria-hidden="true"></span>
							{/key}
							<span class="chip" style="max-width:100%;height:24px;padding:0 8px 0 6px;font-size:11px;background:{info.bg}"
								><Icon name={info.icon} size={14} />{info.label}</span
							>
							<b>Draft diagram ERD</b>
							<small>{cur.meta}</small>
						</div>
					</div>
				</div>
			</div>

			<div class="lower">
				<div class="chat">
					<span class="chat-head"><span class="chat-icon"><Icon name="database" size={15} /></span>Chat · Basis Data K3</span>
					<div class="feed">
						{#each feed as f (f.id)}
							{#if f.act}
								<div class="act">
									<span class="act-icon" style="background:{f.bg}"><Icon name={f.icon} size={15} /></span>
									<span class="act-text"><small>{f.who} {f.text} · {f.time}</small><b>Draft diagram ERD</b></span>
								</div>
							{:else}
								<div class="msg">
									<span class="av" style="--s:24px;font-size:9px;background:{f.bg}">{f.ini}</span>
									<span class="bubble">{f.text}</span>
								</div>
							{/if}
						{/each}
					</div>
				</div>
				<div class="pulse-card">
					<span class="pulse-head"><b>Group Pulse</b><span class="pct">{pct}</span></span>
					<span class="bar"><span style:width={pct}></span></span>
					<span class="pulse-foot"><span>{done} dari 6 tugas selesai</span><span>Raka {step === LAST ? '1/1' : '0/1'}</span></span>
				</div>
			</div>
		</div>

		<div class="steps">
			<div class="line"><span style:width="{(step / LAST) * 100}%"></span></div>
			<div class="dots">
				{#each STEPS as s, i (i)}
					<button class="step" class:reached={i <= step} class:on={i === step} aria-current={i === step ? 'step' : undefined} onclick={() => go(i)}>
						<span class="n">{i + 1}</span>
						<span class="step-label">{s.label}</span>
					</button>
				{/each}
			</div>
		</div>
	</div>
</section>

<style>
	.card {
		background: var(--surface);
		border-radius: 40px;
		padding: clamp(24px, 4vw, 48px);
		display: flex;
		flex-direction: column;
		gap: 30px;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
	}
	.top {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		gap: 20px;
		flex-wrap: wrap;
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: 12px;
		max-width: 640px;
	}
	.controls {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.round {
		width: 46px;
		height: 46px;
		border-radius: 50%;
		border: none;
		background: var(--muted);
		display: flex;
		align-items: center;
		justify-content: center;
		transition: background 0.2s;
	}
	.round:hover:not(:disabled) {
		background: var(--border);
	}
	.round:disabled {
		opacity: 0.4;
		cursor: default;
	}
	.play {
		height: 46px;
		padding: 0 20px 0 14px;
		border-radius: 23px;
		border: none;
		background: var(--ink);
		color: var(--on-ink);
		font-size: 15px;
		font-weight: 600;
		display: flex;
		align-items: center;
		gap: 6px;
		transition: opacity 0.2s;
	}
	.play:hover {
		opacity: 0.88;
	}
	.caption {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-height: 76px;
	}
	.num {
		font-size: 13px;
		font-weight: 700;
		color: var(--text2);
	}
	.label {
		font-size: 24px;
		font-weight: 800;
		letter-spacing: -0.02em;
	}
	.sub {
		font-size: 16px;
		line-height: 1.5;
		color: var(--text3);
	}
	.stage {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	.scroll {
		overflow-x: auto;
		margin: 0 -4px;
		padding: 0 4px 4px;
	}
	.board-wrap {
		position: relative;
		min-width: 760px;
	}
	.board {
		display: grid;
		grid-template-columns: repeat(5, minmax(0, 1fr));
		gap: 10px;
	}
	.col {
		background: var(--muted);
		border-radius: 20px;
		padding: 10px;
		display: flex;
		flex-direction: column;
		gap: 8px;
		min-height: 330px;
	}
	.col-head {
		display: flex;
		align-items: center;
		gap: 7px;
		padding: 4px 4px 2px;
		font-size: 13px;
		font-weight: 700;
	}
	.col-head i {
		width: 10px;
		height: 10px;
		border-radius: 50%;
	}
	.slot {
		height: 112px;
		border-radius: 16px;
		border: 1.5px dashed var(--hairline);
		transition: border-color 0.4s;
	}
	.slot.here {
		border-color: transparent;
	}
	.other {
		background: var(--surface);
		border-radius: 14px;
		padding: 10px;
		display: flex;
		flex-direction: column;
		gap: 8px;
		opacity: 0.7;
		font-size: 13px;
		font-weight: 600;
	}
	.mover {
		position: absolute;
		top: 42px;
		width: calc((100% - 40px) / 5);
		padding: 0 10px;
		transition: left 0.8s var(--ease-in-out);
	}
	.task {
		position: relative;
		height: 112px;
		background: var(--surface);
		border-radius: 16px;
		padding: 10px 12px;
		display: flex;
		flex-direction: column;
		gap: 7px;
		box-shadow:
			0 0 0 2px var(--ink),
			0 18px 36px -16px rgba(0, 0, 0, 0.35);
		transition: box-shadow 0.4s;
	}
	.task.done {
		box-shadow:
			0 0 0 2px var(--ring-done),
			0 18px 36px -16px rgba(0, 0, 0, 0.35);
	}
	.task .chip {
		transition: background 0.4s;
	}
	.task b {
		font-size: 14px;
		line-height: 1.25;
	}
	.task small {
		font-size: 11px;
		color: var(--text2);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.pulse {
		position: absolute;
		inset: 0;
		border-radius: 16px;
		pointer-events: none;
	}
	.pulse.on {
		animation: pulse 1s ease-out 2;
	}

	.lower {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: 16px;
		align-items: stretch;
		min-width: 0;
	}
	@media (min-width: 960px) {
		.lower {
			grid-template-columns: minmax(0, 1.7fr) minmax(0, 1fr);
		}
	}
	.chat {
		background: var(--background);
		border-radius: 22px;
		padding: 14px;
		display: flex;
		flex-direction: column;
		gap: 8px;
		min-height: 250px;
		min-width: 0;
	}
	.chat-head {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 13px;
		font-weight: 700;
	}
	.chat-icon {
		width: 26px;
		height: 26px;
		border-radius: 9px;
		background: var(--mint);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.feed {
		flex: 1;
		display: flex;
		flex-direction: column;
		justify-content: flex-end;
		gap: 8px;
	}
	.act {
		background: var(--surface);
		border-radius: 14px;
		box-shadow: inset 0 0 0 1px var(--border);
		padding: 8px 10px;
		display: flex;
		align-items: center;
		gap: 8px;
		animation: up 0.4s ease both;
	}
	.act-icon {
		flex: none;
		width: 28px;
		height: 28px;
		border-radius: 10px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.act-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		font-size: 12px;
	}
	.act-text small {
		font-size: 11px;
		color: var(--text2);
	}
	.msg {
		display: flex;
		gap: 6px;
		align-items: flex-end;
		animation: up 0.4s ease both;
	}
	.bubble {
		background: var(--surface);
		border-radius: 14px 14px 14px 5px;
		padding: 7px 10px;
		font-size: 12px;
		line-height: 1.4;
		box-shadow: 0 1px 1.5px rgba(0, 0, 0, 0.06);
	}
	.pulse-card {
		background: var(--butter);
		border-radius: 22px;
		padding: 20px;
		display: flex;
		flex-direction: column;
		justify-content: center;
		gap: 12px;
		min-width: 0;
	}
	.pulse-head {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: 8px;
		font-size: 14px;
	}
	.pct {
		font-size: 22px;
		font-weight: 800;
		font-variant-numeric: tabular-nums;
		letter-spacing: -0.03em;
	}
	.bar {
		height: 8px;
		border-radius: 4px;
		background: color-mix(in srgb, var(--surface) 70%, transparent);
		overflow: hidden;
	}
	.bar span {
		display: block;
		height: 100%;
		background: var(--ink);
		border-radius: 4px;
		transition: width 0.9s var(--ease-out);
	}
	.pulse-foot {
		display: flex;
		justify-content: space-between;
		font-size: 12px;
		color: light-dark(#4a3f22, var(--text2));
	}

	.steps {
		position: relative;
		padding-top: 6px;
	}
	.line {
		position: absolute;
		left: 18px;
		right: 18px;
		top: 24px;
		height: 2px;
		background: var(--border);
	}
	.line span {
		display: block;
		height: 100%;
		background: var(--ink);
		transition: width 0.6s var(--ease-out);
	}
	.dots {
		position: relative;
		display: grid;
		grid-template-columns: repeat(6, minmax(0, 1fr));
		gap: 6px;
	}
	.step {
		border: none;
		background: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		text-align: center;
	}
	.n {
		width: 38px;
		height: 38px;
		border-radius: 50%;
		background: var(--surface);
		color: var(--secondary);
		box-shadow: inset 0 0 0 1.5px var(--disabled);
		font-size: 14px;
		font-weight: 700;
		display: flex;
		align-items: center;
		justify-content: center;
		transition:
			background 0.3s,
			color 0.3s;
	}
	.reached .n {
		background: var(--ink);
		color: var(--on-ink);
		box-shadow: none;
	}
	.step-label {
		font-size: 13px;
		font-weight: 500;
		color: var(--secondary);
		line-height: 1.3;
		transition: color 0.3s;
	}
	.reached .step-label {
		color: var(--ink);
	}
	.on .step-label {
		font-weight: 700;
	}
</style>
