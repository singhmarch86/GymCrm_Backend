import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/member_feedback.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// PT feedback — staff-transcribed notes from either the member or a
/// trainer. See lib/models/member_feedback.dart and migration 035 in the
/// backend repo.
class PtFeedbackService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<MemberFeedback> create({
    required int memberId,
    required String authorRole,
    required String note,
    int? trainerId,
    int? ptPackageId,
    int? ptAppointmentId,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/pt/feedback'),
        headers: headers,
        body: jsonEncode({
          'member_id': memberId,
          'author_role': authorRole,
          'note': note,
          if (trainerId != null) 'trainer_id': trainerId,
          if (ptPackageId != null) 'pt_package_id': ptPackageId,
          if (ptAppointmentId != null) 'pt_appointment_id': ptAppointmentId,
        }),
      ),
    );
    return MemberFeedback.fromJson(unwrapJson(response)['data']);
  }

  Future<List<MemberFeedback>> byMember(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/feedback'),
        headers: headers,
      ),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => MemberFeedback.fromJson(e)).toList();
  }

  Future<List<MemberFeedback>> byTrainer(int trainerId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/trainers/$trainerId/feedback'),
        headers: headers,
      ),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => MemberFeedback.fromJson(e)).toList();
  }
}
