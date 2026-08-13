/// Lead — a prospective member moving through the sales pipeline.
/// Maps backend LeadResponse (internal/leads/dto.go).
class Lead {
  final int id;
  final int gymId;
  final String name;
  final String phone;
  final String? email;
  final String? gender;

  final String source;
  final String sourceLabel;
  final String? goal;
  final String? goalLabel;
  final String? notes;

  final String status;
  final String statusLabel;

  final String? trialDate;
  final String? followUpDate;
  final String? lostReason;

  final int? assignedUserId;
  final String? assignedUserName;
  final int? convertedMemberId;

  final String createdAt;
  final String updatedAt;

  Lead({
    required this.id,
    required this.gymId,
    required this.name,
    required this.phone,
    this.email,
    this.gender,
    required this.source,
    required this.sourceLabel,
    this.goal,
    this.goalLabel,
    this.notes,
    required this.status,
    required this.statusLabel,
    this.trialDate,
    this.followUpDate,
    this.lostReason,
    this.assignedUserId,
    this.assignedUserName,
    this.convertedMemberId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lead.fromJson(Map<String, dynamic> j) => Lead(
    id: j['id'] ?? 0,
    gymId: j['gym_id'] ?? 0,
    name: j['name'] ?? '',
    phone: j['phone'] ?? '',
    email: j['email'],
    gender: j['gender'],
    source: j['source'] ?? 'walk_in',
    sourceLabel: j['source_label'] ?? '',
    goal: j['goal'],
    goalLabel: j['goal_label'],
    notes: j['notes'],
    status: j['status'] ?? 'new_lead',
    statusLabel: j['status_label'] ?? '',
    trialDate: j['trial_date'],
    followUpDate: j['follow_up_date'],
    lostReason: j['lost_reason'],
    assignedUserId: j['assigned_user_id'],
    assignedUserName: j['assigned_user_name'],
    convertedMemberId: j['converted_member_id'],
    createdAt: j['created_at'] ?? '',
    updatedAt: j['updated_at'] ?? '',
  );

  /// Display-friendly follow-up date, e.g. "Today", "Tomorrow", "15 Jul"
  String get followUpLabel {
    if (followUpDate == null) return '';
    try {
      final d = DateTime.parse(followUpDate!);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diff = d.difference(today).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Tomorrow';
      if (diff == -1) return 'Yesterday';
      if (diff < 0) return 'Overdue (${diff.abs()}d)';
      const months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${d.day} ${months[d.month]}';
    } catch (_) {
      return followUpDate!;
    }
  }

  bool get isFollowUpOverdue {
    if (followUpDate == null) return false;
    try {
      final d = DateTime.parse(followUpDate!);
      return d.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  bool get isJoined => status == 'joined';
  bool get isLost => status == 'lost';
  bool get isActive => !isJoined && !isLost;
}

/// ConvertLeadResponse maps backend ConvertLeadResponse.
class ConvertLeadResponse {
  final Lead lead;
  final int memberId;
  final String message;

  ConvertLeadResponse({
    required this.lead,
    required this.memberId,
    required this.message,
  });

  factory ConvertLeadResponse.fromJson(Map<String, dynamic> j) =>
      ConvertLeadResponse(
        lead: Lead.fromJson(j['lead'] as Map<String, dynamic>),
        memberId: j['member_id'] ?? 0,
        message: j['message'] ?? '',
      );
}

/// LeadSummary maps backend LeadSummaryResponse.
class LeadSummary {
  final int totalLeads;
  final int todayLeads;
  final int pendingFollowUps;
  final int trialsScheduled;
  final double conversionRate;
  final Map<String, int> byStatus;
  final Map<String, int> bySource;

  LeadSummary({
    required this.totalLeads,
    required this.todayLeads,
    required this.pendingFollowUps,
    required this.trialsScheduled,
    required this.conversionRate,
    required this.byStatus,
    required this.bySource,
  });

  factory LeadSummary.fromJson(Map<String, dynamic> j) => LeadSummary(
    totalLeads: j['total_leads'] ?? 0,
    todayLeads: j['today_leads'] ?? 0,
    pendingFollowUps: j['pending_follow_ups'] ?? 0,
    trialsScheduled: j['trials_scheduled'] ?? 0,
    conversionRate: (j['conversion_rate'] ?? 0.0).toDouble(),
    byStatus: Map<String, int>.from(
      (j['by_status'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      ),
    ),
    bySource: Map<String, int>.from(
      (j['by_source'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      ),
    ),
  );
}
