import 'api_config.dart';
import 'api_response.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/member.dart';
import 'token_manager.dart';

class MemberService {
  static const String baseUrl = kBaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  Future<List<Member>> getMembers() async {
    final headers = await _authHeaders();

    final response = await guardRequest(
      () => http.get(Uri.parse('$baseUrl/api/v1/members'), headers: headers),
    );

    final json = unwrapJson(response);
    final List membersJson = json['data']['members'] as List;
    return membersJson.map((e) => Member.fromJson(e)).toList();
  }

  /// Searches members by name or phone. Used by the transfer dialog to find a
  /// receiving member without listing everyone.
  Future<List<Member>> searchMembers(String query) async {
    final headers = await _authHeaders();

    final uri = Uri.parse(
      '$baseUrl/api/v1/members/search',
    ).replace(queryParameters: {'q': query});
    final response = await guardRequest(() => http.get(uri, headers: headers));

    final json = unwrapJson(response);
    final List membersJson = json['data']['members'] as List;
    return membersJson.map((e) => Member.fromJson(e)).toList();
  }

  /// Creates a member and returns the created record — callers that need the
  /// new member's id (e.g. transferring a membership to them immediately)
  /// don't have to refetch.
  Future<Member> createMember({
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
    String? address,
    String? gender,
    int? membershipPlanId,
    DateTime? startDate,
    DateTime? expiryDate,
    DateTime? dateOfBirth,
    String? notes,
    String? emergencyContactName,
    String? emergencyContactPhone,
  }) async {
    final headers = await _authHeaders();

    final response = await guardRequest(
      () => http.post(
        Uri.parse('$baseUrl/api/v1/members'),
        headers: headers,
        body: jsonEncode({
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
          if (address != null && address.isNotEmpty) 'address': address,
          if (gender != null) 'gender': gender,
          if (membershipPlanId != null) 'membership_plan_id': membershipPlanId,
          if (startDate != null) 'start_date': _dateOnly(startDate),
          if (expiryDate != null) 'expiry_date': _dateOnly(expiryDate),
          if (dateOfBirth != null) 'date_of_birth': _dateOnly(dateOfBirth),
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (emergencyContactName != null && emergencyContactName.isNotEmpty)
            'emergency_contact_name': emergencyContactName,
          if (emergencyContactPhone != null && emergencyContactPhone.isNotEmpty)
            'emergency_contact_phone': emergencyContactPhone,
        }),
      ),
    );

    final json = unwrapJson(response);
    return Member.fromJson(json['data']);
  }

  Future<void> updateMember({
    required int memberId,
    required String firstName,
    required String lastName,
    required String phone,
    required String status,
    int? membershipPlanId,
  }) async {
    final headers = await _authHeaders();

    final response = await guardRequest(
      () => http.put(
        Uri.parse('$baseUrl/api/v1/members/$memberId'),
        headers: headers,
        body: jsonEncode({
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone,
          'status': status,
          'membership_plan_id': membershipPlanId,
        }),
      ),
    );

    unwrapJson(response);
  }

  Future<void> deleteMember(int memberId) async {
    final headers = await _authHeaders();

    final response = await guardRequest(
      () => http.delete(
        Uri.parse('$baseUrl/api/v1/members/$memberId'),
        headers: headers,
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      unwrapJson(response);
    }
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
