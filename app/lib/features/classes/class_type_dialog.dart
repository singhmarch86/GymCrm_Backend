import 'package:flutter/material.dart';

import '../../models/class_models.dart';
import '../../services/api_response.dart';
import '../../services/classes_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Create-class-type dialog. Centered Dialog, not a side panel — this app's
/// short forms all use this shape (see member_detail_screen.dart for why).
Future<ClassType?> showCreateClassTypeDialog(BuildContext context) {
  return showDialog<ClassType>(
    context: context,
    builder: (_) => const CreateClassTypeDialog(),
  );
}

/// Edit-class-type dialog — same form, pre-filled, plus an active/inactive
/// toggle. Editing never touches schedules or sessions already created from
/// this type; they hold their own snapshot taken at creation time
/// (FR-02 §0.1), so this only changes what happens from here on.
Future<ClassType?> showEditClassTypeDialog(
  BuildContext context,
  ClassType existing,
) {
  return showDialog<ClassType>(
    context: context,
    builder: (_) => CreateClassTypeDialog(existing: existing),
  );
}

class CreateClassTypeDialog extends StatefulWidget {
  final ClassType? existing;
  const CreateClassTypeDialog({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<CreateClassTypeDialog> createState() => _CreateClassTypeDialogState();
}

class _CreateClassTypeDialogState extends State<CreateClassTypeDialog> {
  final _service = ClassesService();
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _durationController = TextEditingController(
    text: '${widget.existing?.durationMinutes ?? 60}',
  );
  late final _capacityController = TextEditingController(
    text: '${widget.existing?.defaultCapacity ?? 12}',
  );
  late bool _isActive = widget.existing?.isActive ?? true;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  /// Never gate the button purely on live onChanged/setState reactivity — a
  /// browser autofilling a field (as this one hit: the Name field visibly
  /// showing "Yoga" from autofill while Flutter's controller still thought it
  /// was empty) can set the DOM value without firing the event Flutter
  /// listens for, leaving the button permanently disabled even though the
  /// field looks filled in. _submit() re-reads the controllers directly at
  /// tap time instead, so it's correct regardless of whether onChanged fired.
  bool get _canSubmit => !_saving;

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final duration = int.tryParse(_durationController.text.trim()) ?? 0;
    final capacity = int.tryParse(_capacityController.text.trim()) ?? 0;

    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (duration <= 0) {
      setState(() => _error = 'Duration must be greater than 0');
      return;
    }
    if (capacity <= 0) {
      setState(() => _error = 'Default capacity must be greater than 0');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ct = widget.isEdit
          ? await _service.updateClassType(
              widget.existing!.id,
              name: name,
              durationMinutes: duration,
              defaultCapacity: capacity,
              description: _descriptionController.text.trim(),
              isActive: _isActive,
            )
          : await _service.createClassType(
              name: name,
              durationMinutes: duration,
              defaultCapacity: capacity,
              description: _descriptionController.text.trim(),
            );
      if (!mounted) return;
      Navigator.pop(context, ct);
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
      title: widget.isEdit ? 'Edit class type' : 'New class type',
      subtitle: widget.isEdit
          ? widget.existing!.name
          : 'The offering — Yoga, Zumba, HIIT',
      icon: Icons.self_improvement,
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
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Name'),
          AppSpacing.gapXs,
          TextField(
            controller: _nameController,
            onChanged: (_) => setState(() {}),
            // Browsers will otherwise offer to autofill this from saved form
            // data — seen in practice filling in a previous class type's name
            // without notifying Flutter, leaving the field looking populated
            // while the app still thought it was empty.
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'Yoga'),
          ),
          AppSpacing.gapLg,

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Duration (min)'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [],
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Default capacity'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _capacityController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [],
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Description (optional)'),
          AppSpacing.gapXs,
          TextField(
            controller: _descriptionController,
            autofillHints: const [],
            decoration: const InputDecoration(
              hintText: 'What members should expect',
            ),
          ),

          if (widget.isEdit) ...[
            AppSpacing.gapLg,
            LifecycleNotice(
              tone: _isActive ? LifecycleTone.info : LifecycleTone.warning,
              text: _isActive
                  ? 'Active — can be used for new schedules.'
                  : 'Inactive — cannot be scheduled going forward. Existing schedules and sessions are unaffected.',
            ),
            AppSpacing.gapSm,
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Active',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
        ],
      ),
    );
  }
}
