import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pt_package.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Personal training packages and appointments. No business rules here —
/// the server is the only source of truth for sessions remaining. See
/// FR-03-trainers-pt-appointments.md in the backend repo.
class PtService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  // ── Packages ───────────────────────────────────────────────────────────────

  Future<List<PtPackage>> getPackages({int? trainerId}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/pt-packages').replace(
      queryParameters: trainerId != null ? {'trainer_id': '$trainerId'} : null,
    );
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => PtPackage.fromJson(e)).toList();
  }

  Future<List<PtPackage>> getMemberPackages(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/members/$memberId/pt-packages'), headers: headers),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => PtPackage.fromJson(e)).toList();
  }

  /// Sells a package to a member. `totalSessions` is a fixed count set once
  /// at sale — there's no top-up; sell a new package instead.
  Future<PtPackage> createPackage({
    required int memberId,
    required int trainerId,
    required String packageName,
    required int totalSessions,
    required int amountInPaise,
    DateTime? expiryDate,

    // The money, recorded with the sale (FR-21 section 3).
    //
    // An empty [paymentMode] means nothing was taken and the server raises a
    // due instead. Never defaulted to cash here or on the server: assuming
    // payment for an unpaid package is the leak this closes.
    String paymentMode = '',
    int amountPaidInPaise = 0,
    DateTime? dueDate,
    String referenceNumber = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/pt-packages'),
          headers: headers,
          body: jsonEncode({
            'member_id': memberId,
            'trainer_id': trainerId,
            'package_name': packageName,
            'total_sessions': totalSessions,
            'amount_in_paise': amountInPaise,
            if (expiryDate != null) 'expiry_date': _ymd(expiryDate),
            'payment_mode': paymentMode,
            'amount_paid_in_paise': amountPaidInPaise,
            if (dueDate != null) 'due_date': _ymd(dueDate),
            'reference_number': referenceNumber,
          }),
        ));
    return PtPackage.fromJson(unwrapJson(response)['data']);
  }

  /// Manually changes a package's status — e.g. to cancelled. Nothing expires
  /// packages automatically.
  Future<PtPackage> updatePackageStatus(int id, String status) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.patch(
          Uri.parse('$kBaseUrl/api/v1/pt-packages/$id/status'),
          headers: headers,
          body: jsonEncode({'status': status}),
        ));
    return PtPackage.fromJson(unwrapJson(response)['data']);
  }

  // ── Appointments ───────────────────────────────────────────────────────────

  /// Books a 1:1 session. Deliberately does not check or reserve a session
  /// credit — the guard is on completing it, not booking it.
  Future<PtAppointment> bookAppointment({
    required int ptPackageId,
    required DateTime scheduledAt,
    int durationMinutes = 60,
    String notes = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/pt-appointments'),
          headers: headers,
          body: jsonEncode({
            'pt_package_id': ptPackageId,
            'scheduled_at': scheduledAt.toUtc().toIso8601String(),
            'duration_minutes': durationMinutes,
            'notes': notes,
          }),
        ));
    return PtAppointment.fromJson(unwrapJson(response)['data']);
  }

  Future<List<PtAppointment>> getAppointments({
    required DateTime from,
    required DateTime to,
    int? trainerId,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/pt-appointments').replace(
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        if (trainerId != null) 'trainer_id': '$trainerId',
      },
    );
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => PtAppointment.fromJson(e)).toList();
  }

  /// Sets an appointment's outcome. Only 'completed' consumes a session
  /// credit from the linked package — cancelled/no_show consume nothing.
  Future<PtAppointment> setOutcome(int id, String status) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/pt-appointments/$id/outcome'),
          headers: headers,
          body: jsonEncode({'status': status}),
        ));
    return PtAppointment.fromJson(unwrapJson(response)['data']);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
