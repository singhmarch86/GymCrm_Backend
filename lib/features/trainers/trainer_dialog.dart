import 'package:flutter/material.dart';

import '../../models/trainer.dart';
import '../../services/api_response.dart';
import '../../services/trainer_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Add-trainer dialog. A trainer is a standalone roster entry — not a
/// `User` login — so this never touches auth or staff accounts.
Future<Trainer?> showCreateTrainerDialog(BuildContext context) {
  return showDialog<Trainer>(context: context, builder: (_) => const TrainerDialog());
}

/// Edit-trainer dialog — same form, pre-filled, plus an active/inactive
/// toggle. Never affects PT packages already tied to this trainer.
Future<Trainer?> showEditTrainerDialog(BuildContext context, Trainer existing) {
  return showDialog<Trainer>(context: context, builder: (_) => TrainerDialog(existing: existing));
}

class TrainerDialog extends StatefulWidget {
  final Trainer? existing;
  const TrainerDialog({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<TrainerDialog> createState() => _TrainerDialogState();
}

class _TrainerDialogState extends State<TrainerDialog> {
  final _service = TrainerService();
  late final _firstNameController = TextEditingController(text: widget.existing?.firstName ?? '');
  late final _lastNameController = TextEditingController(text: widget.existing?.lastName ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  late final _emailController = TextEditingController(text: widget.existing?.email ?? '');
  late final _specializationController =
      TextEditingController(text: widget.existing?.specialization ?? '');
  late final _commissionController =
      TextEditingController(text: widget.existing?.commissionPct?.toString() ?? '');
  late bool _isActive = (widget.existing?.status ?? 'active') == 'active';

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _specializationController.dispose();
    _commissionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();

    if (firstName.isEmpty) {
      setState(() => _error = 'First name is required');
      return;
    }
    if (lastName.isEmpty) {
      setState(() => _error = 'Last name is required');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'Phone is required');
      return;
    }
    final commissionText = _commissionController.text.trim();
    double? commission;
    if (commissionText.isNotEmpty) {
      commission = double.tryParse(commissionText);
      if (commission == null || commission < 0 || commission > 100) {
        setState(() => _error = 'Commission must be a number between 0 and 100');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final t = widget.isEdit
          ? await _service.updateTrainer(
              widget.existing!.id,
              firstName: firstName,
              lastName: lastName,
              phone: phone,
              email: _emailController.text.trim(),
              specialization: _specializationController.text.trim(),
              status: _isActive ? 'active' : 'inactive',
              commissionPct: commission,
            )
          : await _service.createTrainer(
              firstName: firstName,
              lastName: lastName,
              phone: phone,
              email: _emailController.text.trim(),
              specialization: _specializationController.text.trim(),
              commissionPct: commission,
            );
      if (!mounted) return;
      Navigator.pop(context, t);
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
      title: widget.isEdit ? 'Edit trainer' : 'New trainer',
      subtitle: widget.isEdit ? widget.existing!.fullName : 'Add someone to the PT roster',
      icon: Icons.sports_rounded,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: widget.isEdit ? 'Save' : 'Create',
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('First name'),
                    AppSpacing.gapXs,
                    TextField(controller: _firstNameController, autofillHints: const []),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Last name'),
                    AppSpacing.gapXs,
                    TextField(controller: _lastNameController, autofillHints: const []),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Phone'),
          AppSpacing.gapXs,
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [],
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Email (optional)'),
          AppSpacing.gapXs,
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [],
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Specialization (optional)'),
          AppSpacing.gapXs,
          TextField(
            controller: _specializationController,
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'Strength, Yoga, HIIT…'),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Commission % (optional)'),
          AppSpacing.gapXs,
          TextField(
            controller: _commissionController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofillHints: const [],
          ),

          if (widget.isEdit) ...[
            AppSpacing.gapLg,
            LifecycleNotice(
              tone: _isActive ? LifecycleTone.info : LifecycleTone.warning,
              text: _isActive
                  ? 'Active — can be assigned new PT packages.'
                  : 'Inactive — cannot be assigned new packages. Existing packages and appointments are unaffected.',
            ),
            AppSpacing.gapSm,
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
        ],
      ),
    );
  }
}
