import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/api_config.dart';
import '../services/api_response.dart';

/// Client for the vendor console (FR-12). The platform token is held in
/// memory only — it is a 2-hour credential that can reach every customer, so
/// it is never written to disk and a page reload signs the admin out.
class PlatformService {
  static String? _token;
  static Map<String, dynamic>? admin;

  static bool get signedIn => _token != null;
  static void signOut() {
    _token = null;
    admin = null;
  }

  static void useToken(String token, Map<String, dynamic>? who) {
    _token = token;
    admin = who;
  }

  /// An empty collection comes back as `data: null`, not `[]`.
  static List<Map<String, dynamic>> _list(dynamic d) =>
      d == null ? [] : List<Map<String, dynamic>>.from(d as List);

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final uri = Uri.parse('$kBaseUrl/api/v1/platform$path');
    final headers = {
      ..._headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final res = await guardRequest(() async {
      switch (method) {
        case 'POST':
          return http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
        case 'PATCH':
          return http.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          );
        default:
          return http.get(uri, headers: headers);
      }
    });
    try {
      return unwrapJson(res)['data'];
    } on ApiException catch (e) {
      // A dead platform session (expired after 2h, admin disabled) is signed out.
      if (e.statusCode == 401 && token == null && path != '/login') signOut();
      rethrow;
    }
  }

  /// Returns the raw login result: totp_required / enrolment_required / token.
  static Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String code = '',
    String recoveryCode = '',
  }) async {
    final d = await _send(
      'POST',
      '/login',
      body: {
        'email': email,
        'password': password,
        if (code.isNotEmpty) 'code': code,
        if (recoveryCode.isNotEmpty) 'recovery_code': recoveryCode,
      },
    );
    return Map<String, dynamic>.from(d);
  }

  static Future<Map<String, dynamic>> startEnrolment(String enrolToken) async =>
      Map<String, dynamic>.from(
        await _send('POST', '/2fa/setup', token: enrolToken),
      );

  static Future<Map<String, dynamic>> confirmEnrolment(
    String enrolToken,
    String code,
  ) async => Map<String, dynamic>.from(
    await _send(
      'POST',
      '/2fa/confirm',
      body: {'code': code},
      token: enrolToken,
    ),
  );

  static Future<List<Map<String, dynamic>>> gyms() async =>
      _list(await _send('GET', '/gyms'));

  static Future<Map<String, dynamic>> gym(int id) async =>
      Map<String, dynamic>.from(await _send('GET', '/gyms/$id'));

  static Future<void> createGym(Map<String, dynamic> body) =>
      _send('POST', '/gyms', body: body);

  static Future<void> patchGym(int id, Map<String, dynamic> body) =>
      _send('PATCH', '/gyms/$id', body: body);

  static Future<void> suspend(int id, String reason) =>
      _send('POST', '/gyms/$id/suspend', body: {'reason': reason});

  static Future<void> resume(int id, String reason) =>
      _send('POST', '/gyms/$id/resume', body: {'reason': reason});

  static Future<Map<String, dynamic>> enter(int id, String reason) async =>
      Map<String, dynamic>.from(
        await _send('POST', '/gyms/$id/enter', body: {'reason': reason}),
      );

  static Future<Map<String, dynamic>> accessLog({int? gymId}) async =>
      Map<String, dynamic>.from(
        await _send(
          'GET',
          '/access-log${gymId == null ? '' : '?gym_id=$gymId'}',
        ),
      );

  static Future<List<Map<String, dynamic>>> admins() async =>
      _list(await _send('GET', '/admins'));

  static Future<Map<String, dynamic>> createAdmin(
    String email,
    String name,
  ) async => Map<String, dynamic>.from(
    await _send('POST', '/admins', body: {'email': email, 'name': name}),
  );

  static Future<String> resetAdmin(int id) async {
    final d = await _send('POST', '/admins/$id/reset');
    return d['temporary_password'] as String;
  }
}
