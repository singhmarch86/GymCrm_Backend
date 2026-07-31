import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/lifecycle_event.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Membership lifecycle operations: freeze, unfreeze, upgrade, transfer,
/// terminate — plus the preview endpoints that let the UI show limits and costs
/// before staff commit to anything.
///
/// No business rules live here. Every bound and every amount comes from the
/// server, so what staff are shown is exactly what will be applied.
class LifecycleService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  String _base(int memberId) => '$kBaseUrl/api/v1/members/$memberId';

  // ── Previews ───────────────────────────────────────────────────────────────

  /// Whether this member can be frozen, and for how long.
  Future<FreezeEligibility> freezeEligibility(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('${_base(memberId)}/freeze-eligibility'), headers: headers),
    );
    return FreezeEligibility.fromJson(unwrapJson(response)['data']);
  }

  /// Prorated cost of moving this member to [newPlanId].
  Future<UpgradeQuote> upgradeQuote(int memberId, int newPlanId) async {
    final headers = await _headers();
    final uri = Uri.parse('${_base(memberId)}/upgrade-quote')
        .replace(queryParameters: {'new_plan_id': '$newPlanId'});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return UpgradeQuote.fromJson(unwrapJson(response)['data']);
  }

  /// Refund owed if this membership were terminated today, net of [feeInPaise].
  Future<TerminationQuote> terminationQuote(int memberId, {int feeInPaise = 0}) async {
    final headers = await _headers();
    final uri = Uri.parse('${_base(memberId)}/termination-quote')
        .replace(queryParameters: {'fee_in_paise': '$feeInPaise'});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return TerminationQuote.fromJson(unwrapJson(response)['data']);
  }

  // ── Operations ─────────────────────────────────────────────────────────────

  /// Pauses a membership. Expiry extends 1:1 with the frozen duration.
  Future<MemberLifecycleResult> freeze(
    int memberId, {
    required DateTime startDate,
    required DateTime endDate,
    int feeInPaise = 0,
    String reason = '',
    String notes = '',
  }) async {
    return _post(memberId, 'freeze', {
      'start_date': _ymd(startDate),
      'end_date': _ymd(endDate),
      'fee_in_paise': feeInPaise,
      'reason': reason,
      'notes': notes,
    });
  }

  /// Ends a freeze. Ending early returns the unused days to the member.
  Future<MemberLifecycleResult> unfreeze(
    int memberId, {
    DateTime? effectiveDate,
    String notes = '',
  }) async {
    return _post(memberId, 'unfreeze', {
      if (effectiveDate != null) 'effective_date': _ymd(effectiveDate),
      'notes': notes,
    });
  }

  /// Moves the member to a different plan. Expiry is unchanged; the difference
  /// is prorated across the remaining days and recorded as owed — not collected.
  Future<MemberLifecycleResult> upgrade(
    int memberId, {
    required int newPlanId,
    String reason = '',
    String notes = '',
  }) async {
    return _post(memberId, 'upgrade', {
      'new_plan_id': newPlanId,
      'reason': reason,
      'notes': notes,
    });
  }

  /// Moves remaining validity to another member. The source is terminated.
  Future<MemberLifecycleResult> transfer(
    int memberId, {
    required int toMemberId,
    int feeInPaise = 0,
    String reason = '',
    String notes = '',
  }) async {
    return _post(memberId, 'transfer', {
      'to_member_id': toMemberId,
      'fee_in_paise': feeInPaise,
      'reason': reason,
      'notes': notes,
    });
  }

  /// Ends a membership permanently. Terminal — a reason is required.
  Future<MemberLifecycleResult> terminate(
    int memberId, {
    required String reason,
    int terminationFeeInPaise = 0,
    String notes = '',
  }) async {
    return _post(memberId, 'terminate', {
      'reason': reason,
      'termination_fee_in_paise': terminationFeeInPaise,
      'notes': notes,
    });
  }

  // ── History ────────────────────────────────────────────────────────────────

  /// A member's lifecycle history, newest first.
  Future<List<LifecycleEvent>> timeline(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('${_base(memberId)}/lifecycle-events'), headers: headers),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => LifecycleEvent.fromJson(e)).toList();
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<MemberLifecycleResult> _post(
    int memberId,
    String action,
    Map<String, dynamic> body,
  ) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('${_base(memberId)}/$action'),
        headers: headers,
        body: jsonEncode(body),
      ),
    );
    return MemberLifecycleResult.fromJson(unwrapJson(response)['data']);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
