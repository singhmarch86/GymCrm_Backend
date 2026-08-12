import 'package:http/http.dart' as http;

import '../models/date_span.dart';
import '../models/staff_analytics.dart';
import '../models/staff_work.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Staff work dashboard (FR-13, ranges per FR-18 §9).
///
/// Read-only by design. There is no write method here and there should never
/// be one: the ledgers this reads are append-only, so a misattribution cannot
/// be corrected from this screen — only explained.
class StaffWorkService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  /// One span's work, per person.
  ///
  /// Which staff come back is decided by the server from the caller's token —
  /// an owner sees everyone, anybody else sees only themselves — so there is
  /// deliberately no user filter to pass here.
  Future<StaffWorkDay> getDay({DateSpan? span}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/staff-work')
        .replace(queryParameters: _spanParams(span));
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return StaffWorkDay.fromJson(unwrapJson(response)['data']);
  }

  /// Per-person lead workflow (FR-18 §7). Carrying counts are always "now";
  /// only the funnel is scoped to [span].
  Future<LeadWorkReport> getLeadWork({DateSpan? span}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/staff-work/leads')
        .replace(queryParameters: _spanParams(span));
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return LeadWorkReport.fromJson(unwrapJson(response)['data']);
  }

  /// How the desk's workload has moved over [span] (FR-22).
  ///
  /// Not a ranking, and the response gives a client no way to build one: the
  /// people come back ordered by name with no score, and the only comparison
  /// present is each person against their own previous period.
  Future<StaffAnalytics> getAnalytics({DateSpan? span}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/staff-work/analytics')
        .replace(queryParameters: _spanParams(span));
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return StaffAnalytics.fromJson(unwrapJson(response)['data']);
  }

  /// The individual rows behind one number.
  ///
  /// A null [userId] means the unattributed bucket — a real query, not a
  /// missing argument.
  Future<StaffWorkItems> getItems({
    required DateSpan span,
    required String category,
    int? userId,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/staff-work/items').replace(
      queryParameters: {
        ..._spanParams(span),
        'category': category,
        if (userId != null) 'user_id': '$userId',
      },
    );

    final response = await guardRequest(() => http.get(uri, headers: headers));
    return StaffWorkItems.fromJson(unwrapJson(response)['data']);
  }

  /// A single day still goes as `date`, so the request says what it means and
  /// so an older server keeps working. Anything longer sends from/to.
  static Map<String, String> _spanParams(DateSpan? span) {
    if (span == null) return const {};
    if (span.isSingleDay) return {'date': span.fromParam};
    return {'from': span.fromParam, 'to': span.toParam};
  }
}
