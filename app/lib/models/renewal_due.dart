/// A member due for renewal, as returned by GET /api/v1/members/renewals.
///
/// Mirrors the backend's RenewalDueResponse (internal/members/dto.go):
/// id, member_name, phone, plan_id, plan_name, expiry_date, days_remaining, status.
class RenewalDue {
  final int id;
  final String memberName;
  final String phone;

  final int? planId;
  final String? planName;

  final String? expiryDate;
  final int daysRemaining;

  /// One of: EXPIRED, DUE_TODAY, EXPIRING_SOON, UPCOMING, ACTIVE
  final String status;

  RenewalDue({
    required this.id,
    required this.memberName,
    required this.phone,
    this.planId,
    this.planName,
    this.expiryDate,
    required this.daysRemaining,
    required this.status,
  });

  factory RenewalDue.fromJson(Map<String, dynamic> json) {
    return RenewalDue(
      id: json['id'] ?? 0,
      memberName: json['member_name'] ?? '',
      phone: json['phone'] ?? '',
      planId: json['plan_id'] as int?,
      planName: json['plan_name'],
      expiryDate: json['expiry_date'],
      daysRemaining: json['days_remaining'] ?? 0,
      status: json['status'] ?? '',
    );
  }

  /// Display-friendly expiry text, matching the PRD mock:
  /// "Expires Today" / "Expires Tomorrow" / "Expires in 5 Days" / "Expired 3 days ago"
  String get expiryText {
    switch (status) {
      case 'DUE_TODAY':
        return 'Expires Today';
      case 'EXPIRED':
        return 'Expired ${daysRemaining.abs()} ${daysRemaining.abs() == 1 ? 'day' : 'days'} ago';
      default:
        if (daysRemaining == 1) {
          return 'Expires Tomorrow';
        }
        return 'Expires in $daysRemaining Days';
    }
  }
}
