import 'package:flutter/material.dart';

import '../../models/lifecycle_event.dart';
import '../../models/plan.dart';
import '../../services/api_response.dart';
import '../../services/lifecycle_service.dart';
import '../../services/plan_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import 'lifecycle_shared.dart';

/// Change-plan dialog.
///
/// The prorated amount is re-quoted from the server every time the plan
/// changes, so the figure staff read to a member is the figure that will be
/// recorded — the dialog never computes money itself.
Future<MemberLifecycleResult?> showUpgradeDialog(
  BuildContext context, {
  required int memberId,
  required String memberName,
  int? currentPlanId,
}) {
  return showDialog<MemberLifecycleResult>(
    context: context,
    builder: (_) => UpgradeDialog(
      memberId: memberId,
      memberName: memberName,
      currentPlanId: currentPlanId,
    ),
  );
}

class UpgradeDialog extends StatefulWidget {
  final int memberId;
  final String memberName;
  final int? currentPlanId;

  const UpgradeDialog({
    super.key,
    required this.memberId,
    required this.memberName,
    this.currentPlanId,
  });

  @override
  State<UpgradeDialog> createState() => _UpgradeDialogState();
}

class _UpgradeDialogState extends State<UpgradeDialog> {
  final _service = LifecycleService();
  final _planService = PlanService();
  final _reasonController = TextEditingController();

  List<Plan> _plans = [];
  int? _selectedPlanId;
  UpgradeQuote? _quote;

  bool _loading = true;
  bool _quoting = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final plans = await _planService.getActivePlans();
      if (!mounted) return;
      setState(() {
        // The member's current plan is not a destination.
        _plans = plans.where((p) => p.id != widget.currentPlanId).toList();
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

  Future<void> _quoteFor(int planId) async {
    setState(() {
      _selectedPlanId = planId;
      _quoting = true;
      _quote = null;
      _error = null;
    });
    try {
      final q = await _service.upgradeQuote(widget.memberId, planId);
      if (!mounted) return;
      setState(() {
        _quote = q;
        _quoting = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _quoting = false;
      });
    }
  }

  Future<void> _submit() async {
    final planId = _selectedPlanId;
    if (planId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _service.upgrade(
        widget.memberId,
        newPlanId: planId,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, result);
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
    final q = _quote;

    return LifecycleDialogShell(
      title: 'Change plan',
      subtitle: widget.memberName,
      icon: Icons.swap_horiz,
      accent: AppColors.primary,
      loading: _loading,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Change plan',
          loading: _saving,
          onPressed: (q != null && !_saving) ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Move to'),
          AppSpacing.gapXs,
          for (final plan in _plans) ...[
            _PlanOption(
              plan: plan,
              selected: plan.id == _selectedPlanId,
              onTap: () => _quoteFor(plan.id),
            ),
            AppSpacing.gapXs,
          ],

          if (_quoting) ...[
            AppSpacing.gapMd,
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ],

          if (q != null) ...[
            AppSpacing.gapMd,
            LifecycleOutcome(
              emphasisColor: q.isDowngrade
                  ? AppColors.success
                  : AppColors.primary,
              rows: [
                ('Days remaining', '${q.remainingDays}'),
                (
                  'Rate change per day',
                  '${formatRupees(q.oldDailyRatePaise / 100)} → ${formatRupees(q.newDailyRatePaise / 100)}',
                ),
                if (q.isDowngrade)
                  ('Credit to member', formatRupees(q.amountCreditInRupees))
                else
                  ('Amount due now', formatRupees(q.amountDueInRupees)),
              ],
            ),
            AppSpacing.gapSm,
            LifecycleNotice(
              tone: q.isDowngrade ? LifecycleTone.info : LifecycleTone.warning,
              text: q.isDowngrade
                  // Be explicit: staff will be asked about this by the member.
                  ? 'A downgrade is recorded as credit, not refunded. Expiry stays the same.'
                  : 'This records the amount as due — it does not collect it. Take payment separately. Expiry stays the same.',
            ),
            AppSpacing.gapLg,
            const LifecycleFieldLabel('Reason (optional)'),
            AppSpacing.gapXs,
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                hintText: 'Member requested, promotional offer…',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  final Plan plan;
  final bool selected;
  final VoidCallback onTap;

  const _PlanOption({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                plan.name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              '${formatRupees(plan.priceInRupees)} · ${plan.durationDays}d',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
