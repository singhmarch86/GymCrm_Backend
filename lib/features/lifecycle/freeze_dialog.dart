import 'package:flutter/material.dart';

import '../../models/lifecycle_event.dart';
import '../../services/api_response.dart';
import '../../services/lifecycle_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import 'lifecycle_shared.dart';

/// Freeze dialog. Returns the resulting member state via Navigator.pop so the
/// caller can refresh without refetching.
///
/// Eligibility is loaded before the form is usable: staff see the allowance and
/// the permitted range up front rather than filling in dates and being rejected.
Future<MemberLifecycleResult?> showFreezeDialog(
  BuildContext context, {
  required int memberId,
  required String memberName,
}) {
  return showDialog<MemberLifecycleResult>(
    context: context,
    builder: (_) => FreezeDialog(memberId: memberId, memberName: memberName),
  );
}

class FreezeDialog extends StatefulWidget {
  final int memberId;
  final String memberName;

  const FreezeDialog({super.key, required this.memberId, required this.memberName});

  @override
  State<FreezeDialog> createState() => _FreezeDialogState();
}

class _FreezeDialogState extends State<FreezeDialog> {
  final _service = LifecycleService();
  final _reasonController = TextEditingController();

  FreezeEligibility? _eligibility;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late DateTime _startDate;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final e = await _service.freezeEligibility(widget.memberId);
      if (!mounted) return;
      setState(() {
        _eligibility = e;
        // Open on a sensible duration inside the permitted range rather than a
        // fixed 30, which may exceed what this member has left.
        _days = _days.clamp(e.minDays, e.maxDays < e.minDays ? e.minDays : e.maxDays);
        _loading = false;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.message;
        _loading = false;
      });
    }
  }

  DateTime get _endDate => _startDate.add(Duration(days: _days));

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _service.freeze(
        widget.memberId,
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _eligibility;

    return LifecycleDialogShell(
      title: 'Freeze membership',
      subtitle: widget.memberName,
      icon: Icons.ac_unit,
      accent: AppColors.info,
      loading: _loading,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Freeze for $_days days',
          loading: _saving,
          onPressed: (e != null && e.eligible && !_saving) ? _submit : null,
        ),
      ],
      child: e == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!e.eligible)
                  LifecycleNotice(
                    text: e.reason.isEmpty ? 'This membership cannot be frozen.' : e.reason,
                    tone: LifecycleTone.blocked,
                  )
                else ...[
                  LifecycleNotice(
                    text: '${e.freezeDaysLeftYtd} of 90 freeze days left this membership year.',
                    tone: LifecycleTone.info,
                  ),
                  AppSpacing.gapLg,

                  const LifecycleFieldLabel('Starts'),
                  AppSpacing.gapXs,
                  _DatePickerField(
                    value: _startDate,
                    onChanged: (d) => setState(() => _startDate = d),
                  ),
                  AppSpacing.gapLg,

                  LifecycleFieldLabel('Duration — ${e.minDays} to ${e.maxDays} days'),
                  AppSpacing.gapXs,
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _days.toDouble(),
                          min: e.minDays.toDouble(),
                          max: (e.maxDays < e.minDays ? e.minDays : e.maxDays).toDouble(),
                          divisions: (e.maxDays - e.minDays) > 0 ? (e.maxDays - e.minDays) : null,
                          label: '$_days days',
                          onChanged: (v) => setState(() => _days = v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '$_days d',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.gapMd,

                  // The consequence, stated plainly. This is the thing staff
                  // are actually promising the member.
                  LifecycleOutcome(
                    rows: [
                      ('Frozen until', formatDate(_endDate)),
                      ('Expiry moves out by', '$_days days'),
                    ],
                  ),
                  AppSpacing.gapLg,

                  const LifecycleFieldLabel('Reason (optional)'),
                  AppSpacing.gapXs,
                  TextField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      hintText: 'Travelling, injury, work posting…',
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _DatePickerField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          // Matches the server's effective-dating window (FR-01 §0.4):
          // 7 days back, 30 days forward.
          firstDate: now.subtract(const Duration(days: 7)),
          lastDate: now.add(const Duration(days: 30)),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          suffixIcon: Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(formatDate(value)),
      ),
    );
  }
}
