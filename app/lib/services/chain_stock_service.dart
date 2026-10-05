import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chain_stock.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Inventory across branches (FR-22).
///
/// The chain view is read-only. The one write is a transfer, and it always
/// comes from a person confirming a quantity — nothing here rebalances stock
/// on its own.
class ChainStockService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<ChainStock> getChain() async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/stock/chain');
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return ChainStock.fromJson(unwrapJson(response)['data']);
  }

  /// Moves [quantity] units of [productId] from the branch you are signed in
  /// to, into [toGymId].
  ///
  /// The product id is the *sending* branch's row. The server resolves the
  /// destination's own row, creating it if that branch does not carry the
  /// item yet.
  Future<void> send({
    required int productId,
    required int toGymId,
    required int quantity,
    String? reason,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/stock/transfer');
    final response = await guardRequest(
      () => http.post(
        uri,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'product_id': productId,
          'to_gym_id': toGymId,
          'quantity': quantity,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        }),
      ),
    );
    unwrapJson(response);
  }

  Future<List<TransferRow>> history({int limit = 50}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/stock/transfers',
    ).replace(queryParameters: {'limit': '$limit'});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final data = unwrapJson(response)['data'] as List?;
    return (data ?? [])
        .map((r) => TransferRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
