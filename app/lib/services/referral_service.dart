import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/referral.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Member-to-member referral tracking. Reward is free membership days
/// credited to the referrer — never cash, never automatic. See
/// internal/referrals in the backend repo for the rules enforced server-side.
class ReferralService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<List<Referral>> getReferrals({int? referrerMemberId}) async {
    final headers = await _headers();
    final uri = referrerMemberId != null
        ? Uri.parse('$kBaseUrl/api/v1/members/$referrerMemberId/referrals')
        : Uri.parse('$kBaseUrl/api/v1/referrals');
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Referral.fromJson(e)).toList();
  }

  Future<Referral> createReferral({
    required int referrerMemberId,
    required String referredName,
    required String referredPhone,
    String notes = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/referrals'),
        headers: headers,
        body: jsonEncode({
          'referrer_member_id': referrerMemberId,
          'referred_name': referredName,
          'referred_phone': referredPhone,
          'notes': notes,
        }),
      ),
    );
    return Referral.fromJson(unwrapJson(response)['data']);
  }

  Future<Referral> markJoined(
    int referralId, {
    required int referredMemberId,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/referrals/$referralId/mark-joined'),
        headers: headers,
        body: jsonEncode({'referred_member_id': referredMemberId}),
      ),
    );
    return Referral.fromJson(unwrapJson(response)['data']);
  }

  /// Rewards a joined referral — extends the referrer's expiry by
  /// [rewardDays]. Requires the referral to already be 'joined'.
  Future<Referral> rewardReferrer(
    int referralId, {
    required int rewardDays,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/referrals/$referralId/reward'),
        headers: headers,
        body: jsonEncode({'reward_days': rewardDays}),
      ),
    );
    return Referral.fromJson(unwrapJson(response)['data']);
  }

  Future<Referral> expire(int referralId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/referrals/$referralId/expire'),
        headers: headers,
      ),
    );
    return Referral.fromJson(unwrapJson(response)['data']);
  }
}
