#!/usr/bin/env bash
#
# Restore a GymCRM backup.
#
#   ./deploy/restore.sh deploy/backups/gymcrm-2026-08-09_030000.sql.gz
#
# This exists because a backup you have never restored is not a backup, it is
# a file. Run it against a scratch database at least once before you need it
# for real — the day you need it is the worst possible day to discover the
# dumps were unusable.
#
# It OVERWRITES the target database. The dump is taken with --clean
# --if-exists, so it drops existing objects before recreating them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$SCRIPT_DIR/docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
SERVICE="${SERVICE:-postgres}"

BACKUP="${1:-}"
[ -n "$BACKUP" ] || { echo "usage: $0 <backup.sql.gz> [target_db]" >&2; exit 1; }
[ -f "$BACKUP" ] || { echo "no such file: $BACKUP" >&2; exit 1; }

# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
: "${DB_USER:?}" "${DB_NAME:?}" "${DB_PASSWORD:?}"

TARGET_DB="${2:-$DB_NAME}"

gzip -t "$BACKUP" || { echo "backup is not valid gzip" >&2; exit 1; }

cat <<EOF

  Restoring : $BACKUP
  Into      : database "$TARGET_DB"

  This REPLACES the contents of that database. If it is the live one, every
  member, payment and invoice recorded since the backup was taken is lost.

EOF
read -r -p 'Type the database name to confirm: ' confirm
[ "$confirm" = "$TARGET_DB" ] || { echo "aborted"; exit 1; }

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T \
    -e PGPASSWORD="$DB_PASSWORD" "$SERVICE" \
    psql -U "$DB_USER" -d "$TARGET_DB" -v ON_ERROR_STOP=1 \
    < <(gunzip -c "$BACKUP")

echo "restored into $TARGET_DB"
