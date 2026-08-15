import 'package:http/http.dart' as http;

import '../models/pt_report.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// PT reports — read-only, server-composed. See lib/models/pt_report.dart.
class PtReportService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<MemberPtReport> forMember(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/pt-report'),
        headers: headers,
      ),
    );
    return MemberPtReport.fromJson(unwrapJson(response)['data']);
  }

  Future<TrainerPtReport> forTrainer(int trainerId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/trainers/$trainerId/pt-report'),
        headers: headers,
      ),
    );
    return TrainerPtReport.fromJson(unwrapJson(response)['data']);
  }
}
