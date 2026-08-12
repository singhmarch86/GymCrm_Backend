import 'package:flutter/material.dart';

import '../../models/expected_payments.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

/// Expected payments (FR-19 §5).
///
/// The counterpart of Money & work: that tab is what came in, this is what has
/// reason to come in. It is the only queue with a date control above it,
/// because it is the only one asking about a window rather than about now.
///
/// The two figures are never added. Raised money is a decision the gym already
/// made; expiring money is a plan price nobody has agreed to pay. On live data
/// the second is thirteen times the first, so one blended total would be a
/// forecast with a ledger's face on it.
class ExpectedView extends StatelessWidget {
  final ExpectedPayments data;

  /// Opens a member. Null on screens with nowhere to go.
  final void Function(int memberId)? onOpenMember;

  const ExpectedView({super.key, required this.data, this.onOpenMember});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(40),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.event_available_rounded,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('Nothing due in this window',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'No dues fall here and no memberships expire here. Try a wider '
            'range — most of what a gym expects sits a month or two out.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        _Headline(data: data),
        const SizedBox(height: 12),
        if (data.buckets.length > 1) ...[
          _Shape(data: data),
          const SizedBox(height: 14),
        ],
        _Caveat(data: data),
        const SizedBox(height: 6),
        ...data.items.map((i) => _Row(item: i, onOpen: onOpenMember)),
        if (data.truncated) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Showing the first ${data.items.length}, soonest first. The '
              'totals above cover the whole window — they are not the sum of '
              'this list.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: Colors.grey.shade600),
            ),
          ),
        ],
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  final ExpectedPayments data;

  const _Headline({required this.data});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _side(
              amount: data.raisedInPaise,
              colour: AppColors.primary,
              title: 'Already raised',
              detail: data.raisedCount == 1
                  ? '1 due written down'
                  : '${data.raisedCount} dues written down',
            ),
          ),
          Container(width: 1, height: 54, color: Colors.grey.shade200),
          Expanded(
            child: _side(
              amount: data.expiringInPaise,
              colour: Colors.grey.shade700,
              title: 'If they renew',
              detail: data.expiringCount == 1
                  ? '1 membership expires'
                  : '${data.expiringCount} memberships expire',
            ),
          ),
        ],
      ),
    );
  }

  Widget _side({
    required int amount,
    required Color colour,
    required String title,
    required String detail,
  }) =>
      Column(
        children: [
          Text(_rupees(amount),
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.bold, color: colour)),
          const SizedBox(height: 3),
          Text(title,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 1),
          Text(detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
        ],
      );
}

/// Side-by-side bars, never stacked.
///
/// Stacking would draw the two kinds as one quantity, which is the exact claim
/// the rest of this screen refuses to make.
class _Shape extends StatelessWidget {
  final ExpectedPayments data;

  const _Shape({required this.data});

  @override
  Widget build(BuildContext context) {
    final peak = data.peakInPaise;
    if (peak == 0) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                data.bucketUnit == 'month' ? 'By month' : 'Day by day',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _key(AppColors.primary, 'raised'),
              const SizedBox(width: 10),
              _key(Colors.grey.shade400, 'if they renew'),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 74,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in data.buckets)
                    _Column(bucket: b, peak: peak, unit: data.bucketUnit),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _key(Color c, String label) => Row(
        children: [
          Container(width: 8, height: 8, color: c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      );
}

class _Column extends StatelessWidget {
  final ExpectedBucket bucket;
  final int peak;
  final String unit;

  const _Column({required this.bucket, required this.peak, required this.unit});

  static const _maxBar = 50.0;

  @override
  Widget build(BuildContext context) {
    final raised = bucket.raisedInPaise / peak * _maxBar;
    final expiring = bucket.expiringInPaise / peak * _maxBar;

    // Every bucket gets a label when the columns are months; days get one
    // every fifth, or the axis turns into a smear.
    final labelled = unit == 'month' ||
        bucket.key.endsWith('1') ||
        bucket.key.endsWith('5') ||
        bucket.key.endsWith('0');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: unit == 'month' ? 8 : 3),
      child: Tooltip(
        message: '${bucket.label}\n'
            'raised ${_rupees(bucket.raisedInPaise)} · '
            'if they renew ${_rupees(bucket.expiringInPaise)}',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _bar(raised, AppColors.primary),
                const SizedBox(width: 2),
                _bar(expiring, Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 12,
              // "Aug 2026" -> "Aug", "3 Sep" -> "3". Either way the first
              // word is the part that identifies the column; the rest is
              // context the heading above already gives.
              child: labelled
                  ? Text(
                      bucket.label.split(' ').first,
                      style: TextStyle(
                          fontSize: 9, color: Colors.grey.shade500),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // A zero keeps a visible hairline rather than vanishing: an empty day is a
  // fact about the span, and a gap reads as missing data.
  Widget _bar(double h, Color c) => Container(
        width: 6,
        height: h < 1 ? 1 : h,
        color: h < 1 ? Colors.grey.shade300 : c,
      );
}

class _Caveat extends StatelessWidget {
  final ExpectedPayments data;

  const _Caveat({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '"If they renew" is the ceiling, not a forecast: it assumes every '
              'expiring member renews on the same plan at today\'s price. '
              'Nobody has agreed to any of it. Only the raised figure is money '
              'the gym has actually written down.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final ExpectedItem item;
  final void Function(int memberId)? onOpen;

  const _Row({required this.item, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colour = item.isRaised ? AppColors.primary : Colors.grey.shade700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onOpen == null ? null : () => onOpen!(item.memberId),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(item.member,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          _tag(
                            item.isRaised ? 'raised' : 'expiring',
                            item.isRaised
                                ? AppColors.primary
                                : Colors.grey.shade600,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(_subtitle(),
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade600)),
                      // Said before the call, not discovered during it.
                      if (!item.isRaised && item.owedInPaise > 0) ...[
                        const SizedBox(height: 3),
                        Text('Already owes ${_rupees(item.owedInPaise)}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.danger)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_rupees(item.amountInPaise),
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: colour)),
                    if (item.estimated)
                      Text('plan price',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (item.date != null) {
      parts.add(item.isRaised
          ? 'due ${_date(item.date!)}'
          : 'expires ${_date(item.date!)}');
    }
    if (item.planName != null && item.planName!.isNotEmpty) {
      parts.add(item.planName!);
    }
    if (item.phone.isNotEmpty) parts.add(item.phone);
    return parts.join(' · ');
  }

  static Widget _tag(String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w700, color: colour)),
      );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _rupees(int paise) {
  final rupees = paise ~/ 100;
  if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  if (rupees >= 1000) {
    return '₹${(rupees / 1000).toStringAsFixed(rupees >= 10000 ? 0 : 1)}k';
  }
  return '₹$rupees';
}
