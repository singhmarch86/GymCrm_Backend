import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/visitor.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Walk-in visitor check-in/out. No business rules here — see
/// docs in the backend repo (internal/visitors) for what's enforced server-side.
class VisitorService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<Visitor> checkIn({
    required String name,
    String phone = '',
    String purpose = 'trial',
    int? hostStaffUserId,
    String notes = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/visitors/check-in'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'purpose': purpose,
          if (hostStaffUserId != null) 'host_staff_user_id': hostStaffUserId,
          'notes': notes,
        }),
      ),
    );
    return Visitor.fromJson(unwrapJson(response)['data']);
  }

  Future<Visitor> checkOut(int id) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/visitors/$id/check-out'),
        headers: headers,
      ),
    );
    return Visitor.fromJson(unwrapJson(response)['data']);
  }

  Future<Visitor> convertToLead(
    int id, {
    String email = '',
    String gender = '',
    String goal = '',
    String trialDate = '',
    String followUpDate = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/visitors/$id/convert-to-lead'),
        headers: headers,
        body: jsonEncode({
          'email': email,
          'gender': gender,
          'goal': goal,
          'trial_date': trialDate,
          'follow_up_date': followUpDate,
        }),
      ),
    );
    return Visitor.fromJson(unwrapJson(response)['data']);
  }

  Future<List<Visitor>> list({DateTime? from, DateTime? to}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/visitors').replace(
      queryParameters: {
        if (from != null) 'from': _ymd(from),
        if (to != null) 'to': _ymd(to),
      },
    );
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Visitor.fromJson(e)).toList();
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
