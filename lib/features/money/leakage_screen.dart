import 'package:flutter/material.dart';

import '../../models/leakage.dart';
import '../../services/queue_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/readable_width.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../utils/money.dart';

/// Money leakage (FR-21).
///
/// Every other money screen in the product is about money somebody owes. This
/// one is about money nobody ever asked for — sessions delivered past a
/// package's limit, members still training after their membership ran out.
/// None of it appears in the collections queue, because no debt was ever
/// written down.
///
/// Deliberately read-only. Each row needs a person to decide what it actually
/// was: goodwill somebody approved, a cash payment nobody keyed in, or a real
/// loss. A button that billed the member automatically would turn a finding
/// into an accusation, and the first false positive would cost the gym a
/// member.
class LeakageScreen extends StatefulWidget {
  const LeakageScreen({super.key});

  @override
  State<LeakageScreen> createState() => _LeakageScreenState();
}

class _LeakageScreenState extends State<LeakageScreen> {
  bool _loading = true;
  String? _error;
  LeakageReport? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await QueueService().getLeakage();
      if (!mounted) return;
      setState(() {
        _report = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Money leaks'),
        toolbarHeight: 48,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);

    final report = _report;
    if (report == null) return const LoadingView();

    return RefreshIndicator(
      onRefresh: _load,
      // Capped like every other card list: across a wide monitor a name and
      // its amount end up a hand's width apart, which is the scanning
      // problem tables solve reappearing inside the cards.
      child: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            _Headline(report: report),
            const SizedBox(height: 6),
            for (final g in report.groups) ..._group(g),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These are findings, not accusations. A session past a '
                      'limit may be goodwill somebody approved, and a visit '
                      'after expiry may be a cash renewal nobody entered. '
                      'Nothing here bills anybody — check the row, then decide.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _group(LeakGroup g) {
    // Empty groups are kept. "No sessions given away" is one of the more
    // useful sentences this screen can say, and a heading that vanishes at
    // zero denies the reader that.
    if (g.items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 2),
          child: Row(
            children: [
              const Icon(
                Icons.check_rounded,
                size: 15,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${g.label} — none found',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final colour = g.severity == 'urgent'
        ? AppColors.danger
        : AppColors.warning;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colour,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    g.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: colour,
                    ),
                  ),
                ),
                if (g.valueInPaise > 0)
                  Text(
                    moneyShort(g.valueInPaise),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Text(
                g.note,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      ...g.items.map((i) => _LeakRow(item: i, colour: colour)),
    ];
  }
}

class _Headline extends StatelessWidget {
  final LeakageReport report;

  const _Headline({required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.isClear) {
      return AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(
              Icons.verified_rounded,
              size: 44,
              color: AppColors.success,
            ),
            const SizedBox(height: 10),
            const Text(
              'Nothing leaking',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'No sessions past a package limit, and nobody training on an '
              'expired membership.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text(
            moneyShort(report.valuedInPaise),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${report.totalCount} '
            '${report.totalCount == 1 ? 'finding' : 'findings'}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          // The most important sentence on the screen. An owner who reads this
          // as "we lost exactly this much" will either relax or accuse
          // somebody, and both are wrong.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              'This is the floor, not the total. It counts only what could be '
              'valued honestly and prices everything at what the member '
              'already pays — below what a walk-in would.'
              '${report.unvaluedCount == 0 ? '' : ' ${report.unvaluedCount} '
                        'more ${report.unvaluedCount == 1 ? 'finding carries' : 'findings carry'} '
                        'no figure at all.'}',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeakRow extends StatelessWidget {
  final LeakItem item;
  final Color colour;

  const _LeakRow({required this.item, required this.colour});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.member,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.detail,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (item.valueInPaise > 0)
                  Text(
                    moneyShort(item.valueInPaise),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colour,
                    ),
                  )
                else
                  Text(
                    'no figure',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 3,
              children: [
                if (item.trainer != null)
                  _meta(Icons.person_rounded, item.trainer!),
                if (item.since != null)
                  _meta(Icons.schedule_rounded, 'since ${_date(item.since!)}'),
                if (item.phone.isNotEmpty)
                  _meta(Icons.call_rounded, item.phone),
              ],
            ),
            // How the number was reached, next to the number. A figure nobody
            // can reconstruct is a figure nobody will act on.
            if (item.basis.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Valued at ${item.basis}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: Colors.grey.shade500),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ],
  );
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';
