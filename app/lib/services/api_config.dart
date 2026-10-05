/// Single source of truth for the backend base URL.
///
/// Set at build time, so one codebase ships to every environment:
///
///   Local dev (the default, no flag needed):
///     flutter run -d chrome
///
///   Deployed behind one origin — nginx serves the app and proxies /api to
///   the Go service. Pass an EMPTY value so every request becomes relative:
///     flutter build web --release --dart-define=API_BASE_URL=
///
///   Backend on a separate host (needs CORS configured there):
///     flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
///
///   Physical device on the same WiFi (find your IP: ipconfig getifaddr en0):
///     flutter run --dart-define=API_BASE_URL=http://192.168.1.105:8089
///
/// Same-origin is the deployment worth preferring: relative URLs mean no CORS
/// to configure, no mixed-content trouble behind HTTPS, and no rebuild when
/// the API's hostname changes.
const String kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8089',
);
