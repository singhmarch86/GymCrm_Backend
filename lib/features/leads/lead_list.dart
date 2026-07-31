import 'package:flutter/material.dart';

import '../../models/lead.dart';
import '../../widgets/empty_state.dart';

import 'lead_card.dart';

class LeadList extends StatelessWidget {
  final bool isLoading;
  final List<Lead> leads;
  final Future<void> Function() onRefresh;
  final void Function(Lead) onTap;
  final Future<void> Function(Lead, String newStatus) onAdvance;
  final VoidCallback? onAddLead;

  const LeadList({
    super.key,
    required this.isLoading,
    required this.leads,
    required this.onRefresh,
    required this.onTap,
    required this.onAdvance,
    this.onAddLead,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (leads.isEmpty) {
      return EmptyStateView(
        icon: Icons.person_search_rounded,
        title: 'No Leads Found',
        body: 'Tap below to register a new walk-in enquiry.',
        actionLabel: onAddLead != null ? 'Add Lead' : null,
        onAction: onAddLead,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: leads.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: LeadCard(
            lead: leads[i],
            onTap: () => onTap(leads[i]),
            onAdvance: (newStatus) => onAdvance(leads[i], newStatus),
          ),
        ),
      ),
    );
  }
}
