import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/payment.dart';

import '../../theme/app_colors.dart';
import '../../widgets/ledger_table.dart';
import '../invoices/quick_invoice.dart';
import 'collect_payment_dialog.dart';
import 'empty_payments.dart';
import 'payment_card.dart';

class PaymentList extends StatelessWidget {
  final bool isLoading;
  final List<Payment> payments;
  final Future<void> Function() onRefresh;

  /// Called after a payment is successfully collected so the parent screen
  /// can mark itself as having changed data (dashboard auto-refresh contract).
  final VoidCallback? onPaymentCollected;

  const PaymentList({
    super.key,
    required this.isLoading,
    required this.payments,
    required this.onRefresh,
    this.onPaymentCollected,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (payments.isEmpty) {
      return const EmptyPayments();
    }

    // A ledger: rows exist to be scanned and compared, so above the
    // breakpoint the money lines up in a column. Below it the cards stay,
    // because a table on a phone means sideways scrolling or unreadable text.
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LedgerTable<Payment>(
        rows: payments,
        columns: const [
          LedgerColumn('Member', flex: 4),
          LedgerColumn('For', flex: 4),
          LedgerColumn('Status', flex: 2),
          LedgerColumn('Date', flex: 3),
          LedgerColumn('Amount', flex: 3, numeric: true),
        ],
        cells: (p) => [
          LedgerCell(p.memberName, bold: true),
          LedgerCell(p.planName ?? 'Membership fee',
              colour: Colors.grey.shade700),
          LedgerTag(p.status, _statusColour(p.status)),
          LedgerCell(p.paidDate ?? p.dueDate ?? '—',
              colour: Colors.grey.shade700),
          // Right-aligned so digits line up by place value and a bigger
          // number is visibly bigger — the whole reason this is a table.
          LedgerCell('₹${p.amountInRupees.toStringAsFixed(0)}',
              bold: true,
              colour: p.status == 'paid'
                  ? AppColors.textPrimary
                  : AppColors.danger),
        ],
        card: (payment) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PaymentCard(
            payment: payment,
            onCollect: () => _collect(context, payment),
            onInvoice: () => QuickInvoice.createAndOpen(
              context,
              memberId: payment.memberId,
              description: payment.planName ?? 'Membership fee',
              amountInPaise: payment.amountInPaise,
              itemType: payment.planId != null ? 'plan' : 'custom',
              referenceId: payment.planId,
            ),
          ),
        ),
        // Tapping a row does what the card's main action does: an unpaid one
        // opens collection, a paid one has nothing left to do.
        onTap: (p) {
          if (p.status != 'paid') _collect(context, p);
        },
      ),
    );
  }

  static Color _statusColour(String status) {
    switch (status) {
      case 'paid':
        return AppColors.success;
      case 'overdue':
        return AppColors.danger;
      case 'written_off':
        return Colors.grey;
    }
    return AppColors.warning;
  }

  Future<void> _collect(BuildContext context, Payment payment) async {
    // Build a minimal Member from the Payment's denormalised fields so
    // CollectPaymentDialog has the name/plan info it needs without requiring
    // PaymentsScreen to maintain a separate member list.
    final nameParts = payment.memberName.trim().split(' ');
    final member = Member(
      id: payment.memberId,
      firstName: nameParts.isNotEmpty ? nameParts.first : payment.memberName,
      lastName: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
      phone: payment.phone,
      status: payment.status,
      membershipPlanId: payment.planId,
      membershipPlanName: payment.planName,
    );

    if (!context.mounted) return;

    final result = await showCollectPaymentDialog(
      context,
      member: member,
    );

    if (result == true) {
      onPaymentCollected?.call();
      await onRefresh();
    }
  }
}
