import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../screens/add_member_screen.dart';
import '../../screens/edit_member_screen.dart';
import '../../screens/member_detail_screen.dart';
import '../../services/api_response.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';

import 'member_card.dart';
import 'member_table.dart';

class MemberList extends StatefulWidget {
  final bool isLoading;
  final List<Member> members;
  final Future<void> Function() onRefresh;
  final VoidCallback? onMemberChanged;

  const MemberList({
    super.key,
    required this.isLoading,
    required this.members,
    required this.onRefresh,
    this.onMemberChanged,
  });

  @override
  State<MemberList> createState() => _MemberListState();
}

class _MemberListState extends State<MemberList> {
  // Sorted client-side over the page already fetched. Server-side sorting is
  // the right answer once paging matters, and deliberately not smuggled in
  // behind a layout change (FR-17 §6).
  String _sortKey = '';
  bool _sortAsc = true;

  List<Member> get _sorted {
    if (_sortKey.isEmpty) return widget.members;
    final rows = [...widget.members];
    int cmp(String? a, String? b) {
      // Nulls last in both directions: "no expiry recorded" is not a date and
      // should never lead the list somebody is working down.
      if (a == null || a.isEmpty) return 1;
      if (b == null || b.isEmpty) return -1;
      return a.compareTo(b);
    }

    rows.sort(
      (x, y) => _sortKey == 'expiry'
          ? cmp(x.expiryDate, y.expiryDate)
          : cmp(x.lastVisitAt, y.lastVisitAt),
    );
    return _sortAsc ? rows : rows.reversed.toList();
  }

  void _onSort(String key) => setState(() {
    if (_sortKey == key) {
      _sortAsc = !_sortAsc;
    } else {
      _sortKey = key;
      _sortAsc = true;
    }
  });

  Future<void> _openDetail(BuildContext context, Member member) async {
    // The panel closes fully before we act on its result — see
    // showMemberDetailPanel's doc comment for why this can't just open
    // the edit dialog / confirmation itself.
    final action = await showMemberDetailPanel(context, member);
    if (!context.mounted) return;

    if (action == 'changed') {
      // A lifecycle operation (freeze/upgrade/transfer/terminate) ran inside
      // the panel. It already reflects the new state itself; the outer list
      // just needs to catch up.
      widget.onMemberChanged?.call();
      await widget.onRefresh();
    } else if (action == 'edit') {
      final result = await showEditMemberDialog(context, member);
      if (result == true) {
        widget.onMemberChanged?.call();
        await widget.onRefresh();
      }
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Member'),
          content: const Text('Are you sure you want to delete this member?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                // Same reason as AppTheme.dialogActionButton — AlertDialog lays
                // its actions out in an OverflowBar, so the theme's infinite
                // minimum width would push this button out of view.
                minimumSize: const Size(120, 48),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      if (!context.mounted) return;

      try {
        await MemberService().deleteMember(member.id);
        widget.onMemberChanged?.call();
        await widget.onRefresh();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException
                  ? e.message
                  : "Couldn't delete this member. Please try again.",
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _addMember(BuildContext context) async {
    final result = await showAddMemberDialog(context);
    if (result == true) {
      widget.onMemberChanged?.call();
      await widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.members.isEmpty) {
      return EmptyStateView(
        icon: Icons.groups_outlined,
        title: 'No Members Found',
        body: 'Start by adding your first gym member.',
        actionLabel: 'Add Member',
        onAction: () => _addMember(context),
      );
    }

    // 900px is the shell's breakpoint, so the table appears exactly when the
    // rail does and the two never disagree about what "desk width" means.
    if (MediaQuery.sizeOf(context).width >= 900) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: MemberTable(
          members: _sorted,
          onTap: (m) => _openDetail(context, m),
          onCollectPayment: (m) => _openDetail(context, m),
          onRenew: (m) => _openDetail(context, m),
          sortKey: _sortKey,
          sortAscending: _sortAsc,
          onSort: _onSort,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: widget.members.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final member = widget.members[index];

          return MemberCard(
            member: member,
            onTap: () => _openDetail(context, member),
          );
        },
      ),
    );
  }
}
