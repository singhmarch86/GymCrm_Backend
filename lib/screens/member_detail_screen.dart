import 'package:flutter/material.dart';

import '../features/lifecycle/freeze_dialog.dart';
import '../features/lifecycle/lifecycle_shared.dart' show formatDate;
import '../features/lifecycle/lifecycle_timeline.dart';
import '../features/lifecycle/terminate_dialog.dart';
import '../features/lifecycle/transfer_dialog.dart';
import '../features/lifecycle/upgrade_dialog.dart';
import '../models/lifecycle_event.dart';
import '../models/member.dart';
import '../services/lifecycle_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_spacing.dart' show AppSpacing;
import '../widgets/status_chip.dart';

/// Shows member details as a full-page route.
///
/// Returns:
///   - `'edit'`    — user tapped Edit Member; caller should open the edit
///                   dialog after this page has fully closed
///   - `'delete'`  — user tapped Delete Member; caller should confirm and
///                   delete after this page has fully closed
///   - `'changed'` — a lifecycle operation (freeze/upgrade/transfer/terminate)
///                   ran inside this panel; caller should refresh its list
///   - `null`      — nothing changed
///
/// This was previously a custom slide-in side panel (via showGeneralDialog),
/// but that transition triggered a real Flutter desktop MouseTracker bug
/// ('!_debugDuringDeviceUpdate' assertion cascading into "Lost connection
/// to device") on its own open/close animation — not just when nesting a
/// second modal on top of it. A plain MaterialPageRoute doesn't have this
/// problem, so detail views use it instead; only the short Add/Edit forms
/// (centered Dialogs, unaffected by this bug) keep the "professional
/// modal" treatment. Lifecycle actions follow the same rule — freeze, upgrade,
/// transfer and terminate are all centered Dialogs, opened from this page
/// rather than as a second full-screen route.
Future<String?> showMemberDetailPanel(BuildContext context, Member member) {
  return Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => MemberDetailPanel(member: member)),
  );
}

class MemberDetailPanel extends StatefulWidget {
  final Member member;

  const MemberDetailPanel({super.key, required this.member});

  @override
  State<MemberDetailPanel> createState() => _MemberDetailPanelState();
}

class _MemberDetailPanelState extends State<MemberDetailPanel> {
  // Local view of lifecycle-relevant state, updated in place after each
  // operation so the panel reflects reality without a round-trip refetch of
  // the whole member.
  late String _status;
  late DateTime? _expiryDate;
  String? _planName;
  DateTime? _frozenFrom;
  DateTime? _frozenUntil;

  int _timelineToken = 0;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _status = widget.member.status;
    _expiryDate = widget.member.expiryDate != null
        ? DateTime.tryParse(widget.member.expiryDate!)
        : null;
    _planName = widget.member.membershipPlanName;
  }

  void _applyResult(MemberLifecycleResult r) {
    setState(() {
      _status = r.status;
      _expiryDate = r.expiryDate;
      _planName = r.planName ?? _planName;
      _frozenFrom = r.frozenFrom;
      _frozenUntil = r.frozenUntil;
      _timelineToken++;
      _changed = true;
    });
  }

  bool get _isFrozen => _status == 'frozen';
  bool get _isTerminated => _status == 'terminated';

  String get _memberName => '${widget.member.firstName} ${widget.member.lastName}';

  Future<void> _freeze() async {
    final result = await showFreezeDialog(
      context,
      memberId: widget.member.id,
      memberName: _memberName,
    );
    if (result != null) _applyResult(result);
  }

  Future<void> _unfreeze() async {
    final result = await LifecycleService().unfreeze(widget.member.id);
    if (!mounted) return;
    _applyResult(result);
  }

  Future<void> _upgrade() async {
    final result = await showUpgradeDialog(
      context,
      memberId: widget.member.id,
      memberName: _memberName,
      currentPlanId: widget.member.membershipPlanId,
    );
    if (result != null) _applyResult(result);
  }

  Future<void> _transfer() async {
    final result = await showTransferDialog(
      context,
      memberId: widget.member.id,
      memberName: _memberName,
      expiryDate: _expiryDate != null ? formatDate(_expiryDate!) : null,
    );
    if (result != null) _applyResult(result);
  }

  Future<void> _terminate() async {
    final result = await showTerminateDialog(
      context,
      memberId: widget.member.id,
      memberName: _memberName,
    );
    if (result != null) _applyResult(result);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _changed ? 'changed' : null);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text(_memberName)),
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
                              'Membership',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                            ),
                          ),
                          StatusChip(status: _status),
                        ],
                      ),
                      AppSpacing.gapMd,
                      _DetailRow('Phone', widget.member.phone),
                      _DetailRow('Email', widget.member.email ?? '-'),
                      _DetailRow('Gender', widget.member.gender ?? '-'),
                      _DetailRow('Address', widget.member.address ?? '-'),
                      _DetailRow('Plan', _planName ?? '-'),
                      _DetailRow('Start Date', widget.member.startDate ?? '-'),
                      _DetailRow(
                        'Expiry Date',
                        _expiryDate != null ? formatDate(_expiryDate!) : '-',
                        last: !_isFrozen,
                      ),
                      if (_isFrozen && _frozenFrom != null && _frozenUntil != null)
                        _DetailRow(
                          'Frozen',
                          '${formatDate(_frozenFrom!)} – ${formatDate(_frozenUntil!)}',
                          last: true,
                        ),
                    ],
                  ),
                ),
              ),

              AppSpacing.gapXl,

              if (_isTerminated)
                const _TerminatedNotice()
              else
                _LifecycleActions(
                  isFrozen: _isFrozen,
                  onFreeze: _freeze,
                  onUnfreeze: _unfreeze,
                  onUpgrade: _upgrade,
                  onTransfer: _transfer,
                  onTerminate: _terminate,
                ),

              AppSpacing.gapXl,

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Member'),
                  onPressed: () => Navigator.pop(context, 'edit'),
                ),
              ),

              AppSpacing.gapSm,

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete Member'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context, 'delete'),
                ),
              ),

              AppSpacing.gapXxl,

              const Text(
                'Membership history',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              AppSpacing.gapMd,
              LifecycleTimeline(memberId: widget.member.id, refreshToken: _timelineToken),
            ],
          ),
        ),
      ),
    );
  }
}

/// Freeze/unfreeze, change plan, transfer, terminate — grouped so front-desk
/// staff see every membership-changing action in one place, separate from the
/// unrelated Edit/Delete controls below.
class _LifecycleActions extends StatelessWidget {
  final bool isFrozen;
  final VoidCallback onFreeze;
  final VoidCallback onUnfreeze;
  final VoidCallback onUpgrade;
  final VoidCallback onTransfer;
  final VoidCallback onTerminate;

  const _LifecycleActions({
    required this.isFrozen,
    required this.onFreeze,
    required this.onUnfreeze,
    required this.onUpgrade,
    required this.onTransfer,
    required this.onTerminate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Membership actions',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        AppSpacing.gapSm,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (isFrozen)
              OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('End freeze'),
                onPressed: onUnfreeze,
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.ac_unit, size: 18),
                label: const Text('Freeze'),
                onPressed: onFreeze,
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Change plan'),
              // Matches the backend guard: proration maths on a frozen
              // membership isn't something anyone can explain to a member.
              onPressed: isFrozen ? null : onUpgrade,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_calls, size: 18),
              label: const Text('Transfer'),
              onPressed: onTransfer,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Terminate'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: onTerminate,
            ),
          ],
        ),
      ],
    );
  }
}

class _TerminatedNotice extends StatelessWidget {
  const _TerminatedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.danger),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This membership is terminated. Restoring it requires selling a new membership.',
              style: TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.35),
            ),
          ),
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
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
