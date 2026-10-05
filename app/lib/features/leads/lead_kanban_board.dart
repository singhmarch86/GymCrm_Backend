import 'package:flutter/material.dart';

import '../../models/lead.dart';
import '../../theme/app_colors.dart';

import 'lead_pipeline_constants.dart';

/// Kanban view of the pipeline: one column per stage, so the whole funnel is
/// visible at once rather than one filtered list at a time.
///
/// Cards are moved via an explicit menu rather than drag-and-drop. Dragging
/// reads better in a demo, but it depends on sustained pointer tracking, which
/// is exactly what the Flutter desktop MouseTracker bug destabilises — and a
/// move that silently fails mid-drag would corrupt the pipeline. A menu is
/// unambiguous, keyboard-reachable, and works identically on web and desktop.
class LeadKanbanBoard extends StatelessWidget {
  final List<Lead> leads;
  final void Function(Lead) onTap;

  /// Called with the destination status. The parent owns the mark-as-lost
  /// reason prompt, since 'lost' requires a reason the board can't collect.
  final void Function(Lead, String newStatus) onMove;

  const LeadKanbanBoard({
    super.key,
    required this.leads,
    required this.onTap,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kPipelineStages.map((stage) {
          final stageLeads = leads
              .where((l) => l.status == stage.status)
              .toList();
          return _StageColumn(
            stage: stage,
            leads: stageLeads,
            onTap: onTap,
            onMove: onMove,
          );
        }).toList(),
      ),
    );
  }
}

class _StageColumn extends StatelessWidget {
  final PipelineStage stage;
  final List<Lead> leads;
  final void Function(Lead) onTap;
  final void Function(Lead, String) onMove;

  const _StageColumn({
    required this.stage,
    required this.leads,
    required this.onTap,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Column header ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: stage.color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
            ),
            child: Row(
              children: [
                Icon(stage.icon, size: 16, color: stage.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stage.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: stage.color,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: stage.color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${leads.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Cards ──────────────────────────────────────────────────────
          if (leads.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
              child: Center(
                child: Text(
                  'No leads',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
            )
          else
            ConstrainedBox(
              // Cap the column so a lopsided stage can't stretch the board to
              // an unusable height; the column scrolls internally instead.
              constraints: const BoxConstraints(maxHeight: 560),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: leads.length,
                itemBuilder: (_, i) => _KanbanCard(
                  lead: leads[i],
                  stage: stage,
                  onTap: () => onTap(leads[i]),
                  onMove: (to) => onMove(leads[i], to),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  final Lead lead;
  final PipelineStage stage;
  final VoidCallback onTap;
  final void Function(String) onMove;

  const _KanbanCard({
    required this.lead,
    required this.stage,
    required this.onTap,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final overdue = lead.isFollowUpOverdue;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: overdue
              ? AppColors.danger.withValues(alpha: 0.35)
              : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lead.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _moveMenu(context),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                lead.phone,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _miniTag(
                    Icons.sensors_rounded,
                    lead.sourceLabel,
                    Colors.indigo,
                  ),
                  if (lead.followUpDate != null)
                    _miniTag(
                      Icons.event_rounded,
                      lead.followUpLabel,
                      overdue ? AppColors.danger : Colors.grey.shade600,
                    ),
                  if (lead.assignedUserName != null &&
                      lead.assignedUserName!.isNotEmpty)
                    _miniTag(
                      Icons.person_rounded,
                      lead.assignedUserName!.split(' ').first,
                      Colors.teal,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniTag(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _moveMenu(BuildContext context) {
    // Every stage except the one the lead is already in.
    final targets = kPipelineStages
        .where((s) => s.status != lead.status)
        .toList();

    return PopupMenuButton<String>(
      tooltip: 'Move ${lead.name}',
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 16,
        color: Colors.grey.shade500,
      ),
      onSelected: onMove,
      itemBuilder: (_) => targets
          .map(
            (s) => PopupMenuItem<String>(
              value: s.status,
              height: 40,
              child: Row(
                children: [
                  Icon(s.icon, size: 15, color: s.color),
                  const SizedBox(width: 10),
                  Text(
                    'Move to ${s.label}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
