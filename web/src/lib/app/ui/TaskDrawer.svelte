<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { userName } from '../derive.ts';
	import { dueLabel, initials, isOverdue, STATUS, tint } from '../format.ts';
	import { pending, sendMessage } from '../messages.svelte.ts';
	import { closeTask } from '../nav.ts';
	import { flash, store } from '../store.svelte.ts';
	import Composer from './Composer.svelte';
	import Modal from './Modal.svelte';
	import Thread from './Thread.svelte';

	let { taskID }: { taskID: string } = $props();

	const now = new Date();
	const snap = $derived(store.snap!);
	const me = $derived(snap.currentUserID);
	const task = $derived(snap.tasks.find((t) => t.id === taskID));
	const project = $derived(snap.projects.find((p) => p.id === task?.projectID));
	const user = (id: string) => snap.users.find((u) => u.id === id);
	const name = (id: string) => userName(snap, id);
	const lower = (id: string) => (id === me ? 'kamu' : name(id));
	const subs = $derived(task?.submissions ?? []);
	const last = $derived(subs.at(-1));
	const thread = $derived(snap.messages.filter((m) => m.taskID === taskID));
	const comments = $derived(thread.filter((m) => m.kind === 'text').length);
	const readOnly = $derived(project?.status !== 'active');
	const waitHours = $derived(Math.floor((now.getTime() - new Date(last?.createdAt ?? now).getTime()) / 3_600_000));

	type Tab = 'overview' | 'submission' | 'discussion';
	let tab = $state<Tab>('overview');
	let body = $state<HTMLDivElement>();

	// Tombol utama atau keterangan di bawah drawer, sesuai peran dan status (desain taskVals).
	const footer = $derived.by((): { cta?: { label: string; icon: string; run: () => void }; info?: string; icon?: string } => {
		if (!task || !project) return {};
		if (project.status === 'archived') return { info: 'Proyek diarsipkan · tugas hanya bisa dilihat', icon: 'inventory_2' };
		if (project.status === 'completed') return { info: 'Proyek selesai · tugas hanya bisa dilihat', icon: 'task_alt' };
		const mine = task.assigneeID === me;
		if (mine && task.status === 'todo') return { cta: { label: 'Mulai kerjakan', icon: 'play_arrow', run: start } };
		if (mine && task.status === 'in_progress') return { cta: { label: 'Kirim hasil', icon: 'upload', run: openSubmit } };
		if (mine && task.status === 'needs_revision') return { cta: { label: 'Kirim revisi', icon: 'upload', run: openSubmit } };
		if (task.reviewerID === me && task.status === 'in_review')
			return { cta: { label: `Review revisi ${subs.length}`, icon: 'rate_review', run: openReview } };
		if (task.status === 'done') return { info: `Disetujui oleh ${lower(last?.reviewerID || task.reviewerID)}`, icon: 'check_circle' };
		if (task.status === 'in_review') return { info: `Menunggu review dari ${lower(task.reviewerID)}`, icon: 'hourglass_top' };
		if (task.status === 'needs_revision') return { info: `Menunggu revisi dari ${lower(task.assigneeID)}`, icon: 'hourglass_top' };
		if (task.status === 'in_progress') return { info: `Sedang dikerjakan ${lower(task.assigneeID)}`, icon: 'autorenew' };
		return { info: `Belum dimulai oleh ${lower(task.assigneeID)}`, icon: 'hourglass_top' };
	});

	let modal = $state<'submit' | 'review' | null>(null);
	let note = $state('');
	let links = $state<string[]>(['']);
	let changes = $state(false);
	let feedback = $state('');
	let error = $state('');

	async function start() {
		try {
			await store.mutate('startTask', { id: task!.id, expectedVersion: task!.version });
			flash('Tugas dimulai. Semangat!');
		} catch (e) {
			flash((e as Error).message, 'err');
		}
	}
	function openSubmit() {
		note = error = '';
		links = [''];
		modal = 'submit';
	}
	function openReview() {
		feedback = error = '';
		changes = false;
		modal = 'review';
	}

	// Aturan server: maksimal 5 link https lengkap, tanpa kredensial (@), maksimal 2048 karakter.
	const validLink = (url: string) => {
		try {
			const u = new URL(url);
			return u.protocol === 'https:' && !!u.hostname.includes('.') && !url.includes('@') && url.length <= 2048;
		} catch {
			return false;
		}
	};

	async function submit() {
		error = '';
		const text = note.trim();
		const list = links.map((l) => l.trim()).filter(Boolean);
		if (!text) return void (error = 'Tulis catatan singkat tentang yang kamu kerjakan.');
		if (list.some((l) => !validLink(l))) return void (error = 'Link harus diawali https:// dan berupa alamat lengkap.');
		try {
			await store.mutate('submitWork', { taskID: task!.id, expectedVersion: task!.version, note: text, links: list });
			modal = null;
			tab = 'submission';
			flash(`Terkirim. ${name(task!.reviewerID)} akan diberi tahu.`);
		} catch (e) {
			const failure = e as Error & { code?: string };
			error =
				failure.code === 'stale_version'
					? 'Tugas ini sudah berubah. Tutup lalu buka lagi untuk melihat status terbaru.'
					: failure.message;
		}
	}

	async function review(approve: boolean) {
		error = '';
		const text = feedback.trim();
		if (!approve && !text) return void (error = 'Jelaskan apa yang perlu diubah.');
		try {
			await store.mutate('review', { taskID: task!.id, approve, feedback: approve ? '' : text, expectedVersion: task!.version });
			modal = null;
			flash(approve ? 'Disetujui. Tugas selesai.' : `Revisi diminta. ${name(task!.assigneeID)} akan diberi tahu.`);
		} catch (e) {
			const failure = e as Error & { code?: string };
			error =
				failure.code === 'stale_version' || failure.code === 'already_reviewed'
					? 'Tugas ini sudah direview atau berubah status.'
					: failure.message;
		}
	}

	// Diskusi: gulir ke pesan terbaru saat dibuka atau ada pesan baru.
	$effect(() => {
		if (tab !== 'discussion') return;
		thread.length;
		pending.length;
		queueMicrotask(() => body?.scrollTo({ top: body.scrollHeight }));
	});

	let closeButton = $state<HTMLButtonElement>();
	$effect(() => {
		closeButton?.focus();
	});
</script>

<svelte:window
	onkeydown={(e) => {
		// Esc menutup drawer kecuali ada dialog atau menu yang sedang terbuka di atasnya.
		if (e.key === 'Escape' && !modal && !document.querySelector('dialog[open], [role=menu]')) closeTask();
	}}
/>

<button class="scrim" aria-label="Tutup detail tugas" tabindex="-1" onclick={() => closeTask()}></button>
<div class="drawer" role="dialog" aria-modal="true" aria-label={task?.title ?? 'Detail tugas'}>
	{#if !task || !project}
		<div class="head">
			<div class="chips"><b>Tugas tidak ditemukan</b></div>
			<button class="close" bind:this={closeButton} aria-label="Tutup (Esc)" onclick={() => closeTask()}><Icon name="close" size={21} /></button>
		</div>
		<p class="gone">Mungkin tugas ini dihapus atau kamu sudah tidak menjadi anggota grupnya.</p>
	{:else}
		<div class="head">
			<div class="top">
				<div class="chips">
					<span class="chip big" style:background={STATUS[task.status].bg}><Icon name={STATUS[task.status].icon} size={17} />{STATUS[task.status].label}</span>
					{#if isOverdue(new Date(task.dueAt), task.status, now)}<span class="chip big flag" style="background:var(--coral)"><Icon name="error" size={17} />Terlambat</span>{/if}
					{#if task.status === 'in_review' && waitHours > 48}<span class="chip big flag" style="background:var(--lavender)"><Icon name="pending_actions" size={17} />Menunggu {waitHours} jam</span>{/if}
				</div>
				<button class="close" bind:this={closeButton} aria-label="Tutup (Esc)" title="Tutup (Esc)" onclick={() => closeTask()}><Icon name="close" size={21} /></button>
			</div>
			<h2>{task.title}</h2>
			<a class="project" href="/app/proyek/{project.id}"><Icon name="folder" size={17} />{project.title}<Icon name="chevron_right" size={17} /></a>
			<div class="tabs" role="tablist">
				{#each [['overview', 'Ringkasan', 0], ['submission', 'Hasil kerja', subs.length], ['discussion', 'Diskusi', comments]] as const as [key, label, count] (key)}
					<button role="tab" aria-selected={tab === key} class:on={tab === key} onclick={() => (tab = key)}>
						{label}{#if count && key !== 'overview'}<span class="count">{count}</span>{/if}
					</button>
				{/each}
			</div>
		</div>

		<div class="body" bind:this={body}>
			{#if tab === 'overview'}
				<div class="stack">
					{#if task.status === 'needs_revision' && last?.feedback}
						<div class="feedback">
							<b><Icon name="undo" size={18} />{name(last.reviewerID)} meminta revisi</b>
							<span>{last.feedback}</span>
						</div>
					{/if}
					<div class="facts">
						{#each [['Pelaksana', task.assigneeID], ['Reviewer', task.reviewerID]] as [label, id] (label)}
							<div class="fact">
								<span class="av" style="--s:36px;font-size:12px" style:background={tint(user(id)?.tint)}>{initials(user(id)?.name)}</span>
								<span class="fact-text"><small>{label}</small><b>{name(id)}</b></span>
							</div>
						{/each}
						<div class="fact">
							<span class="fact-icon"><Icon name="schedule" size={19} /></span>
							<span class="fact-text"><small>Deadline</small><b>{dueLabel(new Date(task.dueAt), task.status, now)}</b></span>
						</div>
						<div class="fact">
							<span class="fact-icon"><Icon name="history" size={19} /></span>
							<span class="fact-text"><small>Hasil kerja</small><b>{subs.length ? `Revisi ${subs.length}` : 'Belum ada'}</b></span>
						</div>
					</div>
					<div class="desc">
						<span class="label">Deskripsi</span>
						<p>{task.description || 'Belum ada deskripsi.'}</p>
					</div>
					<button class="discuss" onclick={() => (tab = 'discussion')}>
						<span class="discuss-icon"><Icon name="forum" size={21} /></span>
						<span class="discuss-text"><b>Diskusi tugas ini</b><small>{comments} komentar · terpisah dari chat grup</small></span>
						<Icon name="chevron_right" size={22} />
					</button>
				</div>
			{:else if tab === 'submission'}
				<div class="stack">
					{#each [...subs].reverse() as s (s.id)}
						{@const awaiting = !s.decision && s.revision === subs.length && task.status === 'in_review'}
						{@const chip = s.decision === 'approved' ? ['Disetujui', 'var(--mint)', 'check_circle'] : s.decision ? ['Perlu revisi', 'var(--coral)', 'undo'] : [awaiting ? 'Menunggu review' : 'Terkirim', 'var(--lavender)', 'visibility']}
						<div class="sub">
							<div class="sub-head">
								<span class="sub-title"><b>Revisi {s.revision}</b><small>{name(s.authorID)} · {new Date(s.createdAt).toLocaleString('id-ID', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).replace('.', ':')}</small></span>
								<span class="chip sub-chip" style:background={chip[1]}><Icon name={chip[2]} size={16} />{chip[0]}</span>
							</div>
							<p>{s.note}</p>
							{#each s.links as l (l)}
								<a class="link" href={l} target="_blank" rel="noopener noreferrer"><Icon name="link" size={18} /><span>{l.replace('https://', '')}</span><Icon name="open_in_new" size={17} /></a>
							{/each}
							{#if s.feedback}
								<div class="note"><small>Catatan {name(s.reviewerID)}</small><span>{s.feedback}</span></div>
							{/if}
							{#if awaiting && task.reviewerID !== me}
								<div class="note lock">
									<Icon name="lock" size={17} />{task.assigneeID === me ? 'Kamu tidak bisa menyetujui hasil kerjamu sendiri.' : `Hanya ${name(task.reviewerID)} yang bisa mereview.`}
								</div>
							{/if}
						</div>
					{:else}
						<div class="empty">
							<span class="empty-icon"><Icon name="inventory_2" size={25} /></span>
							<b>Belum ada hasil kerja</b>
							<span>Pelaksana mengirim catatan dan maksimal 5 link https. Semua revisi tersimpan di sini.</span>
						</div>
					{/each}
				</div>
			{:else}
				<span class="hint">Komentar di sini hanya untuk tugas ini.</span>
				{#if thread.length || pending.some((p) => p.taskID === taskID)}
					<Thread {snap} messages={thread} pending={pending.filter((p) => p.taskID === taskID)} />
				{:else}
					<div class="start">
						<b>Mulai diskusi</b>
						<span>Pertanyaan soal tugas ini tetap di sini, tidak tenggelam di chat grup.</span>
					</div>
				{/if}
			{/if}
		</div>

		<div class="foot">
			{#if tab === 'discussion'}
				{#if readOnly}
					<div class="readonly"><Icon name="lock" size={18} />{project.status === 'archived' ? 'Diskusi hanya-baca karena proyek diarsipkan.' : 'Diskusi hanya-baca karena proyek sudah selesai.'}</div>
				{:else}
					<Composer placeholder="Komentari tugas ini…" onsend={(text) => sendMessage(project.groupID, task.id, text)} />
				{/if}
			{:else if footer.cta}
				<button class="cta" disabled={store.busy} onclick={footer.cta.run}>
					{#if store.busy}<span class="spin" aria-hidden="true"></span>{:else}<Icon name={footer.cta.icon} size={21} />{/if}{footer.cta.label}
				</button>
			{:else if footer.info}
				<div class="info"><Icon name={footer.icon ?? 'info'} size={19} />{footer.info}</div>
			{/if}
		</div>
	{/if}
</div>

{#if modal === 'submit' && task}
	<Modal title={task.status === 'needs_revision' ? 'Kirim revisi' : 'Kirim hasil'} sub="{task.title} · {name(task.reviewerID)} akan diberi tahu untuk mereview." busy={store.busy} onclose={() => (modal = null)}>
		<form id="submit-form" class="form" onsubmit={(e) => (e.preventDefault(), submit())} novalidate>
			<label class="field">
				<span>Apa yang kamu kerjakan? <em>*</em></span>
				<textarea class="input" bind:value={note} rows="4" maxlength="1000" placeholder="Contoh: Tabel sudah 3NF, alasan dekomposisi ada di halaman 2."></textarea>
			</label>
			<div class="field">
				<span class="label-row"><span>Link (opsional)</span><small>{links.filter((l) => l.trim()).length}/5</small></span>
				{#each links as _, i (i)}
					<span class="link-field"><Icon name="link" size={18} /><input bind:value={links[i]} placeholder="https://docs.google.com/…" aria-label="Link hasil kerja {i + 1}" inputmode="url" /></span>
				{/each}
				{#if links.length < 5}
					<button type="button" class="add" onclick={() => links.push('')}><Icon name="add" size={19} />Tambah link</button>
				{/if}
			</div>
			{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		</form>
		{#snippet footer()}
			<button class="btn btn-ghost" type="button" disabled={store.busy} onclick={() => (modal = null)}>Batal</button>
			<button class="btn btn-primary" form="submit-form" disabled={store.busy}>
				{#if store.busy}<span class="spin" aria-hidden="true"></span>{/if}{store.busy ? 'Mengirim…' : 'Kirim untuk direview'}
			</button>
		{/snippet}
	</Modal>
{:else if modal === 'review' && task && last}
	<Modal title="Review hasil kerja" busy={store.busy} onclose={() => (modal = null)}>
		<div class="sub">
			<small class="muted">Revisi {last.revision} · {name(last.authorID)}</small>
			<p>{last.note}</p>
			{#each last.links as l (l)}
				<a class="link" href={l} target="_blank" rel="noopener noreferrer"><Icon name="link" size={18} /><span>{l.replace('https://', '')}</span><Icon name="open_in_new" size={17} /></a>
			{/each}
		</div>
		{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		{#if !changes}
			<div class="review-actions">
				<button class="btn btn-ghost outline" onclick={() => ((changes = true), (error = ''))}><Icon name="undo" size={20} />Minta revisi</button>
				<button class="btn btn-primary" disabled={store.busy} onclick={() => review(true)}>
					{#if store.busy}<span class="spin" aria-hidden="true"></span>{:else}<Icon name="check_circle" size={20} />{/if}{store.busy ? 'Menyimpan…' : 'Setujui'}
				</button>
			</div>
		{:else}
			<form class="form" onsubmit={(e) => (e.preventDefault(), review(false))} novalidate>
				<label class="field">
					<span>Apa yang perlu diubah? <em>*</em></span>
					<textarea class="input" bind:value={feedback} rows="3" maxlength="1000" placeholder="Spesifik dan ramah, misal: pisahkan Fine jadi entity sendiri."></textarea>
				</label>
				<div class="review-actions end">
					<button type="button" class="btn btn-ghost" onclick={() => ((changes = false), (error = ''))}>Kembali</button>
					<button class="btn btn-primary" disabled={store.busy}>{store.busy ? 'Mengirim…' : `Kirim ke ${name(task.assigneeID)}`}</button>
				</div>
			</form>
		{/if}
	</Modal>
{/if}

<style>
	.scrim {
		position: fixed;
		inset: 0;
		z-index: 40;
		border: none;
		background: light-dark(rgba(20, 22, 24, 0.16), rgba(0, 0, 0, 0.45));
		cursor: default;
		animation: fade 0.2s ease;
	}
	.drawer {
		position: fixed;
		top: 0;
		right: 0;
		bottom: 0;
		z-index: 41;
		width: 580px;
		max-width: calc(100% - 96px);
		background: var(--background);
		border-left: 1px solid var(--border);
		box-shadow: -30px 0 60px -24px rgba(0, 0, 0, 0.3);
		display: flex;
		flex-direction: column;
		animation: slide 0.26s cubic-bezier(0.2, 0.9, 0.3, 1);
	}
	@keyframes slide {
		from {
			transform: translateX(40px);
			opacity: 0;
		}
	}
	.head {
		flex: none;
		padding: 16px 20px 12px 24px;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.top {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.chips {
		flex: 1;
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}
	.chip.big {
		height: 30px;
		padding: 0 12px 0 9px;
		gap: 5px;
		font-size: 13px;
		align-self: center;
		transition: background 0.3s;
	}
	.flag {
		box-shadow: inset 0 0 0 1.5px var(--ink);
	}
	.close {
		flex: none;
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 50%;
		background: var(--chip);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	h2 {
		margin: 0;
		font-size: 26px;
		font-weight: 700;
		letter-spacing: -0.025em;
		line-height: 1.15;
		text-wrap: pretty;
	}
	.project {
		align-self: flex-start;
		height: 30px;
		padding: 0 6px;
		margin-left: -6px;
		border-radius: 10px;
		display: flex;
		align-items: center;
		gap: 4px;
		font-size: 14px;
		color: var(--text3);
	}
	.project:hover {
		background: var(--chip);
	}
	.tabs {
		display: flex;
		gap: 2px;
		padding: 4px;
		border-radius: 16px;
		background: var(--chip);
	}
	.tabs button {
		flex: 1;
		min-width: 0;
		height: 38px;
		border: none;
		border-radius: 12px;
		background: transparent;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		font-size: 14px;
		font-weight: 600;
		transition: background 0.15s;
	}
	.tabs .on {
		background: light-dark(var(--surface), #3b3f43);
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
	}
	.count {
		min-width: 20px;
		height: 20px;
		padding: 0 6px;
		border-radius: 10px;
		background: var(--lavender);
		font-size: 12px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.body {
		flex: 1;
		min-height: 0;
		overflow: auto;
		padding: 4px 24px 20px;
	}
	.stack {
		display: flex;
		flex-direction: column;
		gap: 12px;
		animation: fade 0.2s ease;
	}
	.feedback {
		background: var(--coral);
		border-radius: 20px;
		padding: 14px 16px;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.feedback b {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 14px;
	}
	.feedback span {
		font-size: 15px;
		line-height: 1.45;
	}
	.facts {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 10px;
	}
	.fact {
		background: var(--surface);
		border-radius: 18px;
		padding: 12px 14px;
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.fact-icon {
		flex: none;
		width: 36px;
		height: 36px;
		border-radius: 50%;
		background: var(--muted);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.fact-text {
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	.fact-text small {
		font-size: 12px;
		color: var(--secondary);
	}
	.fact-text b {
		font-size: 15px;
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.desc {
		background: var(--surface);
		border-radius: 20px;
		padding: 16px 18px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.label {
		font-size: 12px;
		font-weight: 700;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--text2);
	}
	.desc p,
	.sub p {
		margin: 0;
		font-size: 15px;
		line-height: 1.55;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	.discuss {
		text-align: left;
		border: none;
		background: var(--lavender);
		border-radius: 20px;
		padding: 14px 16px;
		display: flex;
		align-items: center;
		gap: 12px;
		transition: filter 0.15s;
	}
	.discuss:hover {
		filter: brightness(0.98);
	}
	.discuss-icon {
		flex: none;
		width: 40px;
		height: 40px;
		border-radius: 14px;
		box-shadow: inset 0 0 0 1.5px var(--ink);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.discuss-text {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.discuss-text b {
		font-size: 15px;
		font-weight: 600;
	}
	.discuss-text small {
		font-size: 13px;
		color: var(--text3);
	}
	.sub {
		background: var(--surface);
		border-radius: 20px;
		padding: 16px 18px;
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.sub-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 8px;
		flex-wrap: wrap;
	}
	.sub-title {
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.sub-title b {
		font-size: 16px;
	}
	.sub-title small,
	.muted {
		font-size: 13px;
		color: var(--secondary);
	}
	.sub-chip {
		height: 28px;
		padding: 0 11px 0 8px;
		gap: 4px;
		font-size: 12px;
		align-self: center;
	}
	.link {
		min-height: 42px;
		padding: 0 12px;
		border-radius: 14px;
		background: var(--muted);
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 14px;
		font-weight: 500;
		transition: background 0.15s;
	}
	.link:hover {
		background: var(--border);
	}
	.link span {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.note {
		border-top: 1px solid var(--border);
		padding-top: 12px;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.note small {
		font-size: 13px;
		font-weight: 600;
		color: var(--secondary);
	}
	.note span {
		font-size: 15px;
		line-height: 1.45;
	}
	.note.lock {
		flex-direction: row;
		align-items: center;
		gap: 8px;
		font-size: 13px;
		color: var(--text3);
	}
	.empty,
	.start {
		border-radius: 20px;
		padding: 28px 20px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		text-align: center;
	}
	.empty {
		background: var(--surface);
	}
	.empty-icon {
		width: 50px;
		height: 50px;
		border-radius: 18px;
		background: var(--butter);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.empty b,
	.start b {
		font-size: 16px;
		font-weight: 600;
	}
	.empty span:not(.empty-icon),
	.start span {
		font-size: 14px;
		line-height: 1.5;
		color: var(--secondary);
	}
	.hint {
		display: block;
		padding: 2px 0 4px;
		font-size: 13px;
		color: var(--secondary);
	}
	.foot {
		flex: none;
		padding: 12px 24px 20px;
		border-top: 1px solid var(--border);
	}
	.cta {
		width: 100%;
		height: 52px;
		border: none;
		border-radius: 18px;
		background: var(--ink);
		color: var(--on-ink);
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		font-size: 16px;
		font-weight: 600;
		animation: up 0.2s ease both;
	}
	.cta:active {
		transform: scale(0.99);
	}
	.cta:disabled {
		opacity: 0.6;
	}
	.info {
		min-height: 50px;
		padding: 8px 16px;
		border-radius: 18px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		font-size: 14px;
		font-weight: 500;
		text-align: center;
	}
	.readonly {
		min-height: 44px;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		font-size: 14px;
		color: var(--text3);
	}
	.gone {
		padding: 0 24px;
		color: var(--secondary);
	}
	.form {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	.label-row {
		display: flex;
		justify-content: space-between;
	}
	em {
		font-style: normal;
		color: var(--danger);
	}
	.link-field {
		height: 46px;
		padding: 0 12px;
		border-radius: 14px;
		background: var(--surface);
		box-shadow: inset 0 0 0 1px var(--border);
		display: flex;
		align-items: center;
		gap: 8px;
		color: var(--secondary);
	}
	.link-field input {
		flex: 1;
		min-width: 0;
		border: none;
		outline: none;
		background: none;
		font: inherit;
		font-size: 15px;
		font-weight: 500;
		color: var(--ink);
	}
	.add {
		align-self: flex-start;
		height: 36px;
		border: none;
		background: none;
		padding: 0;
		display: flex;
		align-items: center;
		gap: 4px;
		font-size: 14px;
		font-weight: 600;
	}
	.review-actions {
		display: flex;
		gap: 10px;
	}
	.review-actions > .btn {
		flex: 1;
	}
	.review-actions.end {
		justify-content: flex-end;
	}
	.review-actions.end > .btn {
		flex: none;
	}
	.outline {
		box-shadow: inset 0 0 0 1.5px var(--ink);
	}
</style>
