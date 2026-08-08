import 'package:flutter/material.dart';

import '../../models/pt_package.dart';
import '../../services/api_response.dart';
import '../../services/pt_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Books a 1:1 PT appointment against an active package. Deliberately does
/// not check or reserve a session credit here — see FR-03 §3; the guard is
/// on completing the appointment, not booking it.
Future<PtAppointment?> showBookAppointmentDialog(
  BuildContext context, {
  required List<PtPackage> activePackages,
}) {
  return showDialog<PtAppointment>(
    context: context,
    builder: (_) => BookAppointmentDialog(activePackages: activePackages),
  );
}

class BookAppointmentDialog extends StatefulWidget {
  final List<PtPackage> activePackages;
  const BookAppointmentDialog({super.key, required this.activePackages});

  @override
  State<BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<BookAppointmentDialog> {
  final _service = PtService();
  final _notesController = TextEditingController();

  int? _packageId;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  int _duration = 60;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.activePackages.isNotEmpty) _packageId = widget.activePackages.first.id;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _packageId != null && !_saving;

  Future<void> _submit() async {
    if (_packageId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scheduledAt = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
      final appt = await _service.bookAppointment(
        ptPackageId: _packageId!,
        scheduledAt: scheduledAt,
        durationMinutes: _duration,
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, appt);
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
    if (widget.activePackages.isEmpty) {
      return LifecycleDialogShell(
        title: 'Book appointment',
        subtitle: 'No active packages',
        icon: Icons.event_available,
        accent: AppColors.primary,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
        child: const LifecycleNotice(
          tone: LifecycleTone.blocked,
          text: 'No active PT packages exist yet. Sell a package to a member first.',
        ),
      );
    }

    return LifecycleDialogShell(
      title: 'Book appointment',
      subtitle: 'A 1:1 session against a package',
      icon: Icons.event_available,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(text: 'Book', loading: _saving, onPressed: _canSubmit ? _submit : null),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Package'),
          AppSpacing.gapXs,
          DropdownButtonFormField<int>(
            initialValue: _packageId,
            // Package labels can run long (member + package + trainer name) —
            // isExpanded is required for the ellipsis to actually kick in;
            // without it the button sizes to intrinsic text width and
            // overflows instead of truncating.
            isExpanded: true,
            items: widget.activePackages
                .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        '${p.memberName} · ${p.packageName} (${p.sessionsRemaining}/${p.totalSessions} left) · ${p.trainerName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _packageId = v),
          ),
          AppSpacing.gapLg,

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Date'),
                    AppSpacing.gapXs,
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 16)),
                        child: Text(formatDate(_date)),
                      ),
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Time'),
                    AppSpacing.gapXs,
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: _time);
                        if (picked != null) setState(() => _time = picked);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(suffixIcon: Icon(Icons.access_time, size: 16)),
                        child: Text(_time.format(context)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Duration (min)'),
          AppSpacing.gapXs,
          DropdownButtonFormField<int>(
            initialValue: _duration,
            items: const [30, 45, 60, 75, 90]
                .map((d) => DropdownMenuItem(value: d, child: Text('$d min')))
                .toList(),
            onChanged: (v) => setState(() => _duration = v ?? _duration),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Notes (optional)'),
          AppSpacing.gapXs,
          TextField(controller: _notesController, autofillHints: const []),
        ],
      ),
    );
  }
}
