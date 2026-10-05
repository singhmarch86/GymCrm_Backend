import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/wallet.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Member wallet: stored credit on an account.
/// See docs/FR-08-member-wallet.md in the backend repo.
///
/// Every balance change goes through the server, which appends a ledger row and
/// moves the balance inside one locked transaction. The app never computes a
/// balance itself.
class WalletService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<Wallet> get(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/wallet'),
        headers: headers,
      ),
    );
    return Wallet.fromJson(unwrapJson(response)['data']);
  }

  Future<void> topUp(
    int memberId, {
    required int amountInPaise,
    String reason = '',
  }) async {
    await _post(memberId, 'topup', amountInPaise, reason);
  }

  /// Spends credit. Throws an [ApiException] (409) if the balance is short —
  /// the wallet never goes negative.
  Future<void> spend(
    int memberId, {
    required int amountInPaise,
    String reason = '',
  }) async {
    await _post(memberId, 'spend', amountInPaise, reason);
  }

  /// Corrects a balance. The amount is signed, and a reason is mandatory.
  Future<void> adjust(
    int memberId, {
    required int deltaInPaise,
    required String reason,
  }) async {
    await _post(memberId, 'adjust', deltaInPaise, reason);
  }

  Future<void> _post(
    int memberId,
    String action,
    int amountInPaise,
    String reason,
  ) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/wallet/$action'),
        headers: headers,
        body: jsonEncode({'amount_in_paise': amountInPaise, 'reason': reason}),
      ),
    );
    unwrapJson(response);
  }
}
