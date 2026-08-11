import 'package:flutter/material.dart';

import '../../models/lead_pipeline.dart';
import '../../theme/app_colors.dart';

/// Commit to what happens next for one lead (FR-18 §1).
///
/// Both a step and a date, or neither. The backend rejects a step without a
/// date, and this sheet enforces the same rule at the point of entry — a step
/// nobody will be reminded of is exactly the failure the workflow exists to
/// remove, and letting it through here would only move the error later.
///
/// Returns true if something was saved.
Future<bool?> showNextStepSheet(
  BuildContext context, {
  required String leadName,
  required String stageLabel,
  String? currentStep,
  DateTime? currentDue,
  String? suggestedStep,
  DateTime? suggestedDue,
  String? suggestionReason,
  required Future<void> Function(String step, DateTime due) onSave,
  Future<void> Function()? onClear,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NextStepSheet(
      leadName: leadName,
      stageLabel: stageLabel,
      currentStep: currentStep,
      currentDue: currentDue,
      suggestedStep: suggestedStep,
      suggestedDue: suggestedDue,
      suggestionReason: suggestionReason,
      onSave: onSave,
      onClear: onClear,
    ),
  );
}

class _NextStepSheet extends StatefulWidget {
  final String leadName;
  final String stageLabel;
  final String? currentStep;
  final DateTime? currentDue;
  final String? suggestedStep;
  final DateTime? suggestedDue;
  final String? suggestionReason;
  final Future<void> Function(String step, DateTime due) onSave;
  final Future<void> Function()? onClear;

  const _NextStepSheet({
    required this.leadName,
    required this.stageLabel,
    this.currentStep,
    this.currentDue,
    this.suggestedStep,
    this.suggestedDue,
    this.suggestionReason,
    required this.onSave,
    this.onClear,
  });

  @override
  State<_NextStepSheet> createState() => _NextStepSheetState();
}

class _NextStepSheetState extends State<_NextStepSheet> {
  late String? _step = widget.suggestedStep ?? widget.currentStep;
  late DateTime _due =
      widget.suggestedDue ?? widget.currentDue ?? DateTime.now();
  bool _saving = false;
  String? _error;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      // Backdating is allowed: staff catch up on yesterday's work, and
      // refusing it would push them to enter a date they do not mean.
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'When is this due?',
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _save() async {
    if (_step == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_step!, _due);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't save that. Try again.";
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('What happens next?',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('${widget.leadName} · ${widget.stageLabel}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),

            // The suggestion explains itself. An unexplained prefill gets
            // accepted without thought, which is the same as automating it.
            if (widget.suggestionReason != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded,
                        size: 15, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(widget.suggestionReason!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final o in NextStepOption.fallback)
                  ChoiceChip(
                    label: Text(o.label,
                        style: const TextStyle(fontSize: 12)),
                    selected: _step == o.step,
                    onSelected: (sel) =>
                        setState(() => _step = sel ? o.step : null),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),

            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded,
                        size: 17, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text(_formatDue(_due),
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Icon(Icons.edit_calendar_rounded,
                        size: 16, color: Colors.grey.shade500),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.danger)),
            ],

            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.onClear != null)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            await widget.onClear!();
                            if (context.mounted) Navigator.pop(context, true);
                          },
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
                    child: const Text('Clear'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  // Disabled with no step chosen: this sheet cannot produce a
                  // half-set workflow, which is the whole point of it.
                  onPressed: (_step == null || _saving) ? null : _save,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDue(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final due = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = due.difference(today).inDays;

    final date = '${d.day} ${months[d.month - 1]} ${d.year}';
    if (diff == 0) return 'Today · $date';
    if (diff == 1) return 'Tomorrow · $date';
    if (diff < 0) return '${-diff} days ago · $date';
    return 'In $diff days · $date';
  }
}
