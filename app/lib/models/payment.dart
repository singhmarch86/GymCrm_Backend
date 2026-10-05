/// Maps backend PaymentResponse (internal/payments/dto.go).
/// All snake_case keys match the Go json tags exactly.
class Payment {
  final int id;
  final int gymId;
  final int memberId;
  final String memberName;
  final String phone;

  final int? planId;
  final String? planName;

  final int amountInPaise;
  final double amountInRupees;

  /// paid | pending | overdue  (overdue is computed server-side)
  final String status;

  /// cash | upi | credit_card | debit_card | bank_transfer
  final String? paymentMode;

  final String? dueDate;
  final String? paidDate;
  final String? referenceNumber;
  final String? notes;
  final String createdAt;

  Payment({
    required this.id,
    required this.gymId,
    required this.memberId,
    required this.memberName,
    required this.phone,
    this.planId,
    this.planName,
    required this.amountInPaise,
    required this.amountInRupees,
    required this.status,
    this.paymentMode,
    this.dueDate,
    this.paidDate,
    this.referenceNumber,
    this.notes,
    required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] ?? 0,
      gymId: json['gym_id'] ?? 0,
      memberId: json['member_id'] ?? 0,
      memberName: json['member_name'] ?? '',
      phone: json['phone'] ?? '',
      planId: json['plan_id'] as int?,
      planName: json['plan_name'],
      amountInPaise: json['amount_in_paise'] ?? 0,
      amountInRupees: (json['amount_in_rupees'] ?? 0).toDouble(),
      status: json['status'] ?? 'paid',
      paymentMode: json['payment_mode'],
      dueDate: json['due_date'],
      paidDate: json['paid_date'],
      referenceNumber: json['reference_number'],
      notes: json['notes'],
      createdAt: json['created_at'] ?? '',
    );
  }

  /// Human-readable payment mode label.
  String get paymentModeLabel {
    switch (paymentMode) {
      case 'upi':
        return 'UPI';
      case 'credit_card':
        return 'Credit Card';
      case 'debit_card':
        return 'Debit Card';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'cash':
        return 'Cash';
      default:
        return paymentMode ?? '—';
    }
  }

  /// Display date — prefer paidDate, fall back to dueDate.
  String get displayDate => paidDate ?? dueDate ?? '—';
}
