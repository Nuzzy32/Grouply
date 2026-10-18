# Dark theme — spesifikasi bersama Swift + Flutter

Tujuan: mode gelap yang mengikuti pengaturan sistem (iOS/Android), identik di kedua client. Mode terang tidak boleh berubah satu piksel pun. Tidak ada toggle di dalam aplikasi pada tahap ini (ikut sistem saja).

## Token

Setiap warna di UI harus berasal dari token. Hex inline dan `.white`/`Colors.white` dipetakan ke token berdasarkan **perannya**, bukan nilainya.

| Token | Terang | Gelap | Peran |
|---|---|---|---|
| `background` | F8F9F7 | 121314 | Latar layar |
| `surface` (baru) | FFFFFF | 1C1E20 | Kartu, sheet, field, bubble lawan bicara (`.white` sebagai latar) |
| `ink` | 202124 | ECEDEE | Teks utama, isi tombol primer, tab bar kapsul, bubble milik sendiri |
| `onInk` (baru) | FFFFFF | 1A1B1D | Teks/ikon di atas permukaan `ink` (`.white` sebagai teks) |
| `secondary` | 62676B | A3A8AD | Teks sekunder |
| `text2` | 4D5155 | C2C6CA | |
| `text3` | 3C4043 | D5D8DB | |
| `muted` | F0F3F1 | 222527 | |
| `border` | E8E9E7 | 2E3134 | Garis, hairline |
| `chip` (baru) | ECEEEB | 26292B | Latar chip/banner abu (`ECEEEB` inline) |
| `placeholder` (baru) | 9AA0A6 | 868C93 | Placeholder, ikon nonaktif |
| `disabled` (baru) | C4C7C5 | 4A4F53 | Isi tombol nonaktif, track |
| `faint` (baru) | B4B8BC | 5B6166 | |
| `hairline` (baru) | D5D8DB | 3A3E42 | |
| `tertiary` (baru) | 80868B | 9AA0A6 | |
| `lavender` | DED2FF | 3A3354 | Pastel: di gelap jadi gelap-jenuh, teks di atasnya tetap `ink` |
| `mint` | C9F2D6 | 1F3D2B | |
| `sky` | D8EAF4 | 1E3442 | |
| `butter` | F9E9BE | 413720 | |
| `coral` | F6CED1 | 47282B | |
| `danger` | A8231B | FF8A80 | |
| `link` (baru) | 1F4F86 / 1F3F76 | 8AB4F8 | Tautan/aksi biru |

Tetap sama di kedua mode (nada menengah, terbaca di latar gelap): warna ring status `E6C25E`, `86B8D6`, `A893EE`, `E08C94`, `62C484`, serta hijau `34C759`.

Kontras yang sudah dihitung (gelap): ink/background 15.9, ink/surface 14.3, secondary/surface 7.0, secondary/chip 6.1, onInk/ink 14.7, ink di atas tiap pastel ≥ 10.0, danger/surface 7.3, link/surface 7.9.

## Aturan

- Bayangan (shadow) hairline: alpha tetap; boleh dihilangkan di gelap bila terlihat kotor, jangan ditambah.
- Overlay/scrim hitam tetap hitam.
- App icon, gambar brand, dan avatar berwarna tidak diubah.
- Status bar/keyboard mengikuti mode.
- Jangan mengubah layout, ukuran, atau teks.

## Implementasi

- **Swift**: token `GLTheme` menjadi warna dinamis `UIColor { trait in … }`, sehingga pemakaian token tidak berubah. Hapus `.preferredColorScheme(.light)` dan `UIUserInterfaceStyle: Light` (project.yml → regenerasi xcodegen). Ganti hex inline dan `.white` ke token sesuai peran.
- **Flutter**: `GLTheme` membaca kecerahan aktif (`GLTheme.dark`), di-set dari `MediaQuery.platformBrightness` di root, lalu seluruh tree dibangun ulang saat kecerahan berubah. Token jadi getter (bukan `const`); hapus `const` di pemakaian yang terdampak. `ThemeData` mendapat `brightness` yang sesuai.

## Verifikasi

- Tes yang ada tetap lulus di kedua platform.
- Screenshot terang vs gelap untuk Welcome, Beranda, Grup, Chat, Tugas Saya, detail tugas, detail proyek, sheet login.
- Mode terang dibandingkan dengan screenshot sebelum perubahan: tidak boleh ada perbedaan.
