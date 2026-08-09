# Deploying GymCRM

One VPS, three containers: the Go API, Postgres, and nginx serving the Flutter
web build. Everything sits behind a single origin, so there is no CORS to
configure and no rebuild when the hostname changes.

Sized for one gym or a small chain. If that stops being true the database is
the first thing to move out, not the last.

---

## 1. Build the web app

From the `gymcrm_app` repo:

```bash
flutter build web --release --dart-define=API_BASE_URL=
```

**The empty `API_BASE_URL` is the important part.** It makes every request
relative (`/api/v1/...`), so the app talks to whatever host it was served from.
Leave it out and the bundle will hard-code `localhost:8089` and fail on any
machine that is not yours.

Then copy the output next to the compose file:

```bash
mkdir -p deploy/web
rsync -a --delete ../gymcrm_app/build/web/ deploy/web/
```

**Do not `rm -rf deploy/web` while the stack is running.** Docker bind-mounts
that directory by inode, not by path — delete it and the running nginx
container is left pointing at a directory that no longer exists, serving 403
on every request. `rsync --delete` replaces the *contents* and leaves the
directory itself alone. If you do delete it by accident, `docker compose ...
restart web` re-binds it.

## 2. Write the secrets

```bash
cp deploy/.env.example deploy/.env
```

Fill in `deploy/.env`. Generate a real JWT secret — do not invent one by hand:

```bash
openssl rand -base64 48
```

`deploy/.env` is gitignored and must stay that way. If a JWT secret ever
reaches a commit, rotate it: anyone holding it can mint a valid token for any
gym.

## 3. Start it

```bash
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env up -d --build
```

The app is on port 80. Check it:

```bash
curl -s localhost/api/v1/health
```

## 4. HTTPS

**Do this before a real gym touches it.** Logins and member phone numbers go
over this connection; on plain HTTP they travel in clear text over whatever
café WiFi the owner is using.

nginx terminates TLS with a free Let's Encrypt certificate, renewed
automatically. You need a **domain pointing at this server** first — a bare IP
cannot get a certificate.

Set `DOMAIN` and `LETSENCRYPT_EMAIL` in `deploy/.env`, then run once:

```bash
./deploy/init-tls.sh
```

That script exists to solve a genuine chicken-and-egg: **nginx will not start
without a certificate, and certbot cannot obtain one without nginx running** to
answer the challenge. It places a throwaway self-signed certificate, starts
nginx, lets certbot replace it with a real one, and reloads. Run once and never
again.

From then on, start the stack with the TLS overlay:

```bash
docker compose -f deploy/docker-compose.prod.yml \
               -f deploy/docker-compose.tls.yml \
               --env-file deploy/.env up -d
```

Port 80 redirects to 443, except `/.well-known/acme-challenge/` which must stay
on plain HTTP or renewal fails silently and the certificate expires 90 days
later.

### Confirm renewal before trusting it

```bash
docker compose -f deploy/docker-compose.prod.yml -f deploy/docker-compose.tls.yml \
  --env-file deploy/.env run --rm --entrypoint "certbot renew --dry-run" certbot
```

certbot checks twice daily and nginx reloads every 12 hours to pick up a new
certificate — a certificate renewed at 3am is useless until nginx reloads it,
and nginx does not notice new files on its own.

### HSTS starts short on purpose

`nginx-tls.conf` sets `Strict-Transport-Security: max-age=300`. **HSTS cannot be
undone from the server side** — once a browser caches a long max-age it refuses
plain HTTP for that domain until it expires, even if your certificate breaks.
Run for a week, confirm renewals are clean, then raise it to `31536000`.

### If something else already terminates TLS

Skip the overlay entirely. Use the base compose file, set `HTTP_PORT=8080`, and
point your load balancer or existing reverse proxy at it.

---

## Updating a running deployment

```bash
# 1. rebuild the bundle (on your machine, not the server)
#      flutter build web --release --dart-define=API_BASE_URL=
# 2. replace the CONTENTS of deploy/web — never the directory itself:
rsync -a --delete ../gymcrm_app/build/web/ deploy/web/
# 3. restart:
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env up -d --build
```

Static files are picked up without a restart, since nginx reads them per
request. A restart is only needed if the API changed — or if you deleted and
recreated `deploy/web`, which breaks the mount as described above.

nginx serves `index.html` and the service worker with `no-store`, so browsers
pick up a new build immediately. The hashed JS and asset files are cached hard,
which is safe because their names change every build.

## Applying a migration

Postgres only runs `/docker-entrypoint-initdb.d` on a **brand-new** volume. An
existing database ignores it entirely, which is deliberate — automatic
migrations against live member data are how gyms lose their history.

Apply new ones explicitly, and take a dump first:

```bash
docker compose -f deploy/docker-compose.prod.yml exec -T postgres \
  pg_dump -U "$DB_USER" "$DB_NAME" > backup-$(date +%F).sql

docker compose -f deploy/docker-compose.prod.yml exec -T postgres \
  psql -U "$DB_USER" -d "$DB_NAME" < migrations/0XX_whatever.sql
```

Those dumps contain real member names and phone numbers. Keep them off the
repo and off shared drives.

## Backups

`deploy/backup.sh` takes a gzipped `pg_dump`, verifies it, and only then prunes
anything older than `KEEP_DAYS` (default 14).

**The ordering is the point.** A backup job that prunes before verifying — or
regardless of whether tonight's dump worked — quietly deletes every good backup
you have over a fortnight, and you find out on the day you need one. This one
refuses to prune if the dump is empty, is not valid gzip, has no
`PostgreSQL database dump complete` marker, is under 10 KB, or is less than
half the size of the previous backup.

Run it nightly. `crontab -e` on the host:

```
30 2 * * * /srv/gymcrm/deploy/backup.sh >> /var/log/gymcrm-backup.log 2>&1
```

It exits non-zero on any failure, so wrap it in whatever alerting you have. **A
backup job nobody is alerted about is a backup job that has been broken for
three weeks.**

### Get them off the box

A backup that only exists on the machine you are trying to recover is not a
backup. Add a second line to copy them somewhere else — object storage, another
VPS, anything:

```
0 3 * * * rclone copy /srv/gymcrm/deploy/backups remote:gymcrm-backups
```

These dumps contain **real member names, phone numbers and payment history**.
They are written `0600` into a `0700` directory. Wherever you copy them needs
to be at least as private, and they must never reach the repo.

### Restoring

```bash
./deploy/restore.sh deploy/backups/gymcrm-2026-08-09_030000.sql.gz
```

It asks you to type the database name before overwriting anything.

**Do a restore drill before a pilot gym relies on this.** Restore into a
scratch database and compare row counts against live:

```bash
./deploy/restore.sh deploy/backups/<latest>.sql.gz restoretest
```

A backup you have never restored is a file, not a backup. This script and the
verification above were tested this way against the 800-member demo database —
members, attendance, sales and alerts all came back identical.

---

## What this deliberately does not include

- **TLS certificates.** Deliberately left to a reverse proxy rather than baked
  in, because the right answer depends on whether you use a domain, a subdomain
  per gym, or an IP.
- **Multi-tenancy across servers.** Every gym in one database, separated by
  `gym_id`, is the design. One Postgres holds many gyms.
- **Automatic migrations on boot.** See above. This is a choice, not an
  omission.
- **A demo seeder.** `APP_ENV=production` disables it. A production database
  starts empty and the first gym is created through the app.
