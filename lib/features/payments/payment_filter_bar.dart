import 'package:flutter/material.dart';

enum PaymentFilterOption { all, paid, pending, overdue, today, thisMonth }

extension PaymentFilterApi on PaymentFilterOption {
  String get apiValue {
    switch (this) {
      case PaymentFilterOption.all:
        return '';
      case PaymentFilterOption.paid:
        return 'paid';
      case PaymentFilterOption.pending:
        return 'pending';
      case PaymentFilterOption.overdue:
        return 'overdue';
      case PaymentFilterOption.today:
        return 'paid'; // Today filter uses date_from/date_to, not status
      case PaymentFilterOption.thisMonth:
        return 'paid';
    }
  }

  String get label {
    switch (this) {
      case PaymentFilterOption.all:
        return 'All';
      case PaymentFilterOption.paid:
        return 'Paid';
      case PaymentFilterOption.pending:
        return 'Pending';
      case PaymentFilterOption.overdue:
        return 'Overdue';
      case PaymentFilterOption.today:
        return 'Today';
      case PaymentFilterOption.thisMonth:
        return 'This Month';
    }
  }
}

class PaymentFilterBar extends StatelessWidget {
  final PaymentFilterOption selected;
  final ValueChanged<PaymentFilterOption> onChanged;

  const PaymentFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: PaymentFilterOption.values.map((filter) {
          final isSelected = selected == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: isSelected,
              onSelected: (_) => onChanged(filter),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              selectedColor: Colors.blue.shade600,
              backgroundColor: Colors.grey.shade100,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
