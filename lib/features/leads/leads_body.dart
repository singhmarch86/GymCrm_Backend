import 'package:flutter/material.dart';

import '../../models/lead.dart';

import 'lead_filter_bar.dart';
import 'lead_list.dart';
import 'lead_search_bar.dart';

class LeadsBody extends StatelessWidget {
  final List<Lead> leads;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final String selectedStatus;
  final TextEditingController searchController;
  final void Function(String status) onStatusChanged;
  final void Function(String search) onSearchChanged;
  final void Function(Lead) onTap;
  final Future<void> Function(Lead, String) onAdvance;
  final VoidCallback? onAddLead;

  const LeadsBody({
    super.key,
    required this.leads,
    required this.isLoading,
    required this.onRefresh,
    required this.selectedStatus,
    required this.searchController,
    required this.onStatusChanged,
    required this.onSearchChanged,
    required this.onTap,
    required this.onAdvance,
    this.onAddLead,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LeadSearchBar(
          controller: searchController,
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 16),
        LeadFilterBar(
          selectedStatus: selectedStatus,
          onStatusChanged: onStatusChanged,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LeadList(
            leads: leads,
            isLoading: isLoading,
            onRefresh: onRefresh,
            onTap: onTap,
            onAdvance: onAdvance,
            onAddLead: onAddLead,
          ),
        ),
      ],
    );
  }
}
