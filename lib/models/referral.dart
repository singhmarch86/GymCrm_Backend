/// Referral — tracks member-to-member referrals and rewards.
/// Full implementation in the Referral System sprint.
class Referral {
  final int id;
  final int gymId;
  final int referrerId;   // member who referred
  final String referrerName;
  final int? referredId;  // null if lead hasn't joined yet
  final String referredName;
  final String referredPhone;
  final String status;    // pending | joined | rewarded
  final int? rewardDays;  // free days given to referrer
  final String createdAt;

  Referral({
    required this.id,
    required this.gymId,
    required this.referrerId,
    required this.referrerName,
    this.referredId,
    required this.referredName,
    required this.referredPhone,
    required this.status,
    this.rewardDays,
    required this.createdAt,
  });

  factory Referral.fromJson(Map<String, dynamic> j) => Referral(
        id: j['id'] ?? 0,
        gymId: j['gym_id'] ?? 0,
        referrerId: j['referrer_id'] ?? 0,
        referrerName: j['referrer_name'] ?? '',
        referredId: j['referred_id'],
        referredName: j['referred_name'] ?? '',
        referredPhone: j['referred_phone'] ?? '',
        status: j['status'] ?? 'pending',
        rewardDays: j['reward_days'],
        createdAt: j['created_at'] ?? '',
      );
}
