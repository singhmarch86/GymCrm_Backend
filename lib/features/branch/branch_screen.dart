import 'package:flutter/material.dart';

import '../../models/branch.dart';
import '../../services/api_response.dart';
import '../../services/branch_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Branches: switch between locations, see the chain at a glance, add one.
/// See docs/FR-06-multi-location.md.
///
/// Switching replaces the session token, so everything downstream — members,
/// payments, invoices, reports — follows automatically without any other
/// screen needing to know branches exist.
class BranchScreen extends StatefulWidget {
  const BranchScreen({super.key});

  @override
  State<BranchScreen> createState() => _BranchScreenState();
}

class _BranchScreenState extends State<BranchScreen> {
  final _service = BranchService();
  List<Branch> _branches = [];
  List<BranchSummary> _summary = [];
  int? _currentGymId;
  bool _loading = true;
  bool _switching = false;
  String? _error;
  bool _switched = false;

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
      final branches = await _service.getBranches();
      final current = await StorageService.getGymId();

      // Consolidated figures are owner-only, so a staff user simply doesn't see
      // that section rather than being shown a permission error.
      List<BranchSummary> summary = [];
      if (branches.any((b) => b.isOwner)) {
        try {
          summary = await _service.chainSummary();
        } on ApiException {
          summary = [];
        }
      }

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _summary = summary;
        _currentGymId = current;
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

  Future<void> _switch(Branch b) async {
    if (b.id == _currentGymId) return;
    setState(() => _switching = true);
    try {
      await _service.switchBranch(b.id);
      if (!mounted) return;
      setState(() {
        _currentGymId = b.id;
        _switching = false;
        _switched = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Now working in ${b.displayName}')),
      );
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _switching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Best-performing first. Sorted client-side because the summary endpoint is
  /// month-to-date and small; the period report ranks server-side.
  List<BranchSummary> _ranked() {
    final list = [..._summary];
    list.sort((a, b) => b.revenueInPaise.compareTo(a.revenueInPaise));
    return list;
  }

  Future<void> _setTargets(BranchSummary s) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TargetsDialog(summary: s),
    );
    if (saved == true) _load();
  }

  Future<void> _addBranch() async {
    final created = await showDialog<Branch>(
      context: context,
      builder: (_) => const _AddBranchDialog(),
    );
    if (created != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _branches.any((b) => b.isOwner);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // A switch changes everything the dashboard shows, so the caller must
        // reload rather than keep displaying another branch's figures.
        if (!didPop) Navigator.pop(context, _switched);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Branches')),
        floatingActionButton: canAdd
            ? FloatingActionButton.extended(
                onPressed: _addBranch,
                icon: const Icon(Icons.add),
                label: const Text('Add branch'),
              )
            : null,
        body: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorBanner(message: _error!, onRetry: _load)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  const Text(
                    'Your branches',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  AppSpacing.gapXs,
                  const Text(
                    'Switching changes everything you see — members, payments and reports '
                    'all belong to one branch at a time.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  AppSpacing.gapMd,

                  for (final b in _branches) ...[
                    _BranchCard(
                      branch: b,
                      isCurrent: b.id == _currentGymId,
                      busy: _switching,
                      onTap: () => _switch(b),
                    ),
                    AppSpacing.gapSm,
                  ],

                  if (_summary.length > 1) ...[
                    AppSpacing.gapLg,
                    const Text(
                      'Across your branches',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppSpacing.gapXs,
                    const Text(
                      'Owner view. Read-only.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    AppSpacing.gapMd,
                    // Ranked by revenue — the league table's whole point is
                    // that branches can see where they stand.
                    for (final entry in _ranked().indexed) ...[
                      _SummaryCard(
                        summary: entry.$2,
                        rank: entry.$1 + 1,
                        showRank: _summary.length > 1,
                        onSetTargets: () => _setTargets(entry.$2),
                      ),
                      AppSpacing.gapSm,
                    ],
                    AppSpacing.gapSm,
                    LifecycleOutcome(
                      emphasisColor: AppColors.primary,
                      rows: [
                        (
                          'Active members',
                          '${_summary.fold<int>(0, (a, s) => a + s.activeMembers)}',
                        ),
                        (
                          'Expiring in 30 days',
                          '${_summary.fold<int>(0, (a, s) => a + s.expiringSoon)}',
                        ),
                        (
                          'Revenue this month',
                          formatRupees(
                            _summary.fold<int>(
                                  0,
                                  (a, s) => a + s.revenueInPaise,
                                ) /
                                100,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final Branch branch;
  final bool isCurrent;
  final bool busy;
  final VoidCallback onTap;

  const _BranchCard({
    required this.branch,
    required this.isCurrent,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: (isCurrent || busy) ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent ? AppColors.primaryLight : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrent ? AppColors.primary : AppColors.border,
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isCurrent ? Icons.location_on : Icons.location_on_outlined,
              size: 20,
              color: isCurrent ? AppColors.primary : AppColors.textSecondary,
            ),
            AppSpacing.gapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (branch.city != null && branch.city!.isNotEmpty)
                        branch.city!,
                      branch.role,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrent)
              const Text(
                'Current',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              )
            else
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

class _SummaryCard extends StatelessWidget {
  final BranchSummary summary;
  final int rank;
  final bool showRank;
  final VoidCallback onSetTargets;

  const _SummaryCard({
    required this.summary,
    required this.rank,
    required this.showRank,
    required this.onSetTargets,
  });

  /// Attainment colour: behind is only meaningful against a target, so a branch
  /// with no target set is never shown as failing.
  Color get _attainmentColor {
    if (!summary.hasTarget) return AppColors.textSecondary;
    if (summary.revenueAttainmentPct >= 100) return AppColors.success;
    if (summary.revenueAttainmentPct >= 70) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showRank) ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank == 1 ? AppColors.success : AppColors.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: rank == 1 ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  summary.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                formatRupees(summary.revenueInRupees),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            '${summary.activeMembers} active · ${summary.newMembersThisMonth} joined · '
            '${summary.expiringSoon} expiring',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),

          if (summary.hasTarget) ...[
            AppSpacing.gapSm,
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      // Capped at 1.0 so a branch at 140% doesn't render a bar
                      // that looks broken.
                      value: (summary.revenueAttainmentPct / 100).clamp(
                        0.0,
                        1.0,
                      ),
                      minHeight: 6,
                      backgroundColor: AppColors.background,
                      valueColor: AlwaysStoppedAnimation(_attainmentColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${summary.revenueAttainmentPct.toStringAsFixed(0)}% of target',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _attainmentColor,
                  ),
                ),
              ],
            ),
          ],

          AppSpacing.gapXs,
          Row(
            children: [
              Text(
                summary.revenuePerMemberInPaise > 0
                    ? '${formatRupees(summary.revenuePerMemberInPaise / 100)} per member'
                    : '—',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onSetTargets,
                child: Text(summary.hasTarget ? 'Change target' : 'Set target'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Setting what a branch should achieve. Without a target, a league table only
/// reports who is biggest — which usually just reflects branch age.
class _TargetsDialog extends StatefulWidget {
  final BranchSummary summary;
  const _TargetsDialog({required this.summary});

  @override
  State<_TargetsDialog> createState() => _TargetsDialogState();
}

class _TargetsDialogState extends State<_TargetsDialog> {
  final _service = BranchService();
  late final _revenueController = TextEditingController(
    text: widget.summary.revenueTargetInPaise > 0
        ? (widget.summary.revenueTargetInPaise / 100).toStringAsFixed(0)
        : '',
  );
  late final _memberController = TextEditingController(
    text: widget.summary.memberTarget > 0
        ? '${widget.summary.memberTarget}'
        : '',
  );

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _revenueController.dispose();
    _memberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final revenue = double.tryParse(_revenueController.text.trim()) ?? 0;
    final members = int.tryParse(_memberController.text.trim()) ?? 0;
    if (revenue < 0 || members < 0) {
      setState(() => _error = 'Targets cannot be negative');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.setTargets(
        widget.summary.gymId,
        revenueTargetInPaise: (revenue * 100).round(),
        memberTarget: members,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
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
      title: 'Monthly target',
      subtitle: widget.summary.displayName,
      icon: Icons.flag_outlined,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Save',
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Revenue target (₹ per month)'),
          AppSpacing.gapXs,
          TextField(
            controller: _revenueController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'e.g. 500000'),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('New members target (per month)'),
          AppSpacing.gapXs,
          TextField(
            controller: _memberController,
            keyboardType: TextInputType.number,
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'e.g. 20'),
          ),
          AppSpacing.gapMd,

          const LifecycleNotice(
            tone: LifecycleTone.info,
            text:
                'Leave at 0 to track a branch without judging it against a target.',
          ),
        ],
      ),
    );
  }
}

class _AddBranchDialog extends StatefulWidget {
  const _AddBranchDialog();

  @override
  State<_AddBranchDialog> createState() => _AddBranchDialogState();
}

class _AddBranchDialogState extends State<_AddBranchDialog> {
  final _service = BranchService();
  final _nameController = TextEditingController();
  final _shortNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Branch name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final b = await _service.createBranch(
        name: name,
        branchName: _shortNameController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, b);
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
      title: 'Add a branch',
      subtitle: 'A new location in your organization',
      icon: Icons.add_location_alt_outlined,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Create branch',
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Full name'),
          AppSpacing.gapXs,
          TextField(
            controller: _nameController,
            autofillHints: const [],
            decoration: const InputDecoration(
              hintText: 'e.g. FitZone Model Town',
            ),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Short label'),
          AppSpacing.gapXs,
          TextField(
            controller: _shortNameController,
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'e.g. Model Town'),
          ),
          AppSpacing.gapLg,

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('City'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _cityController,
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('State'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _stateController,
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Phone'),
          AppSpacing.gapXs,
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [],
          ),
          AppSpacing.gapMd,

          const LifecycleNotice(
            tone: LifecycleTone.info,
            text:
                'A new branch starts empty — its own members, staff, plans and invoice '
                'number series. Nothing is copied from your existing branches.',
          ),
        ],
      ),
    );
  }
}
