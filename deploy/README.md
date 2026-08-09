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
rm -rf deploy/web && cp -r ../gymcrm_app/build/web deploy/web
```

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

## 4. Put HTTPS in front of it

**Do this before a real gym touches it.** Logins and member phone numbers go
over this connection, and on plain HTTP they travel in clear text over whatever
café WiFi the owner is using.

The simplest route on a fresh VPS is Caddy or nginx with certbot in front,
terminating TLS and proxying to port 80. Point `HTTP_PORT` at something like
`8080` in `.env` first so the reverse proxy can own port 80.

---

## Updating a running deployment

```bash
# rebuild the web bundle, copy it in, then:
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env up -d --build
```

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

Nothing here backs itself up. Before a pilot gym relies on this, put a nightly
`pg_dump` on a cron and copy it somewhere off the box — a gym losing its member
list is not a recoverable situation for them or for you.

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
