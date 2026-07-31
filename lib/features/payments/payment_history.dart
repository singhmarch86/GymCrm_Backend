import 'package:flutter/material.dart';

import '../../models/payment.dart';
import '../../services/payment_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/status_chip.dart';

/// Embeddable payment history widget for a specific member.
/// Used inside MemberDetailScreen (or any future detail view).
///
/// Fetches from GET /api/v1/members/{memberId}/payments.
class PaymentHistory extends StatefulWidget {
  final int memberId;

  const PaymentHistory({super.key, required this.memberId});

  @override
  State<PaymentHistory> createState() => _PaymentHistoryState();
}

class _PaymentHistoryState extends State<PaymentHistory> {
  bool _loading = true;
  List<Payment> _payments = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data =
          await PaymentService().getMemberPayments(widget.memberId);
      if (!mounted) return;
      setState(() {
        _payments = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: AppColors.danger),
        ),
      );
    }

    if (_payments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No payment history'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Payment History',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _payments.length,
          separatorBuilder: (_, __) => Divider(
            color: Colors.grey.shade200,
            height: 1,
          ),
          itemBuilder: (_, i) => _PaymentHistoryTile(payment: _payments[i]),
        ),
      ],
    );
  }
}

class _PaymentHistoryTile extends StatelessWidget {
  final Payment payment;

  const _PaymentHistoryTile({required this.payment});

  String _formatDate(String? raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}-'
          '${_monthAbbr(d.month)}-'
          '${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String _monthAbbr(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${payment.amountInRupees.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(payment.paidDate ?? payment.dueDate),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                if (payment.paymentMode != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    payment.paymentModeLabel,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          StatusChip(status: payment.status),
        ],
      ),
    );
  }
}
