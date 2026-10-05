import 'package:flutter/material.dart';

import '../../models/staff.dart';
import '../../services/api_response.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/error_banner.dart';

/// Add or edit a staff member. [existing] null means "add".
///
/// Password only appears when adding — changing it later is a deliberate,
/// separate "Reset password" action rather than something you can do by
/// accident while correcting a typo in someone's name.
Future<bool?> showStaffFormDialog(BuildContext context, {Staff? existing}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => StaffFormDialog(existing: existing),
  );
}

class StaffFormDialog extends StatefulWidget {
  final Staff? existing;

  const StaffFormDialog({super.key, this.existing});

  @override
  State<StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  final _password = TextEditingController();

  late String _role;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _role = e?.role ?? 'staff';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final svc = StaffService();
      if (_isEdit) {
        await svc.updateStaff(
          widget.existing!.id,
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          role: _role,
        );
      } else {
        await svc.createStaff(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          role: _role,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : "Couldn't save this staff member. Please try again.";
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
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
                      Icon(
                        _isEdit
                            ? Icons.edit_rounded
                            : Icons.person_add_alt_1_rounded,
                        color: AppColors.primary,
                      ),
                      AppSpacing.hGapSm,
                      Text(
                        _isEdit ? 'Edit Staff' : 'Add Staff',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  AppSpacing.gapLg,

                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Full Name'),
                    validator: (v) => Validators.required(v, 'Name'),
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Phone (used to log in)',
                    ),
                    validator: Validators.phone,
                  ),
                  AppSpacing.gapMd,

                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                    ),
                    validator: Validators.emailOptional,
                  ),
                  AppSpacing.gapMd,

                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(
                        value: 'staff',
                        child: Text('Staff — day-to-day access'),
                      ),
                      DropdownMenuItem(
                        value: 'owner',
                        child: Text('Owner — full access incl. staff admin'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _role = v);
                    },
                  ),

                  if (!_isEdit) ...[
                    AppSpacing.gapMd,
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Temporary Password',
                        helperText: 'At least 8 characters, including a digit',
                      ),
                      validator: _validatePassword,
                      onFieldSubmitted: (_) => _save(),
                    ),
                  ],

                  if (_error != null) ...[
                    AppSpacing.gapMd,
                    ErrorBanner.inline(message: _error!),
                  ],

                  AppSpacing.gapXl,

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      AppSpacing.hGapSm,
                      ElevatedButton(
                        style: AppTheme.dialogActionButton,
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isEdit ? 'Save Changes' : 'Add Staff'),
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

  /// Mirrors the backend's rule (users.validatePassword) so the user gets the
  /// feedback inline rather than after a round-trip.
  static String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Must be at least 8 characters';
    if (value.length > 72) return 'Must not exceed 72 characters';
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Must contain at least one digit';
    }
    return null;
  }
}
