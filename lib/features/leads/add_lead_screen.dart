import 'package:flutter/material.dart';

import '../../services/api_response.dart';
import '../../services/lead_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/error_banner.dart';

import 'lead_pipeline_constants.dart';

/// Shows the "new lead" form as a centered modal dialog, matching the
/// CollectPaymentDialog/AddMemberDialog convention.
Future<bool?> showAddLeadDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const AddLeadDialog(),
  );
}

class AddLeadDialog extends StatefulWidget {
  const AddLeadDialog({super.key});

  @override
  State<AddLeadDialog> createState() => _AddLeadDialogState();
}

class _AddLeadDialogState extends State<AddLeadDialog> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();

  String _source = 'walk_in';
  String? _goal;
  String? _gender;
  DateTime? _trialDate;
  DateTime? _followUpDate;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _fmt(DateTime d) {
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month]} ${d.year}';
  }

  Future<void> _pickDate(bool isTrial) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isTrial) {
          _trialDate = picked;
        } else {
          _followUpDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'source': _source,
        if (_emailController.text.trim().isNotEmpty) 'email': _emailController.text.trim(),
        if (_goal != null) 'goal': _goal,
        if (_gender != null) 'gender': _gender,
        if (_notesController.text.trim().isNotEmpty) 'notes': _notesController.text.trim(),
        if (_trialDate != null) 'trial_date': _iso(_trialDate!),
        if (_followUpDate != null) 'follow_up_date': _iso(_followUpDate!),
      };

      await LeadService().createLead(data);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ApiException ? e.message : "Couldn't add this lead. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
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
                  const Row(
                    children: [
                      Icon(Icons.person_add_rounded, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('New Lead', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ],
                  ),

                  AppSpacing.gapLg,

                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                    validator: (v) => Validators.required(v, 'Name'),
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                    validator: Validators.phone,
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                      prefixIcon: Icon(Icons.email_rounded),
                    ),
                    validator: Validators.emailOptional,
                  ),
                  AppSpacing.gapMd,

                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(
                      labelText: 'Gender (optional)',
                      prefixIcon: Icon(Icons.wc_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),

                  AppSpacing.gapMd,

                  DropdownButtonFormField<String>(
                    initialValue: _source,
                    decoration: const InputDecoration(
                      labelText: 'Source',
                      prefixIcon: Icon(Icons.sensors_rounded),
                    ),
                    items: kLeadSources
                        .map((s) => DropdownMenuItem(value: s['value'], child: Text(s['label']!)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _source = v);
                    },
                  ),
                  AppSpacing.gapMd,

                  DropdownButtonFormField<String>(
                    initialValue: _goal,
                    decoration: const InputDecoration(
                      labelText: 'Goal (optional)',
                      prefixIcon: Icon(Icons.flag_rounded),
                    ),
                    items: kLeadGoals
                        .map((g) => DropdownMenuItem(value: g['value'], child: Text(g['label']!)))
                        .toList(),
                    onChanged: (v) => setState(() => _goal = v),
                  ),

                  AppSpacing.gapMd,

                  InkWell(
                    onTap: () => _pickDate(true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Trial Date (optional)',
                        prefixIcon: Icon(Icons.fitness_center_rounded),
                      ),
                      child: Text(
                        _trialDate != null ? _fmt(_trialDate!) : 'Pick a date',
                        style: TextStyle(color: _trialDate != null ? Colors.black87 : Colors.grey.shade500),
                      ),
                    ),
                  ),
                  AppSpacing.gapMd,

                  InkWell(
                    onTap: () => _pickDate(false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Follow-up Date (optional)',
                        prefixIcon: Icon(Icons.event_rounded),
                      ),
                      child: Text(
                        _followUpDate != null ? _fmt(_followUpDate!) : 'Pick a date',
                        style: TextStyle(color: _followUpDate != null ? Colors.black87 : Colors.grey.shade500),
                      ),
                    ),
                  ),

                  AppSpacing.gapMd,

                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.notes_rounded),
                      alignLabelWithHint: true,
                    ),
                  ),

                  if (_error != null) ...[
                    AppSpacing.gapMd,
                    ErrorBanner.inline(message: _error!),
                  ],

                  AppSpacing.gapXl,

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      AppSpacing.hGapSm,
                      Expanded(
                        flex: 2,
                        child: AppButton(
                          text: 'Register Lead',
                          icon: Icons.person_add_rounded,
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
