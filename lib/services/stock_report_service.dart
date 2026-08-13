import 'package:http/http.dart' as http;

import '../models/date_span.dart';
import '../models/stock_report.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Stock analytics (FR-23).
///
/// Read-only, and it stays that way. The report suggests reorder levels but
/// never writes them: a suggestion that silently edits a threshold somebody
/// set is a change nobody agreed to.
class StockReportService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  /// [leadDays] is how long a restock takes. Left null it uses the server
  /// default of 7 — which is an assumption, not a measurement, and the screen
  /// says so.
  Future<StockReport> getReport({DateSpan? span, int? leadDays}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/stock/analytics').replace(
      queryParameters: {
        ..._spanParams(span),
        if (leadDays != null) 'lead_days': '$leadDays',
      },
    );
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return StockReport.fromJson(unwrapJson(response)['data']);
  }

  static Map<String, String> _spanParams(DateSpan? span) {
    if (span == null) return const {};
    if (span.isSingleDay) return {'date': span.fromParam};
    return {'from': span.fromParam, 'to': span.toParam};
  }
}
