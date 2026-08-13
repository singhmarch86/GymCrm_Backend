import 'package:flutter/material.dart';

import '../../models/lifecycle_event.dart';
import '../../services/api_response.dart';
import '../../services/lifecycle_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import 'lifecycle_shared.dart';

/// Terminate dialog.
///
/// Termination is terminal — restoring a member means selling a new membership.
/// The dialog says so plainly and requires both a reason and an explicit typed
/// confirmation, because an accidental termination cannot be undone.
Future<MemberLifecycleResult?> showTerminateDialog(
  BuildContext context, {
  required int memberId,
  required String memberName,
}) {
  return showDialog<MemberLifecycleResult>(
    context: context,
    builder: (_) => TerminateDialog(memberId: memberId, memberName: memberName),
  );
}

class TerminateDialog extends StatefulWidget {
  final int memberId;
  final String memberName;

  const TerminateDialog({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  @override
  State<TerminateDialog> createState() => _TerminateDialogState();
}

class _TerminateDialogState extends State<TerminateDialog> {
  final _service = LifecycleService();
  final _reasonController = TextEditingController();
  final _feeController = TextEditingController(text: '0');
  final _confirmController = TextEditingController();

  TerminationQuote? _quote;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _confirmWord = 'TERMINATE';

  @override
  void initState() {
    super.initState();
    _reasonController.addListener(_onFormChanged);
    _confirmController.addListener(_onFormChanged);
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _feeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _load({int feeInPaise = 0}) async {
    try {
      final q = await _service.terminationQuote(
        widget.memberId,
        feeInPaise: feeInPaise,
      );
      if (!mounted) return;
      setState(() {
        _quote = q;
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

  int get _feePaise {
    final rupees = double.tryParse(_feeController.text.trim()) ?? 0;
    return (rupees * 100).round();
  }

  bool get _canSubmit =>
      _reasonController.text.trim().isNotEmpty &&
      _confirmController.text.trim().toUpperCase() == _confirmWord &&
      !_saving;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _service.terminate(
        widget.memberId,
        reason: _reasonController.text.trim(),
        terminationFeeInPaise: _feePaise,
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
    final q = _quote;

    return LifecycleDialogShell(
      title: 'Terminate membership',
      subtitle: widget.memberName,
      icon: Icons.cancel_outlined,
      accent: AppColors.danger,
      loading: _loading,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Terminate',
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
                'This cannot be undone. Restoring this member later means selling a new membership.',
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Reason (required)'),
          AppSpacing.gapXs,
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              hintText: 'Moved city, dissatisfied, medical…',
            ),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Termination fee (₹)'),
          AppSpacing.gapXs,
          TextField(
            controller: _feeController,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _load(feeInPaise: _feePaise),
            onEditingComplete: () => _load(feeInPaise: _feePaise),
            decoration: const InputDecoration(
              prefixText: '₹ ',
              helperText: 'Deducted from the refund',
            ),
          ),
          AppSpacing.gapLg,

          if (q != null)
            LifecycleOutcome(
              emphasisColor: AppColors.danger,
              rows: [
                ('Days remaining', '${q.remainingDays}'),
                ('Gross refund', formatRupees(q.grossRefundInPaise / 100)),
                ('Less fee', formatRupees(q.terminationFeeInPaise / 100)),
                ('Refund owed', formatRupees(q.netRefundInRupees)),
              ],
            ),
          AppSpacing.gapSm,
          const LifecycleNotice(
            tone: LifecycleTone.info,
            text:
                'The refund is recorded against this member, not paid out here. Settle it through Payments.',
          ),
          AppSpacing.gapLg,

          LifecycleFieldLabel('Type $_confirmWord to confirm'),
          AppSpacing.gapXs,
          TextField(
            controller: _confirmController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: _confirmWord),
          ),
        ],
      ),
    );
  }
}
