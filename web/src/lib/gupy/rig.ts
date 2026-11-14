// Gerak maskot Gupy, sama dengan flutter/lib/ui/gupy.dart (koordinat kanvas 2048 px).

export type Layer =
	| 'ekor_pangkal'
	| 'ekor_tengah'
	| 'ekor_ujung'
	| 'badan'
	| 'lengan_atas_kanan'
	| 'lengan_bawah_kanan'
	| 'lengan_atas_kiri'
	| 'lengan_bawah_kiri'
	| 'kepala'
	| 'mata_ramah'
	| 'mata_setengah'
	| 'mata_tutup'
	| 'mulut_senyum'
	| 'mulut_setengah_tertawa'
	| 'mulut_tertawa'
	| CelLayer;
/** Pose rayakan berlapis, urutan gambar dari belakang ke depan. */
export const CEL = ['ekor', 'badan', 'kaki_kanan', 'kaki_kiri', 'tangan_kiri', 'kepala', 'tangan_kanan'] as const;
type CelLayer = `cel_${(typeof CEL)[number]}`;

/** Kotak tiap layer di kanvas 2048 px (static/gupy/*.webp = crop ini pada 50%). */
export const BOXES: Record<Layer, [number, number, number, number]> = {
	ekor_pangkal: [1150, 1400, 320, 250],
	ekor_tengah: [1310, 1298, 380, 332],
	ekor_ujung: [1498, 1138, 242, 338],
	badan: [516, 858, 938, 1016],
	lengan_atas_kanan: [628, 968, 274, 280],
	lengan_bawah_kanan: [456, 1106, 316, 346],
	lengan_atas_kiri: [1106, 974, 268, 288],
	lengan_bawah_kiri: [1234, 1130, 274, 318],
	kepala: [482, 192, 1030, 792],
	mata_ramah: [518, 296, 942, 480],
	mata_setengah: [518, 296, 942, 480],
	mata_tutup: [518, 296, 942, 480],
	mulut_senyum: [834, 648, 572, 238],
	mulut_setengah_tertawa: [854, 668, 506, 240],
	mulut_tertawa: [766, 656, 580, 324],
	cel_ekor: [890, 1034, 916, 482],
	cel_badan: [580, 906, 518, 734],
	cel_kaki_kanan: [304, 1166, 470, 488],
	cel_kaki_kiri: [840, 1414, 528, 458],
	cel_tangan_kiri: [858, 866, 732, 314],
	cel_kepala: [558, 294, 860, 724],
	cel_tangan_kanan: [346, 372, 468, 698]
};

type Pt = [number, number];
const FEET: Pt = [985, 1874];
const NECK: Pt = [970, 930];
const SHOULDER_R: Pt = [842, 1028];
// Pusat siku; ujung kedua ruas lengan dipotong melingkar di sini (_src/build.sh).
const ELBOW_R: Pt = [697, 1172];
const SHOULDER_L: Pt = [1160, 1030];
const ELBOW_L: Pt = [1298, 1200];
// Sendi ekor: pangkal (tersembunyi di balik badan), tengah, ujung.
const TAIL: Pt = [1260, 1550];
const TAIL_MID: Pt = [1392, 1513];
const TAIL_TIP: Pt = [1597, 1386];

/** Garis telapak kaki pada kanvas (layer dan pose memakai framing yang sama). */
export const FEET_LINE = 0.912;

export const WAVE_SECONDS = 1.68;
// Siku terangkat ke samping (di belakang kepala, tidak menutupi dagu), lengan bawah tegak dan melambai.
const UPPER_KEYS: Pt[] = [
	[0, 0],
	[0.22, 18],
	[0.36, 34],
	[0.48, 29],
	[1.1, 31],
	[1.3, 26],
	[1.5, -3],
	[1.68, 0]
];
const ELBOW_KEYS: Pt[] = [
	[0, 0],
	[0.22, 26],
	[0.36, 74],
	[0.5, 50],
	[0.66, 76],
	[0.82, 50],
	[0.98, 74],
	[1.14, 52],
	[1.3, 44],
	[1.5, -4],
	[1.68, 0]
];

const smooth = (a: number, b: number, x: number) => {
	const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
	return t * t * (3 - 2 * t);
};

/** Hermite kubik melewati `keys` (tangen Catmull-Rom, datar di kedua ujung). */
export function spline(keys: Pt[], t: number): number {
	if (t <= keys[0][0]) return keys[0][1];
	const last = keys.length - 1;
	if (t >= keys[last][0]) return keys[last][1];
	let i = 0;
	while (keys[i + 1][0] < t) i++;
	const [t1, v1] = keys[i];
	const [t2, v2] = keys[i + 1];
	const h = t2 - t1;
	const slope = (j: number) =>
		j === 0 || j === last ? 0 : (keys[j + 1][1] - keys[j - 1][1]) / (keys[j + 1][0] - keys[j - 1][0]);
	const m1 = slope(i) * h;
	const m2 = slope(i + 1) * h;
	const u = (t - t1) / h;
	const u2 = u * u;
	const u3 = u2 * u;
	return (2 * u3 - 3 * u2 + 1) * v1 + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * v2 + (u3 - u2) * m2;
}

function rotate([x, y]: Pt, deg: number): Pt {
	const r = (deg * Math.PI) / 180;
	return [x * Math.cos(r) - y * Math.sin(r), x * Math.sin(r) + y * Math.cos(r)];
}

/** Transform satu layer: geser `dx,dy`, putar `deg` dan skala di sekitar `pivot`. */
export type Pose = { pivot: Pt; dx: number; dy: number; deg: number; sx: number; sy: number };

/**
 * Pose seluruh rig pada detik `t`. `u` = detik sejak lambaian dimulai (null = tidak melambai);
 * `idle` = napas/goyang/ekor jalan terus; tanpa idle, gerak hanya muncul selama lambaian.
 */
export function rigPose(t: number, u: number | null, idle: boolean) {
	const waving = u !== null && u >= 0;
	const w = waving ? smooth(0, 0.3, u!) * (1 - smooth(1.2, WAVE_SECONDS, u!)) : 0;
	const a = idle ? 1 : w;
	const breathPhase = (2 * Math.PI * t) / 3.2;
	const breath = ((1 - Math.cos(breathPhase)) / 2) * a;
	const sway = 0.7 * Math.sin((2 * Math.PI * t) / 5.3) * a;
	const body = sway - 1.2 * w;
	const sy = 1 + 0.016 * breath;
	const sx = 1 - 0.005 * breath;
	const attach = (p: Pt): Pt => {
		const [x, y] = rotate([(p[0] - FEET[0]) * sx, (p[1] - FEET[1]) * sy], body);
		return [FEET[0] + x - p[0], FEET[1] + y - p[1]];
	};
	const lagged = Math.sin(breathPhase - 0.7) * a;
	const head = body + 1.1 * lagged + 0.5 * Math.sin((2 * Math.PI * t) / 5.3 - 0.9) * a - 4.5 * w;
	const armSwing = 1.8 * Math.sin(breathPhase - 0.5) * a;
	const upperR = body + armSwing + (waving ? spline(UPPER_KEYS, u!) : 0);
	// Lengan bawah sedikit tertinggal (follow-through).
	const forearmR = upperR + 2.2 * Math.sin(breathPhase - 1.1) * a + (waving ? spline(ELBOW_KEYS, u!) : 0);
	const armL = body - armSwing - 3 * w;
	const forearmL = armL - 2.2 * Math.sin(breathPhase - 1.1) * a - 4 * w;
	// Ekor: gelombang merambat dari pangkal ke ujung, tiap sendi menambah sudut sebelumnya.
	const tailPhase = (2 * Math.PI * t) / 2.7;
	const tailBase = body + (2.4 * Math.sin(tailPhase) + 0.8 * Math.sin(2 * tailPhase + 1.1)) * a;
	const tailMid = tailBase + 3 * Math.sin(tailPhase - 0.8) * a;
	const tailTip = tailMid + 4 * Math.sin(tailPhase - 1.6) * a;
	const at = (pivot: Pt, deg: number, scale: [number, number] = [1, 1]): Pose => {
		const [dx, dy] = attach(pivot);
		return { pivot, dx, dy, deg, sx: scale[0], sy: scale[1] };
	};
	// Ruas berikutnya menempel di sendi ruas sebelumnya yang sudah diputar.
	const child = (parent: Pose, pivot: Pt, deg: number): Pose => {
		const [x, y] = rotate([pivot[0] - parent.pivot[0], pivot[1] - parent.pivot[1]], parent.deg);
		return {
			pivot,
			dx: parent.pivot[0] + parent.dx + x - pivot[0],
			dy: parent.pivot[1] + parent.dy + y - pivot[1],
			deg,
			sx: 1,
			sy: 1
		};
	};
	const upper = at(SHOULDER_R, upperR);
	const upperL = at(SHOULDER_L, armL);
	const base = at(TAIL, tailBase);
	const mid = child(base, TAIL_MID, tailMid);
	return {
		ekor_ujung: child(mid, TAIL_TIP, tailTip),
		ekor_tengah: mid,
		ekor_pangkal: base,
		badan: { pivot: FEET, dx: 0, dy: 0, deg: body, sx, sy } as Pose,
		lengan_atas_kanan: upper,
		lengan_bawah_kanan: child(upper, ELBOW_R, forearmR),
		lengan_atas_kiri: upperL,
		lengan_bawah_kiri: child(upperL, ELBOW_L, forearmL),
		kepala: at(NECK, head),
		// Senyum -> setengah tertawa -> tertawa saat lambaian naik, dan sebaliknya.
		mouth: (w > 0.6 ? 'mulut_tertawa' : w > 0.2 ? 'mulut_setengah_tertawa' : 'mulut_senyum') as Layer
	};
}

/** Tinggi lompatan (0..1) pose rayakan pada detik `t` dari 1,2 detik. */
export const HOP_SECONDS = 1.2;
export function hopLift(t: number) {
	if (t <= 0.17 || t >= 0.64) return 0;
	const u = (t - 0.17) / 0.47;
	return 4 * u * (1 - u);
}
const HOP_SY: Pt[] = [
	[0, 1],
	[0.14, 0.9],
	[0.21, 1.08],
	[0.4, 1],
	[0.55, 1.03],
	[0.63, 1.02],
	[0.68, 0.91],
	[0.78, 1.04],
	[0.9, 0.985],
	[1.02, 1.005],
	[1.2, 1]
];
const HOP_TILT: Pt[] = [
	[0, 0],
	[0.14, 1.5],
	[0.3, -3],
	[0.55, 2],
	[0.68, 0],
	[1.2, 0]
];
// Sudut anggota badan (derajat, searah jarum jam) di sendinya: lengan turun saat jongkok,
// terayun naik saat lepas landas, memantul setelah mendarat; kaki hanya menekuk di udara.
const HOP_LIMBS: Record<(typeof CEL)[number], [Pt, Pt[]]> = {
	ekor: [[984, 1378], [[0, 0], [0.14, -4], [0.3, 8], [0.5, -3], [0.68, -8], [0.84, 5], [1, -2], [1.2, 0]]],
	badan: [FEET, [[0, 0]]],
	kaki_kanan: [[671, 1372], [[0, 0], [0.17, 0], [0.4, 9], [0.62, 0], [1.2, 0]]],
	kaki_kiri: [[969, 1523], [[0, 0], [0.17, 0], [0.4, -8], [0.62, 0], [1.2, 0]]],
	tangan_kiri: [[945, 1075], [[0, 0], [0.14, 10], [0.3, -14], [0.48, -5], [0.7, 9], [0.86, -3], [1.02, 1], [1.2, 0]]],
	kepala: [[890, 975], [[0, 0], [0.14, -2], [0.3, 3], [0.5, -1.5], [0.7, 2], [0.88, -0.8], [1.2, 0]]],
	tangan_kanan: [[745, 1000], [[0, 0], [0.14, -10], [0.3, 12], [0.46, 4], [0.6, 9], [0.72, -6], [0.88, 3], [1.04, -1], [1.2, 0]]]
};
export function hopPose(t: number) {
	const sy = spline(HOP_SY, t);
	const parts = CEL.map((n) => {
		const [pivot, keys] = HOP_LIMBS[n];
		return [`cel_${n}` as Layer, { pivot, dx: 0, dy: 0, deg: spline(keys, t), sx: 1, sy: 1 } as Pose] as const;
	});
	return { lift: hopLift(t), sx: 1 - (sy - 1) * 0.6, sy, deg: spline(HOP_TILT, t), parts };
}
