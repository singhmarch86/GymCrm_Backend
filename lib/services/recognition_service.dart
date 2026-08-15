import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/recognition.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Private member recognition. See lib/models/recognition.dart.
class RecognitionService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<Recognition> create({
    required int memberId,
    required String reason,
    String? signalType,
    int? signalId,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/recognitions'),
        headers: headers,
        body: jsonEncode({
          'reason': reason,
          if (signalType != null) 'signal_type': signalType,
          if (signalId != null) 'signal_id': signalId,
        }),
      ),
    );
    return Recognition.fromJson(unwrapJson(response)['data']);
  }

  Future<List<Recognition>> byMember(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/recognitions'),
        headers: headers,
      ),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Recognition.fromJson(e)).toList();
  }
}
