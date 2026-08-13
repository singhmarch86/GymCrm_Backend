import 'package:flutter/material.dart';

/// Mirrors backend RenewalFilter values (internal/members/service.go):
/// all | today | tomorrow | this_week | expired
enum RenewalFilterOption { all, today, tomorrow, thisWeek, expired }

extension RenewalFilterOptionApi on RenewalFilterOption {
  /// The exact string the backend's ?filter= query param expects.
  String get apiValue {
    switch (this) {
      case RenewalFilterOption.all:
        return 'all';
      case RenewalFilterOption.today:
        return 'today';
      case RenewalFilterOption.tomorrow:
        return 'tomorrow';
      case RenewalFilterOption.thisWeek:
        return 'this_week';
      case RenewalFilterOption.expired:
        return 'expired';
    }
  }
}

class RenewalFilterBar extends StatelessWidget {
  final RenewalFilterOption selectedFilter;
  final ValueChanged<RenewalFilterOption> onFilterChanged;

  const RenewalFilterBar({
    super.key,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildChip(label: "All", filter: RenewalFilterOption.all),
          const SizedBox(width: 10),
          _buildChip(label: "Today", filter: RenewalFilterOption.today),
          const SizedBox(width: 10),
          _buildChip(label: "Tomorrow", filter: RenewalFilterOption.tomorrow),
          const SizedBox(width: 10),
          _buildChip(label: "This Week", filter: RenewalFilterOption.thisWeek),
          const SizedBox(width: 10),
          _buildChip(label: "Expired", filter: RenewalFilterOption.expired),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required RenewalFilterOption filter,
  }) {
    return ChoiceChip(
      label: Text(label),

      selected: selectedFilter == filter,

      onSelected: (_) {
        onFilterChanged(filter);
      },

      showCheckmark: false,

      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

      selectedColor: Colors.blue.shade600,

      backgroundColor: Colors.grey.shade100,

      labelStyle: TextStyle(
        color: selectedFilter == filter ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}
