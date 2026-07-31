import 'package:flutter/material.dart';

import '../../models/payment.dart';

import 'payment_filter_bar.dart';
import 'payment_list.dart';
import 'payment_search_bar.dart';

/// Stateless — filter and search state lives in PaymentsScreen.
/// This widget only renders what it's given and reports user input upward.
class PaymentsBody extends StatelessWidget {
  final List<Payment> payments;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final VoidCallback? onPaymentCollected;
  final PaymentFilterOption selectedFilter;
  final TextEditingController searchController;
  final void Function({
    required PaymentFilterOption filter,
    required String search,
  }) onQueryChanged;

  const PaymentsBody({
    super.key,
    required this.payments,
    required this.isLoading,
    required this.onRefresh,
    required this.onQueryChanged,
    required this.selectedFilter,
    required this.searchController,
    this.onPaymentCollected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PaymentSearchBar(
          controller: searchController,
          onChanged: (_) => onQueryChanged(
            filter: selectedFilter,
            search: searchController.text.trim(),
          ),
        ),
        const SizedBox(height: 18),
        PaymentFilterBar(
          selected: selectedFilter,
          onChanged: (f) => onQueryChanged(
            filter: f,
            search: searchController.text.trim(),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: PaymentList(
            payments: payments,
            isLoading: isLoading,
            onRefresh: onRefresh,
            onPaymentCollected: onPaymentCollected,
          ),
        ),
      ],
    );
  }
}
