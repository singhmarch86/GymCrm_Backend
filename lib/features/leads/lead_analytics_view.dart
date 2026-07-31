import 'package:flutter/material.dart';

import '../../models/lead_pipeline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

import 'lead_pipeline_constants.dart';

/// Pipeline analytics: where leads come from, where they drop off, and why
/// they are lost.
///
/// The funnel bars are drawn with plain Containers rather than a chart library.
/// A funnel is just proportional widths with labels, and hand-rolling it keeps
/// the exact per-stage colours from lead_pipeline_constants instead of fighting
/// a chart theme.
class LeadAnalyticsView extends StatelessWidget {
  final LeadAnalytics analytics;

  const LeadAnalyticsView({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final topCount =
        analytics.funnel.isNotEmpty ? analytics.funnel.first.count : 0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _sectionTitle('Conversion Funnel'),
        _hint('How many leads reached each stage, and the drop-off between them.'),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              ...analytics.funnel.map((s) => _funnelRow(s, topCount)),
              if (analytics.lostCount > 0) ...[
                Divider(color: Colors.grey.shade200, height: 24),
                Row(
                  children: [
                    const Icon(Icons.cancel_rounded,
                        size: 16, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Text(
                      '${analytics.lostCount} lost',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '— exited the pipeline without joining',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),
        _sectionTitle('Conversion by Source'),
        _hint('Which channels actually produce paying members.'),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: analytics.bySource.isEmpty
                ? [_emptyRow('No source data yet')]
                : analytics.bySource.map(_sourceRow).toList(),
          ),
        ),

        const SizedBox(height: 24),
        _sectionTitle('Why Leads Are Lost'),
        _hint('Top reasons recorded when marking a lead as lost.'),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: analytics.lostReasons.isEmpty
                ? [_emptyRow('No lost leads recorded')]
                : analytics.lostReasons.map(_lostRow).toList(),
          ),
        ),

        // Time-in-stage is derived from recorded stage transitions. Until leads
        // actually move through the pipeline there is no history, and showing
        // "0 days" everywhere would read as a real measurement rather than an
        // absence of data — so the whole section is withheld instead.
        if (analytics.hasStageDurations) ...[
          const SizedBox(height: 24),
          _sectionTitle('Average Time in Stage'),
          _hint('How long leads sit at each step before moving on.'),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              children: analytics.funnel
                  .where((s) => s.avgDays > 0)
                  .map(_durationRow)
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Funnel ─────────────────────────────────────────────────────────────────

  Widget _funnelRow(FunnelStage stage, int topCount) {
    final cfg = stageFor(stage.status);
    final fraction = topCount > 0 ? stage.count / topCount : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cfg.icon, size: 14, color: cfg.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stage.label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${stage.count}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cfg.color,
                ),
              ),
              // Drop-off from the previous stage — the number worth acting on.
              if (stage.stepConversion > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cfg.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${stage.stepConversion.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: cfg.color,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation(cfg.color),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Source performance ─────────────────────────────────────────────────────

  Widget _sourceRow(SourcePerformance s) {
    // Colour the rate by how good it is, so a weak channel is obvious.
    final rateColor = s.conversionRate >= 25
        ? AppColors.success
        : s.conversionRate >= 15
            ? AppColors.warning
            : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              s.label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (s.conversionRate / 100).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation(rateColor),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            child: Text(
              '${s.conversionRate.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: rateColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: Text(
              '${s.joined}/${s.total}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Lost reasons ───────────────────────────────────────────────────────────

  Widget _lostRow(LostReason r) {
    final label = r.reason.isEmpty
        ? 'Not specified'
        : r.reason[0].toUpperCase() + r.reason.substring(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.remove_circle_outline_rounded,
              size: 14, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${r.count}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _durationRow(FunnelStage s) {
    final cfg = stageFor(s.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(cfg.icon, size: 14, color: cfg.color),
          const SizedBox(width: 10),
          Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13))),
          Text(
            '${s.avgDays.toStringAsFixed(1)} days',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: cfg.color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Chrome ─────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      );

  Widget _emptyRow(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ),
      );
}
