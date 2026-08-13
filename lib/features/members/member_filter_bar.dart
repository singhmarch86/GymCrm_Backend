import 'package:flutter/material.dart';

enum MemberFilter { all, active, expired, expiring }

class MemberFilterBar extends StatelessWidget {
  final MemberFilter selectedFilter;
  final ValueChanged<MemberFilter> onFilterChanged;

  const MemberFilterBar({
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
          _buildChip(label: "All", filter: MemberFilter.all),
          const SizedBox(width: 10),
          _buildChip(label: "Active", filter: MemberFilter.active),
          const SizedBox(width: 10),
          _buildChip(label: "Expired", filter: MemberFilter.expired),
          const SizedBox(width: 10),
          _buildChip(label: "Expiring", filter: MemberFilter.expiring),
        ],
      ),
    );
  }

  Widget _buildChip({required String label, required MemberFilter filter}) {
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
