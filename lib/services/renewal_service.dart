import 'api_config.dart';
import 'api_response.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/renewal_due.dart';
import 'token_manager.dart';

class RenewalService {
  static const String baseUrl = kBaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  /// =========================
  /// GET MEMBERS DUE FOR RENEWAL
  /// =========================
  Future<List<RenewalDue>> getRenewalsDue({
    String filter = 'all',
    String search = '',
  }) async {
    final headers = await _authHeaders();

    final query = <String, String>{
      if (filter.isNotEmpty && filter != 'all') 'filter': filter,
      if (search.isNotEmpty) 'search': search,
    };

    final uri = Uri.parse('$baseUrl/api/v1/members/renewals')
        .replace(queryParameters: query.isEmpty ? null : query);

    final response = await guardRequest(() => http.get(uri, headers: headers));
    final json = unwrapJson(response);
    final List renewalsJson = json['data']['renewals'] as List;

    return renewalsJson.map((e) => RenewalDue.fromJson(e)).toList();
  }

  /// =========================
  /// RENEW A MEMBER
  /// =========================
  Future<void> renewMember({
    required int memberId,
    required int planId,
    required double amountPaidInRupees,
    String? startDate,
    String notes = '',
  }) async {
    final headers = await _authHeaders();

    final response = await guardRequest(() => http.post(
          Uri.parse('$baseUrl/api/v1/members/$memberId/renew'),
          headers: headers,
          body: jsonEncode({
            'plan_id': planId,

            // Backend expects paise
            'amount_paid_in_paise': (amountPaidInRupees * 100).round(),

            if (startDate != null) 'start_date': startDate,
            'notes': notes,
          }),
        ));

    unwrapJson(response);
  }
}
