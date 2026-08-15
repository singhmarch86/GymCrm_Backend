/// PT reports — the member side and the trainer side, independently. Both
/// are read-only compositions the server assembles; see internal/ptreport
/// in the backend repo.
library;

class PackageSummary {
  final int id;
  final int trainerId;
  final String trainerName;
  final String packageName;
  final int totalSessions;
  final int sessionsUsed;
  final int sessionsRemaining;
  final String status;
  final DateTime? expiryDate;

  const PackageSummary({
    required this.id,
    required this.trainerId,
    required this.trainerName,
    required this.packageName,
    required this.totalSessions,
    required this.sessionsUsed,
    required this.sessionsRemaining,
    required this.status,
    this.expiryDate,
  });

  factory PackageSummary.fromJson(Map<String, dynamic> j) => PackageSummary(
    id: j['id'] ?? 0,
    trainerId: j['trainer_id'] ?? 0,
    trainerName: j['trainer_name'] ?? '',
    packageName: j['package_name'] ?? '',
    totalSessions: j['total_sessions'] ?? 0,
    sessionsUsed: j['sessions_used'] ?? 0,
    sessionsRemaining: j['sessions_remaining'] ?? 0,
    status: j['status'] ?? 'active',
    expiryDate: j['expiry_date'] != null
        ? DateTime.tryParse(j['expiry_date'])
        : null,
  );
}

class ReportFeedbackRow {
  final int id;
  final String authorRole;
  final String note;
  final DateTime createdAt;

  const ReportFeedbackRow({
    required this.id,
    required this.authorRole,
    required this.note,
    required this.createdAt,
  });

  factory ReportFeedbackRow.fromJson(Map<String, dynamic> j) =>
      ReportFeedbackRow(
        id: j['id'] ?? 0,
        authorRole: j['author_role'] ?? 'member',
        note: j['note'] ?? '',
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
      );
}

class RhythmSummary {
  final double recentConsistency;
  final double recentRate;
  final bool isBroken;

  const RhythmSummary({
    required this.recentConsistency,
    required this.recentRate,
    required this.isBroken,
  });

  factory RhythmSummary.fromJson(Map<String, dynamic> j) => RhythmSummary(
    recentConsistency: (j['recent_consistency'] as num?)?.toDouble() ?? 0,
    recentRate: (j['recent_rate'] as num?)?.toDouble() ?? 0,
    isBroken: j['is_broken'] ?? false,
  );
}

class MemberPtReport {
  final int memberId;
  final List<PackageSummary> packages;
  final List<ReportFeedbackRow> feedback;
  final RhythmSummary? rhythm;

  const MemberPtReport({
    required this.memberId,
    required this.packages,
    required this.feedback,
    this.rhythm,
  });

  factory MemberPtReport.fromJson(Map<String, dynamic> j) => MemberPtReport(
    memberId: j['member_id'] ?? 0,
    packages: ((j['packages'] as List?) ?? [])
        .map((e) => PackageSummary.fromJson(e))
        .toList(),
    feedback: ((j['feedback'] as List?) ?? [])
        .map((e) => ReportFeedbackRow.fromJson(e))
        .toList(),
    rhythm: j['rhythm'] != null ? RhythmSummary.fromJson(j['rhythm']) : null,
  );
}

class MemberRef {
  final int id;
  final String name;

  const MemberRef({required this.id, required this.name});

  factory MemberRef.fromJson(Map<String, dynamic> j) =>
      MemberRef(id: j['id'] ?? 0, name: j['name'] ?? '');
}

class TrainerPtReport {
  final int trainerId;
  final int sessionsCompleted;
  final List<ReportFeedbackRow> feedback;
  final List<MemberRef> assignedMembers;
  final int? lastPayoutInPaise;
  final DateTime? lastPayoutPeriodTo;

  const TrainerPtReport({
    required this.trainerId,
    required this.sessionsCompleted,
    required this.feedback,
    required this.assignedMembers,
    this.lastPayoutInPaise,
    this.lastPayoutPeriodTo,
  });

  factory TrainerPtReport.fromJson(Map<String, dynamic> j) => TrainerPtReport(
    trainerId: j['trainer_id'] ?? 0,
    sessionsCompleted: j['sessions_completed'] ?? 0,
    feedback: ((j['feedback'] as List?) ?? [])
        .map((e) => ReportFeedbackRow.fromJson(e))
        .toList(),
    assignedMembers: ((j['assigned_members'] as List?) ?? [])
        .map((e) => MemberRef.fromJson(e))
        .toList(),
    lastPayoutInPaise: j['last_payout_in_paise'],
    lastPayoutPeriodTo: j['last_payout_period_to'] != null
        ? DateTime.tryParse(j['last_payout_period_to'])
        : null,
  );
}
