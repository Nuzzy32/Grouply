import { defineEnvVars } from '@sveltejs/kit/env';

// Nilai publik (boleh sampai ke browser), dibaca dari web/.env. Lihat .env.example.
export const variables = defineEnvVars({
	PUBLIC_SUPABASE_URL: { public: true, static: true, description: 'URL API Supabase' },
	PUBLIC_SUPABASE_PUBLISHABLE_KEY: {
		public: true,
		static: true,
		description: 'Publishable key Supabase, bukan secret key',
		schema: (value) => {
			if (!value) throw new Error('PUBLIC_SUPABASE_PUBLISHABLE_KEY belum diisi di web/.env.');
			// Secret key memberi akses penuh tanpa RLS dan tidak boleh sampai ke browser.
			if (value.startsWith('sb_secret_')) throw new Error('Pakai publishable key, bukan secret key.');
			return value;
		}
	}
});
