# syntax=docker/dockerfile:1

# COMS3011A Lab 3 - Dockerfile for the SvelteKit guestbook app.
# Multi-stage build: a build stage compiles the app, the final stage ships
# only production dependencies and the compiled output, so the image stays
# small and has no build tooling or credentials baked in.

# ---- Stage 1: install all dependencies and build the app -------------------
FROM node:22-alpine AS build
WORKDIR /app

# Install the exact dependency versions from package-lock.json first, so this
# layer is cached and only rebuilds when the lockfile changes.
# (.npmrc sets engine-strict=true; node:22-alpine satisfies the required
# Node versions 20.19+ / 22.12+ / 24+.)
COPY package.json package-lock.json .npmrc ./
RUN npm ci

# Now copy the rest of the source and compile into build/.
COPY . .
RUN npm run build

# ---- Stage 2: production runtime image --------------------------------------
FROM node:22-alpine
WORKDIR /app

# Production dependencies only (equivalent to the optional
# `npm prune --omit=dev` step, but leaves no build-only packages behind).
COPY package.json package-lock.json .npmrc ./
RUN npm ci --omit=dev && npm cache clean --force

# The compiled app from the build stage. Run with `node build`.
COPY --from=build /app/build ./build

# The app listens on $PORT bound to $HOST (defaults 3000 / 0.0.0.0).
# DATABASE_URL is deliberately NOT set here - it comes from compose so no
# credentials are baked into the image.
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000

EXPOSE 3000
USER node
CMD ["node", "build"]
