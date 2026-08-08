import 'package:flutter/material.dart';

import '../../models/payment.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_chip.dart';

class PaymentCard extends StatelessWidget {
  final Payment payment;
  final VoidCallback? onCollect;
  final VoidCallback? onTap;
  /// Raises a GST invoice for this payment. Money and documents are separate
  /// records (FR-04 §0.1), so a payment can exist without an invoice — this is
  /// how staff produce one after the fact.
  final VoidCallback? onInvoice;

  const PaymentCard({
    super.key,
    required this.payment,
    this.onCollect,
    this.onTap,
    this.onInvoice,
  });

  /// Canonical color for the amount / date emphasis row — mirrors StatusChip.
  Color get _statusColor {
    switch (payment.status) {
      case 'paid':
        return AppColors.success;
      case 'overdue':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  bool get _showCollectButton =>
      payment.status == 'pending' || payment.status == 'overdue';

  @override
  Widget build(BuildContext context) {
    final initial = payment.memberName.isNotEmpty
        ? payment.memberName[0].toUpperCase()
        : '?';

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header row: avatar + name/phone + status badge ──────────────
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.memberName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      payment.phone,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // StatusChip is the single source of truth for status colors —
              // no inline badge logic here per the application design system.
              StatusChip(status: payment.status),
            ],
          ),

          const SizedBox(height: 14),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 10),

          // ── Plan row ────────────────────────────────────────────────────
          if (payment.planName != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 17,
                  color: Colors.deepPurple,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    payment.planName!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // ── Amount + payment mode ────────────────────────────────────────
          Row(
            children: [
              Icon(
                Icons.currency_rupee_rounded,
                size: 17,
                color: _statusColor,
              ),
              const SizedBox(width: 8),
              Text(
                '₹${payment.amountInRupees.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _statusColor,
                ),
              ),
              if (payment.paymentMode != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    payment.paymentModeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // ── Date row ─────────────────────────────────────────────────────
          Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 15,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 8),
              Text(
                _dateLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),

          if (onInvoice != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onInvoice,
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('Invoice'),
              ),
            ),
          ],

          // ── Collect Payment button ───────────────────────────────────────
          if (_showCollectButton && onCollect != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCollect,
                icon: const Icon(
                  Icons.payment_rounded,
                  size: 18,
                ),
                label: const Text('Collect Payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _dateLabel {
    if (payment.paidDate != null) {
      return 'Paid: ${_formatDate(payment.paidDate!)}';
    }
    if (payment.dueDate != null) {
      return 'Due: ${_formatDate(payment.dueDate!)}';
    }
    return '—';
  }

  String _formatDate(String raw) {
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
    } catch (_) {
      return raw;
    }
  }
}
