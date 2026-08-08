import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/product.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Retail: products, stock and counter sales.
/// See docs/FR-07-pos-inventory.md in the backend repo.
///
/// Stock arithmetic happens server-side inside a locked transaction, so two
/// tills selling the last item cannot both succeed. The app never computes or
/// sends a stock figure.
class PosService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  // ── Products ───────────────────────────────────────────────────────────────

  Future<List<Product>> getProducts({String search = '', bool lowStockOnly = false}) async {
    final headers = await _headers();
    final params = <String, String>{};
    if (search.isNotEmpty) params['search'] = search;
    if (lowStockOnly) params['low_stock'] = 'true';

    final uri = Uri.parse('$kBaseUrl/api/v1/products')
        .replace(queryParameters: params.isEmpty ? null : params);
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Product.fromJson(e)).toList();
  }

  Future<Product> createProduct({
    required String name,
    required int priceInPaise,
    int costInPaise = 0,
    String sku = '',
    String category = '',
    int reorderLevel = 0,
    int openingStock = 0,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/products'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'price_in_paise': priceInPaise,
            'cost_in_paise': costInPaise,
            'sku': sku,
            'category': category,
            'reorder_level': reorderLevel,
            'opening_stock': openingStock,
          }),
        ));
    return Product.fromJson(unwrapJson(response)['data']);
  }

  Future<Product> updateProduct(
    int id, {
    String? name,
    int? priceInPaise,
    int? costInPaise,
    int? reorderLevel,
    bool? isActive,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.put(
          Uri.parse('$kBaseUrl/api/v1/products/$id'),
          headers: headers,
          body: jsonEncode({
            if (name != null) 'name': name,
            if (priceInPaise != null) 'price_in_paise': priceInPaise,
            if (costInPaise != null) 'cost_in_paise': costInPaise,
            if (reorderLevel != null) 'reorder_level': reorderLevel,
            if (isActive != null) 'is_active': isActive,
          }),
        ));
    return Product.fromJson(unwrapJson(response)['data']);
  }

  /// Records a stock change with its reason. Positive adds, negative removes.
  Future<Product> adjustStock(
    int productId, {
    required int quantity,
    String movementType = 'adjustment',
    String reason = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/products/$productId/stock'),
          headers: headers,
          body: jsonEncode({
            'quantity': quantity,
            'movement_type': movementType,
            'reason': reason,
          }),
        ));
    return Product.fromJson(unwrapJson(response)['data']);
  }

  Future<List<StockMovement>> stockHistory(int productId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/products/$productId/stock-history'), headers: headers),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => StockMovement.fromJson(e)).toList();
  }

  // ── Sales ──────────────────────────────────────────────────────────────────

  /// Records a completed counter transaction. Rejected with a 409 if stock is
  /// short, unless the gym allows negative stock.
  Future<Sale> recordSale({
    required List<CartLine> lines,
    int? memberId,
    String paymentMode = 'cash',
    int discountInPaise = 0,
    String notes = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/sales'),
          headers: headers,
          body: jsonEncode({
            if (memberId != null) 'member_id': memberId,
            'payment_mode': paymentMode,
            'discount_in_paise': discountInPaise,
            'notes': notes,
            'items': lines
                .map((l) => {'product_id': l.product.id, 'quantity': l.quantity})
                .toList(),
          }),
        ));
    return Sale.fromJson(unwrapJson(response)['data']);
  }

  Future<List<Sale>> getSales({DateTime? from, DateTime? to}) async {
    final headers = await _headers();
    final params = <String, String>{};
    if (from != null) params['from'] = _ymd(from);
    if (to != null) params['to'] = _ymd(to);

    final uri = Uri.parse('$kBaseUrl/api/v1/sales')
        .replace(queryParameters: params.isEmpty ? null : params);
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Sale.fromJson(e)).toList();
  }

  /// Reverses a sale by recording a new one with negative quantities. The
  /// original is never edited.
  Future<Sale> refund(int saleId, {required String reason}) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/sales/$saleId/refund'),
          headers: headers,
          body: jsonEncode({'reason': reason}),
        ));
    return Sale.fromJson(unwrapJson(response)['data']);
  }

  Future<RetailSummary> summary({DateTime? from, DateTime? to}) async {
    final headers = await _headers();
    final params = <String, String>{};
    if (from != null) params['from'] = _ymd(from);
    if (to != null) params['to'] = _ymd(to);

    final uri = Uri.parse('$kBaseUrl/api/v1/retail/summary')
        .replace(queryParameters: params.isEmpty ? null : params);
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return RetailSummary.fromJson(unwrapJson(response)['data']);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
