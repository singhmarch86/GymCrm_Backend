import 'package:flutter/material.dart';

import '../../models/renewal_queue.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

/// Renewals due (FR-19 §4).
///
/// Windowed at 30 days either side. Without the cap the already-lapsed tail
/// runs to 88 people going back months, and a permanently red pile that size
/// is wallpaper by the second week.
///
/// The count outside the window is printed at the bottom rather than dropped.
/// Capped is not the same as hidden, and a queue that quietly loses people is
/// worse than one that admits where its edge is.
class RenewalQueueView extends StatelessWidget {
  final RenewalQueue queue;
  final void Function(RenewalItem) onAct;

  const RenewalQueueView({
    super.key,
    required this.queue,
    required this.onAct,
  });

  @override
  Widget build(BuildContext context) {
    if (queue.isClear) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_rounded,
                  size: 60, color: AppColors.success),
              const SizedBox(height: 16),
              const Text('Nothing expiring',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'No memberships expire in the next ${queue.windowDays} days, '
                'and none lapsed in the last ${queue.windowDays}.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        _Headline(queue: queue),
        const SizedBox(height: 6),
        for (final g in queue.groups) ..._group(g),
        const SizedBox(height: 16),
        _Footnote(queue: queue),
      ],
    );
  }

  List<Widget> _group(RenewalGroup g) {
    if (g.items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 2),
          child: Row(
            children: [
              Icon(Icons.check_rounded, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text('${g.label} — none',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ];
    }

    final colour = _severityColour(g.severity);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: colour, shape: BoxShape.circle),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(g.label,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: colour)),
                ),
                Text('${g.items.length} · ~${_rupees(g.valueInPaise)}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Text(g.note,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Colors.grey.shade600)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      ...g.items.map((i) => _RenewalRow(item: i, colour: colour, onAct: onAct)),
    ];
  }

  static Color _severityColour(String s) {
    switch (s) {
      case 'urgent':
        return AppColors.danger;
      case 'warn':
        return AppColors.warning;
    }
    return AppColors.primary;
  }
}

class _Headline extends StatelessWidget {
  final RenewalQueue queue;

  const _Headline({required this.queue});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              _figure('${queue.totalCount}', 'expiring', null),
              Container(width: 1, height: 30, color: Colors.grey.shade200),
              // "worth" and not "revenue": these are memberships that might be
              // renewed, at today's plan prices. It is an estimate and it says
              // so.
              _figure('~${_rupees(queue.valueInPaise)}', 'if all renew', null),
            ],
          ),
          const SizedBox(height: 8),
          Text('within ${queue.windowDays} days, either side of today',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _figure(String value, String label, Color? colour) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colour ?? AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      );
}

/// Says where the window ends, because a queue that silently truncates is
/// worse than one that admits its own edge.
class _Footnote extends StatelessWidget {
  final RenewalQueue queue;

  const _Footnote({required this.queue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              queue.beyondWindow == 0
                  ? 'Anything that lapsed more than ${queue.windowDays} days '
                      'ago is left out of this list on purpose.'
                  : '${queue.beyondWindow} more lapsed over '
                      '${queue.windowDays} days ago and are not listed here — '
                      'past the point where a renewal call usually works. '
                      'They are still in Members, and in At Risk.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

class _RenewalRow extends StatelessWidget {
  final RenewalItem item;
  final Color colour;
  final void Function(RenewalItem) onAct;

  const _RenewalRow({
    required this.item,
    required this.colour,
    required this.onAct,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(13),
        child: InkWell(
          onTap: () => onAct(item),
          borderRadius: BorderRadius.circular(8),
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
                        Text(item.member,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(_subtitle(),
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_when(),
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: colour)),
                      if (item.planInPaise != null)
                        Text(_rupees(item.planInPaise!),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ],
              ),
              if (_signals().isNotEmpty) ...[
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _signals(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      if (item.planName != null) item.planName!,
      if (item.phone.isNotEmpty) item.phone,
    ];
    return parts.isEmpty ? 'No plan on record' : parts.join(' · ');
  }

  String _when() {
    final d = item.daysUntilExpiry;
    if (d < 0) return '${-d}d ago';
    if (d == 0) return 'today';
    return 'in ${d}d';
  }

  /// The two or three facts that change how the call goes.
  List<Widget> _signals() {
    final out = <Widget>[];

    final since = item.daysSinceVisit;
    if (item.lastVisitAt == null) {
      // Never attended at all is the strongest signal on this screen.
      out.add(_tag('never visited', AppColors.danger));
    } else if (since != null && since >= 14) {
      out.add(_tag('last in ${since}d ago', AppColors.warning));
    }

    if (item.owesMoney) {
      out.add(_tag('owes ${_rupees(item.owedInPaise)}', AppColors.danger));
    }

    if (item.previousRenewals == 0) {
      // A first-timer who does not renew is a different problem from a
      // long-standing member drifting away.
      out.add(_tag('first term', Colors.grey.shade600));
    } else {
      out.add(_tag(
          'renewed ${item.previousRenewals}×', AppColors.success));
    }

    return out;
  }

  static Widget _tag(String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: colour)),
      );
}

String _rupees(int paise) {
  final rupees = paise ~/ 100;
  if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  if (rupees >= 1000) {
    return '₹${(rupees / 1000).toStringAsFixed(rupees >= 10000 ? 0 : 1)}k';
  }
  return '₹$rupees';
}
