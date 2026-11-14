<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import Icon from '#lib/Icon.svelte';
	import ThemeToggle from '#lib/ThemeToggle.svelte';
	import { store } from '#lib/app/store.svelte.ts';
	import '#lib/app/app.css';

	type Mode = 'masuk' | 'daftar' | 'lupa';
	const MIN_PASSWORD = 8;
	const EMAIL = /^\S+@\S+\.\S+$/;

	let mode = $state<Mode>(page.url.searchParams.get('mode') === 'daftar' ? 'daftar' : 'masuk');
	let name = $state('');
	let email = $state('');
	let password = $state('');
	let code = $state('');
	let codeSent = $state(false);
	let showPassword = $state(false);
	let working = $state(false);
	let error = $state('');
	let info = $state('');

	store.init();
	$effect(() => {
		if (store.ready && store.userID) void goto('/app', { replaceState: true });
	});

	const strong = $derived(password.length >= MIN_PASSWORD);
	const valid = $derived.by(() => {
		if (mode === 'masuk') return email.trim() !== '' && password !== '';
		if (mode === 'daftar') return name.trim() !== '' && EMAIL.test(email.trim()) && strong;
		return codeSent ? code.trim().length >= 6 && strong : EMAIL.test(email.trim());
	});

	function switchMode(next: Mode) {
		mode = next;
		error = '';
		info = '';
		password = '';
		code = '';
		codeSent = false;
	}

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		if (!valid || working) return;
		working = true;
		error = '';
		info = '';
		try {
			if (mode === 'masuk') await store.signIn(email, password);
			else if (mode === 'daftar') {
				const signedIn = await store.signUp(name, email, password);
				if (!signedIn) {
					switchMode('masuk');
					info = 'Akun dibuat. Buka email konfirmasi, lalu masuk.';
				}
			} else if (!codeSent) {
				await store.sendResetCode(email);
				codeSent = true;
				info = `Jika ${email.trim()} terdaftar, kode 6 digit sudah dikirim ke email itu.`;
			} else await store.resetPassword(email, code, password);
		} catch (failure) {
			error = (failure as Error).message;
		} finally {
			working = false;
		}
	}

	const titles: Record<Mode, [string, string]> = {
		masuk: ['Masuk ke GROUPLY', 'Lanjutkan kerja kelompokmu di laptop.'],
		daftar: ['Buat akun', 'Satu akun untuk iOS, Android, dan Web.'],
		lupa: ['Atur ulang kata sandi', 'Kami kirim kode 6 digit ke emailmu.']
	};
</script>

<svelte:head>
	<title>{titles[mode][0]} · GROUPLY</title>
</svelte:head>

<div class="page">
	<span class="blob" aria-hidden="true" style="left:-120px;top:-80px;background:var(--lavender)"></span>
	<span class="blob" aria-hidden="true" style="right:-100px;bottom:-120px;background:var(--mint)"></span>

	<header>
		<a href="/" class="brand"><img src="/brand.png" alt="" width="34" height="34" /><span>GROUPLY</span></a>
		<ThemeToggle />
	</header>

	<main>
		<form class="card" onsubmit={submit} novalidate>
			{#if mode !== 'lupa'}
				<div class="tabs" role="tablist" aria-label="Masuk atau daftar">
					<button type="button" role="tab" aria-selected={mode === 'masuk'} class:on={mode === 'masuk'} onclick={() => switchMode('masuk')}>Masuk</button>
					<button type="button" role="tab" aria-selected={mode === 'daftar'} class:on={mode === 'daftar'} onclick={() => switchMode('daftar')}>Daftar</button>
				</div>
			{:else}
				<button type="button" class="back" onclick={() => switchMode('masuk')}><Icon name="arrow_back" size={18} />Kembali ke masuk</button>
			{/if}

			<div class="head">
				<h1>{titles[mode][0]}</h1>
				<p>{titles[mode][1]}</p>
			</div>

			{#if info}<div class="notice" role="status">{info}</div>{/if}
			{#if error}<div class="notice error" role="alert">{error}</div>{/if}

			{#if mode === 'daftar'}
				<label class="field">
					Nama
					<input class="input" id="name" bind:value={name} autocomplete="name" maxlength="80" placeholder="Nama panggilan" />
				</label>
			{/if}

			<label class="field">
				Email
				<input
					class="input"
					type="email"
					bind:value={email}
					autocomplete="email"
					placeholder="nama@kampus.ac.id"
					disabled={mode === 'lupa' && codeSent}
				/>
			</label>

			{#if mode === 'lupa' && codeSent}
				<label class="field">
					Kode dari email
					<input class="input code" bind:value={code} inputmode="numeric" autocomplete="one-time-code" maxlength="10" placeholder="123456" />
				</label>
			{/if}

			{#if mode !== 'lupa' || codeSent}
				<div class="field">
					<label for="password">{mode === 'lupa' ? 'Kata sandi baru' : 'Kata sandi'}</label>
					<span class="password">
						<input
							id="password"
							class="input"
							type={showPassword ? 'text' : 'password'}
							bind:value={password}
							autocomplete={mode === 'masuk' ? 'current-password' : 'new-password'}
						/>
						<button type="button" class="eye" onclick={() => (showPassword = !showPassword)} aria-label={showPassword ? 'Sembunyikan kata sandi' : 'Tampilkan kata sandi'}>
							<Icon name={showPassword ? 'visibility_off' : 'visibility'} size={20} />
						</button>
					</span>
					{#if mode !== 'masuk'}<small class:ok={strong}>Minimal {MIN_PASSWORD} karakter</small>{/if}
				</div>
			{/if}

			<button class="btn btn-primary submit" disabled={!valid || working}>
				{#if working}<span class="spin" aria-hidden="true"></span>{/if}
				{mode === 'masuk' ? 'Masuk' : mode === 'daftar' ? 'Buat akun' : codeSent ? 'Simpan kata sandi' : 'Kirim kode'}
			</button>

			{#if mode === 'masuk'}
				<button type="button" class="btn btn-text" onclick={() => switchMode('lupa')}>Lupa kata sandi?</button>
			{:else if mode === 'lupa' && codeSent}
				<button type="button" class="btn btn-text" onclick={() => ((codeSent = false), (info = ''))}>Kirim ulang kode</button>
			{/if}
		</form>
	</main>
</div>

<style>
	.page {
		position: relative;
		min-height: 100dvh;
		overflow: hidden;
		display: flex;
		flex-direction: column;
	}
	.blob {
		position: absolute;
		width: 420px;
		height: 420px;
		border-radius: 50%;
		filter: blur(110px);
		opacity: 0.6;
		pointer-events: none;
	}
	header {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 20px 24px;
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 800;
		letter-spacing: 0.12em;
	}
	.brand img {
		border-radius: 11px;
	}
	main {
		position: relative;
		flex: 1;
		display: grid;
		place-items: center;
		padding: 16px 16px 64px;
	}
	.card {
		width: 100%;
		max-width: 440px;
		background: var(--background);
		border-radius: 32px;
		padding: 28px;
		display: flex;
		flex-direction: column;
		gap: 16px;
		box-shadow:
			0 40px 80px -40px rgba(30, 50, 45, 0.35),
			0 0 0 1px var(--border);
		animation: up 0.4s var(--ease-out) both;
	}
	.tabs {
		display: flex;
		padding: 4px;
		gap: 4px;
		border-radius: 16px;
		background: var(--chip);
	}
	.tabs button {
		flex: 1;
		height: 40px;
		border: none;
		border-radius: 12px;
		background: transparent;
		font-size: 14px;
		font-weight: 600;
		transition:
			background 0.15s,
			box-shadow 0.15s;
	}
	.tabs .on {
		background: var(--surface);
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
	}
	.back {
		align-self: flex-start;
		border: none;
		background: none;
		padding: 4px 0;
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 14px;
		font-weight: 600;
		color: var(--text2);
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	h1 {
		margin: 0;
		font-size: 28px;
		font-weight: 800;
		letter-spacing: -0.03em;
	}
	.head p {
		margin: 0;
		font-size: 15px;
		color: var(--text2);
	}
	.password {
		position: relative;
		display: block;
	}
	.password .input {
		padding-right: 52px;
	}
	.eye {
		position: absolute;
		right: 6px;
		top: 5px;
		width: 40px;
		height: 40px;
		border: none;
		border-radius: 50%;
		background: none;
		display: flex;
		align-items: center;
		justify-content: center;
		color: var(--secondary);
	}
	.code {
		letter-spacing: 0.3em;
		font-variant-numeric: tabular-nums;
	}
	small.ok {
		color: light-dark(#1e7a43, #6fcf97);
	}
	.submit {
		margin-top: 4px;
		width: 100%;
	}
	.btn-text {
		align-self: center;
	}
</style>
