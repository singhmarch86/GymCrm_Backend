import 'package:flutter/material.dart';

import '../../models/trainer.dart';
import '../../services/api_response.dart';
import '../../services/trainer_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../branch/transfer_to_branch_dialog.dart';
import 'trainer_dialog.dart';

/// PT trainer roster. A trainer here is a standalone record (name, phone,
/// comp) — separate from the `trainer_user_id` used for group-class
/// coverage, and separate from a `User` login. See FR-03 §0.
class TrainersScreen extends StatefulWidget {
  const TrainersScreen({super.key});

  @override
  State<TrainersScreen> createState() => _TrainersScreenState();
}

class _TrainersScreenState extends State<TrainersScreen> {
  final _service = TrainerService();
  List<Trainer> _trainers = [];
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
      final trainers = await _service.getTrainers();
      if (!mounted) return;
      setState(() {
        _trainers = trainers;
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

  Future<void> _create() async {
    final created = await showCreateTrainerDialog(context);
    if (created != null) {
      _changed = true;
      _load();
    }
  }

  Future<void> _edit(Trainer t) async {
    final updated = await showEditTrainerDialog(context, t);
    if (updated != null) {
      _changed = true;
      _load();
    }
  }

  Future<void> _move(Trainer t) async {
    final moved = await showTransferToBranchDialog(
      context,
      kind: TransferKind.trainer,
      entityId: t.id,
      entityName: t.fullName,
    );
    if (moved == true) {
      _changed = true;
      _load(); // they belong to another branch now, so they drop off this list
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Trainers')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('New trainer'),
        ),
        body: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorBanner(message: _error!, onRetry: _load)
            : _trainers.isEmpty
            ? const EmptyStateView(
                icon: Icons.sports_rounded,
                title: 'No trainers yet',
                body: 'Add trainers to sell PT packages and book appointments.',
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: _trainers.length,
                  separatorBuilder: (_, __) => AppSpacing.gapSm,
                  itemBuilder: (_, i) => _TrainerCard(
                    trainer: _trainers[i],
                    onTap: () => _edit(_trainers[i]),
                    onMove: () => _move(_trainers[i]),
                  ),
                ),
              ),
      ),
    );
  }
}

class _TrainerCard extends StatelessWidget {
  final Trainer trainer;
  final VoidCallback onTap;
  final VoidCallback onMove;
  const _TrainerCard({
    required this.trainer,
    required this.onTap,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trainer.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      trainer.phone,
                      if (trainer.specialization != null &&
                          trainer.specialization!.isNotEmpty)
                        trainer.specialization!,
                      if (trainer.commissionPct != null)
                        '${trainer.commissionPct}% commission',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (trainer.status != 'active') ...[
              const StatusChip(status: 'cancelled', label: 'Inactive'),
              const SizedBox(width: 8),
            ],
            IconButton(
              tooltip: 'Move to another branch',
              icon: const Icon(Icons.swap_horiz, size: 18),
              onPressed: onMove,
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
