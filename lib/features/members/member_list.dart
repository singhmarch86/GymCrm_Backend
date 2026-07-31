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

class MemberList extends StatelessWidget {
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
      onMemberChanged?.call();
      await onRefresh();
    } else if (action == 'edit') {
      final result = await showEditMemberDialog(context, member);
      if (result == true) {
        onMemberChanged?.call();
        await onRefresh();
      }
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Member'),
          content: const Text('Are you sure you want to delete this member?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
        onMemberChanged?.call();
        await onRefresh();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : "Couldn't delete this member. Please try again."),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _addMember(BuildContext context) async {
    final result = await showAddMemberDialog(context);
    if (result == true) {
      onMemberChanged?.call();
      await onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (members.isEmpty) {
      return EmptyStateView(
        icon: Icons.groups_outlined,
        title: 'No Members Found',
        body: 'Start by adding your first gym member.',
        actionLabel: 'Add Member',
        onAction: () => _addMember(context),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.only(
          top: 8,
          bottom: 100,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final member = members[index];

          return MemberCard(
            member: member,
            onTap: () => _openDetail(context, member),
          );
        },
      ),
    );
  }
}
