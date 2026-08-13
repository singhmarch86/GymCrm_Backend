import 'package:flutter/material.dart';

import '../../models/rhythm.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import 'collapsible_group.dart';

/// Rhythm breaks, shown at the top of the At Risk list (FR-09).
///
/// This section is deliberately separated from the count-based alerts below it.
/// Those say "this member has stopped coming"; this one says "this member is
/// still coming just as often, and that is exactly why nobody else would have
/// spotted them". Mixing the two would bury the only signal on the screen that
/// is early rather than late.
class RhythmBreakSection extends StatelessWidget {
  final List<RhythmBreak> breaks;
  final void Function(RhythmBreak) onResolve;
  final void Function(RhythmBreak) onCopy;

  const RhythmBreakSection({
    super.key,
    required this.breaks,
    required this.onResolve,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    if (breaks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Routine has broken',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${breaks.length}',
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
            'Still coming as often as before, but no longer at their usual time. '
            'The habit goes first; the attendance follows.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        CollapsibleGroup(
          noun: 'more with a broken routine',
          children: breaks
              .map(
                (b) => _RhythmBreakCard(
                  item: b,
                  onResolve: () => onResolve(b),
                  onCopy: () => onCopy(b),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _RhythmBreakCard extends StatelessWidget {
  final RhythmBreak item;
  final VoidCallback onResolve;
  final VoidCallback onCopy;

  const _RhythmBreakCard({
    required this.item,
    required this.onResolve,
    required this.onCopy,
  });

  Color get _severityColor => switch (item.severity) {
    'high' => AppColors.danger,
    'medium' => AppColors.warning,
    _ => AppColors.info,
  };

  @override
  Widget build(BuildContext context) {
    final s = item.stats;

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
                  backgroundColor: _severityColor.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.schedule_rounded,
                    size: 17,
                    color: _severityColor,
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
                        '${item.phone ?? 'no phone'} · used to train at ${s.usualTime}',
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
            const SizedBox(height: 12),

            // The two bars are the whole argument: the slot collapsed, the
            // visits did not. Showing both together is what makes the flag
            // believable without a phone call to check.
            _ConsistencyBar(
              label: 'Kept their ${s.usualTime} slot',
              before: s.baselineConsistency,
              after: s.recentConsistency,
              beforeLabel: '${s.baselineOnSlot}/${s.baselineVisits}',
              afterLabel: '${s.recentOnSlot}/${s.recentVisits}',
              color: _severityColor,
            ),
            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: s.attendanceHolding
                    ? AppColors.warning.withValues(alpha: 0.08)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: s.attendanceHolding
                      ? AppColors.warning.withValues(alpha: 0.3)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    s.attendanceHolding
                        ? Icons.trending_flat_rounded
                        : Icons.trending_down_rounded,
                    size: 16,
                    color: s.attendanceHolding
                        ? AppColors.warning
                        : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.attendanceHolding
                          ? 'They are coming just as often — ${s.rateLine}. '
                                'Nothing else on this screen would catch them.'
                          : 'Coming ${s.rateLine}.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Row(
              children: [
                _WeekdayStrip(label: 'Was', pattern: s.baselineWeekdays),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                _WeekdayStrip(label: 'Now', pattern: s.recentWeekdays),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Before/after pair of bars for one percentage.
class _ConsistencyBar extends StatelessWidget {
  final String label;
  final double before;
  final double after;
  final String beforeLabel;
  final String afterLabel;
  final Color color;

  const _ConsistencyBar({
    required this.label,
    required this.before,
    required this.after,
    required this.beforeLabel,
    required this.afterLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 2),
        // Spelling out the two periods: "Before" and "Now" on their own are
        // ambiguous, and a staff member who has to guess the window will not
        // trust the number.
        Text(
          'Before = 12 to 4 weeks ago · Now = the last 4 weeks',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 6),
        _bar('Before', before, beforeLabel, AppColors.success),
        const SizedBox(height: 4),
        _bar('Now', after, afterLabel, color),
      ],
    );
  }

  Widget _bar(String tag, double value, String detail, Color barColor) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            tag,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            '${(value * 100).round()}%  ($detail)',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Which days of the week were used, as a compact SMTWTFS strip.
///
/// Context only — day-of-week drift never triggers the alert on its own
/// (FR-09 §6), so this is styled quietly rather than as evidence.
class _WeekdayStrip extends StatelessWidget {
  final String label;
  final String pattern;

  const _WeekdayStrip({required this.label, required this.pattern});

  @override
  Widget build(BuildContext context) {
    final safe = pattern.length == 7 ? pattern : '.......';
    return Row(
      children: [
        Text(
          '$label ',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
        ),
        ...List.generate(7, (i) {
          final active = safe[i] != '.';
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              const ['S', 'M', 'T', 'W', 'T', 'F', 'S'][i],
              style: TextStyle(
                fontSize: 9,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? AppColors.primary : Colors.grey.shade400,
              ),
            ),
          );
        }),
      ],
    );
  }
}
