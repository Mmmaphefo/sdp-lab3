import { fail } from '@sveltejs/kit';
import { createEntry, listEntries } from '$lib/server/db';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async () => {
	return { entries: await listEntries() };
};

export const actions: Actions = {
	default: async ({ request }) => {
		const form = await request.formData();
		const values = {
			name: String(form.get('name') ?? '').trim(),
			visitors: String(form.get('visitors') ?? ''),
			visit_date: String(form.get('visit_date') ?? ''),
			duration_days: String(form.get('duration_days') ?? ''),
			rating: String(form.get('rating') ?? '0'),
			comment: String(form.get('comment') ?? '').trim()
		};

		const errors: Record<string, string> = {};
		const int = (s: string) => (/^\d+$/.test(s) ? Number(s) : NaN);
		const visitors = int(values.visitors);
		const duration = int(values.duration_days);
		const rating = int(values.rating);

		if (!values.name) errors.name = 'Please enter your name.';
		else if (values.name.length > 100) errors.name = 'Name must be 100 characters or fewer.';
		if (!(visitors >= 1 && visitors <= 1000)) errors.visitors = 'Visitors must be a whole number from 1.';
		if (!/^\d{4}-\d{2}-\d{2}$/.test(values.visit_date) || isNaN(Date.parse(values.visit_date)))
			errors.visit_date = 'Please choose a valid date.';
		if (!(duration >= 1 && duration <= 3650)) errors.duration_days = 'Duration must be at least 1 day.';
		if (!(rating >= 0 && rating <= 5)) errors.rating = 'Rating must be between 0 and 5 stars.';
		if (values.comment.length > 2000) errors.comment = 'Comments must be 2000 characters or fewer.';

		if (Object.keys(errors).length > 0) return fail(400, { values, errors });

		await createEntry({
			name: values.name,
			visitors,
			visit_date: values.visit_date,
			duration_days: duration,
			rating,
			comment: values.comment
		});
		return { success: true };
	}
};
