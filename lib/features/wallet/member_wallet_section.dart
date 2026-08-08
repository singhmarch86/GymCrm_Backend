import 'package:flutter/material.dart';

import '../../models/wallet.dart';
import '../../services/api_response.dart';
import '../../services/wallet_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart';

/// A member's stored credit, shown on their profile.
///
/// The ledger is displayed rather than just the balance, because the whole
/// point of the design is that a balance is explainable — showing only the
/// number would throw away what it is for.
class MemberWalletSection extends StatefulWidget {
  final int memberId;
  const MemberWalletSection({super.key, required this.memberId});

  @override
  State<MemberWalletSection> createState() => _MemberWalletSectionState();
}

class _MemberWalletSectionState extends State<MemberWalletSection> {
  final _service = WalletService();
  Wallet? _wallet;
  bool _loading = true;
  String? _error;

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
      final w = await _service.get(widget.memberId);
      if (!mounted) return;
      setState(() {
        _wallet = w;
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

  Future<void> _topUp() async {
    final result = await showDialog<_WalletAction>(
      context: context,
      builder: (_) => const _WalletActionDialog(kind: _WalletActionKind.topUp),
    );
    if (result == null) return;
    await _run(() => _service.topUp(widget.memberId,
        amountInPaise: result.amountInPaise, reason: result.reason));
  }

  Future<void> _spend() async {
    final result = await showDialog<_WalletAction>(
      context: context,
      builder: (_) => _WalletActionDialog(
        kind: _WalletActionKind.spend,
        availableInPaise: _wallet?.balanceInPaise ?? 0,
      ),
    );
    if (result == null) return;
    await _run(() => _service.spend(widget.memberId,
        amountInPaise: result.amountInPaise, reason: result.reason));
  }

  Future<void> _adjust() async {
    final result = await showDialog<_WalletAction>(
      context: context,
      builder: (_) => const _WalletActionDialog(kind: _WalletActionKind.adjust),
    );
    if (result == null) return;
    await _run(() => _service.adjust(widget.memberId,
        deltaInPaise: result.amountInPaise, reason: result.reason));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _wallet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Wallet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            if (!_loading && _error == null)
              TextButton.icon(
                onPressed: _topUp,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Top up'),
              ),
          ],
        ),
        AppSpacing.gapXs,

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_error != null)
          Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger))
        else if (w != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: w.hasCredit ? AppColors.successLight : AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: w.hasCredit ? AppColors.success : AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 20, color: w.hasCredit ? AppColors.success : AppColors.textSecondary),
                AppSpacing.gapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatRupees(w.balanceInRupees),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: w.hasCredit ? AppColors.success : AppColors.textSecondary,
                          )),
                      const Text('available credit',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (w.hasCredit)
                  TextButton(onPressed: _spend, child: const Text('Spend')),
                IconButton(
                  tooltip: 'Correct the balance',
                  icon: const Icon(Icons.tune, size: 18),
                  onPressed: _adjust,
                ),
              ],
            ),
          ),

          if (w.transactions.isEmpty) ...[
            AppSpacing.gapSm,
            const Text('No wallet activity yet.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ] else ...[
            AppSpacing.gapSm,
            for (final t in w.transactions.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      t.isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 14,
                      color: t.isCredit ? AppColors.success : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.reason != null && t.reason!.isNotEmpty ? '${t.label} — ${t.reason}' : t.label,
                        style: const TextStyle(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${t.isCredit ? '+' : ''}${formatRupees(t.amountInPaise / 100)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.isCredit ? AppColors.success : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ],
    );
  }
}

// ─── Action dialog ───────────────────────────────────────────────────────────

enum _WalletActionKind { topUp, spend, adjust }

class _WalletAction {
  final int amountInPaise;
  final String reason;
  _WalletAction(this.amountInPaise, this.reason);
}

class _WalletActionDialog extends StatefulWidget {
  final _WalletActionKind kind;
  final int availableInPaise;

  const _WalletActionDialog({required this.kind, this.availableInPaise = 0});

  @override
  State<_WalletActionDialog> createState() => _WalletActionDialogState();
}

class _WalletActionDialogState extends State<_WalletActionDialog> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isDeduction = false; // adjustments only
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
        _WalletActionKind.topUp => 'Add credit',
        _WalletActionKind.spend => 'Spend from wallet',
        _WalletActionKind.adjust => 'Correct the balance',
      };

  bool get _reasonRequired => widget.kind == _WalletActionKind.adjust;

  void _submit() {
    final rupees = double.tryParse(_amountController.text.trim()) ?? 0;
    final reason = _reasonController.text.trim();

    if (rupees <= 0) {
      setState(() => _error = 'Enter an amount greater than 0');
      return;
    }
    if (_reasonRequired && reason.isEmpty) {
      // Mirrors the server rule: an unexplained balance change is exactly what
      // the ledger exists to prevent.
      setState(() => _error = 'A reason is required for a correction');
      return;
    }
    if (widget.kind == _WalletActionKind.spend &&
        (rupees * 100).round() > widget.availableInPaise) {
      setState(() => _error = 'That is more than the available credit');
      return;
    }

    var paise = (rupees * 100).round();
    if (widget.kind == _WalletActionKind.adjust && _isDeduction) paise = -paise;
    Navigator.pop(context, _WalletAction(paise, reason));
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: _title,
      subtitle: widget.kind == _WalletActionKind.spend
          ? '${formatRupees(widget.availableInPaise / 100)} available'
          : 'Stored credit on the account',
      icon: Icons.account_balance_wallet_outlined,
      accent: widget.kind == _WalletActionKind.topUp ? AppColors.success : AppColors.primary,
      error: _error,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        AppButton(text: 'Confirm', onPressed: _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.kind == _WalletActionKind.adjust) ...[
            const LifecycleFieldLabel('Direction'),
            AppSpacing.gapXs,
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Add')),
                ButtonSegment(value: true, label: Text('Deduct')),
              ],
              selected: {_isDeduction},
              onSelectionChanged: (s) => setState(() => _isDeduction = s.first),
            ),
            AppSpacing.gapLg,
          ],

          const LifecycleFieldLabel('Amount (₹)'),
          AppSpacing.gapXs,
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofillHints: const [],
          ),
          AppSpacing.gapLg,

          LifecycleFieldLabel(_reasonRequired ? 'Reason' : 'Reason (optional)'),
          AppSpacing.gapXs,
          TextField(
            controller: _reasonController,
            autofillHints: const [],
            decoration: InputDecoration(
              hintText: switch (widget.kind) {
                _WalletActionKind.topUp => 'e.g. cash top-up at counter',
                _WalletActionKind.spend => 'e.g. protein shake',
                _WalletActionKind.adjust => 'e.g. correcting a mistaken top-up',
              },
            ),
          ),
          AppSpacing.gapMd,

          const LifecycleNotice(
            tone: LifecycleTone.info,
            text: 'Every change is recorded, so the balance can always be explained. '
                'The wallet can never go below zero.',
          ),
        ],
      ),
    );
  }
}
