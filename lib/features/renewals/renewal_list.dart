import 'package:flutter/material.dart';

import '../../models/renewal_due.dart';
import '../../theme/app_text_styles.dart';

import '../invoices/quick_invoice.dart';
import 'empty_renewals.dart';
import 'renewal_card.dart';

/// A flat row in the list — either a section header or a renewal card.
class _ListItem {
  final String? header;
  final RenewalDue? renewal;

  _ListItem.header(this.header) : renewal = null;
  _ListItem.renewal(this.renewal) : header = null;
}

class RenewalList extends StatelessWidget {
  final bool isLoading;
  final List<RenewalDue> renewals;
  final Future<void> Function() onRefresh;
  final void Function(RenewalDue) onRenew;

  const RenewalList({
    super.key,
    required this.isLoading,
    required this.renewals,
    required this.onRefresh,
    required this.onRenew,
  });

  /// Groups renewals into PRD-matching sections: Today, Tomorrow, Next 7 Days,
  /// Upcoming, Expired. Order matches the mock — most urgent first.
  List<_ListItem> _buildGroupedItems() {
    final today = <RenewalDue>[];
    final tomorrow = <RenewalDue>[];
    final next7 = <RenewalDue>[];
    final upcoming = <RenewalDue>[];
    final expired = <RenewalDue>[];

    for (final r in renewals) {
      switch (r.status) {
        case 'EXPIRED':
          expired.add(r);
          break;
        case 'DUE_TODAY':
          today.add(r);
          break;
        case 'EXPIRING_SOON':
          if (r.daysRemaining == 1) {
            tomorrow.add(r);
          } else {
            next7.add(r);
          }
          break;
        default:
          upcoming.add(r);
      }
    }

    final items = <_ListItem>[];

    void addSection(String title, List<RenewalDue> list) {
      if (list.isEmpty) return;
      items.add(_ListItem.header(title));
      for (final r in list) {
        items.add(_ListItem.renewal(r));
      }
    }

    addSection("Today", today);
    addSection("Tomorrow", tomorrow);
    addSection("Next 7 Days", next7);
    addSection("Upcoming", upcoming);
    addSection("Expired", expired);

    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (renewals.isEmpty) {
      return const EmptyRenewals();
    }

    final items = _buildGroupedItems();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(
          top: 8,
          bottom: 100,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          if (item.header != null) {
            return Padding(
              padding: EdgeInsets.only(
                top: index == 0 ? 4 : 20,
                bottom: 10,
              ),
              child: Text(
                item.header!,
                style: AppTextStyles.sectionTitle,
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: RenewalCard(
              renewal: item.renewal!,
              onRenew: () => onRenew(item.renewal!),
              onInvoice: item.renewal!.planId == null
                  ? null
                  : () => QuickInvoice.createForPlan(
                        context,
                        memberId: item.renewal!.id,
                        planId: item.renewal!.planId!,
                      ),
            ),
          );
        },
      ),
    );
  }
}
