import 'package:http/http.dart' as http;

import '../models/staff_work.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Staff work dashboard (FR-13).
///
/// Read-only by design. There is no write method here and there should never
/// be one: the ledgers this reads are append-only, so a misattribution cannot
/// be corrected from this screen — only explained.
class StaffWorkService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  /// One day's work, per person.
  ///
  /// [date] is a local calendar date (YYYY-MM-DD). Omit for today. Which staff
  /// come back is decided by the server from the caller's token — an owner
  /// sees everyone, anybody else sees only themselves — so there is
  /// deliberately no user filter to pass here.
  Future<StaffWorkDay> getDay({DateTime? date}) async {
    final headers = await _headers();
    final query = date == null ? '' : '?date=${_ymd(date)}';
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/staff-work$query'),
          headers: headers),
    );
    return StaffWorkDay.fromJson(unwrapJson(response)['data']);
  }

  /// The individual rows behind one number.
  ///
  /// A null [userId] means the unattributed bucket — a real query, not a
  /// missing argument.
  Future<List<StaffWorkItem>> getItems({
    required DateTime date,
    required String category,
    int? userId,
  }) async {
    final headers = await _headers();
    final params = <String, String>{
      'date': _ymd(date),
      'category': category,
      if (userId != null) 'user_id': '$userId',
    };
    final uri = Uri.parse('$kBaseUrl/api/v1/staff-work/items')
        .replace(queryParameters: params);

    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data']['items'] as List? ?? [];
    return list
        .map((e) => StaffWorkItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Formats the local date without touching UTC. `toIso8601String()` would
  /// convert first and hand the server yesterday for anything before 05:30.
  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
