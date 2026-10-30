#!/usr/bin/env bash
# Build the Flutter web bundle into app/build/web.
#   ./build_web.sh                         API on same origin as the page (relative URLs, no CORS)
#   ./build_web.sh https://api.example.com API on another origin (backend must allow it via CORS)
#   ./build_web.sh http://localhost:8089   local dev against the docker backend
# Serve the result with any static host; for a quick local check:
#   python3 -m http.server 8765 --directory build/web
set -euo pipefail
cd "$(dirname "$0")"
API="${1-}"
flutter build web --release --dart-define=API_BASE_URL="$API"
echo "Built build/web (API_BASE_URL='${API}')"
