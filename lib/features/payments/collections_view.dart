import 'package:flutter/material.dart';

import '../../models/collection_queue.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

/// The collections worklist (FR-19 §3).
///
/// The Payments tab next door is the ledger — everything, searchable. This is
/// what is owed and what to do about it.
///
/// Grouped by member, never by collector. Nothing on this screen totals money
/// against a staff member's name, because a collections list that does is one
/// design decision away from a sales leaderboard.
class CollectionsView extends StatelessWidget {
  final CollectionQueue queue;
  final void Function(CollectionItem) onAct;

  const CollectionsView({
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
              const Text('Nothing outstanding',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Every due has been collected or settled.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recording a call moves a due out of the first group whether '
                  'or not anybody answered — somebody tried, and the next '
                  'person should not repeat it. Nothing here sends a message; '
                  'it records that you made contact.',
                  style: TextStyle(
                      fontSize: 11, height: 1.4, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _group(CollectionGroup g) {
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
                Text('${g.items.length} · ${_rupees(g.totalInPaise)}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
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
      ...g.items.map((i) => _DueRow(item: i, colour: colour, onAct: onAct)),
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
  final CollectionQueue queue;

  const _Headline({required this.queue});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              _figure(_rupees(queue.totalInPaise), 'outstanding', null),
              Container(width: 1, height: 30, color: Colors.grey.shade200),
              _figure('${queue.unchasedCount}', 'nobody on them',
                  queue.unchasedCount > 0 ? AppColors.danger : null),
              Container(width: 1, height: 30, color: Colors.grey.shade200),
              _figure('${queue.membersInvolved}', 'members', null),
            ],
          ),
          const SizedBox(height: 8),
          Text('${queue.totalCount} dues in total',
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
                    fontSize: 18,
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

class _DueRow extends StatelessWidget {
  final CollectionItem item;
  final Color colour;
  final void Function(CollectionItem) onAct;

  const _DueRow({
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(item.member,
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (item.memberInactive) ...[
                              const SizedBox(width: 6),
                              // Said before the call, not discovered during it.
                              _tag('lapsed', AppColors.danger),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(_due(),
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_rupees(item.amountInPaise),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: colour)),
                      // Chasing ₹1,500 when the same person owes ₹9,000
                      // wastes the call.
                      if (item.owesMore)
                        Text('of ${_rupees(item.memberTotalInPaise)}',
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.grey.shade500)),
                    ],
                  ),
                ],
              ),
              if (_lastLine() != null) ...[
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(_lastLine()!,
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _due() {
    final parts = <String>[];
    final d = item.daysOverdue;
    if (d == null) {
      parts.add('no due date');
    } else if (d > 0) {
      parts.add('$d ${d == 1 ? 'day' : 'days'} overdue');
    } else if (d == 0) {
      parts.add('due today');
    } else {
      parts.add('due in ${-d} ${d == -1 ? 'day' : 'days'}');
    }
    if (item.phone.isNotEmpty) parts.add(item.phone);
    return parts.join(' · ');
  }

  String? _lastLine() {
    if (item.promisedOn != null) {
      return 'Promised ${_date(item.promisedOn!)}'
          '${item.lastContactBy == null ? '' : ' · told ${item.lastContactBy}'}';
    }
    if (item.lastContactAt == null) return null;

    final bits = <String>[
      // Reached and not reached are never merged: a call that rang out is work
      // done but it is not contact.
      item.lastReached == true ? 'Spoke to them' : 'No answer',
      _date(item.lastContactAt!),
      if (item.lastContactBy != null) '· ${item.lastContactBy}',
    ];
    final line = bits.join(' ');
    return item.lastContactNote == null || item.lastContactNote!.isEmpty
        ? line
        : '$line — ${item.lastContactNote}';
  }

  static Widget _tag(String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: colour)),
      );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';
}

String _rupees(int paise) {
  final rupees = paise ~/ 100;
  if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  if (rupees >= 1000) {
    return '₹${(rupees / 1000).toStringAsFixed(rupees >= 10000 ? 0 : 1)}k';
  }
  return '₹$rupees';
}
