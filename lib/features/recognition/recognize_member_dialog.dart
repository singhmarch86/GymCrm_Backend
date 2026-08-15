import 'package:flutter/material.dart';

import '../../models/pt_report.dart';
import '../../models/recognition.dart';
import '../../services/api_response.dart';
import '../../services/pt_report_service.dart';
import '../../services/recognition_service.dart';
import '../lifecycle/lifecycle_shared.dart';

enum _SignalChoice { none, rhythm, feedback }

/// Records one act of recognition. Always requires a written reason;
/// citing a signal (attendance consistency or a specific feedback note) is
/// optional context, never an automatic trigger — the owner always decides.
Future<Recognition?> showRecognizeMemberDialog(
  BuildContext context, {
  required int memberId,
}) {
  return showDialog<Recognition>(
    context: context,
    builder: (_) => _RecognizeMemberDialog(memberId: memberId),
  );
}

class _RecognizeMemberDialog extends StatefulWidget {
  final int memberId;
  const _RecognizeMemberDialog({required this.memberId});

  @override
  State<_RecognizeMemberDialog> createState() =>
      _RecognizeMemberDialogState();
}

class _RecognizeMemberDialogState extends State<_RecognizeMemberDialog> {
  final _recognitionService = RecognitionService();
  final _reportService = PtReportService();
  final _reasonController = TextEditingController();

  MemberPtReport? _report;
  bool _loadingContext = true;

  _SignalChoice _signal = _SignalChoice.none;
  int? _feedbackId;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reportService
        .forMember(widget.memberId)
        .then((r) {
          if (mounted) setState(() => _report = r);
        })
        .catchError((_) {})
        .whenComplete(() {
          if (mounted) setState(() => _loadingContext = false);
        });
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Write why this member is being recognized.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await _recognitionService.create(
        memberId: widget.memberId,
        reason: reason,
        signalType: switch (_signal) {
          _SignalChoice.none => null,
          _SignalChoice.rhythm => 'rhythm',
          _SignalChoice.feedback => 'feedback',
        },
        signalId: switch (_signal) {
          _SignalChoice.none => null,
          // One rhythm profile per member — the member id is enough to cite it.
          _SignalChoice.rhythm => widget.memberId,
          _SignalChoice.feedback => _feedbackId,
        },
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
    final rhythm = _report?.rhythm;
    final feedback = _report?.feedback ?? [];

    return LifecycleDialogShell(
      title: 'Recognize member',
      subtitle: 'Private — visible only to staff, never ranked.',
      icon: Icons.stars_outlined,
      accent: Colors.amber.shade800,
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
          const LifecycleFieldLabel('REASON'),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Why is this member being recognized?',
            ),
          ),
          const SizedBox(height: 16),
          const LifecycleFieldLabel('CITE A SIGNAL (OPTIONAL)'),
          const SizedBox(height: 8),
          if (_loadingContext)
            const LinearProgressIndicator()
          else ...[
            RadioGroup<_SignalChoice>(
              groupValue: _signal,
              onChanged: (v) => setState(() {
                _signal = v ?? _SignalChoice.none;
                _feedbackId = null;
              }),
              child: Column(
                children: [
                  const RadioListTile<_SignalChoice>(
                    value: _SignalChoice.none,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Owner judgment only'),
                  ),
                  RadioListTile<_SignalChoice>(
                    value: _SignalChoice.rhythm,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    enabled: rhythm != null,
                    title: Text(
                      rhythm != null
                          ? 'Attendance consistency (${(rhythm.recentConsistency * 100).round()}% recent)'
                          : 'Attendance consistency (no data yet)',
                    ),
                  ),
                  RadioListTile<_SignalChoice>(
                    value: _SignalChoice.feedback,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    enabled: feedback.isNotEmpty,
                    title: Text(
                      feedback.isNotEmpty
                          ? 'A specific feedback note'
                          : 'A specific feedback note (none logged yet)',
                    ),
                  ),
                ],
              ),
            ),
            if (_signal == _SignalChoice.feedback && feedback.isNotEmpty) ...[
              const SizedBox(height: 4),
              DropdownButtonFormField<int>(
                initialValue: _feedbackId,
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
                  for (final f in feedback)
                    DropdownMenuItem<int>(
                      value: f.id,
                      child: Text(
                        f.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _feedbackId = v),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
