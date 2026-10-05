import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/staff.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Staff administration. Every endpoint here is owner-only on the backend —
/// a staff account gets 403, which surfaces as the standard permission message.
class StaffService {
  Future<Map<String, String>> _headers() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  Future<List<Staff>> getStaff() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/users'), headers: headers),
    );
    final json = unwrapJson(response);
    final List list = json['data']['staff'] as List? ?? [];
    return list.map((e) => Staff.fromJson(e)).toList();
  }

  Future<Staff> createStaff({
    required String name,
    required String phone,
    required String password,
    String email = '',
    String role = 'staff',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/users'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'password': password,
          if (email.isNotEmpty) 'email': email,
          'role': role,
        }),
      ),
    );
    final json = unwrapJson(response);
    return Staff.fromJson(json['data']);
  }

  /// Only non-null fields are sent, so the backend leaves the rest untouched.
  Future<Staff> updateStaff(
    int id, {
    String? name,
    String? phone,
    String? email,
    String? role,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.put(
        Uri.parse('$kBaseUrl/api/v1/users/$id'),
        headers: headers,
        body: jsonEncode({
          'name': ?name,
          'phone': ?phone,
          'email': ?email,
          'role': ?role,
        }),
      ),
    );
    final json = unwrapJson(response);
    return Staff.fromJson(json['data']);
  }

  Future<Staff> setStatus(int id, String status) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.patch(
        Uri.parse('$kBaseUrl/api/v1/users/$id/status'),
        headers: headers,
        body: jsonEncode({'status': status}),
      ),
    );
    final json = unwrapJson(response);
    return Staff.fromJson(json['data']);
  }

  Future<void> resetPassword(int id, String password) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.patch(
        Uri.parse('$kBaseUrl/api/v1/users/$id/password'),
        headers: headers,
        body: jsonEncode({'password': password}),
      ),
    );
    // 204 No Content on success — nothing to unwrap unless it failed.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      unwrapJson(response);
    }
  }
}
