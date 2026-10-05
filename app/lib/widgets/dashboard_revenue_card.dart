import 'package:flutter/material.dart';

import '../features/payments/payments_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/app_card.dart';
import '../widgets/dashboard_card_stat.dart';
import '../utils/money.dart';

/// Dashboard revenue card — pure display widget.
/// All data is passed in from DashboardScreen.loadDashboard() so that
/// every module that creates a payment (Renewals, Payments, Lead conversion)
/// triggers a refresh of this card automatically via the onDataChanged chain.
class DashboardRevenueCard extends StatelessWidget {
  final int todayRevenuePaise;
  final int monthRevenuePaise;
  final int pendingPayments;
  final int collectedCount;
  final VoidCallback? onDataChanged;

  const DashboardRevenueCard({
    super.key,
    required this.todayRevenuePaise,
    required this.monthRevenuePaise,
    required this.pendingPayments,
    required this.collectedCount,
    this.onDataChanged,
  });

  Future<void> _openPayments(BuildContext context) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaymentsScreen()),
    );
    if (changed == true) {
      onDataChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => _openPayments(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              const Text(
                'Revenue',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: DashboardCardStat(
                  value: moneyShort(monthRevenuePaise),
                  label: 'This Month',
                  color: AppColors.success,
                  fontSize: 18,
                ),
              ),
              const DashboardCardDivider(),
              Expanded(
                child: DashboardCardStat(
                  value: moneyShort(todayRevenuePaise),
                  label: 'Today',
                  color: AppColors.primary,
                  fontSize: 18,
                ),
              ),
              const DashboardCardDivider(),
              Expanded(
                child: DashboardCardStat(
                  value: '$pendingPayments',
                  label: 'Pending',
                  color: AppColors.warning,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
