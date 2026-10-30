#!/usr/bin/env bash
# Build the web app, upload the backend + web bundle, and (re)start the stack.
# Run from anywhere; re-run for every update. Data in Postgres is untouched.
#
#   ./deploy.sh
#
# First run generates the secrets into $MOKA_HOME/env. On a NEW account, keep
# that same file so the JWT secret and invite code carry over (DB password may
# differ — it is only used inside the VM).
set -euo pipefail
. "$(dirname "$0")/common.sh"

ENV_FILE="$MOKA_HOME/env"
if [ ! -f "$ENV_FILE" ]; then
  log "first deploy: generating secrets into $ENV_FILE"
  ( umask 077
    cat > "$ENV_FILE" <<EOF
DB_USER=gymcrm
DB_NAME=gymcrm
DB_PASSWORD=$(openssl rand -hex 24)
JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')
HTTP_PORT=80
CORS_ALLOWED_ORIGINS=
REGISTRATION_INVITE_CODE=moka-$(openssl rand -hex 8)
ALLOW_PUBLIC_REGISTRATION=false
EOF
  )
fi
chmod 600 "$ENV_FILE"

log "building the web app (relative API URLs, same-origin)"
( cd "$REPO_ROOT/app" && ./build_web.sh >/dev/null )

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
rsync -a --exclude .git --exclude backups --exclude bin "$REPO_ROOT/backend/" "$STAGE/"
mkdir -p "$STAGE/deploy/web"; rsync -a "$REPO_ROOT/app/build/web/" "$STAGE/deploy/web/"
cp "$ENV_FILE" "$STAGE/deploy/.env"
tar czf "$STAGE.tgz" -C "$STAGE" .

log "uploading"
vm_scp "$STAGE.tgz" "$VM_NAME:~/moka-deploy.tgz"; rm -f "$STAGE.tgz"

log "starting the stack"
vm_ssh 'set -e
mkdir -p ~/moka
# Replace code and the web bundle; leave deploy/backups and the pgdata volume alone.
tar xzf ~/moka-deploy.tgz -C ~/moka && rm ~/moka-deploy.tgz
chmod 600 ~/moka/deploy/.env
chmod +x ~/moka/deploy/backup.sh
cd ~/moka
sudo docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env up -d --build
# nginx reads its config only at start; pick up edits to nginx.conf.
sudo docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env restart web
( crontab -l 2>/dev/null | grep -v moka-backup; echo "0 2 * * * cd ~/moka && ./deploy/backup.sh >> ~/moka-backup.log 2>&1 # moka-backup" ) | crontab -'

IP="$(vm_ip)"
sleep 4
log "API check (401 = healthy): $(curl -s -o /dev/null -w '%{http_code}' "http://$IP/api/v1/plans")"
log "Live at http://$IP"
