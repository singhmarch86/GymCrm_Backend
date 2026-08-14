import 'package:flutter/material.dart';

import '../../models/plan.dart';
import '../../models/renewal_due.dart';
import '../../services/api_response.dart';
import '../../services/payment_service.dart';
import '../../services/plan_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../utils/money.dart';

/// Shows the Renew Membership dialog for [renewal] and returns true via
/// Navigator.pop if the renewal succeeded, so callers can refresh their list.
Future<bool?> showRenewDialog(
  BuildContext context, {
  required RenewalDue renewal,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => RenewDialog(renewal: renewal),
  );
}

class RenewDialog extends StatefulWidget {
  final RenewalDue renewal;

  const RenewDialog({super.key, required this.renewal});

  @override
  State<RenewDialog> createState() => _RenewDialogState();
}

class _RenewDialogState extends State<RenewDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  List<Plan> plans = [];
  bool loadingPlans = true;
  bool saving = false;

  int? selectedPlanId;
  DateTime startDate = DateTime.now();
  String _paymentMode = 'cash';

  String? errorText;

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
    selectedPlanId = widget.renewal.planId;
    loadPlans();
  }

  Future<void> loadPlans() async {
    try {
      final data = await PlanService().getActivePlans();

      if (!mounted) return;

      setState(() {
        plans = data;
        loadingPlans = false;

        // Pre-fill amount from the current/selected plan price, if known.
        final current = plans.where((p) => p.id == selectedPlanId);
        if (current.isNotEmpty) {
          _amountController.text = current.first.priceInRupees.toStringAsFixed(
            0,
          );
        }
      });
    } catch (e) {
      debugPrint('RENEW DIALOG — LOAD PLANS ERROR: $e');
      if (!mounted) return;
      setState(() {
        loadingPlans = false;
      });
    }
  }

  void onPlanChanged(int? planId) {
    setState(() {
      selectedPlanId = planId;

      final selected = plans.where((p) => p.id == planId);
      if (selected.isNotEmpty) {
        _amountController.text = selected.first.priceInRupees.toStringAsFixed(
          0,
        );
      }
    });
  }

  Future<void> pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (picked != null) {
      setState(() {
        startDate = picked;
      });
    }
  }

  Plan? get selectedPlan {
    final match = plans.where((p) => p.id == selectedPlanId);
    return match.isEmpty ? null : match.first;
  }

  /// Auto-calculated end date — start_date + plan.duration_days.
  /// This is a preview only; the backend is the source of truth for the
  /// actual calculation (max(current_expiry, today) + duration_days).
  DateTime? get previewEndDate {
    final plan = selectedPlan;
    if (plan == null) return null;
    return startDate.add(Duration(days: plan.durationDays));
  }

  String formatDate(DateTime d) {
    return "${d.day.toString().padLeft(2, '0')}/"
        "${d.month.toString().padLeft(2, '0')}/"
        "${d.year}";
  }

  String isoDate(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  Future<void> save() async {
    setState(() => errorText = null);
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());

    setState(() {
      saving = true;
      errorText = null;
    });

    try {
      // Single atomic backend transaction:
      //   1. Create Payment record (status = paid)
      //   2. Create Renewal linked to that payment
      //   3. Update Member expiry date
      // POST /api/v1/payments is the correct endpoint — it owns the
      // transaction. POST /api/v1/members/{id}/renew is the old sequential
      // path that creates a renewal only, with no payment record.
      await PaymentService().collectPayment(
        memberId: widget.renewal.id,
        planId: selectedPlanId!,
        amountInRupees: amount,
        paymentMode: _paymentMode,
        paymentDate: isoDate(startDate),
        referenceNumber: _referenceController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        errorText = e is ApiException
            ? e.message
            : "Couldn't renew this membership. Please try again.";
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  Row(
                    children: [
                      const Icon(
                        Icons.autorenew_rounded,
                        color: AppColors.primary,
                      ),
                      AppSpacing.hGapSm,
                      const Text(
                        "Renew Membership",
                        style: AppTextStyles.sectionTitle,
                      ),
                    ],
                  ),

                  AppSpacing.gapSm,

                  Text(
                    widget.renewal.memberName,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  AppSpacing.gapXl,

                  Text("Current Plan", style: AppTextStyles.caption),
                  AppSpacing.gapXs,
                  Text(
                    widget.renewal.planName ?? "No Plan",
                    style: AppTextStyles.cardTitle,
                  ),

                  AppSpacing.gapLg,

                  if (loadingPlans)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: selectedPlanId,
                      decoration: const InputDecoration(labelText: "New Plan"),
                      items: plans
                          .map(
                            (plan) => DropdownMenuItem<int>(
                              value: plan.id,
                              child: Text(
                                "${plan.name} (${moneyR(plan.priceInRupees)})",
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: onPlanChanged,
                      validator: (v) =>
                          v == null ? "Please select a plan" : null,
                    ),

                  AppSpacing.gapLg,

                  InkWell(
                    onTap: pickStartDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Start Date",
                      ),
                      child: Text(formatDate(startDate)),
                    ),
                  ),

                  AppSpacing.gapLg,

                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Amount Paid (₹)",
                      prefixIcon: Icon(Icons.currency_rupee_rounded),
                    ),
                    validator: (v) => Validators.positiveNumber(v, 'Amount'),
                  ),

                  AppSpacing.gapLg,

                  // Payment mode — required for the Payment record
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMode,
                    decoration: const InputDecoration(
                      labelText: "Payment Mode",
                    ),
                    items: _modes
                        .map(
                          (m) =>
                              DropdownMenuItem(value: m.$1, child: Text(m.$2)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _paymentMode = v);
                    },
                  ),

                  AppSpacing.gapLg,

                  // Reference number — optional, useful for UPI / bank
                  TextFormField(
                    controller: _referenceController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Reference Number (optional)",
                      hintText: "UPI / bank transaction ID",
                    ),
                  ),

                  AppSpacing.gapLg,

                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Notes (optional)",
                    ),
                  ),

                  AppSpacing.gapLg,

                  if (previewEndDate != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_available_rounded,
                            size: 18,
                            color: AppColors.success,
                          ),
                          AppSpacing.hGapSm,
                          Expanded(
                            child: Text(
                              "New expiry: ${formatDate(previewEndDate!)}",
                              style: const TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (errorText != null) ...[
                    AppSpacing.gapMd,
                    Text(
                      errorText!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ],

                  AppSpacing.gapXl,

                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(context, false),
                          child: const Text("Cancel"),
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        flex: 2,
                        child: AppButton(
                          text: "Save",
                          icon: Icons.check_rounded,
                          loading: saving,
                          onPressed: save,
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
