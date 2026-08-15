/// PT feedback — one entry from either the member or a trainer, both
/// staff-transcribed (trainers have no login, members have no app). See
/// migration 035 in the backend repo.
class MemberFeedback {
  final int id;
  final int memberId;
  final String memberName;
  final String authorRole; // 'member' | 'trainer'
  final int? trainerId;
  final String? trainerName;
  final int? ptPackageId;
  final int? ptAppointmentId;
  final String note;
  final String createdByName;
  final DateTime createdAt;

  const MemberFeedback({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.authorRole,
    this.trainerId,
    this.trainerName,
    this.ptPackageId,
    this.ptAppointmentId,
    required this.note,
    required this.createdByName,
    required this.createdAt,
  });

  bool get isFromMember => authorRole == 'member';

  factory MemberFeedback.fromJson(Map<String, dynamic> j) => MemberFeedback(
    id: j['id'] ?? 0,
    memberId: j['member_id'] ?? 0,
    memberName: j['member_name'] ?? '',
    authorRole: j['author_role'] ?? 'member',
    trainerId: j['trainer_id'],
    trainerName: j['trainer_name'],
    ptPackageId: j['pt_package_id'],
    ptAppointmentId: j['pt_appointment_id'],
    note: j['note'] ?? '',
    createdByName: j['created_by_name'] ?? '',
    createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
  );
}
