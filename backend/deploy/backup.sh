#!/usr/bin/env bash
#
# Nightly Postgres backup for a GymCRM deployment.
#
#   ./deploy/backup.sh
#
# Writes a gzipped pg_dump to $BACKUP_DIR, then prunes dumps older than
# $KEEP_DAYS.
#
# The ordering matters and is the whole point of the script: the new dump is
# verified BEFORE anything old is deleted. A backup job that prunes first, or
# that prunes regardless of whether tonight's dump worked, will quietly delete
# every good backup you have over the course of a fortnight and you will find
# out on the day you need one.
#
# These dumps contain real member names, phone numbers and payment history.
# They are written 0600, and getting them off this machine is still your job —
# a backup that only exists on the box you are trying to recover is not a
# backup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$SCRIPT_DIR/docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
SERVICE="${SERVICE:-postgres}"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { log "FAILED: $*" >&2; exit 1; }

[ -f "$COMPOSE_FILE" ] || die "no compose file at $COMPOSE_FILE"
[ -f "$ENV_FILE" ]     || die "no env file at $ENV_FILE"

# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
: "${DB_USER:?DB_USER not set in $ENV_FILE}"
: "${DB_NAME:?DB_NAME not set in $ENV_FILE}"
: "${DB_PASSWORD:?DB_PASSWORD not set in $ENV_FILE}"

compose() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

STAMP="$(date '+%Y-%m-%d_%H%M%S')"
TARGET="$BACKUP_DIR/gymcrm-$STAMP.sql.gz"
TMP="$TARGET.partial"

# Written to .partial first so an interrupted run can never leave a truncated
# file sitting there looking like a real backup.
trap 'rm -f "$TMP"' EXIT

log "dumping $DB_NAME ..."

# PGPASSWORD is passed through docker exec's environment rather than typed on
# the command line, so it does not show up in `ps` on the host.
if ! compose exec -T \
        -e PGPASSWORD="$DB_PASSWORD" \
        "$SERVICE" \
        pg_dump -U "$DB_USER" -d "$DB_NAME" --clean --if-exists \
    | gzip -9 > "$TMP"
then
    die "pg_dump returned non-zero — nothing pruned"
fi

# ── Verify before pruning ────────────────────────────────────────────────────

[ -s "$TMP" ] || die "dump is empty — nothing pruned"

gzip -t "$TMP" 2>/dev/null || die "dump is not valid gzip — nothing pruned"

# A dump that ran but produced no schema is worse than a failure, because it
# looks like success. Postgres ends every complete dump with this marker.
if ! gunzip -c "$TMP" | tail -5 | grep -q 'PostgreSQL database dump complete'; then
    die "dump has no completion marker, may be truncated — nothing pruned"
fi

SIZE_BYTES="$(wc -c < "$TMP" | tr -d ' ')"
if [ "$SIZE_BYTES" -lt 10240 ]; then
    die "dump is only ${SIZE_BYTES} bytes, that is not a real gym — nothing pruned"
fi

# Compare against the most recent previous backup. A sudden collapse in size
# usually means the dump ran against the wrong database, or somebody dropped
# something. Worth refusing to prune over.
PREV="$(ls -1t "$BACKUP_DIR"/gymcrm-*.sql.gz 2>/dev/null | head -1 || true)"
if [ -n "$PREV" ] && [ -f "$PREV" ]; then
    PREV_SIZE="$(wc -c < "$PREV" | tr -d ' ')"
    if [ "$PREV_SIZE" -gt 0 ] && [ $((SIZE_BYTES * 2)) -lt "$PREV_SIZE" ]; then
        log "WARNING: this dump ($SIZE_BYTES b) is less than half the previous ($PREV_SIZE b)"
        die "suspicious size drop — keeping every existing backup, investigate"
    fi
fi

mv "$TMP" "$TARGET"
chmod 600 "$TARGET"
trap - EXIT

log "wrote $TARGET ($SIZE_BYTES bytes)"

# ── Prune, only now that tonight's dump is known good ────────────────────────

DELETED=0
while IFS= read -r old; do
    rm -f "$old"
    DELETED=$((DELETED + 1))
    log "pruned $(basename "$old")"
done < <(find "$BACKUP_DIR" -name 'gymcrm-*.sql.gz' -type f -mtime "+$KEEP_DAYS" 2>/dev/null)

log "done — kept $(find "$BACKUP_DIR" -name 'gymcrm-*.sql.gz' -type f | wc -l | tr -d ' ') backups, pruned $DELETED"
