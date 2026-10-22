import { json } from '@sveltejs/kit';
import { existsSync } from 'node:fs';
import os from 'node:os';
import { databaseHost, db, ensureSchema } from '$lib/server/db';
import { version } from '../../../../package.json';
import type { RequestHandler } from './$types';

// Diagnostic endpoint used by automark.sh to verify the containerised
// deployment: is the API running in a container, and can it reach and write
// to the database service?
export const GET: RequestHandler = async () => {
	const api = {
		name: 'guestbook',
		version,
		node: process.version,
		env: process.env.NODE_ENV ?? null,
		hostname: os.hostname(),
		uptime_s: Math.round(process.uptime()),
		in_container: existsSync('/.dockerenv') || existsSync('/run/.containerenv')
	};

	const started = performance.now();
	try {
		const sql = db();
		const [info] = await sql`
			SELECT current_setting('server_version') AS server_version,
			       current_setting('server_version_num')::int / 10000 AS major,
			       current_database() AS database,
			       current_user AS "user",
			       host(inet_server_addr()) AS server_addr
		`;
		const latency_ms = Math.round((performance.now() - started) * 100) / 100;

		await ensureSchema();
		const [{ table_exists }] = await sql`SELECT to_regclass('public.entries') IS NOT NULL AS table_exists`;
		const [{ entry_count }] = await sql`SELECT count(*)::int AS entry_count FROM entries`;

		// Prove write access without leaving data behind.
		let write_ok = false;
		await sql
			.begin(async (tx) => {
				const [row] = await tx`
					INSERT INTO entries (name, visitors, visit_date, duration_days, rating, comment)
					VALUES ('__marking_test__', 1, current_date, 1, 5, 'probe')
					RETURNING id
				`;
				const [found] = await tx`SELECT id FROM entries WHERE id = ${row.id}`;
				write_ok = found?.id === row.id;
				throw new Rollback();
			})
			.catch((err) => {
				if (!(err instanceof Rollback)) throw err;
			});

		return json({
			status: 'ok',
			api,
			database: {
				connected: true,
				host: databaseHost(),
				server_addr: info.server_addr,
				server_version: info.server_version,
				major: info.major,
				database: info.database,
				user: info.user,
				latency_ms,
				table_exists,
				entry_count,
				write_ok
			}
		});
	} catch (err) {
		return json(
			{
				status: 'error',
				api,
				database: { connected: false, host: databaseHost(), error: (err as Error).message }
			},
			{ status: 503 }
		);
	}
};

class Rollback extends Error {}
