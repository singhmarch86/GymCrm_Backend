/// Private, owner-curated member recognition — a reason, optionally citing a
/// signal, never a score or rank. See migration 035 in the backend repo.
class Recognition {
  final int id;
  final int memberId;
  final String reason;
  final String? signalType; // 'rhythm' | 'feedback'
  final int? signalId;
  final String createdByName;
  final DateTime createdAt;

  const Recognition({
    required this.id,
    required this.memberId,
    required this.reason,
    this.signalType,
    this.signalId,
    required this.createdByName,
    required this.createdAt,
  });

  factory Recognition.fromJson(Map<String, dynamic> j) => Recognition(
    id: j['id'] ?? 0,
    memberId: j['member_id'] ?? 0,
    reason: j['reason'] ?? '',
    signalType: j['signal_type'],
    signalId: j['signal_id'],
    createdByName: j['created_by_name'] ?? '',
    createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
  );
}
