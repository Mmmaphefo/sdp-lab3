/** Shorten text to at most `max` characters, ending in an ellipsis when cut. */
export function truncate(text: string, max = 32): string {
	const chars = Array.from(text);
	return chars.length <= max ? text : chars.slice(0, max - 1).join('') + '…';
}

export function stars(rating: number): string {
	return '★'.repeat(rating) + '☆'.repeat(5 - rating);
}

export function formatDate(iso: string): string {
	const d = new Date(iso + (iso.length === 10 ? 'T00:00:00Z' : ''));
	return d.toLocaleDateString('en-ZA', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
}
