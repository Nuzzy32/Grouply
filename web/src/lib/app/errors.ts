// Pesan sama dengan client Flutter (store.dart serverMessage dan pemetaan AuthException).
const SERVER: Record<string, string> = {
	stale_version: 'Data sudah diubah orang lain. Muat ulang lalu coba lagi.',
	forbidden: 'Kamu tidak punya izin untuk tindakan ini.',
	invalid_input: 'Data tidak valid. Periksa isian lalu coba lagi.',
	unauthorized: 'Sesi berakhir. Masuk kembali untuk melanjutkan.',
	rate_limited: 'Terlalu banyak permintaan. Coba lagi sebentar.',
	project_read_only: 'Proyek selesai atau diarsipkan hanya dapat dibaca.',
	already_reviewed: 'Hasil kerja ini sudah direview.',
	active_assignment: 'Alihkan tugas aktif dan selesaikan review yang tertunda terlebih dahulu.',
	coordinator_transfer_required: 'Serahkan peran koordinator ke anggota lain terlebih dahulu.',
	group_full: 'Grup sudah mencapai batas anggota.',
	invite_full: 'Kode undangan sudah mencapai batas pemakaian. Minta kode baru.',
	invite_expired: 'Kode undangan sudah kedaluwarsa. Minta kode baru.'
};

const AUTH: Record<string, string> = {
	user_already_exists: 'Email sudah terdaftar. Silakan masuk.',
	email_exists: 'Email sudah terdaftar. Silakan masuk.',
	weak_password: 'Kata sandi terlalu lemah. Gunakan minimal 8 karakter.',
	same_password: 'Gunakan kata sandi yang berbeda dari sebelumnya.',
	otp_expired: 'Kode salah atau kedaluwarsa. Minta kode baru.',
	email_address_invalid: 'Format email tidak valid.',
	signup_disabled: 'Pendaftaran sedang ditutup.',
	over_email_send_rate_limit: 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.',
	over_request_rate_limit: 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.',
	invalid_credentials: 'Email atau kata sandi salah.'
};

/** Error yang pesannya aman ditampilkan ke pengguna. */
export class AppError extends Error {
	constructor(
		message: string,
		readonly code = ''
	) {
		super(message);
	}
}

type Failure = { code?: string; message?: string } | null | undefined;

/** Error RPC: server melempar `raise exception '<kode>'` → code P0001, kode di message. */
export function serverError(error: Failure, fallback: string): AppError {
	const code = error?.code === 'P0001' ? (error.message ?? '') : '';
	return new AppError(SERVER[code] ?? fallback, code);
}

export function authError(error: Failure, fallback: string): AppError {
	const code = error?.code ?? '';
	return new AppError(AUTH[code] ?? fallback, code);
}
