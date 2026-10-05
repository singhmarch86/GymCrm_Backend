/// Membership lifecycle models — freeze, upgrade, transfer, terminate.
///
/// Business rules live server-side (docs/FR-01-membership-lifecycle.md in the
/// backend repo). These types deliberately carry no logic beyond parsing: any
/// limit or amount shown to staff comes from the API, so the number they see is
/// always the number that will be applied.
library;

/// One entry in a member's lifecycle history.
class LifecycleEvent {
  final int id;
  final int memberId;
  final String memberName;
  final String eventType;

  /// Staff-readable phrase built server-side ("Frozen for 30 days"), so every
  /// client renders identical wording.
  final String label;

  final DateTime effectiveDate;

  final String? oldPlanName;
  final String? newPlanName;
  final DateTime? oldExpiryDate;
  final DateTime? newExpiryDate;
  final String? oldStatus;
  final String? newStatus;

  final DateTime? freezeStart;
  final DateTime? freezeEnd;
  final int? freezeDays;

  final int amountDueInPaise;
  final double amountDueInRupees;
  final int amountCreditInPaise;
  final double amountCreditInRupees;
  final int feeInPaise;

  final int? relatedMemberId;
  final String? relatedMemberName;

  final String? reason;
  final String? notes;
  final String performedByUserName;
  final DateTime createdAt;

  const LifecycleEvent({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.eventType,
    required this.label,
    required this.effectiveDate,
    this.oldPlanName,
    this.newPlanName,
    this.oldExpiryDate,
    this.newExpiryDate,
    this.oldStatus,
    this.newStatus,
    this.freezeStart,
    this.freezeEnd,
    this.freezeDays,
    required this.amountDueInPaise,
    required this.amountDueInRupees,
    required this.amountCreditInPaise,
    required this.amountCreditInRupees,
    required this.feeInPaise,
    this.relatedMemberId,
    this.relatedMemberName,
    this.reason,
    this.notes,
    required this.performedByUserName,
    required this.createdAt,
  });

  /// True when this event moved money in either direction — used to decide
  /// whether the timeline row needs a money line at all.
  bool get hasMoney => amountDueInPaise > 0 || amountCreditInPaise > 0;

  factory LifecycleEvent.fromJson(Map<String, dynamic> j) => LifecycleEvent(
    id: j['id'] as int,
    memberId: j['member_id'] as int,
    memberName: (j['member_name'] ?? '') as String,
    eventType: (j['event_type'] ?? '') as String,
    label: (j['label'] ?? '') as String,
    effectiveDate: DateTime.parse(j['effective_date'] as String),
    oldPlanName: j['old_plan_name'] as String?,
    newPlanName: j['new_plan_name'] as String?,
    oldExpiryDate: _date(j['old_expiry_date']),
    newExpiryDate: _date(j['new_expiry_date']),
    oldStatus: j['old_status'] as String?,
    newStatus: j['new_status'] as String?,
    freezeStart: _date(j['freeze_start']),
    freezeEnd: _date(j['freeze_end']),
    freezeDays: j['freeze_days'] as int?,
    amountDueInPaise: (j['amount_due_in_paise'] ?? 0) as int,
    amountDueInRupees: _double(j['amount_due_in_rupees']),
    amountCreditInPaise: (j['amount_credit_in_paise'] ?? 0) as int,
    amountCreditInRupees: _double(j['amount_credit_in_rupees']),
    feeInPaise: (j['fee_in_paise'] ?? 0) as int,
    relatedMemberId: j['related_member_id'] as int?,
    relatedMemberName: j['related_member_name'] as String?,
    reason: j['reason'] as String?,
    notes: j['notes'] as String?,
    performedByUserName: (j['performed_by_user_name'] ?? 'Unknown') as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Resulting member state after a lifecycle operation, plus the event that
/// produced it — returned together so the caller can refresh without refetching.
class MemberLifecycleResult {
  final int memberId;
  final String memberName;
  final String status;
  final String? planName;
  final DateTime? expiryDate;
  final DateTime? frozenFrom;
  final DateTime? frozenUntil;
  final int freezeDaysUsedYtd;
  final int freezeDaysLeftYtd;
  final LifecycleEvent event;

  const MemberLifecycleResult({
    required this.memberId,
    required this.memberName,
    required this.status,
    this.planName,
    this.expiryDate,
    this.frozenFrom,
    this.frozenUntil,
    required this.freezeDaysUsedYtd,
    required this.freezeDaysLeftYtd,
    required this.event,
  });

  factory MemberLifecycleResult.fromJson(Map<String, dynamic> j) =>
      MemberLifecycleResult(
        memberId: j['member_id'] as int,
        memberName: (j['member_name'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        planName: j['plan_name'] as String?,
        expiryDate: _date(j['expiry_date']),
        frozenFrom: _date(j['frozen_from']),
        frozenUntil: _date(j['frozen_until']),
        freezeDaysUsedYtd: (j['freeze_days_used_ytd'] ?? 0) as int,
        freezeDaysLeftYtd: (j['freeze_days_left_ytd'] ?? 0) as int,
        event: LifecycleEvent.fromJson(j['event'] as Map<String, dynamic>),
      );
}

/// Whether a member may be frozen and within what bounds. Fetched before the
/// freeze form opens so limits are shown rather than discovered by rejection.
class FreezeEligibility {
  final bool eligible;
  final String reason;
  final int minDays;
  final int maxDays;
  final int freezeDaysUsedYtd;
  final int freezeDaysLeftYtd;
  final bool currentlyFrozen;

  const FreezeEligibility({
    required this.eligible,
    required this.reason,
    required this.minDays,
    required this.maxDays,
    required this.freezeDaysUsedYtd,
    required this.freezeDaysLeftYtd,
    required this.currentlyFrozen,
  });

  factory FreezeEligibility.fromJson(Map<String, dynamic> j) =>
      FreezeEligibility(
        eligible: (j['eligible'] ?? false) as bool,
        reason: (j['reason'] ?? '') as String,
        minDays: (j['min_days'] ?? 0) as int,
        maxDays: (j['max_days'] ?? 0) as int,
        freezeDaysUsedYtd: (j['freeze_days_used_ytd'] ?? 0) as int,
        freezeDaysLeftYtd: (j['freeze_days_left_ytd'] ?? 0) as int,
        currentlyFrozen: (j['currently_frozen'] ?? false) as bool,
      );
}

/// Prorated cost of changing plan, previewed before staff commit.
class UpgradeQuote {
  final int memberId;
  final String? currentPlanName;
  final int newPlanId;
  final String newPlanName;
  final int remainingDays;
  final int oldDailyRatePaise;
  final int newDailyRatePaise;
  final int amountDueInPaise;
  final double amountDueInRupees;
  final int amountCreditInPaise;
  final double amountCreditInRupees;
  final bool isDowngrade;

  const UpgradeQuote({
    required this.memberId,
    this.currentPlanName,
    required this.newPlanId,
    required this.newPlanName,
    required this.remainingDays,
    required this.oldDailyRatePaise,
    required this.newDailyRatePaise,
    required this.amountDueInPaise,
    required this.amountDueInRupees,
    required this.amountCreditInPaise,
    required this.amountCreditInRupees,
    required this.isDowngrade,
  });

  factory UpgradeQuote.fromJson(Map<String, dynamic> j) => UpgradeQuote(
    memberId: j['member_id'] as int,
    currentPlanName: j['current_plan_name'] as String?,
    newPlanId: j['new_plan_id'] as int,
    newPlanName: (j['new_plan_name'] ?? '') as String,
    remainingDays: (j['remaining_days'] ?? 0) as int,
    oldDailyRatePaise: (j['old_daily_rate_paise'] ?? 0) as int,
    newDailyRatePaise: (j['new_daily_rate_paise'] ?? 0) as int,
    amountDueInPaise: (j['amount_due_in_paise'] ?? 0) as int,
    amountDueInRupees: _double(j['amount_due_in_rupees']),
    amountCreditInPaise: (j['amount_credit_in_paise'] ?? 0) as int,
    amountCreditInRupees: _double(j['amount_credit_in_rupees']),
    isDowngrade: (j['is_downgrade'] ?? false) as bool,
  );
}

/// Refund owed if a membership were terminated today.
class TerminationQuote {
  final int memberId;
  final int remainingDays;
  final int dailyRatePaise;
  final int grossRefundInPaise;
  final int terminationFeeInPaise;
  final int netRefundInPaise;
  final double netRefundInRupees;

  const TerminationQuote({
    required this.memberId,
    required this.remainingDays,
    required this.dailyRatePaise,
    required this.grossRefundInPaise,
    required this.terminationFeeInPaise,
    required this.netRefundInPaise,
    required this.netRefundInRupees,
  });

  factory TerminationQuote.fromJson(Map<String, dynamic> j) => TerminationQuote(
    memberId: j['member_id'] as int,
    remainingDays: (j['remaining_days'] ?? 0) as int,
    dailyRatePaise: (j['daily_rate_paise'] ?? 0) as int,
    grossRefundInPaise: (j['gross_refund_in_paise'] ?? 0) as int,
    terminationFeeInPaise: (j['termination_fee_in_paise'] ?? 0) as int,
    netRefundInPaise: (j['net_refund_in_paise'] ?? 0) as int,
    netRefundInRupees: _double(j['net_refund_in_rupees']),
  );
}

DateTime? _date(dynamic v) =>
    (v == null || v is! String || v.isEmpty) ? null : DateTime.tryParse(v);

double _double(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
