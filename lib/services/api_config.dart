/// Single source of truth for the backend base URL.
///
/// Change this one value when switching between environments:
///
///   Local simulator (iOS/Android):  'http://localhost:8080'
///   Physical device on same WiFi:   'http://192.168.1.105:8080'  ← your Mac's IP
///   Production:                      'https://api.yourdomain.com'
///
/// Find your Mac's local IP:  ipconfig getifaddr en0
const String kBaseUrl = 'http://localhost:8089';
