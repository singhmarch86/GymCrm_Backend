/// Tracks a member-to-member referral. Reward is FREE DAYS added to the
/// referrer's membership on payout — never cash, never automatic.
class Referral {
  final int id;
  final int referrerMemberId;
  final String referrerName;
  final String referredName;
  final String referredPhone;
  final int? referredMemberId;
  final String status; // pending | joined | rewarded | expired
  final int? rewardDays;
  final DateTime? rewardGivenAt;
  final String? notes;
  final String createdByUserName;
  final DateTime createdAt;

  const Referral({
    required this.id,
    required this.referrerMemberId,
    required this.referrerName,
    required this.referredName,
    required this.referredPhone,
    this.referredMemberId,
    required this.status,
    this.rewardDays,
    this.rewardGivenAt,
    this.notes,
    required this.createdByUserName,
    required this.createdAt,
  });

  factory Referral.fromJson(Map<String, dynamic> j) => Referral(
    id: j['id'] as int,
    referrerMemberId: j['referrer_member_id'] as int,
    referrerName: (j['referrer_name'] ?? '') as String,
    referredName: (j['referred_name'] ?? '') as String,
    referredPhone: (j['referred_phone'] ?? '') as String,
    referredMemberId: j['referred_member_id'] as int?,
    status: (j['status'] ?? 'pending') as String,
    rewardDays: j['reward_days'] as int?,
    rewardGivenAt: j['reward_given_at'] == null
        ? null
        : DateTime.parse(j['reward_given_at']),
    notes: j['notes'] as String?,
    createdByUserName: (j['created_by_user_name'] ?? 'Unknown') as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}
