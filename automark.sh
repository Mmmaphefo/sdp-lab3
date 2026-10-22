#!/usr/bin/env bash
#
# automark.sh: build and run a guestbook submission (Dockerfile + compose
# file), then check it via /api/marking-test and a series of stress stages.
#
# Usage: ./automark.sh [--keep] [DIR]
#   DIR     directory containing the app, Dockerfile and compose file (default: this script's directory)
#   --keep  leave the stack running afterwards (default: tear down, removing volumes)
#
# Environment overrides:
#   PROJECT   compose project name (default: automark)
#   BASE_URL  skip port discovery and test against this URL
#   TIMEOUT   seconds to wait for the app to become ready (default: 90)
#
# Nothing here depends on the names students choose for services, volumes,
# databases or host ports. The app service is the one with a `build:` key and
# the database is the one running a postgres image. Where a service can't be
# identified, stages act on the whole compose project or are skipped.

set -uo pipefail

KEEP=0
DIR=""
for arg in "$@"; do
	case "$arg" in
		--keep) KEEP=1 ;;
		-h | --help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) DIR="$arg" ;;
	esac
done
DIR="${DIR:-$(cd "$(dirname "$0")" && pwd)}"
PROJECT="${PROJECT:-automark}"
TIMEOUT="${TIMEOUT:-90}"

# ---------------------------------------------------------------- output ---
if [[ -t 1 ]]; then
	G=$'\e[32m' R=$'\e[31m' Y=$'\e[33m' B=$'\e[1m' D=$'\e[2m' N=$'\e[0m'
else
	G="" R="" Y="" B="" D="" N=""
fi
# Number of required checks in stages 1-7 (keep in sync when adding checks).
# Stage 8 "good practice" checks are scored separately and never fail a run.
REQUIRED_TOTAL=28
PASSED=0 FAILED=0 SKIPPED=0 GP_PASSED=0 WARNED=0

stage() { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; }
pass() { PASSED=$((PASSED + 1)); printf '  %sPASS%s %s\n' "$G" "$N" "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  %sFAIL%s %s\n' "$R" "$N" "$1"; [[ -n "${2:-}" ]] && printf '       %s%s%s\n' "$D" "$2" "$N"; return 0; }
gp_pass() { GP_PASSED=$((GP_PASSED + 1)); printf '  %sPASS%s %s\n' "$G" "$N" "$1"; }
warn() { WARNED=$((WARNED + 1)); printf '  %sWARN%s %s\n' "$Y" "$N" "$1"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf '  %sSKIP%s %s\n' "$D" "$N" "$1"; }
info() { printf '  %s%s%s\n' "$D" "$1" "$N"; }

# check "description" <command...>: PASS if the command succeeds
check() {
	local desc="$1"; shift
	if "$@" > /dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

summary() {
	# Checks that never ran because of an early abort count as not passed.
	local total=$((REQUIRED_TOTAL - SKIPPED))
	((PASSED + FAILED > total)) && total=$((PASSED + FAILED))
	local pct colour
	pct=$(awk -v p="$PASSED" -v t="$total" 'BEGIN { printf "%.1f", t ? p * 100 / t : 0 }')
	if ((PASSED == total)); then colour=$G; else colour=$R; fi
	printf '\n%sRequired checks:%s %s%d/%d passed (%s%%)%s\n' "$B" "$N" "$colour" "$PASSED" "$total" "$pct" "$N"
	if ((GP_PASSED + WARNED > 0)); then
		printf '%sGood practice:%s   %d/%d (%s%d warnings%s)\n' "$B" "$N" "$GP_PASSED" $((GP_PASSED + WARNED)) "$Y" "$WARNED" "$N"
	else
		printf '%sGood practice:%s   not run\n' "$B" "$N"
	fi
	((SKIPPED > 0)) && printf '%sSkipped:%s         %d (need the postgres service to be identified; not counted)\n' "$B" "$N" "$SKIPPED"
	return 0
}

abort() {
	fail "$1" "${2:-}"
	printf '\n  %sStopping early; recent logs:%s\n' "$D" "$N"
	dc logs --tail 40 2>&1 | sed 's/^/    /'
	summary
	exit 1
}

# -------------------------------------------------------------- helpers ---
dc() { docker compose -p "$PROJECT" "$@"; }

cleanup() {
	if [[ $KEEP -eq 1 ]]; then
		printf '\n%sStack left running (project "%s"). Tear down with: docker compose -p %s down -v%s\n' "$D" "$PROJECT" "$PROJECT" "$N"
	else
		dc down -v --remove-orphans > /dev/null 2>&1
	fi
}

BODY=""
CODE=""
# Fetch marking-test into $BODY / $CODE.
marking_test() {
	local out
	out=$(curl -s -m 10 -w $'\n%{http_code}' "$BASE_URL/api/marking-test" 2> /dev/null) || out=$'\n000'
	BODY="${out%$'\n'*}"
	CODE="${out##*$'\n'}"
}

# Wait until marking-test reports status ok, up to $1 seconds.
wait_ready() {
	local limit="$1" start=$SECONDS
	while ((SECONDS - start < limit)); do
		marking_test
		if [[ "$CODE" == 200 ]] && [[ "$(jq -r '.status' <<< "$BODY" 2> /dev/null)" == ok ]]; then
			info "ready after $((SECONDS - start))s"
			return 0
		fi
		sleep 2
	done
	return 1
}

# Resolve the host URL for the app (the port may only be known once it's up).
resolve_base_url() {
	[[ -n "${BASE_URL_OVERRIDE:-}" ]] && { BASE_URL="$BASE_URL_OVERRIDE"; return 0; }
	[[ -z "$APP" || -z "$APP_TARGET" ]] && return 1
	local addr
	addr=$(dc port "$APP" "$APP_TARGET" 2> /dev/null | head -n1)
	[[ -z "$addr" ]] && return 1
	BASE_URL="http://localhost:${addr##*:}"
}

jqb() { jq -e "$1" <<< "$BODY" > /dev/null 2>&1; }
jqv() { jq -r "$1" <<< "$BODY" 2> /dev/null; }

entry_count() { marking_test; jqv '.database.entry_count'; }

# ================================================================ stages ===
command -v docker > /dev/null || { echo "docker is required"; exit 2; }
command -v curl > /dev/null || { echo "curl is required"; exit 2; }
command -v jq > /dev/null || { echo "jq is required (e.g. brew install jq / apt install jq)"; exit 2; }
docker info > /dev/null 2>&1 || { echo "cannot reach the Docker daemon; is it running?"; exit 2; }

cd "$DIR" || { echo "cannot cd to $DIR"; exit 2; }
BASE_URL_OVERRIDE="${BASE_URL:-}"
BASE_URL=""
printf '%sAutomarking%s %s  %s(project: %s)%s\n' "$B" "$N" "$DIR" "$D" "$PROJECT" "$N"

# ---------------------------------------------------------------------------
stage "1. Static checks"

COMPOSE_FILE_FOUND=""
for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
	[[ -f "$f" ]] && { COMPOSE_FILE_FOUND="$f"; break; }
done
if [[ -n "$COMPOSE_FILE_FOUND" ]]; then pass "compose file exists ($COMPOSE_FILE_FOUND)"; else fail "compose file exists"; fi

ERR_FILE=$(mktemp)
CONFIG=$(dc config --format json 2> "$ERR_FILE")
if [[ $? -eq 0 ]]; then
	pass "compose file is valid"
else
	abort "compose file is valid" "$(head -n3 "$ERR_FILE")"
fi
rm -f "$ERR_FILE"

SERVICE_COUNT=$(jq '.services | length' <<< "$CONFIG")
if [[ "$SERVICE_COUNT" -eq 2 ]]; then pass "defines exactly two services"; else fail "defines exactly two services" "found $SERVICE_COUNT"; fi

APP=$(jq -r '[.services | to_entries[] | select(.value.build != null) | .key] | if length == 1 then .[0] else "" end' <<< "$CONFIG")
DB=$(jq -r '[.services | to_entries[] | select((.value.image // "") | test("(^|/)postgres(ql)?(:|@|$)")) | .key] | if length == 1 then .[0] else "" end' <<< "$CONFIG")

if [[ -n "$APP" ]]; then pass "app service is built from the Dockerfile ($APP)"; else fail "exactly one service builds the app (has a build: key)"; fi

# Resolve the Dockerfile and build context the way Docker will, so a submission
# may live in a subdirectory (e.g. build: { context: .., dockerfile: sub/Dockerfile }).
BUILD_CTX="$PWD"
DOCKERFILE="$PWD/Dockerfile"
if [[ -n "$APP" ]]; then
	BUILD_CTX=$(jq -r --arg s "$APP" '.services[$s].build.context // empty' <<< "$CONFIG")
	BUILD_CTX="${BUILD_CTX:-$PWD}"
	DOCKERFILE=$(jq -r --arg s "$APP" '.services[$s].build.dockerfile // "Dockerfile"' <<< "$CONFIG")
	[[ "$DOCKERFILE" == /* ]] || DOCKERFILE="$BUILD_CTX/$DOCKERFILE"
fi
# Display a path relative to the submission directory (handles up to ../..).
rel() {
	local p="$1" up="" base="$PWD"
	for _ in 1 2 3; do
		if [[ "$p" == "$base" ]]; then printf '%s' "${up%/}"; [[ -z "$up" ]] && printf '.'; return; fi
		if [[ "$p" == "$base"/* ]]; then printf '%s%s' "$up" "${p#"$base"/}"; return; fi
		base=$(dirname "$base"); up="../$up"
	done
	printf '%s' "$p"
}
if [[ -f "$DOCKERFILE" ]]; then pass "Dockerfile exists ($(rel "$DOCKERFILE"))"; else fail "Dockerfile exists" "expected at $(rel "$DOCKERFILE")"; fi
if [[ -n "$DB" ]]; then
	pass "database service runs a postgres image ($DB)"
else
	skip "database service runs a postgres image (not identified; DB-specific checks will be skipped)"
fi

APP_TARGET=""
if [[ -n "$APP" ]]; then
	APP_TARGET=$(jq -r --arg s "$APP" '.services[$s].ports // [] | map(select(.published != null and .published != "")) | .[0].target // empty' <<< "$CONFIG")
	if [[ -n "$APP_TARGET" ]]; then
		pass "app publishes a port to the host (container port $APP_TARGET)"
	elif [[ -z "$BASE_URL_OVERRIDE" ]]; then
		abort "app publishes a port to the host" "add a ports: entry to the app service"
	fi
fi

trap cleanup EXIT

# ---------------------------------------------------------------------------
stage "2. Build and start"

dc down -v --remove-orphans > /dev/null 2>&1 # start from a clean slate
info "building (this can take a minute)..."
if BUILD_LOG=$(dc build 2>&1); then
	pass "images build"
else
	printf '%s\n' "$BUILD_LOG" | tail -n 20 | sed 's/^/    /'
	abort "images build"
fi

if UP_LOG=$(dc up -d 2>&1); then
	pass "stack starts (docker compose up -d)"
else
	abort "stack starts" "$(printf '%s' "$UP_LOG" | tail -n 3)"
fi

resolve_base_url || abort "discover app URL" "could not map container port $APP_TARGET of $APP to a host port"
info "app URL: $BASE_URL"

if wait_ready "$TIMEOUT"; then
	pass "marking-test reports ok within ${TIMEOUT}s"
else
	abort "marking-test reports ok within ${TIMEOUT}s" "last response: HTTP $CODE $(head -c 300 <<< "$BODY")"
fi

# ---------------------------------------------------------------------------
stage "3. Marking-test endpoint"

marking_test
info "$(jq -c '{api: {version: .api.version, node: .api.node, env: .api.env}, database: (.database | {host, server_version, database, user, entry_count})}' <<< "$BODY" 2> /dev/null)"

check "HTTP 200 with status ok" jqb '.status == "ok"'
check "API runs inside a container" jqb '.api.in_container == true'
check "API runs with NODE_ENV=production" jqb '.api.env == "production"'
check "database connected" jqb '.database.connected == true'
check "postgres major version >= 14" jqb '.database.major >= 14'
check "entries table exists" jqb '.database.table_exists == true'
check "database accepts writes" jqb '.database.write_ok == true'

DB_HOST=$(jqv '.database.host')
if [[ -z "$DB_HOST" || "$DB_HOST" == null || "$DB_HOST" =~ ^(localhost|127\.|::1$|host\.docker\.internal$) ]]; then
	fail "app reaches the database over the compose network" "DATABASE_URL host is '$DB_HOST'"
else
	pass "DATABASE_URL points at another host ($DB_HOST), not localhost"
fi

if [[ -n "$DB" ]]; then
	SERVER_ADDR=$(jqv '.database.server_addr')
	DB_IPS=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' $(dc ps -q "$DB") 2> /dev/null)
	if [[ -n "$SERVER_ADDR" && " $DB_IPS " == *" $SERVER_ADDR "* ]]; then
		pass "app's database is the '$DB' container ($SERVER_ADDR)"
	else
		fail "app's database is the '$DB' container" "server reports '$SERVER_ADDR', $DB has '${DB_IPS% }'"
	fi
else
	skip "database container identity (postgres service not identified)"
fi

# ---------------------------------------------------------------------------
stage "4. App smoke test"

MARKER="automark-$(date +%s)-$RANDOM"
BEFORE=$(entry_count)
RESP=$(curl -s -m 10 -X POST "$BASE_URL/" \
	-H "Origin: $BASE_URL" -H 'Accept: application/json' -H 'x-sveltekit-action: true' \
	--data-urlencode "name=$MARKER" --data-urlencode 'visitors=2' --data-urlencode "visit_date=$(date +%Y-%m-%d)" \
	--data-urlencode 'duration_days=3' --data-urlencode 'rating=4' \
	--data-urlencode 'comment=Submitted by automark to check the full request path works end to end.')
check "form submission succeeds" jq -e '.type == "success"' <<< "$RESP"
check "home page lists the new entry" bash -c "curl -s -m 10 '$BASE_URL/' | grep -q '$MARKER'"
AFTER=$(entry_count)
if [[ "$AFTER" =~ ^[0-9]+$ && "$BEFORE" =~ ^[0-9]+$ && $AFTER -eq $((BEFORE + 1)) ]]; then
	pass "entry count increased by one ($BEFORE -> $AFTER)"
else
	fail "entry count increased by one" "before=$BEFORE after=$AFTER"
fi

# ---------------------------------------------------------------------------
stage "5. Persistence across docker compose down / up"

info "docker compose down (volumes kept) ..."
dc down > /dev/null 2>&1
dc up -d > /dev/null 2>&1
resolve_base_url
if wait_ready "$TIMEOUT"; then
	pass "stack comes back after down/up"
	COUNT=$(entry_count)
	if [[ "$COUNT" == "$AFTER" ]]; then pass "entry count preserved ($COUNT)"; else fail "entry count preserved" "expected $AFTER, got $COUNT"; fi
	check "smoke-test entry still listed" bash -c "curl -s -m 10 '$BASE_URL/' | grep -q '$MARKER'"
else
	fail "stack comes back after down/up" "HTTP $CODE"
	fail "entry count preserved (not checked: stack did not come back)"
	fail "smoke-test entry still listed (not checked: stack did not come back)"
fi

# ---------------------------------------------------------------------------
stage "6. Recovery after restarting the whole stack"

dc restart > /dev/null 2>&1
resolve_base_url
if wait_ready "$TIMEOUT"; then
	pass "marking-test ok after docker compose restart"
	COUNT=$(entry_count)
	if [[ "$COUNT" == "$AFTER" ]]; then pass "data intact after restart"; else fail "data intact after restart" "expected $AFTER, got $COUNT"; fi
else
	fail "marking-test ok after docker compose restart" "HTTP $CODE"
	fail "data intact after restart (not checked: stack did not recover)"
fi

# ---------------------------------------------------------------------------
stage "7. Recovery after restarting only the database"

if [[ -n "$DB" ]]; then
	APP_STARTED=$(docker inspect -f '{{.State.StartedAt}}' $(dc ps -q "$APP") 2> /dev/null)
	dc restart "$DB" > /dev/null 2>&1
	if wait_ready 45; then
		pass "API reconnects after '$DB' restarts"
		NOW_STARTED=$(docker inspect -f '{{.State.StartedAt}}' $(dc ps -q "$APP") 2> /dev/null)
		if [[ "$APP_STARTED" == "$NOW_STARTED" ]]; then info "(app container was not restarted)"; else info "(app container restarted to recover)"; fi
	else
		fail "API reconnects after '$DB' restarts" "HTTP $CODE $(head -c 200 <<< "$BODY")"
	fi
else
	skip "database-only restart (postgres service not identified; covered by stage 6)"
fi

# ---------------------------------------------------------------------------
stage "8. Good practice (warnings only)"

if [[ -n "$APP" ]]; then
	APP_UID=$(dc exec -T "$APP" id -u 2> /dev/null | tr -d '\r')
	if [[ -n "$APP_UID" && "$APP_UID" != 0 ]]; then gp_pass "app runs as a non-root user (uid $APP_UID)"; else warn "app container runs as root"; fi

	APP_IMAGE=$(docker inspect -f '{{.Image}}' $(dc ps -q "$APP") 2> /dev/null)
	if [[ -n "$APP_IMAGE" ]]; then
		SIZE_MB=$(($(docker image inspect -f '{{.Size}}' "$APP_IMAGE") / 1024 / 1024))
		if ((SIZE_MB <= 300)); then gp_pass "app image is small (${SIZE_MB}MB)"; else warn "app image is ${SIZE_MB}MB (multi-stage build / alpine base / prune dev deps?)"; fi
		if docker image inspect -f '{{json .Config.Env}}' "$APP_IMAGE" | grep -qiE 'DATABASE_URL|PASSWORD'; then
			warn "database credentials are baked into the app image (set them in compose instead)"
		else
			gp_pass "no database credentials baked into the app image"
		fi
	fi

	if jq -e --arg s "$APP" '.services[$s].depends_on // {} | length > 0' <<< "$CONFIG" > /dev/null; then
		gp_pass "app declares depends_on"
	else
		warn "app has no depends_on; startup order is not guaranteed"
	fi
fi

if [[ -n "$DB" ]]; then
	if jq -e --arg s "$DB" '.services[$s].healthcheck.test // empty' <<< "$CONFIG" > /dev/null; then
		gp_pass "database defines a healthcheck"
	else
		warn "database has no healthcheck (so depends_on can't wait for it to be ready)"
	fi
	if jq -e --arg s "$DB" '(.services[$s].ports // []) | length == 0' <<< "$CONFIG" > /dev/null; then
		gp_pass "database port is not published to the host"
	else
		warn "database port is published to the host (only the app needs to reach it)"
	fi
	if jq -e --arg s "$DB" '(.services[$s].volumes // []) | any(.type == "volume")' <<< "$CONFIG" > /dev/null; then
		gp_pass "database data uses a named volume"
	else
		warn "database data does not use a named volume"
	fi
fi

# Docker reads .dockerignore from the build context root, or <Dockerfile>.dockerignore
# next to the Dockerfile (BuildKit), not from wherever the compose file lives.
IGNORE_FILE=""
for f in "$DOCKERFILE.dockerignore" "$BUILD_CTX/.dockerignore"; do
	[[ -f "$f" ]] && { IGNORE_FILE="$f"; break; }
done
if [[ -n "$IGNORE_FILE" ]] && grep -q node_modules "$IGNORE_FILE"; then
	gp_pass ".dockerignore excludes node_modules ($(rel "$IGNORE_FILE"))"
else
	warn "no .dockerignore excluding node_modules in the build context $(rel "$BUILD_CTX") (larger, slower builds)"
fi

summary
[[ $FAILED -eq 0 ]]
