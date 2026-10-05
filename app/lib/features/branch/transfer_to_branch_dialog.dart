import 'package:flutter/material.dart';

import '../../models/branch.dart';
import '../../services/api_response.dart';
import '../../services/branch_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart';

/// What is being moved. The consequences differ per kind, and staff need to be
/// told which one applies before they commit.
enum TransferKind { member, staff, trainer }

/// One dialog for moving a member, a staff member or a trainer to another
/// branch. See docs/FR-06-multi-location.md.
///
/// Shared because the flow is identical — pick a destination, confirm — and the
/// only real difference is the sentence explaining what stays behind. Three
/// near-identical dialogs would have drifted apart.
Future<bool?> showTransferToBranchDialog(
  BuildContext context, {
  required TransferKind kind,
  required int entityId,
  required String entityName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _TransferToBranchDialog(
      kind: kind,
      entityId: entityId,
      entityName: entityName,
    ),
  );
}

class _TransferToBranchDialog extends StatefulWidget {
  final TransferKind kind;
  final int entityId;
  final String entityName;

  const _TransferToBranchDialog({
    required this.kind,
    required this.entityId,
    required this.entityName,
  });

  @override
  State<_TransferToBranchDialog> createState() =>
      _TransferToBranchDialogState();
}

class _TransferToBranchDialogState extends State<_TransferToBranchDialog> {
  final _service = BranchService();
  final _reasonController = TextEditingController();

  List<Branch> _branches = [];
  int? _targetGymId;
  int? _currentGymId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final branches = await _service.getBranches();
      final current = await StorageService.getGymId();
      if (!mounted) return;
      setState(() {
        _currentGymId = current;
        // You can only move something to a branch you actually hold, and never
        // to the one it is already in.
        _branches = branches.where((b) => b.id != current).toList();
        _targetGymId = _branches.isNotEmpty ? _branches.first.id : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  String get _title => switch (widget.kind) {
    TransferKind.member => 'Move member to another branch',
    TransferKind.staff => 'Move staff to another branch',
    TransferKind.trainer => 'Move trainer to another branch',
  };

  /// The consequence sentence — what does NOT move is the part people get
  /// wrong, so it is stated before the button, not after.
  String get _consequence => switch (widget.kind) {
    TransferKind.member =>
      'Their payments and invoices stay with this branch — that revenue was '
          'earned and filed here. The member, and everything from here on, moves.',
    TransferKind.staff =>
      'Their home branch changes and they get access there. Their access to '
          'this branch is kept, so they can still cover shifts.',
    TransferKind.trainer =>
      'PT packages already sold stay with this branch and remain readable. '
          'Only new packages follow the trainer.',
  };

  Future<void> _submit() async {
    final target = _targetGymId;
    if (target == null) {
      setState(() => _error = 'Select a destination branch');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      switch (widget.kind) {
        case TransferKind.member:
          await _service.transferMember(
            widget.entityId,
            target,
            reason: _reasonController.text.trim(),
          );
        case TransferKind.staff:
          await _service.transferStaff(widget.entityId, target);
        case TransferKind.trainer:
          await _service.transferTrainer(widget.entityId, target);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: _title,
      subtitle: widget.entityName,
      icon: Icons.swap_horiz,
      accent: AppColors.primary,
      loading: _loading,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Move',
          loading: _saving,
          onPressed: (_saving || _branches.isEmpty) ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_branches.isEmpty && !_loading)
            const LifecycleNotice(
              tone: LifecycleTone.blocked,
              text:
                  'There is nowhere to move to — you only have access to this branch. '
                  'Add a branch, or ask an owner for access to another one.',
            )
          else ...[
            const LifecycleFieldLabel('Move to'),
            AppSpacing.gapXs,
            DropdownButtonFormField<int>(
              initialValue: _targetGymId,
              isExpanded: true,
              items: _branches
                  .map(
                    (b) => DropdownMenuItem(
                      value: b.id,
                      child: Text(
                        b.city != null && b.city!.isNotEmpty
                            ? '${b.displayName} · ${b.city}'
                            : b.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _targetGymId = v),
            ),
            AppSpacing.gapLg,

            if (widget.kind == TransferKind.member) ...[
              const LifecycleFieldLabel('Reason (optional)'),
              AppSpacing.gapXs,
              TextField(
                controller: _reasonController,
                autofillHints: const [],
                decoration: const InputDecoration(hintText: 'e.g. moved house'),
              ),
              AppSpacing.gapLg,
            ],

            LifecycleNotice(tone: LifecycleTone.warning, text: _consequence),
          ],
          if (_currentGymId == null) ...[
            AppSpacing.gapSm,
            const LifecycleNotice(
              tone: LifecycleTone.info,
              text:
                  'Could not tell which branch you are currently in — sign out and back in '
                  'if the destination list looks wrong.',
            ),
          ],
        ],
      ),
    );
  }
}
