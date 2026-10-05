import 'package:flutter/material.dart';

import '../../models/pt_report.dart';
import '../../models/trainer.dart';
import '../../services/api_response.dart';
import '../../services/pt_report_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/money.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/status_chip.dart';
import '../branch/transfer_to_branch_dialog.dart';
import '../lifecycle/lifecycle_shared.dart' show formatDate;

/// Shows a trainer's static info plus their PT report — sessions delivered,
/// feedback given or received, and who they currently work with. Members are
/// always ordered by name, never by a performance figure (FR-13 §1).
///
/// Full-page route rather than a dialog, same reasoning as
/// [MemberDetailPanel]: a slide-in modal transition triggers a real Flutter
/// desktop MouseTracker bug on this app.
///
/// Returns `'edit'` if the caller should open the edit dialog after this page
/// closes, or `null` if nothing changed.
Future<String?> showTrainerDetailScreen(BuildContext context, Trainer t) {
  return Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => TrainerDetailScreen(trainer: t)),
  );
}

class TrainerDetailScreen extends StatefulWidget {
  final Trainer trainer;

  const TrainerDetailScreen({super.key, required this.trainer});

  @override
  State<TrainerDetailScreen> createState() => _TrainerDetailScreenState();
}

class _TrainerDetailScreenState extends State<TrainerDetailScreen> {
  final _service = PtReportService();
  TrainerPtReport? _report;
  bool _loading = true;
  String? _error;
  bool _changed = false;

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
      final report = await _service.forTrainer(widget.trainer.id);
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
    final t = widget.trainer;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _changed ? 'edit' : null);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text(t.fullName)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Trainer',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          StatusChip(status: t.status),
                        ],
                      ),
                      AppSpacing.gapMd,
                      _DetailRow('Phone', t.phone),
                      _DetailRow('Email', t.email ?? '-'),
                      _DetailRow('Specialization', t.specialization ?? '-'),
                      if (t.commissionPct != null)
                        _DetailRow('Commission', '${t.commissionPct}%'),
                      _DetailRow(
                        'Salary',
                        t.salaryInPaise != null
                            ? money(t.salaryInPaise!)
                            : '-',
                        last: true,
                      ),
                    ],
                  ),
                ),
              ),

              AppSpacing.gapXl,

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Trainer'),
                  onPressed: () {
                    _changed = true;
                    Navigator.pop(context, 'edit');
                  },
                ),
              ),

              AppSpacing.gapSm,

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Move to another branch'),
                  onPressed: () async {
                    final moved = await showTransferToBranchDialog(
                      context,
                      kind: TransferKind.trainer,
                      entityId: t.id,
                      entityName: t.fullName,
                    );
                    if (moved == true && context.mounted) {
                      Navigator.pop(context, 'changed');
                    }
                  },
                ),
              ),

              AppSpacing.gapXxl,

              const Text(
                'PT Report',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              AppSpacing.gapMd,

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.danger,
                  ),
                )
              else if (_report != null) ...[
                _StatsRow(report: _report!),
                AppSpacing.gapLg,

                const Text(
                  'Assigned members',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                AppSpacing.gapXs,
                if (_report!.assignedMembers.isEmpty)
                  const Text(
                    'No active PT packages under this trainer.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in _report!.assignedMembers)
                        Chip(
                          label: Text(
                            m.name,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),

                AppSpacing.gapLg,

                const Text(
                  'Feedback',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                AppSpacing.gapXs,
                if (_report!.feedback.isEmpty)
                  const Text(
                    'No feedback tied to this trainer yet.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  for (final f in _report!.feedback) _FeedbackTile(row: f),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final TrainerPtReport report;
  const _StatsRow({required this.report});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Sessions delivered',
            value: '${report.sessionsCompleted}',
          ),
        ),
        AppSpacing.gapMd,
        Expanded(
          child: _StatTile(
            label: 'Last payout',
            value: report.lastPayoutInPaise != null
                ? money(report.lastPayoutInPaise!)
                : 'None yet',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  final ReportFeedbackRow row;
  const _FeedbackTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final fromMember = row.authorRole == 'member';
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
                child: Text(
                  fromMember ? 'Member said' : 'Trainer noted',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fromMember ? AppColors.info : Colors.teal,
                  ),
                ),
              ),
              Text(
                formatDate(row.createdAt),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(row.note, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;

  const _DetailRow(this.label, this.value, {this.last = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
