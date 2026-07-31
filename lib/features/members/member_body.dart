import 'package:flutter/material.dart';

import '../../models/member.dart';

import 'member_filter_bar.dart';
import 'member_list.dart';
import 'member_search_bar.dart';

class MemberBody extends StatefulWidget {
  final List<Member> members;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  /// Called whenever an edit/delete inside this screen's MemberList
  /// succeeds, so the parent MembersScreen can mark itself as having
  /// changed business data (see member_screen.dart's PopScope handling).
  /// Optional so MemberBody can still be used anywhere it was before
  /// without callers needing to supply this.
  final VoidCallback? onMemberChanged;

  const MemberBody({
    super.key,
    required this.members,
    required this.isLoading,
    required this.onRefresh,
    this.onMemberChanged,
  });

  @override
  State<MemberBody> createState() =>
      _MemberBodyState();
}

class _MemberBodyState
    extends State<MemberBody> {

  final TextEditingController
  searchController =
  TextEditingController();

  MemberFilter selectedFilter =
      MemberFilter.all;

  List<Member> filteredMembers = [];

  @override
  void initState() {
    super.initState();

    filteredMembers = widget.members;
  }

  @override
  void didUpdateWidget(
      covariant MemberBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    applyFilters();
  }

  void applyFilters() {
    List<Member> data = widget.members;

    //----------------------------------
    // Search
    //----------------------------------

    final keyword =
    searchController.text
        .trim()
        .toLowerCase();

    if (keyword.isNotEmpty) {
      data = data.where((m) {

        final fullName =
        "${m.firstName} ${m.lastName}"
            .toLowerCase();

        return fullName.contains(keyword) ||
            m.phone.contains(keyword);

      }).toList();
    }

    //----------------------------------
    // Filter
    //----------------------------------

    switch (selectedFilter) {

      case MemberFilter.active:
        data = data
            .where((m) =>
        m.status
            .toLowerCase() ==
            "active")
            .toList();
        break;

      case MemberFilter.expired:
        data = data
            .where((m) =>
        m.status
            .toLowerCase() ==
            "expired")
            .toList();
        break;

      case MemberFilter.expiring:

        data = data.where((m) {

          if (m.expiryDate == null) {
            return false;
          }

          try {

            final expiry =
            DateTime.parse(
                m.expiryDate!);

            final diff =
                expiry
                    .difference(
                  DateTime.now(),
                )
                    .inDays;

            return diff >= 0 &&
                diff <= 7;

          } catch (_) {

            return false;

          }

        }).toList();

        break;

      case MemberFilter.all:
        break;
    }

    setState(() {
      filteredMembers = data;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Column(
      children: [

        MemberSearchBar(
          controller:
          searchController,
          onChanged: (_) {
            applyFilters();
          },
        ),

        const SizedBox(height: 18),

        MemberFilterBar(
          selectedFilter:
          selectedFilter,
          onFilterChanged:
              (filter) {

            setState(() {
              selectedFilter =
                  filter;
            });

            applyFilters();

          },
        ),

        const SizedBox(height: 18),

        Expanded(
          child: MemberList(
            members:
            filteredMembers,
            isLoading:
            widget.isLoading,
            onRefresh:
            widget.onRefresh,
            onMemberChanged:
            widget.onMemberChanged,
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