# One-shot bootstrap for Windows (PowerShell 5.1+ or 7). Safe to re-run: migrations are
# applied only when the database has no gym yet. Never uses `down -v` (deletes seeded data).
#   Right-click folder > Open in Terminal, then:  powershell -ExecutionPolicy Bypass -File .\setup.ps1
Set-Location $PSScriptRoot

function Need($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Write-Host "Missing: $cmd - $hint"; exit 1 }
}
Need git "install Git for Windows"
Need docker "install Docker Desktop (WSL2 backend) and start it"
Need flutter "install the Flutter SDK and add it to PATH (https://docs.flutter.dev/get-started/install/windows)"

docker info *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "Docker is installed but not running - start Docker Desktop and re-run."; exit 1 }

Set-Location backend
Write-Host "> Starting Postgres..."
docker compose up -d postgres
if ($LASTEXITCODE -ne 0) { exit 1 }
do { Start-Sleep -Seconds 2; $health = (docker compose ps postgres --format '{{.Health}}') } until ($health -eq 'healthy')

$hasGyms = (docker compose exec -T postgres psql -U gymcrm -d gymcrm -tAc "SELECT to_regclass('public.gyms') IS NOT NULL AND EXISTS (SELECT 1 FROM gyms)" 2>$null)
if ("$hasGyms".Trim() -ne 't') {
  Write-Host "> Fresh database - applying migrations 019 onward (001-018 auto-run)..."
  Get-ChildItem migrations\*.sql | Sort-Object Name | ForEach-Object {
    $n = [int]($_.Name.Split('_')[0])
    if ($n -ge 19) {
      Write-Host "   $($_.Name)"
      # Copy the file in and run it with -f: piping through PowerShell would mangle non-ASCII text.
      docker compose cp $_.FullName postgres:/tmp/migration.sql
      docker compose exec -T postgres psql -U gymcrm -d gymcrm -v ON_ERROR_STOP=1 -f /tmp/migration.sql
      if ($LASTEXITCODE -ne 0) { Write-Host "Migration failed: $($_.Name)"; exit 1 }
    }
  }
} else {
  Write-Host "> Database already has data - skipping migrations (apply new ones by hand if you pulled any)."
}

Write-Host "> Building and starting the API (first boot seeds the demo gym)..."
docker compose up -d --build app
if ($LASTEXITCODE -ne 0) {
  Write-Host "   build failed - retrying with the legacy builder"
  $env:DOCKER_BUILDKIT = '0'; $env:COMPOSE_DOCKER_CLI_BUILD = '0'
  docker compose up -d --build app
  if ($LASTEXITCODE -ne 0) { Write-Host "Build failed twice - if it was a download error, just re-run."; exit 1 }
}

Set-Location ..\app
Write-Host "> Fetching Flutter packages..."
flutter pub get

Write-Host ""
Write-Host "OK Backend: http://localhost:8089  (API docs: /swagger/)"
Write-Host "OK Run the app:   cd app; flutter run -d chrome"
Write-Host "   Login: 9876543210 / secure123  (owner of the demo gym)"
