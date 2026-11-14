<!--
	Gupy, maskot Grouply. `pose="rig"` digerakkan dari layer setiap frame (sama dengan Flutter):
	napas, goyang, ekor, kedip acak, dan lambaian. `point` melayang pelan; `celebrate` melompat saat
	diklik. Dekoratif (aria-hidden); prefers-reduced-motion = diam.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { reducedMotion } from '#lib/reveal.ts';
	import { BOXES, FEET_LINE, HOP_SECONDS, WAVE_SECONDS, hopPose, rigPose, type Layer, type Pose } from './rig.ts';

	let {
		size = 160,
		pose = 'rig',
		idle = true,
		waveOnShow = false,
		hoverWave = false
	}: {
		size?: number;
		pose?: 'rig' | 'point' | 'celebrate' | 'santai';
		/** Napas/goyang/kedip terus berjalan; false = diam kecuali saat melambai. */
		idle?: boolean;
		/** Melambai sekali saat pertama terlihat. */
		waveOnShow?: boolean;
		/** Melambai saat kursor masuk (landing). */
		hoverWave?: boolean;
	} = $props();

	let el: HTMLElement;
	let t = $state(0);
	let waveAt = $state<number | null>(null);
	let blinkAt = $state(-1);
	let blinkUntil = $state(-1);
	let hopAt = $state<number | null>(null);
	let reduce = $state(false);
	let visible = false;
	let frame = 0;
	let start = 0;
	let nextBlink = 1.4;
	let secondBlink = false;

	const now = () => (performance.now() - start) / 1000;
	const busy = () =>
		!reduce &&
		visible &&
		((pose === 'rig' && (idle || waveAt !== null || t < blinkUntil)) || hopAt !== null);

	function tick() {
		frame = 0;
		t = now();
		if (pose === 'rig' && idle && t >= nextBlink) {
			blinkAt = t;
			blinkUntil = t + 0.15;
			if (!secondBlink && Math.random() < 0.2) {
				secondBlink = true;
				nextBlink = t + 0.3;
			} else {
				secondBlink = false;
				nextBlink = t + 2.4 + Math.random() * 3.2;
			}
		}
		if (waveAt !== null && t - waveAt >= WAVE_SECONDS) waveAt = null;
		if (hopAt !== null && t - hopAt >= HOP_SECONDS) hopAt = null;
		if (busy()) frame = requestAnimationFrame(tick);
	}
	function run() {
		if (!frame && busy()) frame = requestAnimationFrame(tick);
	}
	function wave() {
		if (reduce || pose !== 'rig' || waveAt !== null) return;
		waveAt = now();
		run();
	}
	function poke() {
		if (pose === 'celebrate') {
			if (reduce || hopAt !== null) return;
			hopAt = now();
			run();
		} else wave();
	}

	onMount(() => {
		start = performance.now();
		reduce = reducedMotion();
		let waved = false;
		// Hanya bergerak saat terlihat; rAF juga berhenti sendiri saat tab disembunyikan.
		const io = new IntersectionObserver(([entry]) => {
			visible = entry.isIntersecting;
			if (visible && waveOnShow && !waved) {
				waved = true;
				wave();
			}
			run();
		});
		io.observe(el);
		return () => {
			io.disconnect();
			cancelAnimationFrame(frame);
		};
	});

	const rig = $derived(
		rigPose(reduce ? 0 : t, waveAt === null ? null : t - waveAt, idle && !reduce)
	);
	const hop = $derived(hopPose(hopAt === null ? 0 : t - hopAt));
	// Kedip tiga tahap: setengah, tutup, setengah (40 / 60 / 50 ms).
	const eyes = $derived.by((): Layer => {
		if (reduce || t >= blinkUntil) return 'mata_ramah';
		const p = t - blinkAt;
		return p >= 0.04 && p < 0.1 ? 'mata_tutup' : 'mata_setengah';
	});

	function style(name: Layer, p: Pose) {
		const [x, y, w, h] = BOXES[name];
		return (
			`left:${x}px;top:${y}px;width:${w}px;height:${h}px;` +
			`transform-origin:${p.pivot[0] - x}px ${p.pivot[1] - y}px;` +
			`transform:translate(${p.dx}px,${p.dy}px) rotate(${p.deg}deg) scale(${p.sx},${p.sy})`
		);
	}
	const src = (name: string) => `/gupy/${name}.webp`;
</script>

{#snippet arm()}
	<img alt="" src={src('lengan_bawah_kanan')} style={style('lengan_bawah_kanan', rig.lengan_bawah_kanan)} />
	<img alt="" src={src('lengan_atas_kanan')} style={style('lengan_atas_kanan', rig.lengan_atas_kanan)} />
{/snippet}

<!-- Dekoratif; klik/hover hanya memicu animasi. -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<span
	class="gupy"
	class:point={pose === 'point'}
	bind:this={el}
	aria-hidden="true"
	style="--s:{size}px;--feet:{FEET_LINE}"
	onclick={poke}
	onpointerenter={hoverWave ? wave : undefined}
>
	{#if pose === 'rig'}
		<span class="shadow"></span>
		<span class="canvas" style="transform:scale({size / 2048})">
			{#each ['ekor_ujung', 'ekor_tengah', 'ekor_pangkal'] as const as n (n)}
				<img alt="" src={src(n)} style={style(n, rig[n])} />
			{/each}
			<img alt="" src={src('badan')} style={style('badan', rig.badan)} />
			{@render arm()}
			<img alt="" src={src('lengan_bawah_kiri')} style={style('lengan_bawah_kiri', rig.lengan_bawah_kiri)} />
			<img alt="" src={src('lengan_atas_kiri')} style={style('lengan_atas_kiri', rig.lengan_atas_kiri)} />
			<img alt="" src={src('kepala')} style={style('kepala', rig.kepala)} />
			<img alt="" src={src(eyes)} style={style(eyes, rig.kepala)} />
			<img alt="" src={src(rig.mouth)} style={style(rig.mouth, rig.kepala)} />
		</span>
	{:else if pose === 'celebrate'}
		<span class="shadow" style="transform:scale({1 - 0.1 * hop.lift},{1 - 0.05 * hop.lift})"></span>
		<span
			class="whole"
			style="transform:translateY({-hop.lift * (120 / 1254) * size}px) rotate({hop.deg}deg) scale({hop.sx},{hop.sy})"
		>
			<span class="canvas" style="transform:scale({size / 2048})">
				{#each hop.parts as [n, p] (n)}
					<img alt="" src={src(n)} style={style(n, p)} />
				{/each}
			</span>
		</span>
	{:else if pose === 'santai'}
		<span class="shadow"></span>
		<img class="whole" alt="" src={src('santai')} />
	{:else}
		<span class="shadow float-shadow"></span>
		<span class="float"><img class="whole breathe" alt="" src={src(pose)} /></span>
	{/if}
</span>

<svelte:head>
	<!-- Mata tertutup & mulut tertawa dimuat lebih dulu agar kedip/lambaian tidak kosong sesaat. -->
	{#if pose === 'rig'}
		{#each ['mata_setengah', 'mata_tutup', 'mulut_setengah_tertawa', 'mulut_tertawa'] as n (n)}
			<link rel="preload" as="image" href={src(n)} />
		{/each}
	{/if}
</svelte:head>

<style>
	.gupy {
		position: relative;
		display: inline-block;
		flex: none;
		width: var(--s);
		height: var(--s);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		user-select: none;
	}
	.canvas {
		position: absolute;
		left: 0;
		top: 0;
		width: 2048px;
		height: 2048px;
		transform-origin: 0 0;
		pointer-events: none;
	}
	.canvas img {
		position: absolute;
		max-width: none;
		will-change: transform;
	}
	.whole {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		transform-origin: 50% calc(var(--feet) * 100%);
		pointer-events: none;
	}
	.shadow {
		position: absolute;
		left: 25%;
		width: 50%;
		height: 7%;
		top: calc(var(--feet) * 100% - 3.5%);
		border-radius: 50%;
		background: light-dark(rgb(0 0 0 / 0.08), rgb(0 0 0 / 0.25));
		filter: blur(calc(var(--s) * 0.03));
	}
	/* Pose diam: melayang ±6 px (3 dtk), bernapas dari kaki (4 dtk), bayangan ikut menyempit. */
	.float {
		position: absolute;
		inset: 0;
		animation: gupy-float 3s ease-in-out infinite alternate;
	}
	.breathe {
		animation: gupy-breathe 2s ease-in-out infinite alternate;
	}
	.float-shadow {
		animation: gupy-shadow 3s ease-in-out infinite alternate;
	}
	@keyframes gupy-float {
		from {
			transform: translateY(6px);
		}
		to {
			transform: translateY(-6px);
		}
	}
	@keyframes gupy-breathe {
		from {
			transform: rotate(-0.4deg) scale(1, 1);
		}
		to {
			transform: rotate(0.4deg) scale(0.996, 1.012);
		}
	}
	@keyframes gupy-shadow {
		to {
			transform: scale(0.9, 0.95);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.float,
		.breathe,
		.float-shadow {
			animation: none;
		}
	}
</style>
