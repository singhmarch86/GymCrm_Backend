import 'api_config.dart';
import 'api_response.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl = kBaseUrl;

  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    final response = await guardRequest(() => http.post(
          Uri.parse('$baseUrl/api/v1/auth/login'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'phone': phone,
            'password': password,
          }),
        ));

    return unwrapJson(response);
  }

  Future<Map<String, dynamic>> register({
    required String gymName,
    required String ownerName,
    required String phone,
    required String password,
    required String city,
    required String state,
    required String address,
    required String email,
  }) async {
    final response = await guardRequest(() => http.post(
          Uri.parse('$baseUrl/api/v1/auth/register'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'gym_name': gymName,
            'owner_name': ownerName,
            'phone': phone,
            'password': password,
            'city': city,
            'state': state,
            'address': address,
            'email': email,
          }),
        ));

    return unwrapJson(response);
  }

  Future<bool> logout(String accessToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('LOGOUT ERROR: $e');
      return false;
    }
  }
}
