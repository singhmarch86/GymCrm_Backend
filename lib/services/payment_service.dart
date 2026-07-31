import 'api_config.dart';
import 'api_response.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/payment.dart';
import 'token_manager.dart';

class PaymentService {
  static const String baseUrl = kBaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  // ─── List payments ──────────────────────────────────────────────────────────

  Future<List<Payment>> getPayments({
    String status = '',
    String search = '',
    String dateFrom = '',
    String dateTo = '',
    int page = 1,
    int perPage = 20,
  }) async {
    final headers = await _authHeaders();

    final query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (status.isNotEmpty) 'status': status,
      if (search.isNotEmpty) 'search': search,
      if (dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo.isNotEmpty) 'date_to': dateTo,
    };

    final uri = Uri.parse('$baseUrl/api/v1/payments').replace(queryParameters: query);

    final response = await guardRequest(() => http.get(uri, headers: headers));
    final json = unwrapJson(response);
    final List list = json['data']['payments'] as List;
    return list.map((e) => Payment.fromJson(e)).toList();
  }

  // ─── Member payment history ─────────────────────────────────────────────────

  Future<List<Payment>> getMemberPayments(int memberId) async {
    final headers = await _authHeaders();

    final response = await guardRequest(
      () => http.get(Uri.parse('$baseUrl/api/v1/members/$memberId/payments'), headers: headers),
    );
    final json = unwrapJson(response);
    final List list = json['data']['payments'] as List;
    return list.map((e) => Payment.fromJson(e)).toList();
  }

  // ─── Collect payment ────────────────────────────────────────────────────────

  /// Single atomic operation: creates payment + renewal + updates member expiry.
  Future<Payment> collectPayment({
    required int memberId,
    required int planId,
    required double amountInRupees,
    required String paymentMode,
    String paymentDate = '',
    String referenceNumber = '',
    String notes = '',
  }) async {
    final headers = await _authHeaders();

    final body = <String, dynamic>{
      'member_id': memberId,
      'plan_id': planId,
      'amount_in_paise': (amountInRupees * 100).round(),
      'payment_mode': paymentMode,
      if (paymentDate.isNotEmpty) 'payment_date': paymentDate,
      if (referenceNumber.isNotEmpty) 'reference_number': referenceNumber,
      if (notes.isNotEmpty) 'notes': notes,
    };

    final response = await guardRequest(() => http.post(
          Uri.parse('$baseUrl/api/v1/payments'),
          headers: headers,
          body: jsonEncode(body),
        ));

    final json = unwrapJson(response);
    return Payment.fromJson(json['data']);
  }

  // ─── Revenue summary ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getRevenueSummary() async {
    final headers = await _authHeaders();

    final response = await guardRequest(
      () => http.get(Uri.parse('$baseUrl/api/v1/payments/summary'), headers: headers),
    );
    final json = unwrapJson(response);
    return json['data'] as Map<String, dynamic>;
  }
}
