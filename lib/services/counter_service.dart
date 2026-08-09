import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/counter_prompt.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// The counter prompt (FR-11).
class CounterService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  /// Fetches the prompt for a member who has just been checked in, and records
  /// that it was shown — which is what drives the 7-day cooldown.
  ///
  /// Returns null when there is nothing to say, which is most of the time.
  Future<CounterPrompt?> forCheckIn(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(Uri.parse('$kBaseUrl/api/v1/counter/checkin/$memberId'),
          headers: headers),
    );
    return CounterPrompt.fromResult(unwrapJson(response)['data'] ?? {});
  }

  /// The same prompt without recording it. Used when staff are just looking at
  /// a member — browsing a record must not burn their cooldown.
  Future<CounterPrompt?> peek(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/counter/prompt/$memberId'),
          headers: headers),
    );
    return CounterPrompt.fromResult(unwrapJson(response)['data'] ?? {});
  }

  /// Records that the staff member did something about it. Optional by design
  /// — mandatory logging at a busy counter gets clicked through meaninglessly.
  Future<void> markActed(int promptId, {String actionNote = ''}) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.patch(
          Uri.parse('$kBaseUrl/api/v1/counter/prompts/$promptId/acted'),
          headers: headers,
          body: jsonEncode({
            if (actionNote.trim().isNotEmpty) 'action_note': actionNote.trim(),
          }),
        ));
    // 204 No Content on success.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      unwrapJson(response);
    }
  }
}
