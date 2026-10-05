import 'package:flutter/material.dart';

import '../models/plan.dart';
import '../services/api_response.dart';
import '../services/plan_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spacing.dart';
import '../utils/validators.dart';
import '../widgets/error_banner.dart';

/// Shows the "edit plan" form as a centered modal dialog, matching the
/// CollectPaymentDialog/AddMemberDialog convention.
Future<bool?> showEditPlanDialog(BuildContext context, Plan plan) {
  return showDialog<bool>(
    context: context,
    builder: (_) => EditPlanDialog(plan: plan),
  );
}

class EditPlanDialog extends StatefulWidget {
  final Plan plan;

  const EditPlanDialog({super.key, required this.plan});

  @override
  State<EditPlanDialog> createState() => _EditPlanDialogState();
}

class _EditPlanDialogState extends State<EditPlanDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController nameController;
  late TextEditingController descriptionController;
  late TextEditingController durationController;
  late TextEditingController priceController;

  bool isActive = true;
  bool isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.plan.name);
    descriptionController = TextEditingController(
      text: widget.plan.description ?? '',
    );
    durationController = TextEditingController(
      text: widget.plan.durationDays.toString(),
    );
    priceController = TextEditingController(
      text: widget.plan.priceInRupees.toString(),
    );

    isActive = widget.plan.isActive;
  }

  Future<void> updatePlan() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      await PlanService().updatePlan(
        planId: widget.plan.id,
        name: nameController.text.trim(),
        description: descriptionController.text.trim(),
        durationDays: int.parse(durationController.text.trim()),
        priceInRupees: double.parse(priceController.text.trim()),
        isActive: isActive,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : "Couldn't update this plan. Please try again.";
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    durationController.dispose();
    priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
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
                      Icon(Icons.edit_rounded, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'Edit Membership Plan',
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
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
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
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Price (₹)'),
                    validator: (v) => Validators.positiveNumber(v, 'Price'),
                  ),

                  AppSpacing.gapSm,

                  SwitchListTile(
                    value: isActive,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    onChanged: (value) => setState(() => isActive = value),
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
                        onPressed: isLoading ? null : updatePlan,
                        child: isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Update Plan'),
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
