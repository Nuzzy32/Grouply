import type { RealtimeChannel } from '@supabase/supabase-js';
import { AppError, authError, serverError } from './errors.ts';
import { supabase } from './supabase.ts';
import type { Snapshot } from './types.ts';

/**
 * Jembatan ke server, sama seperti GrouplyStore di Flutter: semua data dari grouply_snapshot,
 * semua perubahan lewat grouply_mutate lalu snapshot diambil ulang. Tidak ada mutasi lokal.
 */
class Store {
	snap = $state<Snapshot | null>(null);
	userID = $state('');
	/** Sesi tersimpan sudah diperiksa (boleh memutuskan arahkan ke /masuk). */
	ready = $state(false);
	busy = $state(false);
	/** Gagal memuat snapshot setelah masuk. */
	error = $state('');

	#channel: RealtimeChannel | null = null;
	#timer: ReturnType<typeof setTimeout> | undefined;
	#inflight: Promise<void> | null = null;
	#again = false;
	#started = false;

	init() {
		if (this.#started) return;
		this.#started = true;
		supabase.auth.onAuthStateChange((_event, session) => {
			const id = session?.user.id ?? '';
			// Callback ini tidak boleh await panggilan Supabase lain (bisa deadlock), jadi tunda.
			if (id !== this.userID) setTimeout(() => this.#switchUser(id).catch((e: Error) => (this.error = e.message)));
		});
		document.addEventListener('visibilitychange', () => {
			if (!this.userID) return;
			if (document.hidden) this.#disconnect();
			else void this.refresh().then(() => this.#connect(), () => {});
		});
		void supabase.auth.getSession().then(async ({ data }) => {
			await this.#switchUser(data.session?.user.id ?? '').catch((e: Error) => (this.error = e.message));
			this.ready = true;
		});
	}

	async #switchUser(id: string) {
		if (id === this.userID && this.snap) return;
		this.#disconnect();
		this.userID = id;
		this.snap = null;
		this.error = '';
		if (!id) return;
		await this.refresh();
		this.#connect();
	}

	/** Ambil snapshot. Panggilan yang datang saat ada request berjalan menunggu snapshot berikutnya. */
	refresh(): Promise<void> {
		if (this.#inflight) {
			this.#again = true;
			return this.#inflight;
		}
		this.#inflight = (async () => {
			try {
				do {
					this.#again = false;
					await this.#fetch();
				} while (this.#again);
			} finally {
				this.#inflight = null;
			}
		})();
		return this.#inflight;
	}

	async #fetch() {
		const actor = this.userID;
		if (!actor) return;
		const { data, error } = await supabase.rpc('grouply_snapshot');
		if (error) throw serverError(error, 'Data belum dapat dimuat. Periksa koneksi lalu coba lagi.');
		// Abaikan hasil milik sesi lama (logout atau ganti akun saat request berjalan).
		if (actor !== this.userID || (data as Snapshot).currentUserID !== actor) return;
		this.snap = data as Snapshot;
	}

	#scheduleRefresh() {
		clearTimeout(this.#timer);
		this.#timer = setTimeout(() => {
			if (this.busy) return this.#scheduleRefresh();
			void this.refresh().catch(() => {});
		}, 120);
	}

	/** Event realtime hanya sinyal; isinya diabaikan dan snapshot diambil ulang. */
	#connect() {
		const id = this.userID;
		if (!id || this.#channel || document.hidden) return;
		const ping = () => this.#scheduleRefresh();
		const mine = `user_id=eq.${id}`;
		this.#channel = supabase
			.channel(`grouply:${id}`)
			.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages' }, ping)
			.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_reads', filter: mine }, ping)
			.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'user_sync_state', filter: mine }, ping)
			.on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'user_sync_state', filter: mine }, ping)
			.subscribe((status) => {
				if (status === 'SUBSCRIBED') ping();
			});
	}

	#disconnect() {
		clearTimeout(this.#timer);
		if (this.#channel) void supabase.removeChannel(this.#channel);
		this.#channel = null;
	}

	/** Satu mutasi pada satu waktu; setelah berhasil snapshot diambil ulang. */
	async mutate<T = Record<string, unknown>>(action: string, payload: Record<string, unknown>): Promise<T> {
		if (!this.userID) throw new AppError('Masuk terlebih dahulu.');
		if (this.busy) throw new AppError('Tunggu proses sebelumnya selesai.');
		this.busy = true;
		try {
			const { data, error } = await supabase.rpc('grouply_mutate', { action, payload });
			if (error) {
				const failure = serverError(error, 'Perubahan belum terkonfirmasi. Muat ulang sebelum mencoba lagi.');
				if (failure.code === 'unauthorized') await this.#switchUser('');
				else if (failure.code === 'stale_version') void this.refresh().catch(() => {});
				throw failure;
			}
			await this.refresh().catch(() => {
				throw new AppError('Perubahan tersimpan di server, tetapi data belum termuat ulang. Jangan kirim ulang.');
			});
			return data as T;
		} finally {
			this.busy = false;
		}
	}

	async signIn(email: string, password: string) {
		const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
		if (error) throw authError(error, 'Tidak dapat masuk. Periksa akun dan koneksi.');
	}

	/** Mengembalikan false bila server meminta konfirmasi email dulu. */
	async signUp(name: string, email: string, password: string) {
		const { data, error } = await supabase.auth.signUp({
			email: email.trim(),
			password,
			options: { data: { name: name.trim() } }
		});
		if (error) throw authError(error, 'Akun belum dapat dibuat. Periksa isian dan koneksi.');
		return data.session !== null;
	}

	async sendResetCode(email: string) {
		const { error } = await supabase.auth.resetPasswordForEmail(email.trim());
		if (error) throw authError(error, 'Kode belum dapat dikirim. Coba lagi sebentar.');
	}

	async resetPassword(email: string, code: string, password: string) {
		const verified = await supabase.auth.verifyOtp({ email: email.trim(), token: code.trim(), type: 'recovery' });
		if (verified.error) throw authError(verified.error, 'Kata sandi belum dapat diubah. Periksa kode dan koneksi.');
		const updated = await supabase.auth.updateUser({ password });
		if (updated.error) {
			// Kode sudah terpakai; jangan tinggalkan sesi pemulihan yang setengah jadi.
			await supabase.auth.signOut({ scope: 'local' });
			throw authError(updated.error, 'Kata sandi belum dapat diubah. Periksa kode dan koneksi.');
		}
	}

	/** Akun terhapus tidak bisa memuat snapshot lagi, jadi tanpa refresh: langsung tutup sesi lokal. */
	async deleteAccount() {
		if (this.busy) throw new AppError('Tunggu proses sebelumnya selesai.');
		this.busy = true;
		try {
			const { error } = await supabase.rpc('grouply_mutate', { action: 'deleteAccount', payload: {} });
			if (error) throw serverError(error, 'Akun belum dapat dihapus. Periksa koneksi lalu coba lagi.');
		} finally {
			this.busy = false;
		}
		this.#disconnect();
		await supabase.auth.signOut({ scope: 'local' });
	}

	async signOut() {
		this.#disconnect();
		const { error } = await supabase.auth.signOut();
		if (error) {
			await supabase.auth.signOut({ scope: 'local' });
			throw new AppError('Sesi lokal ditutup; pencabutan sesi server belum terkonfirmasi.');
		}
	}
}

export const store = new Store();

type HeaderAction = { label: string; icon: string; run: () => void; locked?: string };
/** Breadcrumb dan tombol aksi di header aplikasi; diisi oleh tiap halaman. */
export const header = $state({ crumbs: [] as { label: string; href?: string }[], action: null as HeaderAction | null });

/** Toast di bawah layar (2,8 detik), seperti desain Grouply Web. */
export const toast = $state({ text: '', kind: 'ok' as 'ok' | 'err' | 'info', id: 0 });
export function flash(text: string, kind: typeof toast.kind = 'ok') {
	toast.text = text;
	toast.kind = kind;
	toast.id++;
}

type Ask = { title: string; text: string; ok?: string; destructive?: boolean; info?: boolean };
/** Dialog konfirmasi bersama (dirender di layout). `info` hanya punya tombol "Mengerti". */
export const confirmState = $state({ ask: null as Ask | null, resolve: (_ok: boolean) => {} });
export function ask(options: Ask): Promise<boolean> {
	confirmState.resolve(false);
	return new Promise((resolve) => {
		confirmState.ask = options;
		confirmState.resolve = (ok) => {
			confirmState.ask = null;
			confirmState.resolve = () => {};
			resolve(ok);
		};
	});
}
