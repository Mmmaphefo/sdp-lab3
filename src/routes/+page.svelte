<script lang="ts">
	import { enhance } from '$app/forms';
	import { fade, fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { formatDate, stars, truncate } from '$lib/format';
	import type { Entry } from '$lib/types';

	let { data, form } = $props();

	const today = new Date().toISOString().slice(0, 10);

	let rating = $state(0);
	let hover = $state(0);
	let submitting = $state(false);
	let thanks = $state(false);
	let selected = $state<Entry | null>(null);
	let closeButton = $state<HTMLButtonElement>();

	const errors = $derived<Record<string, string>>(form?.errors ?? {});
	const values = $derived<Record<string, string>>(form?.values ?? {});

	function open(entry: Entry) {
		selected = entry;
		queueMicrotask(() => closeButton?.focus());
	}

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape' && selected) selected = null;
	}
</script>

<svelte:window onkeydown={onKeydown} />

<header class="topbar">
	<div class="wrap">
		<span class="logo" aria-hidden="true">✦</span>
		<h1>Guestbook</h1>
	</div>
</header>

<main class="wrap">
	<section class="card">
		<div class="card-head">
			<h2>Sign the guestbook</h2>
			<p>Tell us about your stay.</p>
		</div>

		<form
			method="POST"
			use:enhance={() => {
				submitting = true;
				thanks = false;
				return async ({ result, update }) => {
					await update();
					submitting = false;
					if (result.type === 'success') {
						rating = 0;
						thanks = true;
					}
				};
			}}
		>
			<div class="grid">
				<label class="field span-2">
					<span>Name</span>
					<input name="name" autocomplete="name" required maxlength="100" value={values.name ?? ''} />
					{#if errors.name}<small class="error">{errors.name}</small>{/if}
				</label>

				<label class="field">
					<span>Number of visitors</span>
					<input name="visitors" type="number" min="1" max="1000" required value={values.visitors ?? '1'} />
					{#if errors.visitors}<small class="error">{errors.visitors}</small>{/if}
				</label>

				<label class="field">
					<span>Date of stay</span>
					<input name="visit_date" type="date" required value={values.visit_date ?? today} />
					{#if errors.visit_date}<small class="error">{errors.visit_date}</small>{/if}
				</label>

				<label class="field">
					<span>Duration (days)</span>
					<input name="duration_days" type="number" min="1" max="3650" required value={values.duration_days ?? '1'} />
					{#if errors.duration_days}<small class="error">{errors.duration_days}</small>{/if}
				</label>

				<div class="field">
					<span id="rating-label">Review</span>
					<div class="stars" role="radiogroup" aria-labelledby="rating-label">
						{#each [1, 2, 3, 4, 5] as n (n)}
							<button
								type="button"
								role="radio"
								aria-checked={rating === n}
								aria-label="{n} star{n === 1 ? '' : 's'}"
								class:on={(hover || rating) >= n}
								onmouseenter={() => (hover = n)}
								onmouseleave={() => (hover = 0)}
								onclick={() => (rating = n)}>★</button
							>
						{/each}
						<button type="button" class="clear" onclick={() => (rating = 0)} disabled={rating === 0}>
							{rating === 0 ? '0 stars' : 'Clear'}
						</button>
					</div>
					<input type="hidden" name="rating" value={rating} />
					{#if errors.rating}<small class="error">{errors.rating}</small>{/if}
				</div>

				<label class="field span-2">
					<span>Comments</span>
					<textarea name="comment" rows="4" maxlength="2000" placeholder="How was your visit?"
						>{values.comment ?? ''}</textarea
					>
					{#if errors.comment}<small class="error">{errors.comment}</small>{/if}
				</label>
			</div>

			<div class="actions">
				{#if thanks}<span class="thanks" transition:fade>Thanks for signing!</span>{/if}
				<button class="primary" type="submit" disabled={submitting}>
					{submitting ? 'Saving…' : 'Sign guestbook'}
				</button>
			</div>
		</form>
	</section>

	<section class="card">
		<div class="card-head row">
			<h2>Previous guests</h2>
			<span class="count">{data.entries.length} {data.entries.length === 1 ? 'entry' : 'entries'}</span>
		</div>

		{#if data.entries.length === 0}
			<p class="empty">No entries yet. Be the first to sign!</p>
		{:else}
			<div class="table-wrap">
				<table>
					<thead>
						<tr>
							<th>Name</th>
							<th>Date</th>
							<th>Review</th>
							<th>Comment</th>
						</tr>
					</thead>
					<tbody>
						{#each data.entries as entry (entry.id)}
							<!-- Row click is a mouse convenience; keyboard users use the name button. -->
							<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
							<tr class:active={selected?.id === entry.id} onclick={() => open(entry)}>
								<td><button type="button" class="link" onclick={(e) => { e.stopPropagation(); open(entry); }}>{entry.name}</button></td>
								<td class="nowrap">{formatDate(entry.visit_date)}</td>
								<td class="nowrap rating" aria-label="{entry.rating} out of 5 stars">{stars(entry.rating)}</td>
								<td class="muted">{truncate(entry.comment) || '—'}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</section>
</main>

{#if selected}
	<div class="backdrop" transition:fade={{ duration: 150 }} onclick={() => (selected = null)} aria-hidden="true"></div>
	<div
		class="panel"
		role="dialog"
		aria-modal="true"
		aria-labelledby="panel-title"
		transition:fly={{ x: 480, duration: 260, easing: cubicOut, opacity: 1 }}
	>
		<div class="panel-head">
			<h2 id="panel-title">{selected.name}</h2>
			<button bind:this={closeButton} class="icon" type="button" aria-label="Close" onclick={() => (selected = null)}>✕</button>
		</div>
		<p class="panel-rating" aria-label="{selected.rating} out of 5 stars">
			{stars(selected.rating)} <span>{selected.rating}/5</span>
		</p>
		<dl>
			<dt>Date of stay</dt>
			<dd>{formatDate(selected.visit_date)}</dd>
			<dt>Duration</dt>
			<dd>{selected.duration_days} day{selected.duration_days === 1 ? '' : 's'}</dd>
			<dt>Visitors</dt>
			<dd>{selected.visitors}</dd>
			<dt>Signed</dt>
			<dd>{new Date(selected.created_at).toLocaleString('en-ZA')}</dd>
		</dl>
		<h3>Comments</h3>
		<p class="comment">{selected.comment || 'No comment left.'}</p>
	</div>
{/if}

<style>
	.wrap {
		max-width: 960px;
		margin: 0 auto;
		padding: 0 16px;
	}

	.topbar {
		background: var(--surface);
		border-bottom: 1px solid var(--border);
	}
	.topbar .wrap {
		display: flex;
		align-items: center;
		gap: 10px;
		height: 64px;
	}
	.topbar h1 {
		font-size: 1.25rem;
		color: var(--primary-strong);
	}
	.logo {
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: 8px;
		background: var(--primary);
		color: #fff;
	}

	main.wrap {
		padding-block: 32px 64px;
		display: grid;
		gap: 24px;
	}

	.card {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		box-shadow: var(--shadow);
		padding: 24px;
	}
	.card-head {
		margin-bottom: 20px;
	}
	.card-head h2 {
		font-size: 1.125rem;
	}
	.card-head p {
		margin: 4px 0 0;
		color: var(--muted);
	}
	.card-head.row {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
	}
	.count {
		color: var(--muted);
		font-size: 0.875rem;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 16px 20px;
	}
	.span-2 {
		grid-column: span 2;
	}
	@media (max-width: 600px) {
		.grid {
			grid-template-columns: 1fr;
		}
		.span-2 {
			grid-column: auto;
		}
	}

	.field {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.field > span {
		font-size: 0.875rem;
		font-weight: 600;
	}
	input,
	textarea {
		width: 100%;
		padding: 10px 12px;
		border: 1px solid var(--border);
		border-radius: 8px;
		background: #fff;
		transition:
			border-color 0.15s,
			box-shadow 0.15s;
	}
	textarea {
		resize: vertical;
	}
	input:focus,
	textarea:focus {
		outline: none;
		border-color: var(--primary);
		box-shadow: 0 0 0 3px var(--primary-ring);
	}
	.error {
		color: var(--danger);
	}

	.stars {
		display: flex;
		align-items: center;
		gap: 2px;
		height: 44px;
	}
	.stars button {
		border: 0;
		background: none;
		padding: 0 2px;
		font-size: 1.75rem;
		line-height: 1;
		cursor: pointer;
		color: var(--star-empty);
		transition: transform 0.1s;
	}
	.stars button.on {
		color: var(--star);
	}
	.stars button:hover {
		transform: scale(1.1);
	}
	.stars .clear {
		font-size: 0.8125rem;
		color: var(--muted);
		margin-left: 6px;
		white-space: nowrap;
	}
	.stars .clear:disabled {
		cursor: default;
		transform: none;
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		align-items: center;
		gap: 16px;
		margin-top: 20px;
	}
	.thanks {
		color: var(--primary-hover);
		font-weight: 600;
	}
	.primary {
		background: var(--primary);
		color: #fff;
		border: 0;
		border-radius: 8px;
		padding: 10px 20px;
		font-weight: 600;
		cursor: pointer;
		transition: background 0.15s;
	}
	.primary:hover {
		background: var(--primary-hover);
	}
	.primary:disabled {
		opacity: 0.7;
		cursor: progress;
	}

	.empty {
		color: var(--muted);
		text-align: center;
		padding: 24px 0;
		margin: 0;
	}
	.table-wrap {
		overflow-x: auto;
		margin: 0 -24px -24px;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9375rem;
	}
	th {
		text-align: left;
		font-size: 0.75rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--muted);
		background: var(--primary-tint);
		padding: 10px 24px;
	}
	td {
		padding: 12px 24px;
		border-top: 1px solid var(--border);
	}
	tbody tr {
		cursor: pointer;
		transition: background 0.1s;
	}
	tbody tr:hover,
	tbody tr.active {
		background: var(--primary-tint);
	}
	.nowrap {
		white-space: nowrap;
	}
	.rating {
		color: var(--star);
		letter-spacing: 1px;
	}
	.muted {
		color: var(--muted);
	}
	.link {
		border: 0;
		background: none;
		padding: 0;
		font-weight: 600;
		color: var(--primary-strong);
		cursor: pointer;
		text-align: left;
	}

	.backdrop {
		position: fixed;
		inset: 0;
		background: rgb(16 32 27 / 0.3);
		z-index: 10;
	}
	.panel {
		position: fixed;
		top: 0;
		right: 0;
		bottom: 0;
		width: min(440px, 100vw);
		background: var(--surface);
		border-left: 4px solid var(--primary);
		box-shadow: -8px 0 32px rgb(16 32 27 / 0.15);
		z-index: 11;
		padding: 24px;
		overflow-y: auto;
	}
	.panel-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 16px;
	}
	.panel-head h2 {
		font-size: 1.375rem;
		overflow-wrap: anywhere;
	}
	.icon {
		border: 0;
		background: var(--primary-tint);
		color: var(--primary-strong);
		width: 32px;
		height: 32px;
		border-radius: 8px;
		cursor: pointer;
		flex: none;
	}
	.icon:hover {
		background: #d1fae5;
	}
	.panel-rating {
		color: var(--star);
		font-size: 1.25rem;
		margin: 8px 0 20px;
	}
	.panel-rating span {
		color: var(--muted);
		font-size: 0.875rem;
	}
	dl {
		display: grid;
		grid-template-columns: auto 1fr;
		gap: 10px 16px;
		margin: 0 0 24px;
		padding: 16px;
		background: var(--primary-tint);
		border-radius: 8px;
	}
	dt {
		color: var(--muted);
		font-size: 0.875rem;
	}
	dd {
		margin: 0;
		font-weight: 500;
	}
	.panel h3 {
		font-size: 0.875rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--muted);
		margin-bottom: 8px;
	}
	.comment {
		white-space: pre-wrap;
		overflow-wrap: anywhere;
		margin: 0;
	}

	/* Wide screens: form and guest list side by side. */
	@media (min-width: 1200px) {
		.wrap {
			max-width: 1280px;
		}
		main.wrap {
			grid-template-columns: minmax(380px, 440px) minmax(0, 1fr);
			align-items: start;
		}
		main.wrap > .card:first-child {
			position: sticky;
			top: 24px;
		}
		.stars button {
			font-size: 1.375rem;
			padding: 0 1px;
		}
	}
</style>
