import 'package:flutter/material.dart';

import '../../models/member_feedback.dart';
import '../../services/api_response.dart';
import '../../services/pt_feedback_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';
import '../lifecycle/lifecycle_shared.dart' show formatDate;
import 'add_feedback_dialog.dart';

/// A member's PT feedback history — what they said, and what a trainer
/// observed about them. Both staff-transcribed; see
/// lib/models/member_feedback.dart.
class MemberFeedbackSection extends StatefulWidget {
  final int memberId;

  const MemberFeedbackSection({super.key, required this.memberId});

  @override
  State<MemberFeedbackSection> createState() => _MemberFeedbackSectionState();
}

class _MemberFeedbackSectionState extends State<MemberFeedbackSection> {
  final _service = PtFeedbackService();
  List<MemberFeedback> _feedback = [];
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
        _feedback = list;
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

  Future<void> _add() async {
    final created = await showAddFeedbackDialog(
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
              'PT Feedback',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add feedback'),
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
        else if (_feedback.isEmpty)
          const Text(
            'No feedback logged for this member yet.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          )
        else
          for (final f in _feedback) _FeedbackCard(feedback: f),
      ],
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final MemberFeedback feedback;

  const _FeedbackCard({required this.feedback});

  @override
  Widget build(BuildContext context) {
    final fromMember = feedback.isFromMember;
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
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      fromMember
                          ? Icons.person_outline
                          : Icons.sports_gymnastics,
                      size: 14,
                      color: fromMember ? AppColors.info : Colors.teal,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      fromMember ? 'Member said' : 'Trainer noted',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fromMember ? AppColors.info : Colors.teal,
                      ),
                    ),
                    if (feedback.trainerName != null) ...[
                      const Text(
                        '  ·  ',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      Flexible(
                        child: Text(
                          feedback.trainerName!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatDate(feedback.createdAt),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            feedback.note,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Logged by ${feedback.createdByName}',
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
