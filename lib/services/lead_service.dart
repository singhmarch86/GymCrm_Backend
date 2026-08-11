import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/lead.dart';
import '../models/lead_pipeline.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

class LeadService {
  Future<Map<String, String>> _headers() async {
    // Routed through TokenManager so a token that is about to expire is
    // refreshed before the request goes out, instead of failing with a 401.
    return TokenManager.authHeaders();
  }

  // ─── Summary ────────────────────────────────────────────────────────────────

  Future<LeadSummary> getSummary() async {
    final response = await guardRequest(
      () async => http.get(Uri.parse('$kBaseUrl/api/v1/leads/summary'), headers: await _headers()),
    );
    final json = unwrapJson(response);
    return LeadSummary.fromJson(json['data']);
  }

  // ─── List ────────────────────────────────────────────────────────────────────

  Future<List<Lead>> getLeads({
    String status = '',
    String source = '',
    String search = '',
    String assignedTo = '',
    int page = 1,
    int perPage = 30,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (status.isNotEmpty) 'status': status,
      if (source.isNotEmpty) 'source': source,
      if (search.isNotEmpty) 'search': search,
      if (assignedTo.isNotEmpty) 'assigned_to': assignedTo,
    };

    final uri = Uri.parse('$kBaseUrl/api/v1/leads').replace(queryParameters: query);

    final response = await guardRequest(() async => http.get(uri, headers: await _headers()));
    final json = unwrapJson(response);
    final List list = json['data']['leads'] as List;
    return list.map((e) => Lead.fromJson(e)).toList();
  }

  // ─── Single ──────────────────────────────────────────────────────────────────

  Future<Lead> getLead(int id) async {
    final response = await guardRequest(
      () async => http.get(Uri.parse('$kBaseUrl/api/v1/leads/$id'), headers: await _headers()),
    );
    final json = unwrapJson(response);
    return Lead.fromJson(json['data']);
  }

  // ─── Create ──────────────────────────────────────────────────────────────────

  Future<Lead> createLead(Map<String, dynamic> data) async {
    final response = await guardRequest(() async => http.post(
          Uri.parse('$kBaseUrl/api/v1/leads'),
          headers: await _headers(),
          body: jsonEncode(data),
        ));
    final json = unwrapJson(response);
    return Lead.fromJson(json['data']);
  }

  // ─── Update ──────────────────────────────────────────────────────────────────

  Future<Lead> updateLead(int id, Map<String, dynamic> data) async {
    final response = await guardRequest(() async => http.put(
          Uri.parse('$kBaseUrl/api/v1/leads/$id'),
          headers: await _headers(),
          body: jsonEncode(data),
        ));
    final json = unwrapJson(response);
    return Lead.fromJson(json['data']);
  }

  // ─── Advance status ──────────────────────────────────────────────────────────

  Future<Lead> advanceStatus(int id, String status, {String? lostReason}) async {
    final body = <String, dynamic>{'status': status};
    if (lostReason != null && lostReason.isNotEmpty) {
      body['lost_reason'] = lostReason;
    }

    final response = await guardRequest(() async => http.patch(
          Uri.parse('$kBaseUrl/api/v1/leads/$id/status'),
          headers: await _headers(),
          body: jsonEncode(body),
        ));
    final json = unwrapJson(response);
    return Lead.fromJson(json['data']);
  }

  // ─── Convert to member ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> convertToMember(int leadId, Map<String, dynamic> data) async {
    final response = await guardRequest(() async => http.post(
          Uri.parse('$kBaseUrl/api/v1/leads/$leadId/convert'),
          headers: await _headers(),
          body: jsonEncode(data),
        ));
    if (response.statusCode == 409) {
      throw const ApiException('This lead has already been converted to a member', statusCode: 409);
    }
    final json = unwrapJson(response);
    return json['data'] as Map<String, dynamic>;
  }

  Future<void> deleteLead(int id) async {
    final response = await guardRequest(
      () async => http.delete(Uri.parse('$kBaseUrl/api/v1/leads/$id'), headers: await _headers()),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      unwrapJson(response);
    }
  }

  // ─── Activity timeline ───────────────────────────────────────────────────────

  Future<List<LeadActivity>> getActivities(int leadId) async {
    final response = await guardRequest(
      () async => http.get(
        Uri.parse('$kBaseUrl/api/v1/leads/$leadId/activities'),
        headers: await _headers(),
      ),
    );
    final json = unwrapJson(response);
    final List list = json['data']['activities'] as List? ?? [];
    return list.map((e) => LeadActivity.fromJson(e)).toList();
  }

  /// Logs a call, note, follow-up or trial. [date] (YYYY-MM-DD) is only
  /// meaningful for 'follow_up_set' and 'trial_scheduled', where the backend
  /// also updates the matching column on the lead.
  Future<LeadActivity> addActivity(
    int leadId, {
    required String type,
    String note = '',
    String date = '',
    String outcome = '',
  }) async {
    final response = await guardRequest(
      () async => http.post(
        Uri.parse('$kBaseUrl/api/v1/leads/$leadId/activities'),
        headers: await _headers(),
        body: jsonEncode({
          'type': type,
          if (note.isNotEmpty) 'note': note,
          if (date.isNotEmpty) 'date': date,
          if (outcome.isNotEmpty) 'outcome': outcome,
        }),
      ),
    );
    final json = unwrapJson(response);
    return LeadActivity.fromJson(json['data']);
  }

  // ─── Follow-up queue ─────────────────────────────────────────────────────────

  Future<FollowUpQueue> getFollowUps() async {
    final response = await guardRequest(
      () async => http.get(
        Uri.parse('$kBaseUrl/api/v1/leads/followups'),
        headers: await _headers(),
      ),
    );
    final json = unwrapJson(response);
    return FollowUpQueue.fromJson(json['data']);
  }

  // ─── Analytics ───────────────────────────────────────────────────────────────

  Future<LeadAnalytics> getAnalytics() async {
    final response = await guardRequest(
      () async => http.get(
        Uri.parse('$kBaseUrl/api/v1/leads/analytics'),
        headers: await _headers(),
      ),
    );
    final json = unwrapJson(response);
    return LeadAnalytics.fromJson(json['data']);
  }

  // ─── Assignment ──────────────────────────────────────────────────────────────

  Future<List<Assignee>> getAssignees() async {
    final response = await guardRequest(
      () async => http.get(
        Uri.parse('$kBaseUrl/api/v1/leads/assignees'),
        headers: await _headers(),
      ),
    );
    final json = unwrapJson(response);
    final List list = json['data']['assignees'] as List? ?? [];
    return list.map((e) => Assignee.fromJson(e)).toList();
  }

  /// Passing null for [userId] clears the assignment.
  Future<Lead> assignLead(int leadId, int? userId) async {
    final response = await guardRequest(
      () async => http.patch(
        Uri.parse('$kBaseUrl/api/v1/leads/$leadId/assign'),
        headers: await _headers(),
        body: jsonEncode({'assigned_user_id': userId}),
      ),
    );
    final json = unwrapJson(response);
    return Lead.fromJson(json['data']);
  }
}
