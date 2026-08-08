import 'package:flutter/material.dart';

import '../../models/staff.dart';
import '../branch/transfer_to_branch_dialog.dart';
import '../../services/api_response.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';

import 'staff_form_dialog.dart';

/// Staff administration — owner-only on the backend.
///
/// Deactivated staff stay listed (greyed out) rather than disappearing,
/// because they may still own open leads. Hiding them would make that work
/// look unassigned when it isn't.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  bool _loading = true;
  String? _error;
  List<Staff> _staff = [];
  bool _dataChanged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await StaffService().getStaff();
      if (!mounted) return;
      setState(() {
        _staff = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : "Couldn't load your staff list. Please try again.";
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    if (await showStaffFormDialog(context) == true) {
      _dataChanged = true;
      await _load();
    }
  }

  Future<void> _edit(Staff s) async {
    if (await showStaffFormDialog(context, existing: s) == true) {
      _dataChanged = true;
      await _load();
    }
  }

  /// Moves a colleague's home branch. Their access to this branch is kept, so
  /// they can still cover shifts here.
  Future<void> _moveToBranch(Staff s) async {
    final moved = await showTransferToBranchDialog(
      context,
      kind: TransferKind.staff,
      entityId: s.id,
      entityName: s.name,
    );
    if (moved == true) _load();
  }

  Future<void> _toggleStatus(Staff s) async {
    final deactivating = s.isActive;

    if (deactivating) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Deactivate ${s.name}?'),
          content: Text(
            s.leadCount > 0
                ? 'They will no longer be able to log in. Their '
                    '${s.leadCount} open lead${s.leadCount == 1 ? '' : 's'} stay '
                    'assigned to them so nothing gets lost — reassign from the '
                    'Leads screen if needed.'
                : 'They will no longer be able to log in. You can reactivate '
                    'them at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Deactivate',
                  style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      await StaffService().setStatus(s.id, deactivating ? 'inactive' : 'active');
      _dataChanged = true;
      await _load();
    } catch (e) {
      if (!mounted) return;
      // The backend refuses self-deactivation and removing the last owner —
      // surface that reason verbatim, it is the useful part.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : "Couldn't change status."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _resetPassword(Staff s) async {
    final controller = TextEditingController();
    String? inlineError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text('Reset password — ${s.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters, including a digit',
                  errorText: inlineError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final v = controller.text;
                if (v.length < 8 || !v.contains(RegExp(r'[0-9]'))) {
                  setInner(() => inlineError =
                      'At least 8 characters and one digit');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    try {
      await StaffService().resetPassword(s.id, controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset for ${s.name}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : "Couldn't reset the password."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dataChanged,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.person_add_rounded),
          label: const Text('Add Staff'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView(label: 'Loading staff...');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);
    if (_staff.isEmpty) {
      return EmptyStateView(
        icon: Icons.badge_outlined,
        title: 'No Staff Yet',
        body: 'Add trainers and front-desk staff so you can assign leads and '
            'track who is handling what.',
        actionLabel: 'Add Staff',
        onAction: _add,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _staff.length,
        itemBuilder: (_, i) => _row(_staff[i]),
      ),
    );
  }

  Widget _row(Staff s) {
    final dim = !s.isActive;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        // Inactive staff are visibly de-emphasised but still readable, since
        // they may still be the owner of open leads.
        opacity: dim ? 0.55 : 1,
        child: AppCard(
          onTap: () => _edit(s),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: (s.isOwner ? AppColors.primary : AppColors.info)
                    .withValues(alpha: 0.12),
                child: Text(
                  s.initial,
                  style: TextStyle(
                    color: s.isOwner ? AppColors.primary : AppColors.info,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _pill(
                          s.roleLabel,
                          s.isOwner ? AppColors.primary : AppColors.info,
                        ),
                        if (dim) ...[
                          const SizedBox(width: 6),
                          _pill('Inactive', Colors.grey.shade600),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.email.isEmpty ? s.phone : '${s.phone} · ${s.email}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (s.leadCount > 0) ...[
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_search_rounded,
                              size: 12, color: Colors.teal),
                          const SizedBox(width: 4),
                          Text(
                            '${s.leadCount} open lead${s.leadCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions for ${s.name}',
                icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      _edit(s);
                    case 'password':
                      _resetPassword(s);
                    case 'status':
                      _toggleStatus(s);
                    case 'move':
                      _moveToBranch(s);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                  const PopupMenuItem(value: 'password', child: Text('Reset password')),
                  const PopupMenuItem(value: 'move', child: Text('Move to another branch')),
                  PopupMenuItem(
                    value: 'status',
                    child: Text(
                      s.isActive ? 'Deactivate' : 'Reactivate',
                      style: TextStyle(
                        color: s.isActive ? AppColors.danger : AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
