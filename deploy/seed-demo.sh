#!/usr/bin/env bash
#
# Load the demo dataset into a DEMO deployment.
#
#   ./deploy/seed-demo.sh deploy/demo/gymcrm-2026-08-09_205407.sql.gz
#
# ── Read this before using it ────────────────────────────────────────────────
#
# This is for a demo server — something you point a prospective gym owner at,
# with 800 fictional members so the screens look like a real business.
#
# It is NOT for the server a real gym uses. Demo data and customer data must
# never share a database: the day a gym scrolls their member list and finds
# "Aarav Sharma" next to their actual members, you have a credibility problem
# that no apology fixes.
#
# Two things enforce that:
#
#   1. The script REFUSES to run if the target database already contains any
#      gym. It can seed an empty database and nothing else. So it can never
#      overwrite a customer, and never top up a database that is already in
#      use.
#   2. It asks you to type the word "demo" first.
#
# Run a demo server as its own deployment — its own project name, its own
# volume, ideally its own host or at least its own domain.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$SCRIPT_DIR/docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
PROJECT="${PROJECT:-gymcrm-demo}"
SERVICE="${SERVICE:-postgres}"

log()  { printf '\n==> %s\n' "$*"; }
die()  { printf 'REFUSED: %s\n' "$*" >&2; exit 1; }

SEED="${1:-}"
[ -n "$SEED" ] || { echo "usage: $0 <demo-seed.sql.gz>" >&2; exit 1; }
[ -f "$SEED" ] || die "no such file: $SEED"
[ -f "$ENV_FILE" ] || die "no env file at $ENV_FILE"

# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
: "${DB_USER:?}" "${DB_NAME:?}" "${DB_PASSWORD:?}"

compose() { docker compose -p "$PROJECT" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

gzip -t "$SEED" || die "$SEED is not valid gzip"

# ── The guard ────────────────────────────────────────────────────────────────
#
# Counting gyms rather than checking a flag, because a flag can be stale and a
# row cannot. If anything is in there, somebody is using it.
log "Checking the target database is empty"
# stdin is redirected from /dev/null on every compose exec that is not
# loading the dump. `docker compose exec` consumes stdin even with -T, and
# without this the guard query swallows the confirmation keystrokes below —
# read then hits EOF, and `set -e` kills the script with no message at all.
EXISTING="$(compose exec -T -e PGPASSWORD="$DB_PASSWORD" "$SERVICE" \
    psql -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT count(*) FROM gyms" </dev/null 2>/dev/null | tr -d '[:space:]' || echo "unknown")"

if [ "$EXISTING" = "unknown" ]; then
    die "could not read the gyms table — is the '$PROJECT' stack running?"
fi
if [ "$EXISTING" != "0" ]; then
    die "the target database already has $EXISTING gym(s).
     This script only ever seeds an EMPTY database, so it cannot overwrite a
     real customer. If this really is a scratch demo box, tear the volume down
     and start clean:
       docker compose -p $PROJECT -f $COMPOSE_FILE --env-file $ENV_FILE down -v"
fi

cat <<EOF

  Seeding : $SEED
  Into    : project "$PROJECT", database "$DB_NAME"

  This loads ~800 FICTIONAL members. Only ever do this on a demo server.

EOF
read -r -p 'Type demo to confirm: ' confirm
[ "$confirm" = "demo" ] || { echo "aborted"; exit 1; }

log "Loading"
compose exec -T -e PGPASSWORD="$DB_PASSWORD" "$SERVICE" \
    psql -U "$DB_USER" -d "$DB_NAME" -q < <(gunzip -c "$SEED")

MEMBERS="$(compose exec -T -e PGPASSWORD="$DB_PASSWORD" "$SERVICE" \
    psql -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT count(*) FROM members WHERE deleted_at IS NULL" </dev/null | tr -d '[:space:]')"

cat <<EOF

  Done — $MEMBERS members loaded.

  The demo owner login comes from the dataset, not from this script. For the
  standard demo dump that is phone 9876543210 / password secure123.

  CHANGE THAT PASSWORD if the demo server is reachable from the internet. It
  is published in this repo, and a demo box with a known password is still a
  box somebody can log into.

EOF
