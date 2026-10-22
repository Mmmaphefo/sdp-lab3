import adapter from '@sveltejs/adapter-node';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			adapter: adapter(),

			// adapter-node assumes https unless ORIGIN is set, which would make form
			// posts to http://localhost:<any port> fail the CSRF origin check. The
			// guestbook has no sessions/cookies to protect, so accept any origin
			// rather than tying the image to one host port.
			csrf: { trustedOrigins: ['*'] }
		})
	]
});
