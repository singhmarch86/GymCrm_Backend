import 'package:http/http.dart' as http;

import '../models/stock_queue.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Work queues (FR-19) — what is still owed, as opposed to what happened.
///
/// Read-only. Every queue is resolved by acting through the module that owns
/// the thing: restocking goes through PosService.adjustStock, so the stock
/// ledger stays the single writer of stock levels (FR-07 §1). A queue that
/// wrote its own corrections would be a second source of truth.
class QueueService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<StockQueue> getStock() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/queues/stock'),
          headers: headers),
    );
    return StockQueue.fromJson(unwrapJson(response)['data']);
  }
}
