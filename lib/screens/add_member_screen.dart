import 'package:flutter/material.dart';

import '../models/plan.dart';
import '../services/api_response.dart';
import '../services/member_service.dart';
import '../services/plan_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spacing.dart' show AppSpacing;
import '../utils/validators.dart';
import '../widgets/error_banner.dart';

/// Shows the "add member" form as a centered modal dialog — matching the
/// existing CollectPaymentDialog/RenewDialog convention — instead of
/// pushing a full-page route that replaces the whole window.
Future<bool?> showAddMemberDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const AddMemberDialog(),
  );
}

class AddMemberDialog extends StatefulWidget {
  const AddMemberDialog({super.key});

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final _formKey = GlobalKey<FormState>();

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final addressController = TextEditingController();

  String? _gender;
  int? _planId;
  DateTime _startDate = DateTime.now();
  DateTime? _expiryDate;

  List<Plan> _plans = [];
  bool _loadingPlans = true;
  bool _isLoading = false;
  String? _error;

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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPlans = false);
    }
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : (_expiryDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _expiryDate = picked;
      }
    });
  }

  Future<void> saveMember() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await MemberService().createMember(
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        phone: phoneController.text.trim(),
        email: emailController.text.trim(),
        address: addressController.text.trim(),
        gender: _gender,
        membershipPlanId: _planId,
        startDate: _startDate,
        expiryDate: _expiryDate,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : "Couldn't add this member. Please try again.";
      });
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary),
                      AppSpacing.hGapSm,
                      const Text('Add Member', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ],
                  ),

                  AppSpacing.gapLg,

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: firstNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'First Name'),
                          validator: (v) => Validators.required(v, 'First name'),
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: TextFormField(
                          controller: lastNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Last Name'),
                          validator: (v) => Validators.required(v, 'Last name'),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    validator: Validators.phone,
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email (optional)'),
                    validator: Validators.emailOptional,
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: addressController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Address (optional)'),
                    onFieldSubmitted: (_) => saveMember(),
                  ),
                  AppSpacing.gapMd,

                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(labelText: 'Gender (optional)'),
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                  AppSpacing.gapMd,

                  _loadingPlans
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        )
                      : DropdownButtonFormField<int>(
                          initialValue: _planId,
                          decoration: const InputDecoration(labelText: 'Membership Plan (optional)'),
                          items: _plans
                              .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                              .toList(),
                          onChanged: (v) => setState(() => _planId = v),
                        ),
                  AppSpacing.gapMd,

                  Row(
                    children: [
                      Expanded(
                        child: _DateField(
                          label: 'Start Date',
                          value: _formatDate(_startDate),
                          onTap: () => _pickDate(isStart: true),
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: _DateField(
                          label: 'Expiry Date (optional)',
                          value: _expiryDate == null ? 'Not set' : _formatDate(_expiryDate!),
                          onTap: () => _pickDate(isStart: false),
                        ),
                      ),
                    ],
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
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      AppSpacing.hGapSm,
                      ElevatedButton(
                        style: AppTheme.dialogActionButton,
                        onPressed: _isLoading ? null : saveMember,
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save Member'),
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

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value),
            const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
