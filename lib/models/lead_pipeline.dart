import 'lead.dart';

/// One entry in a lead's activity timeline.
/// Maps backend LeadActivity (internal/leads/activity_model.go).
class LeadActivity {
  final int id;
  final int leadId;
  final int? userId;
  final String? userName;
  final String type;
  final String? note;
  final String? fromStatus;
  final String? toStatus;
  final String createdAt;

  LeadActivity({
    required this.id,
    required this.leadId,
    this.userId,
    this.userName,
    required this.type,
    this.note,
    this.fromStatus,
    this.toStatus,
    required this.createdAt,
  });

  factory LeadActivity.fromJson(Map<String, dynamic> j) => LeadActivity(
        id: j['id'] ?? 0,
        leadId: j['lead_id'] ?? 0,
        userId: j['user_id'],
        userName: j['user_name'],
        type: j['type'] ?? 'note',
        note: j['note'],
        fromStatus: j['from_status'],
        toStatus: j['to_status'],
        createdAt: j['created_at'] ?? '',
      );

  /// Relative age, e.g. "just now", "3h ago", "2d ago".
  String get relativeTime {
    try {
      final d = DateTime.parse(createdAt).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      return '${(diff.inDays / 30).floor()}mo ago';
    } catch (_) {
      return '';
    }
  }
}

/// The daily action queue. Maps backend FollowUpResponse.
class FollowUpQueue {
  final List<Lead> overdue;
  final List<Lead> today;
  final List<Lead> upcoming;
  final List<Lead> trials;

  FollowUpQueue({
    required this.overdue,
    required this.today,
    required this.upcoming,
    required this.trials,
  });

  static List<Lead> _leads(dynamic raw) =>
      (raw as List? ?? []).map((e) => Lead.fromJson(e as Map<String, dynamic>)).toList();

  factory FollowUpQueue.fromJson(Map<String, dynamic> j) => FollowUpQueue(
        overdue: _leads(j['overdue']),
        today: _leads(j['today']),
        upcoming: _leads(j['upcoming']),
        trials: _leads(j['trials']),
      );

  /// True when nothing at all needs attention — used to pick between the
  /// "all clear" empty state and the bucketed list.
  bool get isEmpty =>
      overdue.isEmpty && today.isEmpty && upcoming.isEmpty && trials.isEmpty;

  int get actionableCount => overdue.length + today.length;
}

/// One step of the conversion funnel. Maps backend FunnelStageResponse.
///
/// [count] is cumulative — how many leads reached at least this stage — so the
/// funnel decreases monotonically. [stepConversion] is the pass-through rate
/// from the previous stage, which is where the actionable drop-off shows up.
class FunnelStage {
  final String status;
  final String label;
  final int count;
  final double stepConversion;
  final double overallConversion;
  final double avgDays;

  FunnelStage({
    required this.status,
    required this.label,
    required this.count,
    required this.stepConversion,
    required this.overallConversion,
    required this.avgDays,
  });

  factory FunnelStage.fromJson(Map<String, dynamic> j) => FunnelStage(
        status: j['status'] ?? '',
        label: j['label'] ?? '',
        count: j['count'] ?? 0,
        stepConversion: (j['step_conversion'] ?? 0).toDouble(),
        overallConversion: (j['overall_conversion'] ?? 0).toDouble(),
        avgDays: (j['avg_days'] ?? 0).toDouble(),
      );
}

class SourcePerformance {
  final String source;
  final String label;
  final int total;
  final int joined;
  final int lost;
  final double conversionRate;

  SourcePerformance({
    required this.source,
    required this.label,
    required this.total,
    required this.joined,
    required this.lost,
    required this.conversionRate,
  });

  factory SourcePerformance.fromJson(Map<String, dynamic> j) => SourcePerformance(
        source: j['source'] ?? '',
        label: j['label'] ?? '',
        total: j['total'] ?? 0,
        joined: j['joined'] ?? 0,
        lost: j['lost'] ?? 0,
        conversionRate: (j['conversion_rate'] ?? 0).toDouble(),
      );
}

class LostReason {
  final String reason;
  final int count;

  LostReason({required this.reason, required this.count});

  factory LostReason.fromJson(Map<String, dynamic> j) => LostReason(
        reason: j['reason'] ?? '',
        count: j['count'] ?? 0,
      );
}

/// Maps backend AnalyticsResponse.
class LeadAnalytics {
  final List<FunnelStage> funnel;
  final int lostCount;
  final List<SourcePerformance> bySource;
  final List<LostReason> lostReasons;

  LeadAnalytics({
    required this.funnel,
    required this.lostCount,
    required this.bySource,
    required this.lostReasons,
  });

  factory LeadAnalytics.fromJson(Map<String, dynamic> j) => LeadAnalytics(
        funnel: (j['funnel'] as List? ?? [])
            .map((e) => FunnelStage.fromJson(e as Map<String, dynamic>))
            .toList(),
        lostCount: j['lost_count'] ?? 0,
        bySource: (j['by_source'] as List? ?? [])
            .map((e) => SourcePerformance.fromJson(e as Map<String, dynamic>))
            .toList(),
        lostReasons: (j['lost_reasons'] as List? ?? [])
            .map((e) => LostReason.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// True when no stage transitions have been recorded yet, so the
  /// time-in-stage figures are all zero and should be hidden rather than
  /// shown as a misleading "0 days".
  bool get hasStageDurations => funnel.any((f) => f.avgDays > 0);
}

/// A staff member who can own leads. Maps backend Assignee.
class Assignee {
  final int id;
  final String name;
  final String role;
  final int leadCount;

  Assignee({
    required this.id,
    required this.name,
    required this.role,
    required this.leadCount,
  });

  factory Assignee.fromJson(Map<String, dynamic> j) => Assignee(
        id: j['id'] ?? 0,
        name: j['name'] ?? '',
        role: j['role'] ?? 'staff',
        leadCount: j['lead_count'] ?? 0,
      );
}
