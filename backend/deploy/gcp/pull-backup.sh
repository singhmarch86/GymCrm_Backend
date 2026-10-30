#!/usr/bin/env bash
# Take a fresh, verified database dump on the VM and copy it to this laptop
# (and the deploy secrets with it). Run it weekly, and ALWAYS right before
# leaving a GCP account — once the trial ends the VM and its disk go with it.
set -euo pipefail
. "$(dirname "$0")/common.sh"

vm_ssh 'cd ~/moka && ./deploy/backup.sh' | tail -3
LATEST="$(vm_ssh 'ls -1t ~/moka/deploy/backups/gymcrm-*.sql.gz | head -1' | tr -d '\r')"
[ -n "$LATEST" ] || die "no backup found on the VM"
vm_scp "$VM_NAME:$LATEST" "$MOKA_HOME/backups/"
OUT="$MOKA_HOME/backups/$(basename "$LATEST")"
chmod 600 "$OUT"
gzip -t "$OUT" || die "downloaded file is corrupt"
log "saved $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
log "keep a second copy somewhere that is NOT this laptop (external drive / another cloud)"
