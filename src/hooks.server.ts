import type { ServerInit } from '@sveltejs/kit';
import { ensureSchema } from '$lib/server/db';

// Create the schema at startup. If the database isn't ready yet (e.g. no
// depends_on/healthcheck in compose), keep retrying in the background rather
// than crashing; requests will also retry via ensureSchema().
export const init: ServerInit = async () => {
	const attempt = async (n: number): Promise<void> => {
		try {
			await ensureSchema();
			console.log('[guestbook] database schema ready');
		} catch (err) {
			const delay = Math.min(1000 * 2 ** n, 10_000);
			console.warn(`[guestbook] database not ready (${(err as Error).message}); retrying in ${delay}ms`);
			setTimeout(() => void attempt(n + 1), delay);
		}
	};
	void attempt(0);
};
