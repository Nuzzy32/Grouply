export const reducedMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

/** Pasang kelas `.seen` sekali saat elemen masuk layar (anak `.rv` ikut muncul). */
export function reveal(node: HTMLElement, onSeen?: () => void) {
	const io = new IntersectionObserver(
		([entry]) => {
			if (!entry.isIntersecting) return;
			io.disconnect();
			node.classList.add('seen');
			onSeen?.();
		},
		{ threshold: 0.15 }
	);
	io.observe(node);
	return { destroy: () => io.disconnect() };
}
