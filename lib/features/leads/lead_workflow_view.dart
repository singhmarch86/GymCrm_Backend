import 'package:flutter/material.dart';

import '../../models/lead_pipeline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

/// The lead workflow queue (FR-18).
///
/// Not a list of leads — a list of *decisions that are owed*. Unattended sits
/// at the top because a lead nobody has picked up is a worse failure than one
/// being chased late, and until this screen existed it was invisible: those
/// leads never appeared overdue, because they were never due.
class LeadWorkflowView extends StatelessWidget {
  final LeadWorkflow workflow;
  final void Function(WorkflowItem) onTap;

  /// Opens the next-step sheet. This is the only write on the screen, and it
  /// is always a human confirming — nothing here schedules itself.
  final Future<void> Function(WorkflowItem) onSetNextStep;

  const LeadWorkflowView({
    super.key,
    required this.workflow,
    required this.onTap,
    required this.onSetNextStep,
  });

  @override
  Widget build(BuildContext context) {
    if (workflow.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.task_alt_rounded,
                  size: 64, color: AppColors.success),
              const SizedBox(height: 16),
              const Text('No open leads',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Every lead has either joined or been closed.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        _Headline(workflow: workflow),
        const SizedBox(height: 6),
        for (final g in workflow.groups) _group(g),
      ],
    );
  }

  Widget _group(WorkflowGroup g) {
    // Empty groups are rendered as a single quiet line rather than dropped.
    // "0 unattended" is the most useful sentence this screen can say, and a
    // heading that vanishes at zero denies the reader that.
    if (g.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 14, 6, 2),
        child: Row(
          children: [
            Icon(Icons.check_rounded, size: 14, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text('${g.label} — none',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    final color = _tint(g.state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Text(g.label,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(width: 7),
              Text('${g.count}',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ),
        if (g.state == 'unattended')
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 10),
            child: Text(
              'No next step, no date, or nobody assigned. These are the leads '
              'that go quiet without ever looking overdue.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ),
        ...g.items.map((i) => _WorkflowCard(
              item: i,
              color: color,
              onTap: () => onTap(i),
              onSetNextStep: () => onSetNextStep(i),
            )),
      ],
    );
  }

  static Color _tint(String state) {
    switch (state) {
      case 'unattended':
        return AppColors.danger;
      case 'overdue':
        return AppColors.warning;
      case 'today':
        return AppColors.primary;
      case 'upcoming':
        return AppColors.info;
    }
    return AppColors.info;
  }
}

class _Headline extends StatelessWidget {
  final LeadWorkflow workflow;

  const _Headline({required this.workflow});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _figure('${workflow.totalOpen}', 'open leads', null),
          _divider(),
          _figure('${workflow.unattended}', 'unattended',
              workflow.unattended > 0 ? AppColors.danger : null),
          _divider(),
          _figure('${workflow.overdue}', 'overdue',
              workflow.overdue > 0 ? AppColors.warning : null),
          _divider(),
          _figure('${workflow.dueToday}', 'due today', null),
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

  Widget _divider() =>
      Container(width: 1, height: 28, color: Colors.grey.shade200);
}

class _WorkflowCard extends StatelessWidget {
  final WorkflowItem item;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onSetNextStep;

  const _WorkflowCard({
    required this.item,
    required this.color,
    required this.onTap,
    required this.onSetNextStep,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            '${item.phone} · ${item.stageLabel}',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    // Stage age, emphasised once it passes a month. Advisory:
                    // it changes weight, never which group the lead is in.
                    Text(
                      '${item.stageDays}d',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            item.isStale ? FontWeight.bold : FontWeight.normal,
                        color: item.isStale
                            ? AppColors.danger
                            : Colors.grey.shade500,
                      ),
                    ),
                    Text(' in stage',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade400)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _nextStepLine()),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onSetNextStep,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        item.isUnattended ? 'Set next step' : 'Change',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nextStepLine() {
    if (item.isUnattended) {
      // Names the missing part rather than saying "unattended" again. A staff
      // member needs to know *what* to supply, not that something is wrong.
      final missing = item.ownerName == null
          ? 'Nobody is assigned'
          : item.nextStep == null
              ? 'No next step set'
              : 'No date on the next step';
      return Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
          const SizedBox(width: 7),
          Expanded(
            child: Text(missing,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.danger)),
          ),
        ],
      );
    }

    final due = item.nextStepDue;
    final overdue = item.daysOverdue > 0;
    return Row(
      children: [
        Icon(Icons.arrow_forward_rounded, size: 14, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            [
              item.nextStepLabel ?? '',
              if (due != null) _dueText(due, item.daysOverdue),
              if (item.ownerName != null) item.ownerName!,
            ].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(
              fontSize: 12,
              color: overdue ? AppColors.warning : Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }

  static String _dueText(DateTime due, int daysOverdue) {
    if (daysOverdue > 0) {
      return daysOverdue == 1 ? '1 day late' : '$daysOverdue days late';
    }
    final now = DateTime.now();
    final d = DateTime(due.year, due.month, due.day);
    final t = DateTime(now.year, now.month, now.day);
    final diff = d.difference(t).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    return 'in $diff days';
  }
}
