import 'api_config.dart';
import 'api_response.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/plan.dart';
import 'token_manager.dart';

class PlanService {
  static const String baseUrl = kBaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  Future<List<Plan>> getActivePlans() async {
    final headers = await _authHeaders();

    final response = await guardRequest(
      () => http.get(Uri.parse('$baseUrl/api/v1/plans'), headers: headers),
    );

    final json = unwrapJson(response);
    final List plansJson = json['data']['plans'];
    return plansJson.map((e) => Plan.fromJson(e)).toList();
  }

  Future<void> createPlan({
    required String name,
    required double priceInRupees,
    required int durationDays,
    String description = '',
  }) async {
    final headers = await _authHeaders();

    final response = await guardRequest(() => http.post(
          Uri.parse('$baseUrl/api/v1/plans'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'description': description,
            'duration_days': durationDays,
            // Backend expects paise
            'price_in_paise': (priceInRupees * 100).round(),
          }),
        ));

    unwrapJson(response);
  }

  Future<void> updatePlan({
    required int planId,
    required String name,
    required double priceInRupees,
    required int durationDays,
    required bool isActive,
    String description = '',
  }) async {
    final headers = await _authHeaders();

    final response = await guardRequest(() => http.put(
          Uri.parse('$baseUrl/api/v1/plans/$planId'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'description': description,
            'duration_days': durationDays,
            // Backend expects paise
            'price_in_paise': (priceInRupees * 100).round(),
            'is_active': isActive,
          }),
        ));

    unwrapJson(response);
  }

  Future<void> deletePlan(int planId) async {
    final headers = await _authHeaders();

    final response = await guardRequest(
      () => http.delete(Uri.parse('$baseUrl/api/v1/plans/$planId'), headers: headers),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      unwrapJson(response);
    }
  }
}
