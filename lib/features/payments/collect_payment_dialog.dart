import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/plan.dart';
import '../../services/api_response.dart';
import '../../services/payment_service.dart';
import '../../services/plan_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';

/// Shows the Collect Payment dialog.
/// Returns true if payment was successfully collected, false/null otherwise.
///
/// One click → one atomic backend transaction:
///   1. Create Payment
///   2. Create Renewal linked to that payment
///   3. Update Member expiry
Future<bool?> showCollectPaymentDialog(
  BuildContext context, {
  required Member member,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => CollectPaymentDialog(member: member),
  );
}

class CollectPaymentDialog extends StatefulWidget {
  final Member member;

  const CollectPaymentDialog({super.key, required this.member});

  @override
  State<CollectPaymentDialog> createState() =>
      _CollectPaymentDialogState();
}

class _CollectPaymentDialogState extends State<CollectPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  List<Plan> _plans = [];
  bool _loadingPlans = true;
  bool _saving = false;

  int? _selectedPlanId;
  String _paymentMode = 'cash';
  String? _errorText;

  static const _modes = [
    ('cash', 'Cash'),
    ('upi', 'UPI'),
    ('credit_card', 'Credit Card'),
    ('debit_card', 'Debit Card'),
    ('bank_transfer', 'Bank Transfer'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await PlanService().getActivePlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loadingPlans = false;
        // Pre-select the member's current plan if it's still active.
        if (widget.member.membershipPlanId != null) {
          final match = plans.where(
            (p) => p.id == widget.member.membershipPlanId,
          );
          if (match.isNotEmpty) {
            _selectedPlanId = match.first.id;
            _amountController.text =
                match.first.priceInRupees.toStringAsFixed(0);
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPlans = false);
    }
  }

  void _onPlanChanged(int? id) {
    setState(() {
      _selectedPlanId = id;
      final match = _plans.where((p) => p.id == id);
      if (match.isNotEmpty) {
        _amountController.text =
            match.first.priceInRupees.toStringAsFixed(0);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _errorText = null);
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await PaymentService().collectPayment(
        memberId: widget.member.id,
        planId: _selectedPlanId!,
        amountInRupees: amount,
        paymentMode: _paymentMode,
        referenceNumber: _referenceController.text.trim(),
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = e is ApiException ? e.message : "Couldn't collect this payment. Please try again.";
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Header ────────────────────────────────────────────────
                Row(
                  children: [
                    const Icon(
                      Icons.payment_rounded,
                      color: AppColors.primary,
                    ),
                    AppSpacing.hGapSm,
                    const Text(
                      'Collect Payment',
                      style: AppTextStyles.sectionTitle,
                    ),
                  ],
                ),

                AppSpacing.gapSm,

                Text(
                  widget.member.memberName,
                  style: TextStyle(color: Colors.grey.shade600),
                ),

                if (widget.member.membershipPlanName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Current Plan: ${widget.member.membershipPlanName}',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],

                AppSpacing.gapXl,

                // ── Plan selector ──────────────────────────────────────────
                _loadingPlans
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : DropdownButtonFormField<int>(
                        initialValue: _selectedPlanId,
                        decoration: const InputDecoration(
                          labelText: 'Plan',
                        ),
                        items: _plans
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  '${p.name} (₹${p.priceInRupees.toStringAsFixed(0)})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _onPlanChanged,
                        validator: (v) => v == null ? 'Please select a plan' : null,
                      ),

                AppSpacing.gapLg,

                // ── Amount ─────────────────────────────────────────────────
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (v) => Validators.positiveNumber(v, 'Amount'),
                ),

                AppSpacing.gapLg,

                // ── Payment mode ───────────────────────────────────────────
                DropdownButtonFormField<String>(
                  initialValue: _paymentMode,
                  decoration: const InputDecoration(
                    labelText: 'Payment Mode',
                  ),
                  items: _modes
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.$1,
                          child: Text(m.$2),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _paymentMode = v);
                  },
                ),

                AppSpacing.gapLg,

                // ── Reference (optional) ────────────────────────────────────
                TextFormField(
                  controller: _referenceController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Reference Number (optional)',
                    hintText: 'UPI / bank transaction ID',
                  ),
                ),

                AppSpacing.gapLg,

                // ── Notes (optional) ────────────────────────────────────────
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),

                // ── Error ──────────────────────────────────────────────────
                if (_errorText != null) ...[
                  AppSpacing.gapMd,
                  Text(
                    _errorText!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ],

                AppSpacing.gapXl,

                // ── Actions ────────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    AppSpacing.hGapMd,
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        text: 'Save',
                        icon: Icons.check_rounded,
                        loading: _saving,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

// Extension to get member's full name — matches what Member.fromJson provides.
extension _MemberName on Member {
  String get memberName => '$firstName $lastName';
}
