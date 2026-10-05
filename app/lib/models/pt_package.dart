/// PtPackage — a personal training package purchased by a member. A session
/// credit counter: `sessionsUsed` only increments when an appointment tied to
/// it is completed, never when it's booked. See FR-03 §3.
class PtPackage {
  final int id;
  final int memberId;
  final String memberName;
  final int trainerId;
  final String trainerName;
  final String packageName;
  final int totalSessions;
  final int sessionsUsed;
  final int sessionsRemaining;
  final int amountInPaise;
  final double amountInRupees;
  final String? expiryDate;
  final String status; // active | expired | cancelled
  final String createdAt;

  PtPackage({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.trainerId,
    required this.trainerName,
    required this.packageName,
    required this.totalSessions,
    required this.sessionsUsed,
    required this.sessionsRemaining,
    required this.amountInPaise,
    required this.amountInRupees,
    this.expiryDate,
    required this.status,
    required this.createdAt,
  });

  factory PtPackage.fromJson(Map<String, dynamic> j) => PtPackage(
    id: j['id'] ?? 0,
    memberId: j['member_id'] ?? 0,
    memberName: j['member_name'] ?? '',
    trainerId: j['trainer_id'] ?? 0,
    trainerName: j['trainer_name'] ?? '',
    packageName: j['package_name'] ?? '',
    totalSessions: j['total_sessions'] ?? 0,
    sessionsUsed: j['sessions_used'] ?? 0,
    sessionsRemaining: j['sessions_remaining'] ?? 0,
    amountInPaise: j['amount_in_paise'] ?? 0,
    amountInRupees: (j['amount_in_rupees'] as num?)?.toDouble() ?? 0,
    expiryDate: j['expiry_date'],
    status: j['status'] ?? 'active',
    createdAt: j['created_at'] ?? '',
  );
}

/// PtAppointment — a booked 1:1 session against a package. Booking never
/// checks or reserves a credit; only completing it does. See FR-03 §3.
class PtAppointment {
  final int id;
  final int ptPackageId;
  final int trainerId;
  final String trainerName;
  final int memberId;
  final String memberName;
  final String scheduledAt;
  final int durationMinutes;
  final String status; // scheduled | completed | cancelled | no_show
  final String? notes;
  final String createdAt;

  PtAppointment({
    required this.id,
    required this.ptPackageId,
    required this.trainerId,
    required this.trainerName,
    required this.memberId,
    required this.memberName,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    this.notes,
    required this.createdAt,
  });

  DateTime get scheduledAtDate => DateTime.parse(scheduledAt);

  factory PtAppointment.fromJson(Map<String, dynamic> j) => PtAppointment(
    id: j['id'] ?? 0,
    ptPackageId: j['pt_package_id'] ?? 0,
    trainerId: j['trainer_id'] ?? 0,
    trainerName: j['trainer_name'] ?? '',
    memberId: j['member_id'] ?? 0,
    memberName: j['member_name'] ?? '',
    scheduledAt: j['scheduled_at'] ?? '',
    durationMinutes: j['duration_minutes'] ?? 60,
    status: j['status'] ?? 'scheduled',
    notes: j['notes'],
    createdAt: j['created_at'] ?? '',
  );
}
