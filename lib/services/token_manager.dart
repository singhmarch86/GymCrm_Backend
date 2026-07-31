import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'storage_service.dart';

/// Keeps the stored access token usable.
///
/// Access tokens live 15 minutes (middleware.AccessTokenTTL), so any session
/// left idle longer than that used to fail its next request and dump the user
/// back at the login screen mid-task.
///
/// This refreshes **proactively** — it inspects the JWT's `exp` before a
/// request is built and swaps in a new token if it is about to lapse — rather
/// than reactively retrying after a 401. Reactive retry would be wrong here:
/// several services build their headers *outside* the `guardRequest` closure,
/// so replaying that closure would resend the very same expired token. Fixing
/// that would mean rewriting every call site; checking expiry up front works
/// no matter where the headers are assembled.
class TokenManager {
  TokenManager._();

  /// Refresh this far ahead of the real expiry, so a token cannot lapse
  /// in-flight between building headers and the server validating them.
  static const Duration _refreshMargin = Duration(seconds: 60);

  /// De-duplicates concurrent refreshes. The dashboard fires several requests
  /// at once; without this, each would kick off its own refresh and they would
  /// race to rotate the refresh token — the losers invalidating the winner.
  static Future<String?>? _inFlight;

  /// Returns an access token that is valid now, refreshing first if needed.
  /// Returns null when there is no session or the refresh token is also dead —
  /// callers then get a 401 and route to login as before.
  static Future<String?> accessToken() async {
    final stored = await StorageService.getAccessToken();
    if (stored == null || stored.isEmpty) return null;

    if (!_isExpiringSoon(stored)) return stored;

    // Coalesce onto an in-flight refresh if one is already running.
    _inFlight ??= _refresh();
    try {
      return await _inFlight;
    } finally {
      _inFlight = null;
    }
  }

  /// Builds standard authenticated JSON headers, refreshing the token if due.
  /// Every service's header helper routes through here.
  static Future<Map<String, String>> authHeaders() async {
    final token = await accessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ─── Internals ──────────────────────────────────────────────────────────────

  static Future<String?> _refresh() async {
    final refreshToken = await StorageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      // Deliberately a bare http call, not guardRequest: this must never
      // recurse back into the refresh path.
      final response = await http.post(
        Uri.parse('$kBaseUrl/api/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        // The refresh token is spent or revoked — the session is genuinely
        // over. Clear it so the app stops retrying a dead credential.
        await StorageService.clearAll();
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      final newAccess = data?['access_token'] as String?;
      final newRefresh = data?['refresh_token'] as String?;

      if (newAccess == null || newAccess.isEmpty) {
        await StorageService.clearAll();
        return null;
      }

      await StorageService.saveTokens(
        accessToken: newAccess,
        // The backend rotates refresh tokens; fall back to the current one if
        // a future version stops returning a replacement.
        refreshToken: (newRefresh != null && newRefresh.isNotEmpty)
            ? newRefresh
            : refreshToken,
      );

      return newAccess;
    } catch (_) {
      // Network failure — keep the stored session rather than logging the user
      // out over a transient blip. The pending request will surface its own
      // "could not reach the server" error.
      return null;
    }
  }

  /// True when the JWT expires within [_refreshMargin], or cannot be read.
  ///
  /// An unparseable token is treated as expiring so we attempt a refresh
  /// instead of sending something the server will certainly reject.
  static bool _isExpiringSoon(String jwt) {
    final exp = _expiryOf(jwt);
    if (exp == null) return true;
    return DateTime.now().toUtc().add(_refreshMargin).isAfter(exp);
  }

  static DateTime? _expiryOf(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;

      // JWT uses base64url without padding; normalize() restores it.
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;

      final exp = payload['exp'];
      if (exp is! int) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }
}
