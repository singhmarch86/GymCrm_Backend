import 'api_config.dart';
import 'api_response.dart';

import 'package:http/http.dart' as http;

import '../models/dashboard_response.dart';
import 'token_manager.dart';

class DashboardService {
  static const String baseUrl = kBaseUrl;

  Future<DashboardResponse> getDashboard() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    final headers = await TokenManager.authHeaders();

    final response = await guardRequest(() => http.get(
          Uri.parse('$baseUrl/api/v1/dashboard'),
          headers: headers,
        ));

    final json = unwrapJson(response);
    return DashboardResponse.fromJson(json['data']);
  }
}
