import 'package:flutter/material.dart';

import '../../models/lead.dart';
import '../../models/lead_pipeline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

import 'lead_pipeline_constants.dart';

/// The daily action queue: what needs chasing right now, worst first.
///
/// Ordering is deliberate — overdue before today before upcoming — because the
/// whole point is to surface leads going cold, not to be another list view.
class LeadFollowUpsView extends StatelessWidget {
  final FollowUpQueue queue;
  final void Function(Lead) onTap;
  final Future<void> Function(Lead) onLogCall;
  final Future<void> Function(Lead) onReschedule;

  const LeadFollowUpsView({
    super.key,
    required this.queue,
    required this.onTap,
    required this.onLogCall,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.task_alt_rounded, size: 72, color: AppColors.success),
              const SizedBox(height: 18),
              const Text(
                'All caught up',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'No follow-ups are due and no trials are scheduled.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _OutcomeSummary(queue: queue),
        _section(
          context,
          title: 'Overdue',
          subtitle: 'Follow-up date has already passed',
          icon: Icons.warning_amber_rounded,
          color: AppColors.danger,
          leads: queue.overdue,
        ),
        _section(
          context,
          title: 'Due Today',
          subtitle: 'Contact these before the day ends',
          icon: Icons.today_rounded,
          color: AppColors.warning,
          leads: queue.today,
        ),
        _section(
          context,
          title: 'Trials Scheduled',
          subtitle: 'Upcoming trial sessions',
          icon: Icons.fitness_center_rounded,
          color: AppColors.info,
          leads: queue.trials,
        ),
        _section(
          context,
          title: 'Upcoming',
          subtitle: 'Follow-ups scheduled later',
          icon: Icons.event_rounded,
          color: Colors.grey.shade600,
          leads: queue.upcoming,
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Lead> leads,
  }) {
    if (leads.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${leads.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        ...leads.map((l) => _row(context, l, color)),
      ],
    );
  }

  Widget _row(BuildContext context, Lead lead, Color accent) {
    final stage = stageFor(lead.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: () => onTap(lead),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: stage.color.withValues(alpha: 0.12),
              child: Text(
                lead.name.isNotEmpty ? lead.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: stage.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lead.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lead.phone,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _tag(stage.icon, stage.label, stage.color),
                      if (lead.followUpDate != null)
                        _tag(Icons.event_rounded, lead.followUpLabel, accent),
                      if (lead.assignedUserName != null &&
                          lead.assignedUserName!.isNotEmpty)
                        _tag(Icons.person_rounded, lead.assignedUserName!, Colors.teal),
                    ],
                  ),
                ],
              ),
            ),
            // Quick actions — the two things you actually do from this queue.
            IconButton(
              tooltip: 'Log a call with ${lead.name}',
              icon: const Icon(Icons.phone_in_talk_rounded, size: 20),
              color: AppColors.success,
              onPressed: () => onLogCall(lead),
            ),
            IconButton(
              tooltip: 'Reschedule follow-up for ${lead.name}',
              icon: const Icon(Icons.event_repeat_rounded, size: 20),
              color: AppColors.primary,
              onPressed: () => onReschedule(lead),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// What the last week of calling produced (FR-16 §6).
///
/// "14 no answer, 3 call back" tells an owner in one line whether the phone
/// work is landing. The same facts spread across nineteen timeline entries
/// tell them nothing.
class _OutcomeSummary extends StatelessWidget {
  final FollowUpQueue queue;

  const _OutcomeSummary({required this.queue});

  @override
  Widget build(BuildContext context) {
    // Six zeros reads as broken rather than as "nobody has logged anything
    // yet", so the row stays hidden until there is something to say.
    if (!queue.hasLoggedOutcomes) return const SizedBox.shrink();

    final total =
        queue.outcomeCounts.fold<int>(0, (sum, c) => sum + c.count);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.call_made_rounded,
                    size: 15, color: AppColors.primary),
                const SizedBox(width: 7),
                Text(
                  'Last ${queue.outcomeDays} days',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  total == 1 ? '1 logged' : '$total logged',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                // Zero counts stay visible so the row keeps its shape between
                // refreshes — a chart whose categories come and go is
                // unreadable — but they are dimmed so the eye skips them.
                for (final c in queue.outcomeCounts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.count == 0
                          ? Colors.grey.shade50
                          : _tint(c.outcome).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: c.count == 0
                            ? Colors.grey.shade200
                            : _tint(c.outcome).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      '${c.count}  ${c.label}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            c.count == 0 ? FontWeight.normal : FontWeight.w600,
                        color: c.count == 0
                            ? Colors.grey.shade400
                            : _tint(c.outcome),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Colour carries meaning, not decoration: reached is good, unreachable is
  /// a problem, a refusal is final.
  Color _tint(String outcome) {
    switch (outcome) {
      case 'answered':
      case 'interested':
        return AppColors.success;
      case 'no_answer':
      case 'wrong_number':
        return AppColors.danger;
      case 'call_back':
        return AppColors.warning;
      case 'not_interested':
        return Colors.grey.shade600;
    }
    return AppColors.info;
  }
}
