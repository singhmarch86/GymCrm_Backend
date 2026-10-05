import 'package:http/http.dart' as http;

import '../models/rhythm.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Rhythm-break detection (FR-09).
///
/// Note there is no resolve method here on purpose: a rhythm break is a
/// `rhythm_break` row in the same retention_alerts queue, so it is closed
/// through RetentionService.resolve() with the same action note and staff
/// attribution as every other alert.
class RhythmService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  /// Safe to call repeatedly — the backend dedupes against the same partial
  /// unique index the retention alerts use.
  Future<RhythmScanResult> scan() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/rhythm/scan'),
        headers: headers,
      ),
    );
    return RhythmScanResult.fromJson(unwrapJson(response)['data']);
  }

  Future<List<RhythmBreak>> getBreaks() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/rhythm/breaks'),
        headers: headers,
      ),
    );
    final List list = unwrapJson(response)['data']['breaks'] as List? ?? [];
    return list.map((e) => RhythmBreak.fromJson(e)).toList();
  }

  /// Returns null when the member has no describable rhythm yet — the common
  /// case, and not an error worth showing anyone.
  Future<RhythmProfile?> getProfile(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/rhythm/members/$memberId'),
        headers: headers,
      ),
    );
    if (response.statusCode == 404) return null;
    return RhythmProfile.fromJson(unwrapJson(response)['data']);
  }
}
