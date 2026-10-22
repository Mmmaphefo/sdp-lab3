import postgres from 'postgres';
import { env } from '$env/dynamic/private';
import type { Entry } from '$lib/types';

let client: postgres.Sql | undefined;

/** Lazily create the connection pool so builds don't need DATABASE_URL. */
export function db(): postgres.Sql {
	if (!client) {
		if (!env.DATABASE_URL) throw new Error('DATABASE_URL is not set');
		client = postgres(env.DATABASE_URL, {
			max: 10,
			idle_timeout: 20,
			connect_timeout: 10,
			onnotice: () => {}
		});
	}
	return client;
}

/** Host part of DATABASE_URL, e.g. the compose service name of the database. */
export function databaseHost(): string | null {
	try {
		return new URL(env.DATABASE_URL ?? '').hostname || null;
	} catch {
		return null;
	}
}

let schemaReady: Promise<void> | undefined;

export function ensureSchema(): Promise<void> {
	schemaReady ??= db()`
		CREATE TABLE IF NOT EXISTS entries (
			id            serial PRIMARY KEY,
			name          text NOT NULL,
			visitors      integer NOT NULL CHECK (visitors >= 1),
			visit_date    date NOT NULL,
			duration_days integer NOT NULL CHECK (duration_days >= 1),
			rating        integer NOT NULL CHECK (rating BETWEEN 0 AND 5),
			comment       text NOT NULL DEFAULT '',
			created_at    timestamptz NOT NULL DEFAULT now()
		)
	`
		.then(() => undefined)
		.catch((err) => {
			// Allow a later call to retry, e.g. once the database is reachable.
			schemaReady = undefined;
			throw err;
		});
	return schemaReady;
}

export async function listEntries(): Promise<Entry[]> {
	await ensureSchema();
	return db()<Entry[]>`
		SELECT id, name, visitors, visit_date::text AS visit_date, duration_days, rating, comment,
		       to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at
		FROM entries
		ORDER BY created_at DESC, id DESC
	`;
}

export async function createEntry(e: Omit<Entry, 'id' | 'created_at'>): Promise<void> {
	await ensureSchema();
	await db()`
		INSERT INTO entries (name, visitors, visit_date, duration_days, rating, comment)
		VALUES (${e.name}, ${e.visitors}, ${e.visit_date}, ${e.duration_days}, ${e.rating}, ${e.comment})
	`;
}
