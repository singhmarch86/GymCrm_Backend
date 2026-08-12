/// The result of invoicing raised dues from the Expected view (FR-19 §6).
///
/// Reports what it did AND what it declined to do. A batch that quietly drops
/// an already-invoiced due leaves the reader believing it was handled, and
/// they find out at the end of the month.
library;

class InvoicedMember {
  final int invoiceId;
  final int memberId;
  final String member;
  final List<int> paymentIds;
  final int totalInPaise;

  const InvoicedMember({
    required this.invoiceId,
    required this.memberId,
    required this.member,
    required this.paymentIds,
    required this.totalInPaise,
  });

  factory InvoicedMember.fromJson(Map<String, dynamic> j) => InvoicedMember(
        invoiceId: j['invoice_id'] ?? 0,
        memberId: j['member_id'] ?? 0,
        member: j['member'] ?? '',
        paymentIds:
            ((j['payment_ids'] as List?) ?? []).map((e) => e as int).toList(),
        totalInPaise: j['total_in_paise'] ?? 0,
      );
}

class SkippedDue {
  final int paymentId;
  final String reason;

  const SkippedDue({required this.paymentId, required this.reason});

  factory SkippedDue.fromJson(Map<String, dynamic> j) => SkippedDue(
        paymentId: j['payment_id'] ?? 0,
        reason: j['reason'] ?? '',
      );
}

class InvoiceBatch {
  final List<InvoicedMember> created;
  final List<SkippedDue> skipped;
  final int invoiceCount;
  final int totalInPaise;

  const InvoiceBatch({
    required this.created,
    required this.skipped,
    required this.invoiceCount,
    required this.totalInPaise,
  });

  factory InvoiceBatch.fromJson(Map<String, dynamic> j) => InvoiceBatch(
        created: ((j['created'] as List?) ?? [])
            .map((e) => InvoicedMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        skipped: ((j['skipped'] as List?) ?? [])
            .map((e) => SkippedDue.fromJson(e as Map<String, dynamic>))
            .toList(),
        invoiceCount: j['invoice_count'] ?? 0,
        totalInPaise: j['total_in_paise'] ?? 0,
      );
}
