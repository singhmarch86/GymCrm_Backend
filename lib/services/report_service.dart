import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/member_report.dart';
import '../models/payment_report.dart';
import '../models/plan_report.dart';
import '../models/renewal_report.dart';
import '../models/revenue_report.dart';
import 'api_config.dart';
import 'token_manager.dart';

class ReportService {
  Future<Map<String, String>> _headers() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  Future<T> _get<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final uri = Uri.parse('$kBaseUrl$path');
    final response = await http.get(uri, headers: await _headers());

    debugPrint('REPORT $path STATUS: ${response.statusCode}');

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) {
      throw Exception('Failed to load report: $path');
    }

    final json = jsonDecode(response.body);
    return fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<RevenueReport> getRevenueReport() =>
      _get('/api/v1/reports/revenue', RevenueReport.fromJson);

  Future<MemberReport> getMemberReport() =>
      _get('/api/v1/reports/members', MemberReport.fromJson);

  Future<PaymentReport> getPaymentReport() =>
      _get('/api/v1/reports/payments', PaymentReport.fromJson);

  Future<RenewalReport> getRenewalReport() =>
      _get('/api/v1/reports/renewals', RenewalReport.fromJson);

  Future<PlanReport> getPlanReport() =>
      _get('/api/v1/reports/plans', PlanReport.fromJson);
}
