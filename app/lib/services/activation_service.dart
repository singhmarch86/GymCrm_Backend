import 'package:http/http.dart' as http;

import '../models/activation.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// First 90 days: activation (FR-10).
///
/// No resolve method here on purpose: activation alerts live in the same
/// retention_alerts queue as everything else, so they are closed through
/// RetentionService.resolve() with the same note and staff attribution.
class ActivationService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  /// Safe to call repeatedly. The scan also closes alerts that no longer
  /// describe the member, so a member moving between states never ends up
  /// holding two rows.
  Future<ActivationScanResult> scan() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/activation/scan'),
        headers: headers,
      ),
    );
    return ActivationScanResult.fromJson(unwrapJson(response)['data']);
  }

  Future<List<ActivationAlert>> getAlerts() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/activation/alerts'),
        headers: headers,
      ),
    );
    final List list = unwrapJson(response)['data']['alerts'] as List? ?? [];
    return list.map((e) => ActivationAlert.fromJson(e)).toList();
  }

  Future<List<ActivationCohort>> getFunnel({int months = 6}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/activation/funnel',
    ).replace(queryParameters: {'months': '$months'});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data']['cohorts'] as List? ?? [];
    return list.map((e) => ActivationCohort.fromJson(e)).toList();
  }
}
