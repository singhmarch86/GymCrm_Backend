import 'package:flutter/material.dart';

import '../../models/class_models.dart';
import '../../models/staff.dart';
import '../../services/api_response.dart';
import '../../services/classes_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Create-schedule dialog. Creating a schedule immediately materializes the
/// first rolling window of sessions server-side — nothing further is needed
/// for it to be bookable.
Future<ClassSchedule?> showCreateScheduleDialog(
  BuildContext context, {
  required List<ClassType> classTypes,
}) {
  return showDialog<ClassSchedule>(
    context: context,
    builder: (_) => CreateScheduleDialog(classTypes: classTypes),
  );
}

class CreateScheduleDialog extends StatefulWidget {
  final List<ClassType> classTypes;

  const CreateScheduleDialog({super.key, required this.classTypes});

  @override
  State<CreateScheduleDialog> createState() => _CreateScheduleDialogState();
}

class _CreateScheduleDialogState extends State<CreateScheduleDialog> {
  final _service = ClassesService();
  final _staffService = StaffService();

  int? _classTypeId;
  int _dayOfWeek =
      DateTime.now().weekday % 7; // Dart: 1=Mon..7=Sun -> 0=Sun..6=Sat
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  int? _trainerUserId;

  List<Staff> _staff = [];
  bool _loadingStaff = true;
  bool _saving = false;
  String? _error;

  static const _dayNames = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.classTypes.isNotEmpty) _classTypeId = widget.classTypes.first.id;
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final staff = await _staffService.getStaff();
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _loadingStaff = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(
        () => _loadingStaff = false,
      ); // trainer stays optional either way
    }
  }

  bool get _canSubmit => _classTypeId != null && !_saving;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final startTime =
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
      final sched = await _service.createSchedule(
        classTypeId: _classTypeId!,
        dayOfWeek: _dayOfWeek,
        startTime: startTime,
        trainerUserId: _trainerUserId,
      );
      if (!mounted) return;
      Navigator.pop(context, sched);
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
      title: 'New schedule',
      subtitle: 'A repeating slot — day, time, trainer',
      icon: Icons.repeat,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Create schedule',
          loading: _saving,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Class'),
          AppSpacing.gapXs,
          DropdownButtonFormField<int>(
            initialValue: _classTypeId,
            items: widget.classTypes
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _classTypeId = v),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Repeats every'),
          AppSpacing.gapXs,
          DropdownButtonFormField<int>(
            initialValue: _dayOfWeek,
            items: List.generate(
              7,
              (i) => DropdownMenuItem(value: i, child: Text(_dayNames[i])),
            ),
            onChanged: (v) => setState(() => _dayOfWeek = v ?? _dayOfWeek),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Start time'),
          AppSpacing.gapXs,
          InkWell(
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _time,
              );
              if (picked != null) setState(() => _time = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                suffixIcon: Icon(Icons.access_time, size: 18),
              ),
              child: Text(_time.format(context)),
            ),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Trainer (optional)'),
          AppSpacing.gapXs,
          _loadingStaff
              ? const LinearProgressIndicator()
              : DropdownButtonFormField<int?>(
                  initialValue: _trainerUserId,
                  hint: const Text('Unassigned'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    for (final s in _staff)
                      DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _trainerUserId = v),
                ),
          AppSpacing.gapMd,

          const LifecycleNotice(
            tone: LifecycleTone.info,
            text:
                'Duration and capacity default from the class type. '
                'Sessions for the next 30 days are created immediately.',
          ),
        ],
      ),
    );
  }
}
