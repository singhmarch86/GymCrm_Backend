import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/payout.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Trainer payouts (FR-21 §2).
///
/// Nothing here pays anybody by itself. A payout is computed, reviewed as a
/// draft, and only then recorded as paid — and that last step is owner-only,
/// because it is the one operation in the product that moves cash out of the
/// gym.
class PayoutService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  /// What a trainer would earn, without writing anything.
  ///
  /// Exists so nobody has to create a draft to find out and then cancel it,
  /// which would leave abandoned rows in a money table.
  Future<PayoutPreview> preview({
    required int trainerId,
    required DateTime from,
    required DateTime to,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/trainers/$trainerId/payout-preview',
    ).replace(queryParameters: {'from': _ymd(from), 'to': _ymd(to)});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return PayoutPreview.fromJson(unwrapJson(response)['data']);
  }

  Future<List<Payout>> list({String? status}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/payouts',
    ).replace(queryParameters: status == null ? null : {'status': status});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final data = unwrapJson(response)['data'] as List? ?? [];
    return data.map((e) => Payout.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Payout> get(int id) async {
    final headers = await _headers();
    final response = await guardRequest(
      () =>
          http.get(Uri.parse('$kBaseUrl/api/v1/payouts/$id'), headers: headers),
    );
    return Payout.fromJson(unwrapJson(response)['data']);
  }

  /// Stores a draft from the same computation the preview showed.
  Future<Payout> create({
    required int trainerId,
    required DateTime from,
    required DateTime to,
    int adjustmentInPaise = 0,
    String adjustmentReason = '',
    String notes = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/payouts'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'trainer_id': trainerId,
          'from': _ymd(from),
          'to': _ymd(to),
          'adjustment_in_paise': adjustmentInPaise,
          'adjustment_reason': adjustmentReason,
          'notes': notes,
        }),
      ),
    );
    return Payout.fromJson(unwrapJson(response)['data']);
  }

  /// Owner only, enforced by the server from the token.
  Future<void> markPaid(
    int id, {
    String paymentMode = '',
    String referenceNumber = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/payouts/$id/pay'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'payment_mode': paymentMode,
          'reference_number': referenceNumber,
        }),
      ),
    );
    unwrapJson(response);
  }

  Future<void> cancel(int id) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/payouts/$id/cancel'),
        headers: headers,
      ),
    );
    unwrapJson(response);
  }

  /// Never via toUtc(): the gym's day is a local one, and shifting it can move
  /// a payout period across a month boundary.
  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
