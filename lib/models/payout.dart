/// Trainer payouts (FR-21 §2) — money the gym owes the people who work in it.
///
/// The mirror of collections. Three schemes run at once and any trainer may be
/// on any combination: a fixed salary, a percentage of PT the gym has actually
/// been paid for, and a rate per session delivered.
library;

class PayoutLine {
  final int id;

  /// salary | commission | session | adjustment
  final String kind;
  final int? referenceId;
  final String description;
  final int amountInPaise;

  const PayoutLine({
    this.id = 0,
    required this.kind,
    this.referenceId,
    required this.description,
    required this.amountInPaise,
  });

  factory PayoutLine.fromJson(Map<String, dynamic> j) => PayoutLine(
        id: j['id'] ?? 0,
        kind: j['kind'] ?? '',
        referenceId: j['reference_id'],
        description: j['description'] ?? '',
        amountInPaise: j['amount_in_paise'] ?? 0,
      );
}

class Payout {
  final int id;
  final int trainerId;
  final String trainer;

  final DateTime periodStart;
  final DateTime periodEnd;

  /// Kept apart, never merged. A trainer asking "why is this less than last
  /// month" needs to see which part moved.
  final int salaryInPaise;
  final int commissionInPaise;
  final int sessionsInPaise;

  /// Signed — an advance being recovered is negative.
  final int adjustmentInPaise;
  final String? adjustmentReason;

  final int totalInPaise;

  /// draft | paid | cancelled
  final String status;

  final String? notes;
  final DateTime? paidAt;
  final String? paidBy;
  final String? paymentMode;
  final String? referenceNumber;

  final List<PayoutLine> lines;

  const Payout({
    required this.id,
    required this.trainerId,
    required this.trainer,
    required this.periodStart,
    required this.periodEnd,
    required this.salaryInPaise,
    required this.commissionInPaise,
    required this.sessionsInPaise,
    required this.adjustmentInPaise,
    this.adjustmentReason,
    required this.totalInPaise,
    required this.status,
    this.notes,
    this.paidAt,
    this.paidBy,
    this.paymentMode,
    this.referenceNumber,
    this.lines = const [],
  });

  bool get isDraft => status == 'draft';
  bool get isPaid => status == 'paid';

  factory Payout.fromJson(Map<String, dynamic> j) => Payout(
        id: j['id'] ?? 0,
        trainerId: j['trainer_id'] ?? 0,
        trainer: j['trainer'] ?? '',
        periodStart: _date(j['period_start']) ?? DateTime.now(),
        periodEnd: _date(j['period_end']) ?? DateTime.now(),
        salaryInPaise: j['salary_in_paise'] ?? 0,
        commissionInPaise: j['commission_in_paise'] ?? 0,
        sessionsInPaise: j['sessions_in_paise'] ?? 0,
        adjustmentInPaise: j['adjustment_in_paise'] ?? 0,
        adjustmentReason: j['adjustment_reason'],
        totalInPaise: j['total_in_paise'] ?? 0,
        status: j['status'] ?? 'draft',
        notes: j['notes'],
        paidAt: _date(j['paid_at']),
        paidBy: j['paid_by'],
        paymentMode: j['payment_mode'],
        referenceNumber: j['reference_number'],
        lines: ((j['lines'] as List?) ?? [])
            .map((e) => PayoutLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static DateTime? _date(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
}

/// What a payout WOULD be, computed without writing anything.
class PayoutPreview {
  final int trainerId;
  final String trainer;
  final String periodStart;
  final String periodEnd;

  final int salaryInPaise;
  final int commissionInPaise;
  final int sessionsInPaise;
  final int totalInPaise;

  final List<PayoutLine> lines;

  final bool alreadyPaid;

  /// PT sold but not collected. Deliberately NOT in the total — it is why a
  /// figure looks low, and the trainer who sold it will ask.
  final int uncollectedInPaise;
  final int uncollectedCount;

  const PayoutPreview({
    required this.trainerId,
    required this.trainer,
    required this.periodStart,
    required this.periodEnd,
    required this.salaryInPaise,
    required this.commissionInPaise,
    required this.sessionsInPaise,
    required this.totalInPaise,
    required this.lines,
    required this.alreadyPaid,
    required this.uncollectedInPaise,
    required this.uncollectedCount,
  });

  bool get isEmpty => totalInPaise == 0;

  factory PayoutPreview.fromJson(Map<String, dynamic> j) => PayoutPreview(
        trainerId: j['trainer_id'] ?? 0,
        trainer: j['trainer'] ?? '',
        periodStart: j['period_start'] ?? '',
        periodEnd: j['period_end'] ?? '',
        salaryInPaise: j['salary_in_paise'] ?? 0,
        commissionInPaise: j['commission_in_paise'] ?? 0,
        sessionsInPaise: j['sessions_in_paise'] ?? 0,
        totalInPaise: j['total_in_paise'] ?? 0,
        lines: ((j['lines'] as List?) ?? [])
            .map((e) => PayoutLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        alreadyPaid: j['already_paid'] ?? false,
        uncollectedInPaise: j['uncollected_in_paise'] ?? 0,
        uncollectedCount: j['uncollected_count'] ?? 0,
      );
}
