import 'package:flutter/material.dart';

import '../../models/lead.dart';
import '../../models/lead_pipeline.dart';
import '../../services/api_response.dart';
import '../../services/lead_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';

import 'lead_pipeline_constants.dart';

/// Shows lead details as a full-page route.
///
/// Returns:
///   - `true`      — a non-modal action happened in place (status advanced
///                   to a non-"lost" stage) and the page was later closed
///   - `'convert'` — user tapped Convert to Member; caller opens
///                   ConvertLeadScreen after this page has fully closed
///   - `'delete'`  — user tapped Delete; caller confirms and deletes after
///                   this page has fully closed
///   - `'lost'`    — user tapped Mark as Lost; caller prompts for a reason
///                   and advances status after this page has fully closed
///   - `null`      — nothing changed
///
/// This was previously a custom slide-in side panel (via showGeneralDialog),
/// but that transition triggered a real Flutter desktop MouseTracker bug
/// ('!_debugDuringDeviceUpdate' assertion cascading into "Lost connection
/// to device") on its own open/close animation — not just when nesting a
/// second modal on top of it. A plain MaterialPageRoute doesn't have this
/// problem. Convert/Delete/Mark-as-Lost still pop first and let the caller
/// act afterward, which remains the simplest way to keep this file from
/// needing its own confirmation dialogs.
Future<Object?> showLeadDetailPanel(BuildContext context, int leadId) {
  return Navigator.push<Object>(
    context,
    MaterialPageRoute(builder: (_) => LeadDetailPanel(leadId: leadId)),
  );
}

class LeadDetailPanel extends StatefulWidget {
  final int leadId;
  const LeadDetailPanel({super.key, required this.leadId});

  @override
  State<LeadDetailPanel> createState() => _LeadDetailPanelState();
}

class _LeadDetailPanelState extends State<LeadDetailPanel> {
  bool _loading = true;
  Lead? _lead;
  String? _error;
  bool _changed = false;

  List<LeadActivity> _activities = [];
  List<Assignee> _assignees = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadActivities();
    _loadAssignees();
  }

  Future<void> _load() async {
    try {
      final data = await LeadService().getLead(widget.leadId);
      if (!mounted) return;
      setState(() {
        _lead = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : "Couldn't load this lead. Please try again.";
        _loading = false;
      });
    }
  }

  /// Timeline and assignees are secondary to the lead itself — a failure here
  /// leaves the rest of the page usable rather than blocking it behind an error.
  Future<void> _loadActivities() async {
    try {
      final data = await LeadService().getActivities(widget.leadId);
      if (!mounted) return;
      setState(() => _activities = data);
    } catch (_) {}
  }

  Future<void> _loadAssignees() async {
    try {
      final data = await LeadService().getAssignees();
      if (!mounted) return;
      setState(() => _assignees = data);
    } catch (_) {}
  }

  Future<void> _assign(int? userId) async {
    try {
      final updated = await LeadService().assignLead(widget.leadId, userId);
      if (!mounted) return;
      setState(() {
        _lead = updated;
        _changed = true;
      });
      _loadActivities();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : "Couldn't reassign this lead.")),
      );
    }
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'What happened?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || controller.text.trim().isEmpty) return;

    try {
      await LeadService().addActivity(widget.leadId, type: 'note', note: controller.text.trim());
      _loadActivities();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : "Couldn't save the note.")),
      );
    }
  }

  Future<void> _advance(String newStatus) async {
    if (newStatus == 'lost') {
      Navigator.pop(context, 'lost');
      return;
    }
    try {
      final updated = await LeadService().advanceStatus(widget.leadId, newStatus);
      if (!mounted) return;
      setState(() {
        _lead = updated;
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to ${stageFor(newStatus).label}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : "Couldn't update this lead's status."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, true);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(_lead?.name ?? 'Lead Details'),
          actions: [
            if (_lead != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete',
                onPressed: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingView();
    }
    if (_error != null) {
      return ErrorBanner(message: _error!, onRetry: _load);
    }
    if (_lead == null) return const SizedBox.shrink();

    final lead = _lead!;
    final stage = stageFor(lead.status);

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        // ── Convert to Member button ────────────────────────────────────
        if (lead.convertedMemberId != null) ...[
          AppSpacing.gapLg,
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.how_to_reg_rounded, color: AppColors.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Converted to Member',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
                      ),
                      Text(
                        'Member ID: ${lead.convertedMemberId}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else if (lead.status == 'trial_completed' || lead.status == 'joined') ...[
          AppSpacing.gapLg,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'convert'),
              icon: const Icon(Icons.how_to_reg_rounded, size: 20),
              label: const Text(
                'Convert to Member',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],

        // ── Pipeline progress bar ───────────────────────────────────────
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pipeline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              AppSpacing.gapMd,
              _pipelineBar(lead.status),
            ],
          ),
        ),

        AppSpacing.gapLg,

        // ── Quick advance button ────────────────────────────────────────
        if (lead.isActive) ...[
          _advanceSection(lead, stage),
          AppSpacing.gapLg,
        ],

        // ── Owner ───────────────────────────────────────────────────────
        _assigneeSection(lead),

        AppSpacing.gapLg,

        // ── Contact info ────────────────────────────────────────────────
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Contact', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              AppSpacing.gapMd,
              _row(Icons.person_rounded, 'Name', lead.name),
              _row(Icons.phone_rounded, 'Phone', lead.phone),
              if (lead.email != null) _row(Icons.email_rounded, 'Email', lead.email!),
              if (lead.gender != null) _row(Icons.wc_rounded, 'Gender', lead.gender!),
            ],
          ),
        ),

        AppSpacing.gapLg,

        // ── Lead details ────────────────────────────────────────────────
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              AppSpacing.gapMd,
              _row(Icons.sensors_rounded, 'Source', lead.sourceLabel),
              if (lead.goalLabel != null) _row(Icons.flag_rounded, 'Goal', lead.goalLabel!),
              if (lead.trialDate != null)
                _row(Icons.fitness_center_rounded, 'Trial Date', _fmtDateStr(lead.trialDate!)),
              if (lead.followUpDate != null)
                _row(
                  Icons.event_rounded,
                  'Follow-up',
                  lead.followUpLabel,
                  valueColor: lead.isFollowUpOverdue ? AppColors.danger : null,
                ),
              if (lead.assignedUserName != null && lead.assignedUserName!.isNotEmpty)
                _row(Icons.badge_rounded, 'Assigned To', lead.assignedUserName!),
              if (lead.lostReason != null)
                _row(Icons.info_outline_rounded, 'Lost Reason', lead.lostReason!, valueColor: AppColors.danger),
            ],
          ),
        ),

        if (lead.notes != null) ...[
          AppSpacing.gapLg,
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                AppSpacing.gapSm,
                Text(lead.notes!, style: const TextStyle(height: 1.5)),
              ],
            ),
          ),
        ],

        AppSpacing.gapLg,

        // ── Activity timeline ───────────────────────────────────────────
        _timelineSection(),

        AppSpacing.gapXxl,
      ],
    );
  }

  /// Owner picker. Reassignment is logged to the timeline by the backend, so
  /// "who was handling this lead when" stays auditable.
  Widget _assigneeSection(Lead lead) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.badge_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          const Text('Owner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Spacer(),
          if (_assignees.isEmpty)
            Text('—', style: TextStyle(color: Colors.grey.shade500))
          else
            DropdownButton<int?>(
              value: lead.assignedUserId,
              hint: const Text('Unassigned'),
              underline: const SizedBox.shrink(),
              onChanged: _assign,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Unassigned')),
                ..._assignees.map(
                  (a) => DropdownMenuItem<int?>(
                    value: a.id,
                    child: Text(a.name),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _timelineSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Activity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addNote,
                icon: const Icon(Icons.add_comment_rounded, size: 16),
                label: const Text('Add note'),
              ),
            ],
          ),
          AppSpacing.gapSm,
          if (_activities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No activity recorded yet. Stage changes and logged calls will appear here.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            )
          else
            ..._activities.map(_activityRow),
        ],
      ),
    );
  }

  Widget _activityRow(LeadActivity a) {
    final (icon, color) = switch (a.type) {
      'stage_change' => (Icons.arrow_forward_rounded, AppColors.primary),
      'call' => (Icons.phone_in_talk_rounded, AppColors.success),
      'lost' => (Icons.cancel_rounded, AppColors.danger),
      'converted' => (Icons.check_circle_rounded, AppColors.success),
      'follow_up_set' => (Icons.event_rounded, AppColors.warning),
      'trial_scheduled' => (Icons.fitness_center_rounded, AppColors.info),
      'created' => (Icons.person_add_rounded, AppColors.primary),
      _ => (Icons.notes_rounded, Colors.grey),
    };

    // Stage changes describe themselves from the transition; everything else
    // falls back to its note.
    String title;
    if (a.type == 'stage_change' && a.toStatus != null) {
      final from = a.fromStatus != null ? stageFor(a.fromStatus!).label : '';
      final to = stageFor(a.toStatus!).label;
      title = from.isEmpty ? 'Moved to $to' : 'Moved from $from to $to';
    } else if (a.outcome != null) {
      // What came of it leads the line (FR-16): "No answer" is the fact
      // somebody scanning the timeline needs, and the note is the detail.
      final label = FollowUpOutcome.labelFor(a.outcome);
      final note = a.note?.trim() ?? '';
      title = note.isEmpty ? label : '$label — $note';
    } else {
      title = a.note ?? a.type.replaceAll('_', ' ');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, height: 1.4)),
                if (a.type == 'stage_change' && a.note != null && a.note!.isNotEmpty)
                  Text(
                    a.note!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                const SizedBox(height: 2),
                Text(
                  [
                    a.relativeTime,
                    if (a.userName != null && a.userName!.isNotEmpty) a.userName!,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pipelineBar(String currentStatus) {
    final stages = kPipelineStages.where((s) => s.status != 'lost').toList();
    final currentIdx = stages.indexWhere((s) => s.status == currentStatus);

    return Row(
      children: stages.asMap().entries.map((e) {
        final i = e.key;
        final s = e.value;
        final isPast = i < currentIdx;
        final isCurrent = i == currentIdx;
        final isLast = i == stages.length - 1;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (isPast || isCurrent) ? s.color : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        s.icon,
                        size: 16,
                        color: (isPast || isCurrent) ? Colors.white : Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? s.color : Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Container(
                  height: 2,
                  width: 8,
                  color: isPast ? stages[i].color : Colors.grey.shade200,
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _advanceSection(Lead lead, PipelineStage stage) {
    final currentIdx = kPipelineStages.indexWhere((s) => s.status == lead.status);
    final nextStages = <PipelineStage>[];
    if (currentIdx >= 0 && currentIdx < kPipelineStages.length - 2) {
      nextStages.add(kPipelineStages[currentIdx + 1]);
    }
    final lostStage = kPipelineStages.last;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          AppSpacing.gapMd,
          ...nextStages.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _advance(s.status),
                  icon: Icon(s.icon, size: 18),
                  label: Text('Move to ${s.label}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: s.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ),
          if (lead.status != 'lost')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _advance('lost'),
                icon: Icon(lostStage.icon, size: 16, color: lostStage.color),
                label: Text('Mark as Lost', style: TextStyle(color: lostStage.color)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: lostStage.color.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDateStr(String raw) {
    try {
      final d = DateTime.parse(raw);
      const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day.toString().padLeft(2, '0')} ${m[d.month]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }
}
