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

  /// What came of it (FR-16). Null is a real answer — a note has no outcome,
  /// and every row logged before this existed has none. Never inferred.
  final String? outcome;
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
    this.outcome,
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
    outcome: j['outcome'],
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

  /// What the last [outcomeDays] of calling produced (FR-16 §6). Always all
  /// six outcomes, zeros included, so the row keeps its shape between loads.
  final List<OutcomeCount> outcomeCounts;
  final int outcomeDays;

  FollowUpQueue({
    required this.overdue,
    required this.today,
    required this.upcoming,
    required this.trials,
    this.outcomeCounts = const [],
    this.outcomeDays = 7,
  });

  static List<Lead> _leads(dynamic raw) => (raw as List? ?? [])
      .map((e) => Lead.fromJson(e as Map<String, dynamic>))
      .toList();

  factory FollowUpQueue.fromJson(Map<String, dynamic> j) => FollowUpQueue(
    overdue: _leads(j['overdue']),
    today: _leads(j['today']),
    upcoming: _leads(j['upcoming']),
    trials: _leads(j['trials']),
    outcomeCounts: ((j['outcome_counts'] as List?) ?? [])
        .map((e) => OutcomeCount.fromJson(e as Map<String, dynamic>))
        .toList(),
    outcomeDays: j['outcome_days'] ?? 7,
  );

  /// True when nothing at all needs attention — used to pick between the
  /// "all clear" empty state and the bucketed list.
  bool get isEmpty =>
      overdue.isEmpty && today.isEmpty && upcoming.isEmpty && trials.isEmpty;

  int get actionableCount => overdue.length + today.length;

  /// True when nothing has been logged in the window — the counts row is
  /// suppressed rather than showing six zeros, which reads as broken.
  bool get hasLoggedOutcomes => outcomeCounts.any((c) => c.count > 0);
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

  factory SourcePerformance.fromJson(Map<String, dynamic> j) =>
      SourcePerformance(
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

  factory LostReason.fromJson(Map<String, dynamic> j) =>
      LostReason(reason: j['reason'] ?? '', count: j['count'] ?? 0);
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

/// The six follow-up outcomes (FR-16 §2).
///
/// Six, and the count is the point: a desk facing fifteen options picks the
/// first plausible one and the data becomes noise that looks like signal.
class FollowUpOutcome {
  final String value;
  final String label;

  const FollowUpOutcome(this.value, this.label);

  static const answered = FollowUpOutcome('answered', 'Answered');
  static const noAnswer = FollowUpOutcome('no_answer', 'No answer');
  static const callBack = FollowUpOutcome('call_back', 'Call back later');
  static const interested = FollowUpOutcome('interested', 'Interested');
  static const notInterested = FollowUpOutcome(
    'not_interested',
    'Not interested',
  );
  static const wrongNumber = FollowUpOutcome('wrong_number', 'Wrong number');

  static const all = [
    answered,
    noAnswer,
    callBack,
    interested,
    notInterested,
    wrongNumber,
  ];

  static String labelFor(String? value) {
    if (value == null) return '';
    for (final o in all) {
      if (o.value == value) return o.label;
    }
    return value;
  }
}

/// One grouped count on the follow-up screen.
class OutcomeCount {
  final String outcome;
  final String label;
  final int count;

  const OutcomeCount({
    required this.outcome,
    required this.label,
    required this.count,
  });

  factory OutcomeCount.fromJson(Map<String, dynamic> j) => OutcomeCount(
    outcome: j['outcome'] ?? '',
    label: j['label'] ?? '',
    count: j['count'] ?? 0,
  );
}

/// The lead workflow (FR-18).
///
/// Every open lead has exactly one next step, owned by one person, with a
/// date. A lead missing any of the three is Unattended — the state this whole
/// feature exists to make visible.
class WorkflowItem {
  final int leadId;
  final String name;
  final String phone;
  final String status;
  final String stageLabel;

  /// Days in the current stage. Stuck is not a status: a lead sitting in
  /// Contacted for three weeks is not "contacted", it is dying.
  final int stageDays;

  final String? nextStep;
  final String? nextStepLabel;
  final DateTime? nextStepDue;

  final int? ownerId;
  final String? ownerName;

  /// Computed by the server so the UI can never disagree with it about who is
  /// overdue.
  final String state;
  final int daysOverdue;

  const WorkflowItem({
    required this.leadId,
    required this.name,
    required this.phone,
    required this.status,
    required this.stageLabel,
    required this.stageDays,
    this.nextStep,
    this.nextStepLabel,
    this.nextStepDue,
    this.ownerId,
    this.ownerName,
    required this.state,
    this.daysOverdue = 0,
  });

  factory WorkflowItem.fromJson(Map<String, dynamic> j) => WorkflowItem(
    leadId: j['lead_id'] ?? 0,
    name: j['name'] ?? '',
    phone: j['phone'] ?? '',
    status: j['status'] ?? '',
    stageLabel: j['stage_label'] ?? '',
    stageDays: j['stage_days'] ?? 0,
    nextStep: j['next_step'],
    nextStepLabel: j['next_step_label'],
    nextStepDue: j['next_step_due'] == null
        ? null
        : DateTime.tryParse(j['next_step_due'])?.toLocal(),
    ownerId: j['owner_id'],
    ownerName: j['owner_name'],
    state: j['state'] ?? '',
    daysOverdue: j['days_overdue'] ?? 0,
  );

  bool get isUnattended => state == 'unattended';

  /// A lead stuck in one stage for over a month, whatever its due date says.
  /// Advisory only — it changes emphasis, never grouping.
  bool get isStale => stageDays >= 30;
}

class WorkflowGroup {
  final String state;
  final String label;
  final int count;
  final List<WorkflowItem> items;

  const WorkflowGroup({
    required this.state,
    required this.label,
    required this.count,
    required this.items,
  });

  factory WorkflowGroup.fromJson(Map<String, dynamic> j) => WorkflowGroup(
    state: j['state'] ?? '',
    label: j['label'] ?? '',
    count: j['count'] ?? 0,
    items: ((j['items'] as List?) ?? [])
        .map((e) => WorkflowItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class LeadWorkflow {
  final List<WorkflowGroup> groups;
  final int totalOpen;
  final int unattended;
  final int overdue;
  final int dueToday;

  /// Which axis the groups represent: timing | next_step | source | goal.
  /// Sent by the server so a client cannot render one grouping under
  /// another's heading.
  final String groupBy;
  final String groupByLabel;

  const LeadWorkflow({
    required this.groups,
    required this.totalOpen,
    required this.unattended,
    required this.overdue,
    required this.dueToday,
    this.groupBy = 'timing',
    this.groupByLabel = 'What is late',
  });

  factory LeadWorkflow.fromJson(Map<String, dynamic> j) => LeadWorkflow(
    groups: ((j['groups'] as List?) ?? [])
        .map((e) => WorkflowGroup.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalOpen: j['total_open'] ?? 0,
    unattended: j['unattended'] ?? 0,
    overdue: j['overdue'] ?? 0,
    dueToday: j['due_today'] ?? 0,
    groupBy: j['group_by'] ?? 'timing',
    groupByLabel: j['group_by_label'] ?? 'What is late',
  );

  bool get isEmpty => totalOpen == 0;
}

/// The axes the follow-up queue can be cut along (FR-24).
///
/// Named after the question each one answers rather than the column it reads,
/// because the reader is choosing a question. "Where they came from" is a
/// thing somebody wants to know; "source" is a database field.
class WorkflowAxis {
  final String key;
  final String label;

  const WorkflowAxis(this.key, this.label);

  static const all = [
    WorkflowAxis('timing', 'What is late'),
    WorkflowAxis('next_step', 'What needs doing'),
    WorkflowAxis('source', 'Where they came from'),
    WorkflowAxis('goal', 'What they want'),
  ];
}

/// One thing a staff member can commit to doing next.
class NextStepOption {
  final String step;
  final String label;

  const NextStepOption(this.step, this.label);

  /// Mirrors the server's list so the picker works before /next-steps returns.
  /// The server remains the source of truth — FR-18 expects the pilot gym to
  /// revise this vocabulary.
  static const fallback = [
    NextStepOption('first_contact', 'Make first contact'),
    NextStepOption('call_back', 'Call back'),
    NextStepOption('book_trial', 'Book a trial'),
    NextStepOption('confirm_trial', 'Confirm they are coming'),
    NextStepOption('counselling', 'Counselling — discuss plans'),
    NextStepOption('close', 'Close, or record why not'),
    NextStepOption('fix_number', 'Get a working number'),
  ];

  factory NextStepOption.fromJson(Map<String, dynamic> j) =>
      NextStepOption(j['step'] ?? '', j['label'] ?? '');
}
