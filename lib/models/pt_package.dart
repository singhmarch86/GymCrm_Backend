/// PtPackage — a personal training package purchased by a member.
/// Full implementation in the Personal Training sprint.
class PtPackage {
  final int id;
  final int gymId;
  final int memberId;
  final int trainerId;
  final String packageName;
  final int totalSessions;
  final int sessionsUsed;
  final int amountInPaise;
  final String? expiryDate;
  final String status; // active | expired | cancelled
  final String createdAt;

  PtPackage({
    required this.id,
    required this.gymId,
    required this.memberId,
    required this.trainerId,
    required this.packageName,
    required this.totalSessions,
    required this.sessionsUsed,
    required this.amountInPaise,
    this.expiryDate,
    required this.status,
    required this.createdAt,
  });

  int get sessionsRemaining => totalSessions - sessionsUsed;

  factory PtPackage.fromJson(Map<String, dynamic> j) => PtPackage(
        id: j['id'] ?? 0,
        gymId: j['gym_id'] ?? 0,
        memberId: j['member_id'] ?? 0,
        trainerId: j['trainer_id'] ?? 0,
        packageName: j['package_name'] ?? '',
        totalSessions: j['total_sessions'] ?? 0,
        sessionsUsed: j['sessions_used'] ?? 0,
        amountInPaise: j['amount_in_paise'] ?? 0,
        expiryDate: j['expiry_date'],
        status: j['status'] ?? 'active',
        createdAt: j['created_at'] ?? '',
      );
}
