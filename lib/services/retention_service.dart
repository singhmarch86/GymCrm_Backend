import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/retention_alert.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

class RetentionService {
  Future<Map<String, String>> _headers() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  /// Runs the retention scan. Safe to call repeatedly — the backend dedupes
  /// against a partial unique index, so a rescan cannot duplicate alerts.
  Future<ScanResult> scan() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/retention/scan'),
        headers: headers,
      ),
    );
    final json = unwrapJson(response);
    return ScanResult.fromJson(json['data']);
  }

  Future<List<RetentionAlert>> getAlerts({String severity = ''}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/retention/alerts').replace(
      queryParameters: severity.isEmpty ? null : {'severity': severity},
    );
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final json = unwrapJson(response);
    final List list = json['data']['alerts'] as List? ?? [];
    return list.map((e) => RetentionAlert.fromJson(e)).toList();
  }

  Future<RetentionSummary> getSummary() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/retention/summary'),
        headers: headers,
      ),
    );
    final json = unwrapJson(response);
    return RetentionSummary.fromJson(json['data']);
  }

  /// Who has been clearing the at-risk list, over the last [days] days.
  Future<List<StaffActivity>> getStaffActivity({int days = 7}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/retention/staff-activity',
    ).replace(queryParameters: {'days': '$days'});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final json = unwrapJson(response);
    final List list = json['data']['staff'] as List? ?? [];
    return list.map((e) => StaffActivity.fromJson(e)).toList();
  }

  /// [actionNote] records what the staff member actually did. Optional — an
  /// empty note still resolves, it just records the actor without detail.
  Future<void> resolve(int alertId, {String actionNote = ''}) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.patch(
        Uri.parse('$kBaseUrl/api/v1/retention/alerts/$alertId/resolve'),
        headers: headers,
        body: jsonEncode({
          if (actionNote.trim().isNotEmpty) 'action_note': actionNote.trim(),
        }),
      ),
    );
    // 204 No Content on success.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      unwrapJson(response);
    }
  }
}
