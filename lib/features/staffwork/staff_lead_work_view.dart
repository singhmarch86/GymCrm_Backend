import 'package:flutter/material.dart';

import '../../models/date_span.dart';
import '../../models/staff_work.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

/// Per-person lead workflow (FR-18 §7).
///
/// The owner's view, not the worker's. The Leads → Workflow tab answers "what
/// do I do next"; this answers "is Simran coping". Same data, different
/// question, different person — which is why the queue was not moved here.
///
/// Ordered by name, never by output. This is the screen where the leaderboard
/// risk is highest, because it is the one an owner reads *about people*, and a
/// list sorted by conversions is a ranking whatever the heading says.
class StaffLeadWorkView extends StatelessWidget {
  final LeadWorkReport report;
  final DateSpan span;
  final void Function(int leadId)? onOpenLead;

  /// The workflow queue, spliced in below the per-person cards.
  ///
  /// Built by LeadWorkflowView so there is exactly one implementation of the
  /// queue, rendered in two places. The owner reads "is Simran coping" at the
  /// top and "what is actually owed" underneath, without changing screens.
  final List<Widget> queueSections;

  const StaffLeadWorkView({
    super.key,
    required this.report,
    required this.span,
    this.onOpenLead,
    this.queueSections = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'No open leads to carry.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        _GymTotals(report: report),
        const SizedBox(height: 8),
        ...report.staff.map((s) => _StaffLeadCard(
              staff: s,
              span: span,
              onOpenLead: onOpenLead,
            )),
        const SizedBox(height: 14),
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
                  'What each person is carrying is counted as it stands now, '
                  'whatever dates are showing — asking for July does not '
                  'un-neglect a lead still sitting untouched today. What they '
                  'worked is counted ${span.workedSuffix}, and covers calls, '
                  'counselling, trials, joins and notes logged by hand; '
                  'automatic stage history is not counted here.',
                  style: TextStyle(
                      fontSize: 11, height: 1.4, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),

        // The queue. Below the people, because the question this screen opens
        // with is "who is carrying what" — but an owner who spots a problem
        // should be able to act on it here rather than being sent elsewhere.
        if (queueSections.isNotEmpty) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Divider(color: Colors.grey.shade300, height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    "WHAT'S OWED",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.grey.shade500),
                  ),
                ),
                Expanded(
                  child: Divider(color: Colors.grey.shade300, height: 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              'The same queue as Leads → Workflow. Every open lead, and the '
              'decision owed on it.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: Colors.grey.shade600),
            ),
          ),
          ...queueSections,
        ],
      ],
    );
  }
}

class _GymTotals extends StatelessWidget {
  final LeadWorkReport report;

  const _GymTotals({required this.report});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _figure('${report.totalOpen}', 'open leads', null),
          _divider(),
          _figure('${report.totalUnattended}', 'unattended',
              report.totalUnattended > 0 ? AppColors.danger : null),
          _divider(),
          _figure('${report.totalOverdue}', 'overdue',
              report.totalOverdue > 0 ? AppColors.warning : null),
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
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      );

  Widget _divider() =>
      Container(width: 1, height: 28, color: Colors.grey.shade200);
}

class _StaffLeadCard extends StatelessWidget {
  final StaffLeadWork staff;
  final DateSpan span;
  final void Function(int leadId)? onOpenLead;

  const _StaffLeadCard({
    required this.staff,
    required this.span,
    this.onOpenLead,
  });

  @override
  Widget build(BuildContext context) {
    final c = staff.carrying;
    final w = staff.worked;
    final unassigned = staff.isUnassignedBucket;

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
                  radius: 17,
                  backgroundColor: unassigned
                      ? AppColors.danger.withValues(alpha: 0.12)
                      : AppColors.primary.withValues(alpha: 0.12),
                  child: Icon(
                    unassigned
                        ? Icons.person_off_rounded
                        : Icons.person_rounded,
                    size: 17,
                    color: unassigned ? AppColors.danger : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 1),
                      Text(
                        [
                          if (staff.role != null) staff.role!,
                          c.openLeads == 1
                              ? '1 lead'
                              : '${c.openLeads} leads',
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Labelled "now" explicitly. Once a range is on screen, an
            // unlabelled block of counts reads as being scoped to that range,
            // and these are not.
            Text('Carrying now',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 6),

            // Unattended first, because a lead nobody picked up is a worse
            // failure than one being chased late.
            Row(
              children: [
                _stat('${c.unattended}', 'unattended',
                    c.unattended > 0 ? AppColors.danger : null),
                _stat('${c.overdue}', 'overdue',
                    c.overdue > 0 ? AppColors.warning : null),
                _stat('${c.dueToday}', 'due today', null),
              ],
            ),

            const SizedBox(height: 11),

            // The single most actionable line: who they call next.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: c.nextLeadName == null
                  ? Text('Nothing scheduled next',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500))
                  : InkWell(
                      onTap: (onOpenLead == null || c.nextLeadId == null)
                          ? null
                          : () => onOpenLead!(c.nextLeadId!),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_forward_rounded,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Next: ${c.nextLeadName}'
                              '${c.nextDue == null ? '' : ' · ${_due(c.nextDue!)}'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 10),

            Text('Worked ${span.workedSuffix}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),

            if (w.isEmpty)
              Text('Nothing logged',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade500))
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  // Calls and reached are shown together because they are one
                  // fact: a call that rang out is work done, but it is not
                  // contact, and conflating them makes a bad day look good.
                  if (w.calls > 0)
                    _chip('${w.calls} ${_plural(w.calls, 'call')} · '
                        '${w.reached} reached', AppColors.info),
                  if (w.counselling > 0)
                    _chip('${w.counselling} counselling', AppColors.primary),
                  if (w.trialsBooked > 0)
                    _chip(
                        '${w.trialsBooked} '
                        '${_plural(w.trialsBooked, 'trial')} booked',
                        AppColors.warning),
                  if (w.joined > 0)
                    _chip('${w.joined} joined', AppColors.success),
                  if (w.notesLogged > 0)
                    _chip(
                        '${w.notesLogged} ${_plural(w.notesLogged, 'note')}',
                        Colors.grey.shade600),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, Color? colour) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: colour ?? AppColors.textPrimary)),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      );

  Widget _chip(String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colour.withValues(alpha: 0.3)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: colour)),
      );

  static String _plural(int n, String word) => n == 1 ? word : '${word}s';

  static String _due(DateTime d) {
    final now = DateTime.now();
    final due = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return '${-diff}d late';
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    return 'in ${diff}d';
  }
}
