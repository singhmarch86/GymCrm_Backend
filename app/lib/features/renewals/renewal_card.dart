import 'package:flutter/material.dart';

import '../../models/renewal_due.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_chip.dart';

class RenewalCard extends StatelessWidget {
  final RenewalDue renewal;
  final VoidCallback? onRenew;
  final VoidCallback? onTap;

  /// Raises a GST invoice for the renewal. Only offered when the member is on
  /// a plan — an invoice line has to be for something.
  final VoidCallback? onInvoice;

  const RenewalCard({
    super.key,
    required this.renewal,
    this.onRenew,
    this.onTap,
    this.onInvoice,
  });

  /// Canonical application-wide status color mapping — must stay identical
  /// to StatusChip's internal mapping (lib/widgets/status_chip.dart) so the
  /// badge and this card's other urgency indicators (expiry-row icon/text)
  /// never disagree on color for the same status.
  Color get urgencyColor {
    switch (renewal.status) {
      case 'EXPIRED':
        return AppColors.danger;
      case 'DUE_TODAY':
      case 'EXPIRING_SOON':
        return AppColors.warning;
      case 'UPCOMING':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String get statusLabel {
    switch (renewal.status) {
      case 'EXPIRED':
        return 'Expired';
      case 'DUE_TODAY':
        return 'Due Today';
      case 'EXPIRING_SOON':
        return 'Expiring Soon';
      case 'UPCOMING':
        return 'Upcoming';
      default:
        return 'Active';
    }
  }

  /// Expired and far-future (>30 days) members get a "Reminder" action
  /// instead of "Renew" — matches the PRD mock (Aman Gill → [Reminder]).
  bool get showRenewButton =>
      renewal.status == 'DUE_TODAY' ||
      renewal.status == 'EXPIRING_SOON' ||
      renewal.status == 'EXPIRED' ||
      renewal.status == 'UPCOMING';

  @override
  Widget build(BuildContext context) {
    final initial = renewal.memberName.isNotEmpty
        ? renewal.memberName[0].toUpperCase()
        : "?";

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
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
                      renewal.memberName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      renewal.phone,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              StatusChip(status: renewal.status, label: statusLabel),
            ],
          ),

          const SizedBox(height: 14),

          Divider(color: Colors.grey.shade200),

          const SizedBox(height: 10),

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
                  renewal.planName ?? "No Plan Assigned",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 17, color: urgencyColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  renewal.expiryText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: urgencyColor,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),

          if (onInvoice != null && renewal.planId != null) ...[
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

          if (showRenewButton && onRenew != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRenew,
                icon: const Icon(Icons.autorenew_rounded, size: 18),
                label: const Text("Renew"),
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
}
