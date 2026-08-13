import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/pt_package.dart';
import '../../models/trainer.dart';
import '../../services/api_response.dart';
import '../../services/member_service.dart';
import '../../services/pt_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Sells a fixed-session PT package to a member. `totalSessions` is set once
/// here — there's no top-up later, only a fresh package. See FR-03 §2.
Future<PtPackage?> showSellPackageDialog(
  BuildContext context, {
  required List<Trainer> trainers,
}) {
  return showDialog<PtPackage>(
    context: context,
    builder: (_) => SellPackageDialog(trainers: trainers),
  );
}

class SellPackageDialog extends StatefulWidget {
  final List<Trainer> trainers;
  const SellPackageDialog({super.key, required this.trainers});

  @override
  State<SellPackageDialog> createState() => _SellPackageDialogState();
}

class _SellPackageDialogState extends State<SellPackageDialog> {
  final _service = PtService();
  final _memberService = MemberService();
  final _memberSearchController = TextEditingController();
  final _packageNameController = TextEditingController(text: 'PT Package');
  final _sessionsController = TextEditingController(text: '10');
  final _amountController = TextEditingController();

  /// How the money was taken. Empty means it was not — the server raises a
  /// due, and the sale shows up in the collections queue instead of vanishing.
  /// Never pre-set to cash: assuming payment for an unpaid package is the leak
  /// this closes.
  String _paymentMode = '';

  /// Blank means the full price. A smaller figure is a part payment, and the
  /// balance is raised as a due automatically.
  final _paidController = TextEditingController();

  Timer? _debounce;
  List<Member> _results = [];
  Member? _member;
  int? _trainerId;
  DateTime? _expiryDate;

  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.trainers.isNotEmpty) _trainerId = widget.trainers.first.id;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _memberSearchController.dispose();
    _packageNameController.dispose();
    _sessionsController.dispose();
    _amountController.dispose();
    _paidController.dispose();
    super.dispose();
  }

  void _onMemberSearchChanged(String q) {
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
        _results = all.take(6).toList();
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

  Future<void> _submit() async {
    final member = _member;
    final trainerId = _trainerId;
    final packageName = _packageNameController.text.trim();
    final sessions = int.tryParse(_sessionsController.text.trim()) ?? 0;
    final rupees = double.tryParse(_amountController.text.trim()) ?? -1;

    if (member == null) {
      setState(() => _error = 'Select a member');
      return;
    }
    if (trainerId == null) {
      setState(() => _error = 'Select a trainer');
      return;
    }
    if (packageName.isEmpty) {
      setState(() => _error = 'Package name is required');
      return;
    }
    if (sessions <= 0) {
      setState(() => _error = 'Total sessions must be greater than 0');
      return;
    }
    if (rupees < 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }

    final priceInPaise = (rupees * 100).round();

    // Blank means "all of it", which is the common case at the desk.
    final paidText = _paidController.text.trim();
    final paidInPaise = paidText.isEmpty
        ? priceInPaise
        : ((double.tryParse(paidText) ?? -1) * 100).round();

    if (_paymentMode.isNotEmpty && paidInPaise <= 0) {
      setState(
        () => _error =
            'Enter how much was taken, or leave it blank '
            'for the full amount',
      );
      return;
    }
    if (paidInPaise > priceInPaise) {
      setState(() => _error = 'Amount taken is more than the package price');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final pkg = await _service.createPackage(
        memberId: member.id,
        trainerId: trainerId,
        packageName: packageName,
        totalSessions: sessions,
        amountInPaise: priceInPaise,
        expiryDate: _expiryDate,
        paymentMode: _paymentMode,
        amountPaidInPaise: _paymentMode.isEmpty ? 0 : paidInPaise,
      );
      if (!mounted) return;
      Navigator.pop(context, pkg);
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
      title: 'Sell PT package',
      subtitle: 'A fixed set of sessions with one trainer',
      icon: Icons.fitness_center_rounded,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Sell',
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Member'),
          AppSpacing.gapXs,
          TextField(
            controller: _memberSearchController,
            onChanged: _onMemberSearchChanged,
            autofillHints: const [],
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
          if (_member == null && _results.isNotEmpty) ...[
            AppSpacing.gapSm,
            for (final m in _results) ...[
              InkWell(
                onTap: () => setState(() {
                  _member = m;
                  _results = [];
                  _memberSearchController.text = '${m.firstName} ${m.lastName}';
                }),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${m.firstName} ${m.lastName}',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ),
              AppSpacing.gapXs,
            ],
          ],
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Trainer'),
          AppSpacing.gapXs,
          DropdownButtonFormField<int>(
            initialValue: _trainerId,
            isExpanded: true,
            items: widget.trainers
                .map(
                  (t) => DropdownMenuItem(value: t.id, child: Text(t.fullName)),
                )
                .toList(),
            onChanged: (v) => setState(() => _trainerId = v),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Package name'),
          AppSpacing.gapXs,
          TextField(
            controller: _packageNameController,
            autofillHints: const [],
          ),
          AppSpacing.gapLg,

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Total sessions'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _sessionsController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Amount (₹)'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Expiry date (optional)'),
          AppSpacing.gapXs,
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 90)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              );
              if (picked != null) setState(() => _expiryDate = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                suffixIcon: Icon(Icons.calendar_today, size: 16),
              ),
              child: Text(
                _expiryDate != null ? formatDate(_expiryDate!) : 'No expiry',
              ),
            ),
          ),
          AppSpacing.gapLg,

          // The money. Present on the sale itself rather than as a follow-up
          // step somebody can skip: a package with no payment row is money the
          // gym can neither count nor chase, and that was the state of every
          // package in the system before this.
          const LifecycleFieldLabel('Money taken now'),
          AppSpacing.gapXs,
          DropdownButtonFormField<String>(
            initialValue: _paymentMode,
            items: const [
              // First, and the default, because it is the honest answer when
              // nobody has handed anything over. The server raises a due and
              // the sale appears in Collect.
              DropdownMenuItem(
                value: '',
                child: Text('Nothing yet — raise a due'),
              ),
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'upi', child: Text('UPI')),
              DropdownMenuItem(
                value: 'credit_card',
                child: Text('Credit card'),
              ),
              DropdownMenuItem(value: 'debit_card', child: Text('Debit card')),
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text('Bank transfer'),
              ),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() => _paymentMode = v ?? ''),
          ),

          if (_paymentMode.isNotEmpty) ...[
            AppSpacing.gapMd,
            const LifecycleFieldLabel('How much (₹) — blank means all of it'),
            AppSpacing.gapXs,
            TextField(
              controller: _paidController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofillHints: const [],
              decoration: const InputDecoration(
                hintText: 'Leave blank for the full price',
              ),
            ),
            AppSpacing.gapXs,
            Text(
              'Less than the price is a part payment. The balance is raised as '
              'a due automatically, so it gets chased instead of forgotten.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Colors.grey.shade600,
              ),
            ),
          ] else ...[
            AppSpacing.gapXs,
            Text(
              'The full amount is raised as a due, dated today, and appears in '
              'Staff work → Collect.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Colors.grey.shade600,
              ),
            ),
          ],

          AppSpacing.gapMd,

          const LifecycleNotice(
            tone: LifecycleTone.info,
            text:
                'Booking an appointment never checks sessions remaining — '
                'only completing one does. Exhausted packages block further completions.',
          ),
        ],
      ),
    );
  }
}
