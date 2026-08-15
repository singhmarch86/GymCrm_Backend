import 'package:flutter/material.dart';

import '../../models/recognition.dart';
import '../../services/api_response.dart';
import '../../services/recognition_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart' show formatDate;
import 'recognize_member_dialog.dart';

/// Private recognition history for one member. No score, no badge, no
/// ranking — a plain newest-first list of reason + date + who recorded it,
/// same spirit as [LifecycleTimeline].
class MemberRecognitionSection extends StatefulWidget {
  final int memberId;

  const MemberRecognitionSection({super.key, required this.memberId});

  @override
  State<MemberRecognitionSection> createState() =>
      _MemberRecognitionSectionState();
}

class _MemberRecognitionSectionState extends State<MemberRecognitionSection> {
  final _service = RecognitionService();
  List<Recognition> _recognitions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.byMember(widget.memberId);
      if (!mounted) return;
      setState(() {
        _recognitions = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _recognize() async {
    final created = await showRecognizeMemberDialog(
      context,
      memberId: widget.memberId,
    );
    if (created != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recognition',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: _recognize,
              icon: const Icon(Icons.stars_outlined, size: 16),
              label: const Text('Recognize member'),
            ),
          ],
        ),
        AppSpacing.gapXs,

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_error != null)
          Text(
            _error!,
            style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
          )
        else if (_recognitions.isEmpty)
          const Text(
            'No recognition recorded for this member yet.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          )
        else
          for (final r in _recognitions) _RecognitionCard(recognition: r),
      ],
    );
  }
}

class _RecognitionCard extends StatelessWidget {
  final Recognition recognition;
  const _RecognitionCard({required this.recognition});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stars_outlined, size: 14, color: Colors.amber.shade800),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Recognized',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                formatDate(recognition.createdAt),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            recognition.reason,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Recorded by ${recognition.createdByName}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
