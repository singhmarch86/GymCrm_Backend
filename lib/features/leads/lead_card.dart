import 'package:flutter/material.dart';

import '../../models/lead.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

import 'lead_pipeline_constants.dart';

class LeadCard extends StatelessWidget {
  final Lead lead;
  final VoidCallback? onTap;
  final Future<void> Function(String newStatus)? onAdvance;

  const LeadCard({super.key, required this.lead, this.onTap, this.onAdvance});

  @override
  Widget build(BuildContext context) {
    final stage = stageFor(lead.status);
    final initial = lead.name.isNotEmpty ? lead.name[0].toUpperCase() : '?';

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: avatar + name + status badge ────────────────────────
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: stage.color.withValues(alpha: 0.12),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: stage.color,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lead.phone,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // Pipeline stage badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: stage.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(stage.icon, size: 13, color: stage.color),
                    const SizedBox(width: 5),
                    Text(
                      stage.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: stage.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(color: Colors.grey.shade100),
          const SizedBox(height: 8),

          // ── Meta row: source | goal | follow-up ─────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _tag(Icons.sensors_rounded, lead.sourceLabel, Colors.indigo),
              if (lead.goalLabel != null)
                _tag(Icons.flag_rounded, lead.goalLabel!, Colors.teal),
              if (lead.followUpDate != null)
                _tag(
                  Icons.event_rounded,
                  lead.followUpLabel,
                  lead.isFollowUpOverdue
                      ? AppColors.danger
                      : Colors.grey.shade700,
                ),
            ],
          ),

          // ── Quick advance button (hidden for joined/lost) ────────────────
          if (lead.isActive && onAdvance != null) ...[
            const SizedBox(height: 14),
            _nextStageButton(context, stage),
          ],
        ],
      ),
    );
  }

  Widget _tag(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _nextStageButton(BuildContext context, PipelineStage currentStage) {
    // Find next stage (skip 'lost')
    final currentIndex = kPipelineStages.indexWhere(
      (s) => s.status == lead.status,
    );
    if (currentIndex < 0 || currentIndex >= kPipelineStages.length - 2) {
      return const SizedBox.shrink();
    }
    final nextStage = kPipelineStages[currentIndex + 1];

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => onAdvance?.call(nextStage.status),
        icon: Icon(nextStage.icon, size: 16, color: nextStage.color),
        label: Text(
          'Move to ${nextStage.label}',
          style: TextStyle(color: nextStage.color, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: nextStage.color.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}
