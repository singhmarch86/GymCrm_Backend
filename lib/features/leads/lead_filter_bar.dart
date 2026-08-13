import 'package:flutter/material.dart';

import 'lead_pipeline_constants.dart';

class LeadFilterBar extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;

  const LeadFilterBar({
    super.key,
    required this.selectedStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(context, '', 'All', Colors.grey.shade700),
          ...kPipelineStages.map(
            (s) => _chip(context, s.status, s.label, s.color),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String status, String label, Color color) {
    final selected = selectedStatus == status;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onStatusChanged(status),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        selectedColor: color,
        backgroundColor: Colors.grey.shade100,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
