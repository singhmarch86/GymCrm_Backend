import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/trainer.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Trainer roster CRUD. See FR-03-trainers-pt-appointments.md in the backend
/// repo — a trainer here is a standalone record, not a `User` login.
class TrainerService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<List<Trainer>> getTrainers() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/trainers'), headers: headers),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Trainer.fromJson(e)).toList();
  }

  Future<Trainer> createTrainer({
    required String firstName,
    required String lastName,
    required String phone,
    String email = '',
    String specialization = '',
    int? salaryInPaise,
    double? commissionPct,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/trainers'),
          headers: headers,
          body: jsonEncode({
            'first_name': firstName,
            'last_name': lastName,
            'phone': phone,
            'email': email,
            'specialization': specialization,
            if (salaryInPaise != null) 'salary_in_paise': salaryInPaise,
            if (commissionPct != null) 'commission_pct': commissionPct,
          }),
        ));
    return Trainer.fromJson(unwrapJson(response)['data']);
  }

  /// Edits a trainer. Only the fields passed are changed. Never affects PT
  /// packages already tied to them.
  Future<Trainer> updateTrainer(
    int id, {
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? specialization,
    String? status,
    int? salaryInPaise,
    double? commissionPct,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.put(
          Uri.parse('$kBaseUrl/api/v1/trainers/$id'),
          headers: headers,
          body: jsonEncode({
            if (firstName != null) 'first_name': firstName,
            if (lastName != null) 'last_name': lastName,
            if (phone != null) 'phone': phone,
            if (email != null) 'email': email,
            if (specialization != null) 'specialization': specialization,
            if (status != null) 'status': status,
            if (salaryInPaise != null) 'salary_in_paise': salaryInPaise,
            if (commissionPct != null) 'commission_pct': commissionPct,
          }),
        ));
    return Trainer.fromJson(unwrapJson(response)['data']);
  }
}
