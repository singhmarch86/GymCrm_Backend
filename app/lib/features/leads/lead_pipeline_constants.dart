import 'package:flutter/material.dart';

/// Canonical pipeline stage config.
/// Single source of truth for colors, icons, and labels — no duplication
/// across cards, filter bars, or detail screens.
class PipelineStage {
  final String status;
  final String label;
  final Color color;
  final IconData icon;

  const PipelineStage({
    required this.status,
    required this.label,
    required this.color,
    required this.icon,
  });
}

const List<PipelineStage> kPipelineStages = [
  PipelineStage(
    status: 'new_lead',
    label: 'New Lead',
    color: Color(0xFFEA580C), // AppColors.primary (coral)
    icon: Icons.person_add_rounded,
  ),
  PipelineStage(
    status: 'contacted',
    label: 'Contacted',
    color: Color(0xFF7C3AED), // purple
    icon: Icons.phone_rounded,
  ),
  PipelineStage(
    status: 'trial_scheduled',
    label: 'Trial',
    color: Color(0xFFF59E0B), // AppColors.warning
    icon: Icons.calendar_month_rounded,
  ),
  PipelineStage(
    status: 'trial_completed',
    label: 'Tried',
    color: Color(0xFF0891B2), // cyan
    icon: Icons.fitness_center_rounded,
  ),
  PipelineStage(
    status: 'joined',
    label: 'Joined',
    color: Color(0xFF16A34A), // AppColors.success
    icon: Icons.check_circle_rounded,
  ),
  PipelineStage(
    status: 'lost',
    label: 'Lost',
    color: Color(0xFF6B7280), // grey
    icon: Icons.cancel_rounded,
  ),
];

PipelineStage stageFor(String status) {
  return kPipelineStages.firstWhere(
    (s) => s.status == status,
    orElse: () => kPipelineStages.first,
  );
}

/// Lead sources with labels — mirrors backend LeadSource enum.
const List<Map<String, String>> kLeadSources = [
  {'value': 'walk_in', 'label': 'Walk-in'},
  {'value': 'referral', 'label': 'Referral'},
  {'value': 'instagram', 'label': 'Instagram'},
  {'value': 'facebook', 'label': 'Facebook'},
  {'value': 'google', 'label': 'Google'},
  {'value': 'whatsapp', 'label': 'WhatsApp'},
  {'value': 'website', 'label': 'Website'},
  {'value': 'other', 'label': 'Other'},
];

/// Lead goals — mirrors backend LeadGoal enum.
const List<Map<String, String>> kLeadGoals = [
  {'value': 'weight_loss', 'label': 'Weight Loss'},
  {'value': 'muscle_gain', 'label': 'Muscle Gain'},
  {'value': 'fitness', 'label': 'General Fitness'},
  {'value': 'sports', 'label': 'Sports'},
  {'value': 'rehabilitation', 'label': 'Rehabilitation'},
  {'value': 'other', 'label': 'Other'},
];
