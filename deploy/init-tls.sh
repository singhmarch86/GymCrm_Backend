#!/usr/bin/env bash
#
# One-time TLS bootstrap. Run once, on the server, after DNS points at it.
#
#   ./deploy/init-tls.sh
#
# ── The problem this solves ──────────────────────────────────────────────────
#
# There is a chicken-and-egg at first start:
#
#   nginx will not start because the certificate files do not exist yet,
#   and certbot cannot get a certificate because nginx is not running to
#   answer the HTTP challenge.
#
# So this script puts a throwaway self-signed certificate in place, starts
# nginx with it, lets certbot replace it with a real one, and reloads. After
# this runs once, renewal is automatic and this script is never needed again.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
BASE="$SCRIPT_DIR/docker-compose.prod.yml"
TLS="$SCRIPT_DIR/docker-compose.tls.yml"

log()  { printf '\n==> %s\n' "$*"; }
die()  { printf 'FAILED: %s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || die "no env file at $ENV_FILE — copy .env.example first"
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

: "${DOMAIN:?set DOMAIN in $ENV_FILE, e.g. gym.example.com}"
: "${LETSENCRYPT_EMAIL:?set LETSENCRYPT_EMAIL in $ENV_FILE — this is where expiry warnings go}"

compose() { docker compose -f "$BASE" -f "$TLS" --env-file "$ENV_FILE" "$@"; }

# ── Sanity: does this domain actually point here? ────────────────────────────
#
# Getting this wrong is the single most common way to hit Let's Encrypt's
# rate limit (5 failures per hour), which then blocks you for an hour with
# no way to hurry it.
log "Checking DNS for $DOMAIN"
RESOLVED="$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1 || true)"
PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
if [ -n "$RESOLVED" ] && [ -n "$PUBLIC_IP" ] && [ "$RESOLVED" != "$PUBLIC_IP" ]; then
    printf '  %s resolves to %s, this machine looks like %s\n' "$DOMAIN" "$RESOLVED" "$PUBLIC_IP"
    read -r -p '  Continue anyway? [y/N] ' go
    [ "$go" = "y" ] || die "point DNS at this server first, then re-run"
elif [ -z "$RESOLVED" ]; then
    printf '  Could not resolve %s. DNS may not have propagated yet.\n' "$DOMAIN"
    read -r -p '  Continue anyway? [y/N] ' go
    [ "$go" = "y" ] || die "wait for DNS, then re-run"
else
    printf '  OK — %s -> %s\n' "$DOMAIN" "$RESOLVED"
fi

CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

# ── Step 1: throwaway certificate so nginx can start at all ──────────────────
log "Placing a temporary self-signed certificate"
compose run --rm --entrypoint "/bin/sh -c '\
  mkdir -p $CERT_PATH && \
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout $CERT_PATH/privkey.pem \
    -out $CERT_PATH/fullchain.pem \
    -subj \"/CN=localhost\" 2>/dev/null'" certbot \
  || die "could not write the temporary certificate"

# ── Step 2: bring nginx up so the challenge can be answered ──────────────────
log "Starting the stack"
compose up -d --build
sleep 5

# ── Step 3: replace it with a real certificate ───────────────────────────────
log "Requesting a certificate from Let's Encrypt for $DOMAIN"

# The temporary cert must be deleted first, or certbot sees an existing
# certificate for this domain and declines to replace it.
compose run --rm --entrypoint "rm -rf $CERT_PATH /etc/letsencrypt/archive/$DOMAIN /etc/letsencrypt/renewal/$DOMAIN.conf" certbot

STAGING_FLAG=""
if [ "${LETSENCRYPT_STAGING:-0}" = "1" ]; then
    log "Using the STAGING server — the certificate will NOT be trusted by browsers"
    STAGING_FLAG="--staging"
fi

if ! compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $STAGING_FLAG \
    --email $LETSENCRYPT_EMAIL \
    -d $DOMAIN \
    --agree-tos --no-eff-email --non-interactive" certbot
then
    die "certbot failed. Check that port 80 is reachable from the internet and
     that $DOMAIN points at this machine. Re-run with LETSENCRYPT_STAGING=1
     while debugging so you do not burn the rate limit (5 failures per hour)."
fi

# ── Step 4: load the real certificate ────────────────────────────────────────
log "Reloading nginx"
compose exec web nginx -s reload

cat <<EOF

  Done. https://$DOMAIN should now serve GymCRM.

  Renewal is automatic — certbot checks twice a day and nginx reloads every
  12 hours to pick up a new certificate.

  Two follow-ups worth doing:

    1. Confirm renewal actually works before trusting it:
         docker compose -f $BASE -f $TLS --env-file $ENV_FILE \\
           run --rm --entrypoint "certbot renew --dry-run" certbot

    2. After about a week of clean renewals, raise the HSTS max-age in
       deploy/nginx-tls.conf from 300 to 31536000. It starts short on
       purpose — HSTS cannot be undone from the server side.

EOF
