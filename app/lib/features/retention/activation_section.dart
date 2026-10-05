import 'package:flutter/material.dart';

import '../../models/activation.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import 'collapsible_group.dart';

/// New members who haven't got started, shown at the top of the At Risk list
/// (FR-10).
///
/// Kept separate from the other sections because the conversation is
/// different. Every alert below this one is about a member drifting away from
/// a routine. These members have no routine yet — the call isn't "we miss
/// you", it's "let's get you started".
class ActivationSection extends StatelessWidget {
  final List<ActivationAlert> alerts;
  final void Function(ActivationAlert) onResolve;
  final void Function(ActivationAlert) onCopy;

  const ActivationSection({
    super.key,
    required this.alerts,
    required this.onResolve,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    // Grouped by problem, because each group is a different phone call and
    // working them in batches is faster than switching scripts every row.
    final never = alerts
        .where((a) => a.alertType == 'activation_no_first_visit')
        .toList();
    final quiet = alerts
        .where((a) => a.alertType == 'activation_going_quiet')
        .toList();
    final slow = alerts
        .where((a) => a.alertType == 'activation_slow_start')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
          child: Row(
            children: [
              const Icon(Icons.flag_rounded, size: 16, color: AppColors.danger),
              const SizedBox(width: 8),
              const Text(
                'First 90 days',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${alerts.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 10, right: 8),
          child: Text(
            'More members are lost here than anywhere else — usually not because '
            'they were unhappy, but because they never really started.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        _group('Paid, never walked in', never, AppColors.danger),
        _group('Started, then stopped', quiet, AppColors.warning),
        _group('Coming too rarely to stick', slow, AppColors.info),
      ],
    );
  }

  Widget _group(String title, List<ActivationAlert> items, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 4, 6),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${items.length}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        CollapsibleGroup(
          noun: 'more to call',
          children: items
              .map(
                (a) => _ActivationCard(
                  item: a,
                  color: color,
                  onResolve: () => onResolve(a),
                  onCopy: () => onCopy(a),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ActivationCard extends StatelessWidget {
  final ActivationAlert item;
  final Color color;
  final VoidCallback onResolve;
  final VoidCallback onCopy;

  const _ActivationCard({
    required this.item,
    required this.color,
    required this.onResolve,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    item.alertType == 'activation_no_first_visit'
                        ? Icons.door_front_door_outlined
                        : Icons.trending_down_rounded,
                    size: 17,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.memberName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.phone ?? 'no phone'} · joined ${item.daysSinceJoin} days ago',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy the details',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: AppColors.primary,
                  onPressed: onCopy,
                ),
                IconButton(
                  tooltip: 'Mark as handled',
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                  ),
                  color: AppColors.success,
                  onPressed: onResolve,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _fact('${item.visits}', 'visits'),
                _factDivider(),
                _fact(item.visitsPerWeek.toStringAsFixed(1), 'per week'),
                _factDivider(),
                _fact(
                  item.lastVisit == null
                      ? '—'
                      : '${DateTime.now().difference(item.lastVisit!).inDays}d',
                  'since last',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                item.message,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            if (item.callToAction.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.phone_in_talk_rounded, size: 14, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.callToAction,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fact(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    ),
  );

  Widget _factDivider() =>
      Container(width: 1, height: 24, color: Colors.grey.shade200);
}
