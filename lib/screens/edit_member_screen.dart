import 'package:flutter/material.dart';

import '../models/member.dart';
import '../models/plan.dart';
import '../services/api_response.dart';
import '../services/member_service.dart';
import '../services/plan_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spacing.dart' show AppSpacing;
import '../utils/validators.dart';
import '../widgets/error_banner.dart';
import '../utils/money.dart';

/// Shows the "edit member" form as a centered modal dialog, matching the
/// CollectPaymentDialog/AddMemberDialog convention.
Future<bool?> showEditMemberDialog(BuildContext context, Member member) {
  return showDialog<bool>(
    context: context,
    builder: (_) => EditMemberDialog(member: member),
  );
}

class EditMemberDialog extends StatefulWidget {
  final Member member;

  const EditMemberDialog({super.key, required this.member});

  @override
  State<EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends State<EditMemberDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController firstNameController;
  late TextEditingController lastNameController;
  late TextEditingController phoneController;

  bool isLoading = false;
  String? _error;

  String status = 'active';
  List<Plan> plans = [];
  bool _loadingPlans = true;
  int? selectedPlanId;

  @override
  void initState() {
    super.initState();

    firstNameController = TextEditingController(text: widget.member.firstName);
    lastNameController = TextEditingController(text: widget.member.lastName);
    phoneController = TextEditingController(text: widget.member.phone);

    status = widget.member.status;
    selectedPlanId = widget.member.membershipPlanId;

    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final data = await PlanService().getActivePlans();
      if (!mounted) return;
      setState(() {
        plans = data;
        _loadingPlans = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPlans = false);
    }
  }

  Future<void> updateMember() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      await MemberService().updateMember(
        memberId: widget.member.id,
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        phone: phoneController.text.trim(),
        status: status,
        membershipPlanId: selectedPlanId,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : "Couldn't update this member. Please try again.";
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
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
                        'Edit Member',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  AppSpacing.gapLg,

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: firstNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'First Name',
                          ),
                          validator: (v) =>
                              Validators.required(v, 'First name'),
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: TextFormField(
                          controller: lastNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Last Name',
                          ),
                          validator: (v) => Validators.required(v, 'Last name'),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    validator: Validators.phone,
                    onFieldSubmitted: (_) => updateMember(),
                  ),
                  AppSpacing.gapMd,

                  _loadingPlans
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : DropdownButtonFormField<int>(
                          initialValue: selectedPlanId,
                          decoration: const InputDecoration(
                            labelText: 'Membership Plan',
                          ),
                          items: plans
                              .map(
                                (plan) => DropdownMenuItem(
                                  value: plan.id,
                                  child: Text(
                                    '${plan.name} (${moneyR(plan.priceInRupees)})',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => selectedPlanId = value),
                        ),

                  AppSpacing.gapMd,

                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(
                        value: 'expired',
                        child: Text('Expired'),
                      ),
                      DropdownMenuItem(
                        value: 'inactive',
                        child: Text('Inactive'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => status = value);
                    },
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
                        onPressed: isLoading ? null : updateMember,
                        child: isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Update Member'),
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
