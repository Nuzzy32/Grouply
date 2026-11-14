<script lang="ts">
	import Icon from '#lib/Icon.svelte';
	import { userName } from '../derive.ts';
	import { dateInput, dueFromInput, initials, tint } from '../format.ts';
	import { canManageTasks } from '../project.ts';
	import { ask, flash, store } from '../store.svelte.ts';
	import type { Project, Task } from '../types.ts';
	import DueField from './DueField.svelte';
	import Menu from './Menu.svelte';
	import Modal from './Modal.svelte';

	let { task, project }: { task: Task; project: Project } = $props();

	const snap = $derived(store.snap!);
	const group = $derived(snap.groups.find((g) => g.id === project.groupID)!);
	const name = (id: string) => userName(snap, id);
	const user = (id: string) => snap.users.find((u) => u.id === id);
	const manager = $derived(canManageTasks(snap, project));
	const active = $derived(project.status === 'active' && !group.closed);

	// Alasan gembok, urutan dan teks sama dengan _taskEditLock / reassign di Flutter.
	const editLock = $derived.by(() => {
		if (!manager) return 'Hanya koordinator atau koordinator sie yang bisa mengedit detail tugas.';
		if (project.status === 'archived') return 'Proyek ini telah diarsipkan. Pulihkan proyek dulu untuk mengedit tugas.';
		if (project.status === 'completed') return 'Proyek ini sudah selesai. Buka kembali proyek untuk mengedit tugas.';
		if (task.status === 'in_review') return 'Edit dikunci sementara karena hasil pekerjaan sedang diperiksa. Coba lagi setelah review selesai.';
		if (task.status === 'done') return 'Tugas yang sudah disetujui tidak bisa diedit.';
		return '';
	});
	const reassignLock = $derived.by(() => {
		if (!active) return 'Proyek tidak aktif. Buka kembali atau pulihkan proyek untuk mengubah tugas.';
		if (!manager) return 'Hanya koordinator atau koordinator sie yang bisa mengalihkan tugas.';
		if (task.status === 'in_review') return 'Tugas ini tidak dapat dialihkan karena hasil pekerjaan sedang diperiksa. Selesaikan atau batalkan proses review terlebih dahulu.';
		if (task.status === 'done') return 'Tugas yang sudah disetujui tidak bisa dialihkan.';
		return '';
	});
	// Akun terhapus meninggalkan ID kosong; tugas seperti itu tidak bisa dibuka kembali.
	const deletedPeople = $derived(!task.assigneeID || !task.reviewerID);
	const canReopen = $derived(manager && active && task.status === 'done' && !deletedPeople);

	const items = $derived([
		{ label: 'Edit tugas', sub: 'Judul, deskripsi, deadline, reviewer', icon: 'edit', run: openEdit, locked: editLock || undefined },
		{
			label: 'Alihkan pelaksana',
			sub: reassignLock ? undefined : 'Pilih anggota lain',
			icon: 'swap_horiz',
			run: openReassign,
			locked: reassignLock || undefined
		},
		...(canReopen ? [{ label: 'Buka kembali tugas', sub: 'Riwayat hasil dan review tetap disimpan', icon: 'replay', run: reopen }] : [])
	]);

	let modal = $state<'edit' | 'reassign' | null>(null);
	let error = $state('');
	let title = $state('');
	let description = $state('');
	let reviewer = $state('');
	let due = $state('');
	let assignee = $state('');
	let newReviewer = $state('');

	function openEdit() {
		title = task.title;
		description = task.description;
		reviewer = task.reviewerID;
		due = dateInput(new Date(task.dueAt));
		error = '';
		modal = 'edit';
	}
	function openReassign() {
		assignee = '';
		newReviewer = '';
		error = '';
		modal = 'reassign';
	}

	const lateWarning = $derived(dueFromInput(due) && dueFromInput(due)! > new Date(project.dueAt));

	async function saveEdit() {
		error = '';
		const text = title.trim();
		const desc = description.trim();
		const unchangedDue = due === dateInput(new Date(task.dueAt));
		const at = dueFromInput(due);
		const now = new Date();
		const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
		if (!text) return void (error = 'Judul tugas wajib diisi.');
		if (text.length > 120) return void (error = 'Judul tugas maksimal 120 karakter.');
		if (desc.length > 2000) return void (error = 'Deskripsi maksimal 2000 karakter.');
		if (!group.memberIDs.includes(reviewer)) return void (error = 'Reviewer harus anggota aktif grup.');
		if (reviewer === task.assigneeID) return void (error = 'Reviewer harus berbeda dari pelaksana.');
		if (!at || (!unchangedDue && at < today)) return void (error = 'Pilih deadline yang valid, mulai hari ini.');
		if (text === task.title && desc === task.description && reviewer === task.reviewerID && unchangedDue) {
			modal = null;
			return flash('Tidak ada perubahan', 'info');
		}
		try {
			await store.mutate('updateTask', {
				id: task.id,
				expectedVersion: task.version,
				title: text,
				description: desc,
				reviewerID: reviewer,
				dueAt: (unchangedDue ? new Date(task.dueAt) : at).toISOString()
			});
			modal = null;
			flash('Tugas diperbarui');
		} catch (e) {
			error = (e as Error).message;
		}
	}

	async function saveReassign() {
		error = '';
		if (!assignee) return void (error = 'Pilih pelaksana baru.');
		const reviewerID = assignee === task.reviewerID ? newReviewer : task.reviewerID;
		if (!reviewerID || reviewerID === assignee) return void (error = 'Pilih reviewer lain supaya pelaksana dan reviewer tetap berbeda.');
		if (task.status === 'needs_revision') {
			const ok = await ask({
				title: 'Alihkan tugas revisi?',
				text: 'Tugas ini memiliki riwayat revisi. Pelaksana baru akan melanjutkan pekerjaan tanpa menghapus hasil sebelumnya.',
				ok: 'Alihkan'
			});
			if (!ok) return;
		}
		// Hitung teks sebelum mutasi: setelahnya `task` sudah berisi reviewer baru dari snapshot.
		const done = `Pelaksana diganti ke ${name(assignee)}${reviewerID !== task.reviewerID ? ` · reviewer ${name(reviewerID)}` : ''}`;
		try {
			await store.mutate('reassignTask', { id: task.id, expectedVersion: task.version, assigneeID: assignee, reviewerID });
			modal = null;
			flash(done);
		} catch (e) {
			error = (e as Error).message;
		}
	}

	async function reopen() {
		const ok = await ask({ title: 'Buka kembali tugas?', text: 'Riwayat hasil dan keputusan review tetap disimpan.', ok: 'Buka kembali' });
		if (!ok) return;
		try {
			await store.mutate('reopenTask', { id: task.id, expectedVersion: task.version });
			flash('Tugas dibuka kembali');
		} catch (e) {
			flash((e as Error).message, 'err');
		}
	}

	const roleLabel = (id: string) =>
		id === task.assigneeID ? 'Pelaksana saat ini' : id === task.reviewerID ? 'Reviewer saat ini · perlu reviewer pengganti' : id === group.coordinatorID ? 'Koordinator' : 'Anggota';
</script>

{#snippet person(id: string, on: boolean, disabled: boolean, pick: () => void, sub = '')}
	<button type="button" class="person" class:on aria-pressed={on} {disabled} onclick={pick}>
		<span class="av" style="--s:32px;font-size:11px" style:background={tint(user(id)?.tint)}>{initials(user(id)?.name)}</span>
		<span class="p-text"><b>{name(id)}</b>{#if sub}<small>{sub}</small>{/if}</span>
	</button>
{/snippet}

<Menu label="Opsi tugas" {items} />

{#if modal === 'edit'}
	<Modal title="Edit tugas" sub={project.title} width={600} busy={store.busy} onclose={() => (modal = null)}>
		<form id="edit-task" class="form" onsubmit={(e) => (e.preventDefault(), saveEdit())} novalidate>
			<label class="field">
				<span class="label-row"><span>Judul <em>*</em></span><small>{title.trim().length}/120</small></span>
				<input class="input" bind:value={title} maxlength="120" />
			</label>
			<label class="field">
				Deskripsi
				<textarea class="input" bind:value={description} rows="3" maxlength="2000"></textarea>
			</label>
			<div class="field">
				<span>Pelaksana</span>
				<p class="hint">{name(task.assigneeID)} (ubah lewat Alihkan pelaksana)</p>
			</div>
			<div class="field">
				<span>Reviewer <em>*</em></span>
				<div class="people">
					{#each group.memberIDs.filter((id) => id !== task.assigneeID) as id (id)}
						{@render person(id, reviewer === id, false, () => (reviewer = id))}
					{/each}
				</div>
			</div>
			<div class="field">
				<span>Deadline <em>*</em></span>
				<DueField bind:value={due} />
				{#if lateWarning}<div class="notice warn"><Icon name="warning" size={18} />Deadline tugas melewati deadline proyek. Tetap bisa disimpan, pastikan ini disengaja.</div>{/if}
			</div>
			{#if task.status === 'needs_revision'}<p class="hint">Riwayat hasil kerja dan review tetap tersimpan.</p>{/if}
			{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		</form>
		{#snippet footer()}
			<button class="btn btn-ghost" type="button" disabled={store.busy} onclick={() => (modal = null)}>Batal</button>
			<button class="btn btn-primary" form="edit-task" disabled={store.busy}>{store.busy ? 'Menyimpan…' : 'Simpan perubahan'}</button>
		{/snippet}
	</Modal>
{:else if modal === 'reassign'}
	<Modal title="Alihkan pelaksana" sub={task.title} width={560} busy={store.busy} onclose={() => (modal = null)}>
		<div class="list">
			{#each group.memberIDs as id (id)}
				{@render person(id, assignee === id, id === task.assigneeID, () => (assignee = id), roleLabel(id))}
			{/each}
		</div>
		{#if assignee && assignee === task.reviewerID}
			<div class="field">
				<span>Pilih reviewer baru</span>
				<p class="hint">{name(task.reviewerID)} saat ini reviewer tugas ini. Pilih reviewer lain supaya pelaksana dan reviewer tetap berbeda.</p>
				<div class="people">
					{#each group.memberIDs.filter((id) => id !== assignee) as id (id)}
						{@render person(id, newReviewer === id, false, () => (newReviewer = id))}
					{/each}
				</div>
			</div>
		{/if}
		<p class="hint">
			<!-- Server mengembalikan status ke Belum dimulai kecuali tugas revisi (mutate_workflow reassignTask). -->
			{task.status === 'needs_revision'
				? 'Tugas ini punya riwayat revisi. Hasil kerja dan catatan review sebelumnya tetap tersimpan untuk pelaksana baru.'
				: task.status === 'in_progress'
					? 'Status kembali ke Belum dimulai supaya pelaksana baru memulainya sendiri. Riwayat pesan dan hasil kerja tetap tersimpan.'
					: 'Riwayat pesan dan hasil kerja tetap tersimpan.'}
		</p>
		{#if error}<div class="notice error" role="alert">{error}</div>{/if}
		{#snippet footer()}
			<button class="btn btn-ghost" disabled={store.busy} onclick={() => (modal = null)}>Batal</button>
			<button class="btn btn-primary" disabled={store.busy} onclick={saveReassign}>{store.busy ? 'Menyimpan…' : 'Alihkan'}</button>
		{/snippet}
	</Modal>
{/if}

<style>
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
	.hint {
		margin: 0;
		font-size: 14px;
		font-weight: 500;
		line-height: 1.5;
		color: var(--text2);
	}
	.people {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}
	.list {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.person {
		min-height: 44px;
		padding: 4px 14px 4px 4px;
		border-radius: 22px;
		border: 1.5px solid var(--ink);
		background: transparent;
		display: flex;
		align-items: center;
		gap: 8px;
		text-align: left;
		transition: background 0.15s;
	}
	.list .person {
		border-radius: 16px;
		border-color: var(--border);
		background: var(--surface);
	}
	.person.on,
	.list .person.on {
		background: var(--ink);
		border-color: var(--ink);
		color: var(--on-ink);
	}
	.person:disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}
	.p-text {
		display: flex;
		flex-direction: column;
	}
	.p-text b {
		font-size: 14px;
		font-weight: 600;
	}
	.p-text small {
		font-size: 12px;
		opacity: 0.75;
	}
	.notice.warn {
		display: flex;
		gap: 8px;
		align-items: flex-start;
		background: var(--butter);
	}
</style>
