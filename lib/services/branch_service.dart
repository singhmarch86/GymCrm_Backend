import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/branch.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'storage_service.dart';
import 'token_manager.dart';

/// Branches (locations) and branch switching.
/// See docs/FR-06-multi-location.md in the backend repo.
///
/// Switching branch is a **server** operation. The server checks the user's
/// grant for the requested branch and issues a token scoped to it; the app
/// then stores that token. The app never edits a stored gym id itself — the
/// server reads the token, not local state, so doing so would achieve nothing
/// except a false impression of access.
class BranchService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<List<Branch>> getBranches() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/branches'), headers: headers),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Branch.fromJson(e)).toList();
  }

  /// Switches the session to [gymId].
  ///
  /// Throws an [ApiException] (403) if the signed-in user has no grant for
  /// that branch — which is the server refusing, not the app deciding.
  Future<Branch> switchBranch(int gymId) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/branches/switch'),
          headers: headers,
          body: jsonEncode({'gym_id': gymId}),
        ));
    final data = unwrapJson(response)['data'] as Map<String, dynamic>;

    final refresh = await StorageService.getRefreshToken() ?? '';
    await StorageService.saveTokens(
      accessToken: data['access_token'] as String,
      refreshToken: refresh,
    );

    // Kept in sync so anything reading the cached gym/role locally agrees with
    // the token now being sent.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(StorageService.gymIdKey, data['gym_id'] ?? gymId);
    await prefs.setString(StorageService.roleKey, data['role'] ?? 'staff');

    return Branch(
      id: data['gym_id'] ?? gymId,
      name: (data['branch_name'] ?? '') as String,
      branchName: data['branch_name'] as String?,
      role: (data['role'] ?? 'staff') as String,
    );
  }

  Future<Branch> createBranch({
    required String name,
    String branchName = '',
    String city = '',
    String state = '',
    String phone = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/branches'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'branch_name': branchName,
            'city': city,
            'state': state,
            'phone': phone,
          }),
        ));
    return Branch.fromJson(unwrapJson(response)['data']);
  }

  /// Sets what a branch should achieve this month. Owners only, and only for
  /// branches you hold — the server enforces both.
  Future<void> setTargets(
    int gymId, {
    required int revenueTargetInPaise,
    required int memberTarget,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.put(
          Uri.parse('$kBaseUrl/api/v1/branches/$gymId/targets'),
          headers: headers,
          body: jsonEncode({
            'monthly_revenue_target_in_paise': revenueTargetInPaise,
            'monthly_member_target': memberTarget,
          }),
        ));
    unwrapJson(response);
  }

  /// Moves a member to another branch. Their payments and invoices stay with
  /// the branch that issued them.
  Future<void> transferMember(int memberId, int toGymId, {String reason = ''}) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/branches/transfer-member'),
          headers: headers,
          body: jsonEncode({
            'member_id': memberId,
            'to_gym_id': toGymId,
            'reason': reason,
          }),
        ));
    unwrapJson(response);
  }

  /// Moves a staff member's home branch. Owners only; the server enforces it.
  Future<void> transferStaff(int userId, int toGymId, {String role = 'staff'}) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/branches/transfer-staff'),
          headers: headers,
          body: jsonEncode({'user_id': userId, 'to_gym_id': toGymId, 'role': role}),
        ));
    unwrapJson(response);
  }

  /// Moves a trainer to another branch. PT packages already sold stay with the
  /// branch that sold them.
  Future<void> transferTrainer(int trainerId, int toGymId) async {
    final headers = await _headers();
    final response = await guardRequest(() => http.post(
          Uri.parse('$kBaseUrl/api/v1/branches/transfer-trainer'),
          headers: headers,
          body: jsonEncode({'trainer_id': trainerId, 'to_gym_id': toGymId}),
        ));
    unwrapJson(response);
  }

  /// Consolidated figures across the branches you own. Read-only, and scoped
  /// server-side to your own grants.
  Future<List<BranchSummary>> chainSummary() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/org/summary'), headers: headers),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => BranchSummary.fromJson(e)).toList();
  }
}
