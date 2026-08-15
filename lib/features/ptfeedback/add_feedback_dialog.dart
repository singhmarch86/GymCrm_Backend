import 'package:flutter/material.dart';

import '../../models/member_feedback.dart';
import '../../models/trainer.dart';
import '../../services/api_response.dart';
import '../../services/pt_feedback_service.dart';
import '../../services/trainer_service.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Logs one feedback entry against a member. Not tied to a specific PT
/// session — that entry point pre-fills the session instead — so this covers
/// general feedback: what the member said, or what a trainer observed.
Future<MemberFeedback?> showAddFeedbackDialog(
  BuildContext context, {
  required int memberId,
  int? preselectedTrainerId,
  int? ptAppointmentId,
  int? ptPackageId,
}) {
  return showDialog<MemberFeedback>(
    context: context,
    builder: (_) => _AddFeedbackDialog(
      memberId: memberId,
      preselectedTrainerId: preselectedTrainerId,
      ptAppointmentId: ptAppointmentId,
      ptPackageId: ptPackageId,
    ),
  );
}

class _AddFeedbackDialog extends StatefulWidget {
  final int memberId;
  final int? preselectedTrainerId;
  final int? ptAppointmentId;
  final int? ptPackageId;

  const _AddFeedbackDialog({
    required this.memberId,
    this.preselectedTrainerId,
    this.ptAppointmentId,
    this.ptPackageId,
  });

  @override
  State<_AddFeedbackDialog> createState() => _AddFeedbackDialogState();
}

class _AddFeedbackDialogState extends State<_AddFeedbackDialog> {
  final _service = PtFeedbackService();
  final _trainerService = TrainerService();
  final _noteController = TextEditingController();

  String _role = MemberFeedbackRole.member;
  List<Trainer> _trainers = [];
  int? _trainerId;
  bool _loadingTrainers = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _trainerId = widget.preselectedTrainerId;
    _loadTrainers();
  }

  Future<void> _loadTrainers() async {
    try {
      final list = await _trainerService.getTrainers();
      if (!mounted) return;
      setState(() {
        _trainers = list;
        _loadingTrainers = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loadingTrainers = false);
    }
  }

  Future<void> _submit() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      setState(() => _error = 'Write what was said or observed.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await _service.create(
        memberId: widget.memberId,
        authorRole: _role,
        note: note,
        trainerId: _trainerId,
        ptAppointmentId: widget.ptAppointmentId,
        ptPackageId: widget.ptPackageId,
      );
      if (!mounted) return;
      Navigator.pop(context, created);
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
      title: 'Add feedback',
      subtitle: 'Transcribed by staff, either way.',
      icon: Icons.chat_bubble_outline,
      accent: Colors.teal,
      loading: false,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('WHO SAID IT'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: MemberFeedbackRole.member,
                label: Text('Member'),
                icon: Icon(Icons.person_outline, size: 16),
              ),
              ButtonSegment(
                value: MemberFeedbackRole.trainer,
                label: Text('Trainer'),
                icon: Icon(Icons.sports_gymnastics, size: 16),
              ),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 16),
          const LifecycleFieldLabel('TRAINER (OPTIONAL)'),
          const SizedBox(height: 8),
          _loadingTrainers
              ? const LinearProgressIndicator()
              : DropdownButtonFormField<int?>(
                  initialValue: _trainerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('None'),
                    ),
                    for (final t in _trainers)
                      DropdownMenuItem<int?>(
                        value: t.id,
                        child: Text(t.fullName),
                      ),
                  ],
                  onChanged: (v) => setState(() => _trainerId = v),
                ),
          const SizedBox(height: 16),
          const LifecycleFieldLabel('NOTE'),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'What was said or observed...',
            ),
          ),
        ],
      ),
    );
  }
}

/// String constants matching the backend's author_role values.
class MemberFeedbackRole {
  static const member = 'member';
  static const trainer = 'trainer';
}
