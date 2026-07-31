import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/payment.dart';

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

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: payments.length,
        itemBuilder: (context, index) {
          final payment = payments[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: PaymentCard(
              payment: payment,
              onCollect: () => _collect(context, payment),
            ),
          );
        },
      ),
    );
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
