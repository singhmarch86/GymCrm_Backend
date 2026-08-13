import 'package:flutter/material.dart';

import '../../models/renewal_due.dart';

import 'renewal_filter_bar.dart';
import 'renewal_list.dart';
import 'renewal_search_bar.dart';

class RenewalsBody extends StatefulWidget {
  final List<RenewalDue> renewals;
  final bool isLoading;

  /// Called whenever the filter or search term changes, so the parent can
  /// re-fetch from the backend with the new query params. The backend
  /// (members.Service.GetDueForRenewal) owns the filtering/search logic —
  /// this widget just collects the inputs and reports them upward.
  final void Function({
    required RenewalFilterOption filter,
    required String search,
  })
  onQueryChanged;

  final Future<void> Function() onRefresh;
  final void Function(RenewalDue) onRenew;

  const RenewalsBody({
    super.key,
    required this.renewals,
    required this.isLoading,
    required this.onQueryChanged,
    required this.onRefresh,
    required this.onRenew,
  });

  @override
  State<RenewalsBody> createState() => _RenewalsBodyState();
}

class _RenewalsBodyState extends State<RenewalsBody> {
  final TextEditingController searchController = TextEditingController();

  RenewalFilterOption selectedFilter = RenewalFilterOption.all;

  void emitQuery() {
    widget.onQueryChanged(
      filter: selectedFilter,
      search: searchController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RenewalSearchBar(
          controller: searchController,
          onChanged: (_) {
            setState(() {});
            emitQuery();
          },
        ),

        const SizedBox(height: 18),

        RenewalFilterBar(
          selectedFilter: selectedFilter,
          onFilterChanged: (filter) {
            setState(() {
              selectedFilter = filter;
            });
            emitQuery();
          },
        ),

        const SizedBox(height: 18),

        Expanded(
          child: RenewalList(
            renewals: widget.renewals,
            isLoading: widget.isLoading,
            onRefresh: widget.onRefresh,
            onRenew: widget.onRenew,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
