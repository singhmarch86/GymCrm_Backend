import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/lifecycle_event.dart';
import '../../models/member.dart';
import '../../services/api_response.dart';
import '../../services/lifecycle_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import 'lifecycle_shared.dart';

/// Transfer dialog — moves remaining validity to another member.
///
/// Transfers are the most abuse-prone operation in gym software: one membership
/// resold repeatedly. The dialog is deliberately explicit that the source
/// member is terminated by this, and the server records paired events so the
/// chain stays traceable.
///
/// The receiving member can be an existing record, or created on the spot —
/// the common front-desk case is a friend the outgoing member is handing the
/// membership to, who has never been in the system. Creating them here is a
/// plain member record; the transfer that follows is what actually moves
/// money and validity, and goes through the same lifecycle.Transfer call
/// either way.
Future<MemberLifecycleResult?> showTransferDialog(
  BuildContext context, {
  required int memberId,
  required String memberName,
  String? expiryDate,
}) {
  return showDialog<MemberLifecycleResult>(
    context: context,
    builder: (_) => TransferDialog(
      memberId: memberId,
      memberName: memberName,
      expiryDate: expiryDate,
    ),
  );
}

enum _TargetMode { existing, newMember }

class TransferDialog extends StatefulWidget {
  final int memberId;
  final String memberName;
  final String? expiryDate;

  const TransferDialog({
    super.key,
    required this.memberId,
    required this.memberName,
    this.expiryDate,
  });

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final _service = LifecycleService();
  final _memberService = MemberService();

  final _searchController = TextEditingController();
  final _reasonController = TextEditingController();
  final _feeController = TextEditingController(text: '0');
  final _newFirstNameController = TextEditingController();
  final _newLastNameController = TextEditingController();
  final _newPhoneController = TextEditingController();

  _TargetMode _mode = _TargetMode.existing;

  Timer? _debounce;
  List<Member> _results = [];
  Member? _target;

  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _reasonController.dispose();
    _feeController.dispose();
    _newFirstNameController.dispose();
    _newLastNameController.dispose();
    _newPhoneController.dispose();
    super.dispose();
  }

  void _switchMode(_TargetMode m) {
    setState(() {
      _mode = m;
      _target = null;
      _results = [];
      _error = null;
    });
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(q.trim()),
    );
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final all = await _memberService.searchMembers(q);
      if (!mounted) return;
      setState(() {
        // The source member cannot be their own transfer target.
        _results = all.where((m) => m.id != widget.memberId).take(6).toList();
        _searching = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _searching = false;
      });
    }
  }

  /// New-member fields are valid to submit: matches the same bar Add Member
  /// uses, so a person created here is never a lesser record than one added
  /// through the normal flow.
  bool get _newMemberValid =>
      _newFirstNameController.text.trim().isNotEmpty &&
      _newLastNameController.text.trim().isNotEmpty &&
      Validators.phone(_newPhoneController.text.trim()) == null;

  bool get _canSubmit {
    if (_saving) return false;
    final targetOk = _mode == _TargetMode.existing
        ? _target != null
        : _newMemberValid;
    return targetOk && _feePaise != null;
  }

  /// Null when the fee field holds something unparseable — distinct from a
  /// valid zero, so the submit button can tell "no fee" from "bad input".
  int? get _feePaise {
    final rupees = double.tryParse(_feeController.text.trim());
    if (rupees == null || rupees < 0) return null;
    return (rupees * 100).round();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      int targetId;
      if (_mode == _TargetMode.newMember) {
        // Create the receiving member first — a plain member record, no
        // plan or dates. The transfer that follows is what actually moves
        // the membership onto them.
        final created = await _memberService.createMember(
          firstName: _newFirstNameController.text.trim(),
          lastName: _newLastNameController.text.trim(),
          phone: _newPhoneController.text.trim(),
        );
        targetId = created.id;
      } else {
        targetId = _target!.id;
      }

      final result = await _service.transfer(
        widget.memberId,
        toMemberId: targetId,
        feeInPaise: _feePaise ?? 0,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, result);
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
    final target = _target;
    final showOutcome = _mode == _TargetMode.existing
        ? target != null
        : _newMemberValid;
    final receivingName = _mode == _TargetMode.existing
        ? (target != null ? '${target.firstName} ${target.lastName}' : '')
        : '${_newFirstNameController.text.trim()} ${_newLastNameController.text.trim()}'
              .trim();

    return LifecycleDialogShell(
      title: 'Transfer membership',
      subtitle: 'From ${widget.memberName}',
      icon: Icons.swap_calls,
      accent: AppColors.warning,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Transfer',
          loading: _saving,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleNotice(
            tone: LifecycleTone.warning,
            text:
                'The remaining validity moves to the receiving member. This membership is terminated.',
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Transfer to'),
          AppSpacing.gapXs,
          _ModeToggle(mode: _mode, onChanged: _switchMode),
          AppSpacing.gapMd,

          if (_mode == _TargetMode.existing) ...[
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            if (target == null && _results.isNotEmpty) ...[
              AppSpacing.gapSm,
              for (final m in _results) ...[
                _MemberOption(
                  member: m,
                  onTap: () => setState(() {
                    _target = m;
                    _results = [];
                    _searchController.text = '${m.firstName} ${m.lastName}';
                  }),
                ),
                AppSpacing.gapXs,
              ],
            ],
          ] else ...[
            // New member: the same minimum information Add Member requires.
            // No plan, no dates — the transfer below is what gives them one.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newFirstNameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'First name'),
                  ),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: TextField(
                    controller: _newLastNameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Last name'),
                  ),
                ),
              ],
            ),
            AppSpacing.gapSm,
            TextField(
              controller: _newPhoneController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Phone number'),
            ),
          ],

          if (showOutcome) ...[
            AppSpacing.gapLg,
            const LifecycleFieldLabel('Transfer fee (₹)'),
            AppSpacing.gapXs,
            TextField(
              controller: _feeController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                helperText:
                    'Charged by the gym for processing — optional, defaults to 0',
              ),
            ),
            AppSpacing.gapMd,
            LifecycleOutcome(
              emphasisColor: AppColors.warning,
              rows: [
                ('Receiving member', receivingName),
                if (_mode == _TargetMode.newMember)
                  ('Status', 'New member — created on transfer'),
                if (widget.expiryDate != null)
                  ('Validity moving', 'until ${widget.expiryDate}'),
                if ((_feePaise ?? 0) > 0)
                  ('Transfer fee', formatRupees((_feePaise ?? 0) / 100)),
                ('${widget.memberName} becomes', 'Terminated'),
              ],
            ),
            AppSpacing.gapSm,
            LifecycleNotice(
              tone: LifecycleTone.info,
              text: _mode == _TargetMode.existing
                  ? 'The receiving member must not already have an active membership.'
                  : 'A new member record is created, then the membership is transferred to them.',
            ),
            AppSpacing.gapLg,
            const LifecycleFieldLabel('Reason (optional)'),
            AppSpacing.gapXs,
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                hintText: 'Relocating, gifted to family…',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _TargetMode mode;
  final ValueChanged<_TargetMode> onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeButton(
            label: 'Existing member',
            selected: mode == _TargetMode.existing,
            onTap: () => onChanged(_TargetMode.existing),
          ),
        ),
        AppSpacing.gapXs,
        Expanded(
          child: _ModeButton(
            label: 'New member',
            selected: mode == _TargetMode.newMember,
            onTap: () => onChanged(_TargetMode.newMember),
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MemberOption extends StatelessWidget {
  final Member member;
  final VoidCallback onTap;

  const _MemberOption({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${member.firstName} ${member.lastName}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              member.status,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
