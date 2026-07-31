import '../models/referral.dart';

/// ReferralService — stub.
/// Implement endpoints in the Referral System sprint.
class ReferralService {
  Future<List<Referral>> getReferrals() async =>
      throw UnimplementedError('Referral System not yet implemented');

  Future<Referral> createReferral(Map<String, dynamic> data) async =>
      throw UnimplementedError();

  Future<void> rewardReferrer(int referralId) async =>
      throw UnimplementedError();
}
