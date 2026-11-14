#!/bin/zsh
# Render ulang maskot Gupy: EffectCraft -> PNG RGBA 768 px -> WebP.
# Pakai: zsh flutter/assets/mascot/_src/build.sh   (butuh effectcraft-cli, img2webp, cwebp, python3 + Pillow)
# Ganti file di layers/ atau celebrate.png dengan nama sama, lalu jalankan lagi.
set -euo pipefail
cd "${0:A:h}/.."
CLI=${EFFECTCRAFT_CLI:-$HOME/.local/bin/effectcraft-cli}
TMP=$(mktemp -d); trap 'rm -rf $TMP' EXIT

# 1. Render PNG sequence 24 fps (komposisi layer 2048 px, celebrate 1254 px).
for c in idle_loop:0.375 wave_once:0.375 celebrate_once:0.6124402; do
  n=${c%%:*}; rm -rf _render/$n; mkdir -p _render/$n
  $CLI render --project _src/mascot.ecproj --comp $n --out _render/$n/$n.png \
    --format png --channels rgba --resolution ${c##*:} --quality best
done

# 2. Alpha dikuantisasi ke 16 level (tepi tetap halus, alpha lossless WebP ~2x lebih kecil).
python3 - "$TMP" <<'EOF'
import sys, glob, os
import numpy as np
from PIL import Image
for f in glob.glob('_render/*/*.png'):
    im = np.array(Image.open(f).convert('RGBA'))
    a = im[..., 3].astype(int)
    a = np.where(a < 16, 0, np.where(a > 239, 255, (a + 8) // 17 * 17))
    im[..., 3] = a
    im[a == 0, :3] = 0
    d = os.path.join(sys.argv[1], f.split('/')[1]); os.makedirs(d, exist_ok=True)
    Image.fromarray(im).save(os.path.join(d, os.path.basename(f)))
EOF

# 3. Animated WebP. idle_loop memakai tiap frame kedua (12 fps): geraknya < 1 px/frame,
#    jadi tidak terlihat beda, dan ukurannya separuh. Durasi 41/42 ms (83/84 ms) agar rata-rata pas.
enc() { # nama langkah loop (0 = tanpa batas, 1 = sekali)
  local n=$1 step=$2 i=0 k=0 d; local -a args=(-loop $3 -lossy -q 60 -m 6)
  for f in $TMP/$n/${n}_*.png; do
    if (( i % step == 0 )); then
      if (( step == 2 )); then d=83; (( k % 3 == 2 )) && d=84; else d=42; (( k % 3 == 2 )) && d=41; fi
      args+=(-d $d $f); (( k++ )) || true
    fi; (( i++ )) || true
  done
  img2webp $args -o anim/$n.webp >/dev/null
}
mkdir -p anim static
enc idle_loop 2 0; enc wave_once 1 1; enc celebrate_once 1 1

# 4. Pose diam 768 px (dipakai app). anim/ di atas hanya untuk web/video; app memakai rig/.
for p in clipboard phone point; do cwebp -quiet -q 80 -alpha_q 100 -m 6 -resize 768 768 $p.png -o static/$p.webp; done

# 5. Layer rig untuk animasi live (Flutter rig/ + web/static/gupy/): crop tiap layer, skala 50%.
#    Kotak hasil (x, y, w, h pada kanvas 2048) harus sama dengan _layers di lib/ui/gupy.dart dan BOXES di web/src/lib/gupy/rig.ts.
python3 - <<'PY'
import os, subprocess
from PIL import Image
names = ['ekor_pangkal', 'ekor_tengah', 'ekor_ujung', 'badan', 'lengan_atas_kanan', 'lengan_bawah_kanan',
         'lengan_atas_kiri', 'lengan_bawah_kiri', 'kepala', 'mata_ramah', 'mata_setengah', 'mata_tutup',
         'mulut_senyum', 'mulut_setengah_tertawa', 'mulut_tertawa']
# Pose rayakan berlapis (layers/celebrate/*.png, kanvas 2048 sama) -> rig/cel_*.webp
names += ['celebrate/' + n for n in ['ekor', 'badan', 'kaki_kanan', 'kaki_kiri', 'tangan_kiri', 'kepala', 'tangan_kanan']]
# Gupy membawa amplop undangan: badan + amplop dan tangan (rig/undangan_*.webp)
names += ['undangan/badan', 'undangan/amplop_dan_tangan']
# Sendi siku: ujung lengan atas dan pangkal lengan bawah dipotong jadi lingkaran berpusat di
# sendi (jari-jari = setengah tebal lengan), agar tekukan tidak menyisakan tonjolan. Pusat
# (697,1172) / (1298,1200) harus sama dengan _elbowR / _elbowL di gupy.dart dan rig.ts.
import numpy as np
JOINTS = {'kanan': ((842, 1028), (697, 1172)), 'kiri': ((1160, 1030), (1298, 1200))}
def trim(n, im):
    side = n.rsplit('_', 1)[-1]
    if not n.startswith('lengan_') or side not in JOINTS: return im
    S, E = (np.array(p, float) for p in JOINTS[side])
    a = np.array(im.getchannel('A'), float)
    ys, xs = np.mgrid[0:2048, 0:2048]
    dx, dy = xs - E[0], ys - E[1]
    if n.startswith('lengan_atas'): d = E - S; sign = -1   # simpan sisi bahu
    else:  # lengan bawah: arah ke titik berat lengan, simpan sisi tangan
        d = np.array([(xs * a).sum() / a.sum(), (ys * a).sum() / a.sum()]) - E; sign = 1
    d /= np.linalg.norm(d)
    along = (dx * d[0] + dy * d[1]) * sign            # > 0 = sisi yang disimpan
    circle = 72 - np.hypot(dx, dy)                    # > 0 = di dalam lingkaran sendi
    # Tepi dilembutkan ~6 px supaya batas lingkaran tidak terlihat saat lengan lurus.
    keep = np.clip(np.maximum(along, circle) / 6 + 0.5, 0, 1)
    im.putalpha(Image.fromarray((a * keep).astype(np.uint8)))
    return im
for n in names:
    im = trim(n, Image.open(f'layers/{n}.png').convert('RGBA'))
    n = n.replace('celebrate/', 'cel_').replace('undangan/', 'undangan_').replace('amplop_dan_tangan', 'amplop')
    x0, y0, x1, y1 = im.getchannel('A').getbbox()
    x0 -= x0 % 2; y0 -= y0 % 2; x1 += x1 % 2; y1 += y1 % 2
    im.crop((x0, y0, x1, y1)).resize(((x1 - x0) // 2, (y1 - y0) // 2), Image.LANCZOS).save('rig/_tmp.png')
    subprocess.run(['cwebp', '-quiet', '-q', '90', '-alpha_q', '100', '-m', '6', 'rig/_tmp.png', '-o', f'rig/{n}.webp'], check=True)
    print(f"{n}: ({x0}, {y0}, {x1 - x0}, {y1 - y0})")
os.remove('rig/_tmp.png')
PY
# Pose 2048 px baru (framing kaki sama).
for p in point_kanan_bawah santai; do cwebp -quiet -q 80 -alpha_q 100 -m 6 -resize 768 768 $p.png -o static/$p.webp; done
# Gupy mengintip (kartu petunjuk): hanya bagian yang terisi, rata di tepi bawah.
python3 -c "from PIL import Image; Image.open('mengintip.png').crop((420, 1280, 1630, 2048)).resize((605, 384), Image.LANCZOS).save('static/_tmp.png')"
cwebp -quiet -q 85 -alpha_q 100 -m 6 static/_tmp.png -o static/mengintip.webp && rm static/_tmp.png
cp $(ls rig/*.webp | grep -v undangan_) static/point.webp static/santai.webp ../../../web/static/gupy/  # undangan_ hanya untuk Flutter
ls -l anim static rig
