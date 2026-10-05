import 'package:flutter/material.dart';

import '../../models/pt_report.dart';
import '../../services/api_response.dart';
import '../../services/pt_report_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';

/// A member's PT packages — sessions used/remaining per package, plus their
/// attendance-consistency signal cited as-is from member_rhythm_profiles.
/// Feedback lives in [MemberFeedbackSection]; this is the other half of the
/// member-side PT report.
class MemberPtReportSection extends StatefulWidget {
  final int memberId;

  const MemberPtReportSection({super.key, required this.memberId});

  @override
  State<MemberPtReportSection> createState() => _MemberPtReportSectionState();
}

class _MemberPtReportSectionState extends State<MemberPtReportSection> {
  final _service = PtReportService();
  MemberPtReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final report = await _service.forMember(widget.memberId);
      if (!mounted) return;
      setState(() {
        _report = report;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null) {
      return Text(
        _error!,
        style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
      );
    }
    final report = _report!;
    if (report.packages.isEmpty && report.rhythm == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PT Packages',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        AppSpacing.gapXs,
        if (report.packages.isEmpty)
          const Text(
            'No PT packages for this member.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          )
        else
          for (final p in report.packages) _PackageCard(package: p),
        if (report.rhythm != null) ...[
          AppSpacing.gapSm,
          _RhythmCard(rhythm: report.rhythm!),
        ],
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  final PackageSummary package;
  const _PackageCard({required this.package});

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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.packageName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'with ${package.trainerName}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${package.sessionsRemaining} / ${package.totalSessions} left',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _RhythmCard extends StatelessWidget {
  final RhythmSummary rhythm;
  const _RhythmCard({required this.rhythm});

  @override
  Widget build(BuildContext context) {
    final pct = (rhythm.recentConsistency * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: rhythm.isBroken
            ? AppColors.dangerLight
            : AppColors.successLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            rhythm.isBroken ? Icons.trending_down : Icons.trending_up,
            size: 16,
            color: rhythm.isBroken ? AppColors.danger : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rhythm.isBroken
                  ? 'Attendance rhythm has broken — $pct% recent consistency'
                  : 'Attendance is consistent — $pct% recent consistency',
              style: TextStyle(
                fontSize: 12.5,
                color: rhythm.isBroken ? AppColors.danger : AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
