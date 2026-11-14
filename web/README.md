# Grouply Web

Landing page dan aplikasi web Grouply. SvelteKit + Svelte 5, TypeScript, CSS biasa.

- Desain acuan: [`reference/claude-design/web/`](../reference/claude-design/web/)
- Token warna (terang/gelap ikut sistem): [`src/app.css`](src/app.css), dari [Design System](../docs/DESIGN_SYSTEM.md) dan [Dark Theme](../docs/DARK_THEME.md)
- Animasi memakai CSS transition/keyframes dan transisi bawaan Svelte. `prefers-reduced-motion` dihormati secara global.

```sh
npm install
npm run dev      # http://localhost:5173
npm run check    # svelte-check + TypeScript
npm run build
```

Adapter masih `adapter-auto`; ganti saat target deploy dipilih.
