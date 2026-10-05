#!/usr/bin/env bash
# One-shot bootstrap for a fresh machine. Safe to re-run: migrations are
# applied only when the database has no gym yet; otherwise it just rebuilds
# and restarts the app. Never uses `down -v` (that deletes the seeded data).
set -euo pipefail
cd "$(dirname "$0")"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1 — $2"; exit 1; }; }
need git "install git"
need docker "install Docker Desktop or OrbStack"
need flutter "install the Flutter SDK (https://docs.flutter.dev/get-started/install)"
docker info >/dev/null 2>&1 || { echo "Docker is installed but not running — start it and re-run."; exit 1; }

cd backend
echo "▶ Starting Postgres..."
docker compose up -d postgres
until [ "$(docker compose ps postgres --format '{{.Health}}' 2>/dev/null)" = "healthy" ]; do sleep 2; done

PSQL="docker compose exec -T postgres psql -U gymcrm -d gymcrm"
HAS_GYMS=$($PSQL -tAc "SELECT to_regclass('public.gyms') IS NOT NULL AND EXISTS (SELECT 1 FROM gyms)" 2>/dev/null || echo f)

if [ "$HAS_GYMS" != "t" ]; then
  echo "▶ Fresh database — applying migrations 019 onward (001–018 auto-run)..."
  for f in $(ls migrations/*.sql | sort); do
    n=$(basename "$f" | cut -d_ -f1)
    if [ $((10#$n)) -ge 19 ]; then
      echo "   $f"
      $PSQL -v ON_ERROR_STOP=1 < "$f"
    fi
  done
else
  echo "▶ Database already has data — skipping migrations (apply new ones by hand if you pulled any)."
fi

echo "▶ Building and starting the API (first boot seeds the demo gym)..."
if ! docker compose up -d --build app; then
  echo "   build failed — retrying with the legacy builder (buildx permission workaround)"
  DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0 docker compose up -d --build app
fi

cd ../app
echo "▶ Fetching Flutter packages..."
flutter pub get

cat <<MSG

✔ Backend: http://localhost:8089  (API docs: /swagger/)
✔ Run the app:   cd app && flutter run -d chrome
  Login: 9876543210 / secure123  (owner of the demo gym)
MSG
