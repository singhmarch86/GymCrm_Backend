#!/usr/bin/env bash
# Load a dump into the VM's database. REPLACES everything currently in it.
#
#   ./restore.sh [dump.sql.gz]      (default: newest in $MOKA_HOME/backups)
#
# Use on a freshly deployed VM in the new account. The dump was taken with
# --clean --if-exists, so it drops and recreates every table inside one
# transaction: if anything fails, the old data is still there.
set -euo pipefail
. "$(dirname "$0")/common.sh"

DUMP="${1:-$(ls -1t "$MOKA_HOME"/backups/gymcrm-*.sql.gz 2>/dev/null | head -1)}"
[ -f "$DUMP" ] || die "no dump found (pass a path, or run pull-backup.sh first)"
gzip -t "$DUMP" || die "$DUMP is corrupt"

echo "About to REPLACE the database on $VM_NAME ($(vm_ip)) with:"
echo "  $DUMP"
read -r -p "Type YES to continue: " ans
[ "$ans" = "YES" ] || die "aborted"

vm_scp "$DUMP" "$VM_NAME:~/restore.sql.gz"
vm_ssh 'set -e
cd ~/moka
C="sudo docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env"
set -a; . deploy/.env; set +a
$C stop app
gunzip -c ~/restore.sql.gz | $C exec -T -e PGPASSWORD="$DB_PASSWORD" postgres \
    psql -v ON_ERROR_STOP=1 --single-transaction -q -U "$DB_USER" -d "$DB_NAME" >/dev/null
rm -f ~/restore.sql.gz
$C start app
echo "restored; members: $($C exec -T -e PGPASSWORD="$DB_PASSWORD" postgres psql -At -U "$DB_USER" -d "$DB_NAME" -c "select count(*) from members")"'
log "done. Open http://$(vm_ip) and log in with your existing account."
