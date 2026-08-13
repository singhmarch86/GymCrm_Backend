import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/attendance_record.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// AttendanceService — full implementation.
/// Backend endpoints are live from Step 7 of the original build.
class AttendanceService {
  Future<Map<String, String>> _headers() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  // POST /api/v1/attendance/checkin
  Future<AttendanceRecord> checkIn(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/attendance/checkin'),
        headers: headers,
        body: jsonEncode({'member_id': memberId}),
      ),
    );

    // Friendlier, situation-specific messages than unwrapJson's generic
    // 409/404 defaults.
    if (response.statusCode == 409) {
      throw const ApiException('Already checked in today', statusCode: 409);
    }
    if (response.statusCode == 404) {
      throw const ApiException('Member not found', statusCode: 404);
    }

    final json = unwrapJson(response);
    return AttendanceRecord.fromJson(json['data']);
  }

  // GET /api/v1/attendance/today
  Future<List<AttendanceRecord>> getToday({
    int page = 1,
    int perPage = 50,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/attendance/today',
    ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final json = unwrapJson(response);
    final List list = json['data']['attendance'] as List;
    return list.map((e) => AttendanceRecord.fromJson(e)).toList();
  }

  // GET /api/v1/attendance/date/{date}
  Future<List<AttendanceRecord>> getByDate(String date) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/attendance/date/$date'),
        headers: headers,
      ),
    );
    final json = unwrapJson(response);
    final List list = json['data']['attendance'] as List;
    return list.map((e) => AttendanceRecord.fromJson(e)).toList();
  }

  // GET /api/v1/attendance/member/{memberId}
  Future<List<AttendanceRecord>> getMemberHistory(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/attendance/member/$memberId'),
        headers: headers,
      ),
    );
    final json = unwrapJson(response);
    final List list = json['data']['attendance'] as List;
    return list.map((e) => AttendanceRecord.fromJson(e)).toList();
  }

  // GET /api/v1/attendance/recent?limit=N
  Future<List<AttendanceRecord>> getRecent({int limit = 20}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/attendance/recent',
    ).replace(queryParameters: {'limit': '$limit'});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final json = unwrapJson(response);
    final List list = json['data']['attendance'] as List;
    return list.map((e) => AttendanceRecord.fromJson(e)).toList();
  }
}
