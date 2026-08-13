import 'package:flutter/material.dart';

import '../services/api_response.dart';
import '../services/plan_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spacing.dart';
import '../utils/validators.dart';
import '../widgets/error_banner.dart';

/// Shows the "add plan" form as a centered modal dialog, matching the
/// CollectPaymentDialog/AddMemberDialog convention.
Future<bool?> showAddPlanDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const AddPlanDialog(),
  );
}

class AddPlanDialog extends StatefulWidget {
  const AddPlanDialog({super.key});

  @override
  State<AddPlanDialog> createState() => _AddPlanDialogState();
}

class _AddPlanDialogState extends State<AddPlanDialog> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final priceController = TextEditingController();
  final durationController = TextEditingController();
  final descriptionController = TextEditingController();

  bool isLoading = false;
  String? _error;

  Future<void> savePlan() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      await PlanService().createPlan(
        name: nameController.text.trim(),
        priceInRupees: double.parse(priceController.text.trim()),
        durationDays: int.parse(durationController.text.trim()),
        description: descriptionController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : "Couldn't create this plan. Please try again.";
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    priceController.dispose();
    durationController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Add Membership Plan',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  AppSpacing.gapLg,

                  TextFormField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Plan Name'),
                    validator: (v) => Validators.required(v, 'Plan name'),
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Price (₹)'),
                    validator: (v) => Validators.positiveNumber(v, 'Price'),
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Duration (Days)',
                    ),
                    validator: (v) => Validators.positiveInteger(v, 'Duration'),
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: descriptionController,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                  ),

                  if (_error != null) ...[
                    AppSpacing.gapMd,
                    ErrorBanner.inline(message: _error!),
                  ],

                  AppSpacing.gapXl,

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      AppSpacing.hGapSm,
                      ElevatedButton(
                        style: AppTheme.dialogActionButton,
                        onPressed: isLoading ? null : savePlan,
                        child: isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save Plan'),
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
