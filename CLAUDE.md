# GymCRM — context for Claude

Monorepo: `backend/` (Go, net/http ServeMux + GORM + Postgres) and `app/` (Flutter; web is the
supported target). Product: gym-management SaaS for independent gyms in Punjab, positioned on
retention ("tells you when your regulars stop being regular"). Run `./setup.sh` on a fresh machine
(see SETUP.md). Windows: `install-prereqs.ps1` (admin, installs Git/Go/Chrome/Docker/Flutter) then `setup.ps1` — both written but untested on Windows.

## Backend conventions
- Module layout: `internal/<name>/{model,repository,service,handler}.go`; routes are registered
  one by one in `backend/cmd/server/main.go` (protected ones wrapped in `jwt(...)`).
- Tenant isolation: every repository query starts from `database.ScopedDB(ctx, db)`; gym_id comes
  from the JWT via `database.MustGetTenant(ctx)`, never from request params. The `gyms` table is
  the tenant itself (no gym_id column), so it is queried by `id` directly.
- Migrations are forward-only files in `backend/migrations/`. docker-compose only auto-mounts
  001–018; apply later ones by hand (setup.sh does this on a fresh DB).
- Design docs live in `backend/docs/FR-*.md` — read the relevant one before changing a feature.
  `docs/USER-MANUAL.md` and `docs/manual-deck/` (pptx built with `node build.js`) describe the
  product; the deck was verified screen-by-screen against the live app.
- Never `docker compose down -v` (destroys seeded data). If `docker compose build` fails with a
  buildx permission error, use `DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0`.
- Demo seed (`internal/devseed`) runs only when APP_ENV=development and the DB is empty.

## Verify, don't infer
Similarly named features are distinct (e.g. Money Leaks = unbilled value given away, FR-21;
Collections = billed-not-collected, lives inside Payments, FR-19). Check the screen or the
service doc comment before describing a feature.

## Work in this stretch (state as of 2026-10-05)
1. **Pricing-tier gating (Normal / Medium / Premium)** — `backend/internal/entitlements`
   (tier.go, features.go, middleware.go `RequireFeature`), migration 037 `gyms.plan_tier`
   (default 'premium' so existing gyms lose nothing), `plan_tier` returned in the auth GymDTO.
   Flutter mirror: `app/lib/services/entitlements_service.dart` — its Feature list and min-tier map
   MUST stay in sync with `features.go`. Flutter hides gated More-screen tiles, the At Risk tab,
   the Analytics Retention/Staff sub-tabs, and wallet / PT report / feedback / recognition /
   move-to-branch on the member page; the Today screen skips the retention summary below Medium.
   Verified in the browser on Normal, Medium and Premium (2026-10-05).
   Reports and Leads were tagged with the owner piece by piece (2026-10-05): Revenue + Members
   reports and the basic Leads CRM (list/add/edit/assign/stage/convert) are on every plan;
   Payments/Renewals/Plans reports and the Leads Board/Workflow/Follow-ups/Analytics are Medium.
   (The Board is UI-only gated — it reads the same GET /leads as the list.)
   Still NOT gated: "owner-level reports", "full audit/history", "advanced staff controls" (not
   mapped to a screen yet) and Premium-only buttons inside the Branches screen.
2. **Per-gym public advertisement page** — migration 036 (slug, tagline, description, cover photo,
   amenities, public phone, `published` default false). Done: `GET /api/v1/public/gyms/{slug}`
   (no auth) and owner-only `GET/PATCH /api/v1/gyms/public-profile`. NOT done: the server-rendered
   HTML page at `/g/{slug}` (SSR needed for SEO; Flutter web is client-rendered), the Flutter
   settings screen, downloadable QR code. Marketing only — no shop/products on it.
3. Migrations 036/037 verified on a fresh DB via setup.sh (2026-10-05); gating (403 below the
   required tier) and the public-page endpoints were exercised live with curl. The page_url in the
   settings response uses PUBLIC_BASE_URL (defaults to http://localhost:8080; not set in compose).

## Other projects
This repo is GymCRM only. Archecommerce (multi-vendor e-commerce) is a separate project.
