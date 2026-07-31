class PaymentModeBreakdown {
  final String mode;
  final String label;
  final double amountInRupees;
  final int count;

  PaymentModeBreakdown({
    required this.mode,
    required this.label,
    required this.amountInRupees,
    required this.count,
  });

  factory PaymentModeBreakdown.fromJson(Map<String, dynamic> j) =>
      PaymentModeBreakdown(
        mode: j['mode'] ?? '',
        label: j['label'] ?? '',
        amountInRupees: (j['amount_in_rupees'] ?? 0).toDouble(),
        count: j['count'] ?? 0,
      );
}

class PaymentReport {
  final double collectedInRupees;
  final double pendingInRupees;
  final double overdueInRupees;
  final int collectedCount;
  final int pendingCount;
  final List<PaymentModeBreakdown> modeBreakdown;

  PaymentReport({
    required this.collectedInRupees,
    required this.pendingInRupees,
    required this.overdueInRupees,
    required this.collectedCount,
    required this.pendingCount,
    required this.modeBreakdown,
  });

  factory PaymentReport.fromJson(Map<String, dynamic> j) => PaymentReport(
        collectedInRupees: (j['collected_in_rupees'] ?? 0).toDouble(),
        pendingInRupees: (j['pending_in_rupees'] ?? 0).toDouble(),
        overdueInRupees: (j['overdue_in_rupees'] ?? 0).toDouble(),
        collectedCount: j['collected_count'] ?? 0,
        pendingCount: j['pending_count'] ?? 0,
        modeBreakdown: (j['mode_breakdown'] as List? ?? [])
            .map((e) => PaymentModeBreakdown.fromJson(e))
            .toList(),
      );
}
