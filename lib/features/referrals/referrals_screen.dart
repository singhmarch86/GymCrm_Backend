import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/referral.dart';
import '../../services/api_response.dart';
import '../../services/member_service.dart';
import '../../services/referral_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Member-to-member referral tracking. Reward is free membership days
/// credited to the referrer — never cash, never automatic. Status flows
/// pending → joined → rewarded (or → expired).
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  final _service = ReferralService();
  List<Referral> _referrals = [];
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
      final referrals = await _service.getReferrals();
      if (!mounted) return;
      setState(() {
        _referrals = referrals;
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
    final created = await showCreateReferralDialog(context);
    if (created != null) _load();
  }

  Future<void> _markJoined(Referral r) async {
    final memberId = await _pickMember(
      context,
      excludeMemberId: r.referrerMemberId,
      initialQuery: r.referredPhone.isNotEmpty ? r.referredPhone : r.referredName,
    );
    if (memberId == null) return;
    try {
      await _service.markJoined(r.id, referredMemberId: memberId);
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reward(Referral r) async {
    final days = await _promptRewardDays(context);
    if (days == null) return;
    try {
      final updated = await _service.rewardReferrer(r.id, rewardDays: days);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${updated.referrerName} credited $days free days')),
      );
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Referrals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New referral'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorBanner(message: _error!, onRetry: _load)
              : _referrals.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.diversity_3_outlined,
                      title: 'No referrals yet',
                      body: 'Members who bring in a friend show up here.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: _referrals.length,
                        separatorBuilder: (_, __) => AppSpacing.gapSm,
                        itemBuilder: (_, i) => _ReferralCard(
                          referral: _referrals[i],
                          onMarkJoined: () => _markJoined(_referrals[i]),
                          onReward: () => _reward(_referrals[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  final Referral referral;
  final VoidCallback onMarkJoined;
  final VoidCallback onReward;

  const _ReferralCard({required this.referral, required this.onMarkJoined, required this.onReward});

  (Color, Color) get _statusColors => switch (referral.status) {
        'joined' => (AppColors.info, AppColors.infoLight),
        'rewarded' => (AppColors.success, AppColors.successLight),
        'expired' => (AppColors.textSecondary, AppColors.background),
        _ => (AppColors.warning, AppColors.warningLight),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _statusColors;

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
              Expanded(
                child: Text('${referral.referrerName} → ${referral.referredName}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  referral.status[0].toUpperCase() + referral.status.substring(1),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
                ),
              ),
            ],
          ),
          AppSpacing.gapXs,
          Text(referral.referredPhone, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (referral.status == 'rewarded' && referral.rewardDays != null) ...[
            AppSpacing.gapXs,
            Text('Rewarded ${referral.rewardDays} free days',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.success)),
          ],
          if (referral.notes != null && referral.notes!.isNotEmpty) ...[
            AppSpacing.gapXs,
            Text('"${referral.notes}"',
                style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
          ],
          if (referral.status == 'pending' || referral.status == 'joined') ...[
            AppSpacing.gapMd,
            Row(
              children: [
                if (referral.status == 'pending')
                  TextButton(onPressed: onMarkJoined, child: const Text('Mark joined')),
                if (referral.status == 'joined')
                  TextButton(onPressed: onReward, child: const Text('Reward')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Create referral dialog ─────────────────────────────────────────────────

Future<Referral?> showCreateReferralDialog(BuildContext context) {
  return showDialog<Referral>(context: context, builder: (_) => const _CreateReferralDialog());
}

class _CreateReferralDialog extends StatefulWidget {
  const _CreateReferralDialog();

  @override
  State<_CreateReferralDialog> createState() => _CreateReferralDialogState();
}

class _CreateReferralDialogState extends State<_CreateReferralDialog> {
  final _service = ReferralService();
  final _memberService = MemberService();
  final _referrerSearchController = TextEditingController();
  final _referredNameController = TextEditingController();
  final _referredPhoneController = TextEditingController();
  final _notesController = TextEditingController();

  Timer? _debounce;
  List<Member> _results = [];
  Member? _referrer;

  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _referrerSearchController.dispose();
    _referredNameController.dispose();
    _referredPhoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final all = await _memberService.searchMembers(q);
      if (!mounted) return;
      setState(() {
        _results = all.take(6).toList();
        _searching = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _searching = false;
      });
    }
  }

  Future<void> _submit() async {
    final referrer = _referrer;
    final name = _referredNameController.text.trim();
    final phone = _referredPhoneController.text.trim();

    if (referrer == null) {
      setState(() => _error = 'Select the referring member');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = "Referred person's name is required");
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = "Referred person's phone is required");
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ref = await _service.createReferral(
        referrerMemberId: referrer.id,
        referredName: name,
        referredPhone: phone,
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, ref);
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
      title: 'New referral',
      subtitle: 'A member refers someone',
      icon: Icons.diversity_3,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(text: 'Create', loading: _saving, onPressed: _saving ? null : _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Referring member'),
          AppSpacing.gapXs,
          TextField(
            controller: _referrerSearchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search by name or phone…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
          if (_referrer == null && _results.isNotEmpty) ...[
            AppSpacing.gapSm,
            for (final m in _results) ...[
              InkWell(
                onTap: () => setState(() {
                  _referrer = m;
                  _results = [];
                  _referrerSearchController.text = '${m.firstName} ${m.lastName}';
                }),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('${m.firstName} ${m.lastName}', style: const TextStyle(fontSize: 13.5)),
                ),
              ),
              AppSpacing.gapXs,
            ],
          ],
          AppSpacing.gapLg,

          const LifecycleFieldLabel("Referred person's name"),
          AppSpacing.gapXs,
          TextField(
            controller: _referredNameController,
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'Full name'),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel("Referred person's phone"),
          AppSpacing.gapXs,
          TextField(
            controller: _referredPhoneController,
            autofillHints: const [],
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: 'Phone number'),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Notes (optional)'),
          AppSpacing.gapXs,
          TextField(
            controller: _notesController,
            autofillHints: const [],
          ),
        ],
      ),
    );
  }
}

// ─── Small helpers ───────────────────────────────────────────────────────────

Future<int?> _pickMember(
  BuildContext context, {
  required int excludeMemberId,
  String initialQuery = '',
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _MemberPickerDialog(excludeMemberId: excludeMemberId, initialQuery: initialQuery),
  );
}

class _MemberPickerDialog extends StatefulWidget {
  final int excludeMemberId;
  final String initialQuery;
  const _MemberPickerDialog({required this.excludeMemberId, this.initialQuery = ''});

  @override
  State<_MemberPickerDialog> createState() => _MemberPickerDialogState();
}

class _MemberPickerDialogState extends State<_MemberPickerDialog> {
  final _memberService = MemberService();
  late final _controller = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<Member> _results = [];
  bool _searching = false;
  // Distinguishes "haven't searched yet" from "searched, found nothing" —
  // the latter needs an explicit explanation, not a blank dialog that looks
  // frozen. The referred person must already exist as a Member before they
  // can be linked here; "Mark joined" doesn't create one.
  bool _searchedAtLeastOnce = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from the referral's own phone/name and search immediately —
    // staff shouldn't have to retype what we already recorded at creation.
    if (widget.initialQuery.trim().isNotEmpty) {
      _runSearch(widget.initialQuery.trim());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _searchedAtLeastOnce = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q.trim()));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    final all = await _memberService.searchMembers(q);
    if (!mounted) return;
    setState(() {
      _results = all.where((m) => m.id != widget.excludeMemberId).take(6).toList();
      _searching = false;
      _searchedAtLeastOnce = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: 'Which member joined?',
      subtitle: 'Search the new signup',
      icon: Icons.person_search,
      accent: AppColors.info,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            autofillHints: const [],
            decoration: InputDecoration(
              hintText: 'Search by name or phone…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
          AppSpacing.gapSm,
          if (!_searching && _searchedAtLeastOnce && _results.isEmpty)
            LifecycleNotice(
              tone: LifecycleTone.warning,
              text: 'No matching member found. The referred person needs to be '
                  'added as a Member first — go to Members → Add Member, then '
                  'come back here to link them.',
            ),
          for (final m in _results) ...[
            InkWell(
              onTap: () => Navigator.pop(context, m.id),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text('${m.firstName} ${m.lastName}', style: const TextStyle(fontSize: 13.5)),
              ),
            ),
            AppSpacing.gapXs,
          ],
        ],
      ),
    );
  }
}

Future<int?> _promptRewardDays(BuildContext context) {
  final controller = TextEditingController(text: '15');
  return showDialog<int>(
    context: context,
    builder: (_) => LifecycleDialogShell(
      title: 'Reward referral',
      subtitle: "Free days added to the referrer's membership",
      icon: Icons.card_giftcard,
      accent: AppColors.success,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        AppButton(
          text: 'Reward',
          onPressed: () {
            final days = int.tryParse(controller.text.trim()) ?? 0;
            Navigator.pop(context, days > 0 ? days : null);
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Free days'),
          AppSpacing.gapXs,
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofillHints: const [],
          ),
        ],
      ),
    ),
  );
}
