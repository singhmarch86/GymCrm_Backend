.PHONY: run dev db-up db-down db-reset migrate tidy

# ── Local dev (reads .env automatically) ────────────────────
run:
	@export $$(cat .env | grep -v '^#' | xargs) && go run ./cmd/server

# ── Docker Compose (DB only, run app locally) ────────────────
db-up:
	docker compose up postgres -d
	@echo "Postgres ready on localhost:5432"

db-down:
	docker compose down

db-reset:
	docker compose down -v
	docker compose up postgres -d

# ── Full stack via Docker ────────────────────────────────────
up:
	docker compose up --build

down:
	docker compose down

# ── Migrations (requires golang-migrate) ────────────────────
migrate-up:
	@export $$(cat .env | grep -v '^#' | xargs) && \
	migrate -path ./migrations \
	        -database "postgres://$$DB_USER:$$DB_PASSWORD@$$DB_HOST:$$DB_PORT/$$DB_NAME?sslmode=$$DB_SSLMODE" \
	        up

migrate-down:
	@export $$(cat .env | grep -v '^#' | xargs) && \
	migrate -path ./migrations \
	        -database "postgres://$$DB_USER:$$DB_PASSWORD@$$DB_HOST:$$DB_PORT/$$DB_NAME?sslmode=$$DB_SSLMODE" \
	        down 1

# ── Go deps ──────────────────────────────────────────────────
tidy:
	go mod tidy

build:
	go build -o bin/gymcrm ./cmd/server
