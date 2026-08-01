import 'package:flutter/material.dart';

import '../../models/visitor.dart';
import '../../services/api_response.dart';
import '../../services/visitor_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Walk-in visitor log — distinct from Leads (an enquiry) and Members (a
/// signup). A visit only becomes a lead when staff explicitly convert it;
/// nothing here happens automatically.
class VisitorsScreen extends StatefulWidget {
  const VisitorsScreen({super.key});

  @override
  State<VisitorsScreen> createState() => _VisitorsScreenState();
}

class _VisitorsScreenState extends State<VisitorsScreen> {
  final _service = VisitorService();
  List<Visitor> _visitors = [];
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
      final visitors = await _service.list(from: DateTime.now(), to: DateTime.now());
      if (!mounted) return;
      setState(() {
        _visitors = visitors;
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

  Future<void> _checkIn() async {
    final result = await showCheckInDialog(context);
    if (result != null) _load();
  }

  Future<void> _checkOut(Visitor v) async {
    try {
      await _service.checkOut(v.id);
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _convertToLead(Visitor v) async {
    try {
      await _service.convertToLead(v.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${v.name} added to Leads (source: walk-in)')),
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
      appBar: AppBar(title: const Text('Visitors')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _checkIn,
        icon: const Icon(Icons.how_to_reg),
        label: const Text('Check in'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorBanner(message: _error!, onRetry: _load)
              : _visitors.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.groups_2_outlined,
                      title: 'No visits today',
                      body: 'Walk-ins and trial visitors will show up here.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: _visitors.length,
                        separatorBuilder: (_, __) => AppSpacing.gapSm,
                        itemBuilder: (_, i) => _VisitorCard(
                          visitor: _visitors[i],
                          onCheckOut: () => _checkOut(_visitors[i]),
                          onConvert: () => _convertToLead(_visitors[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _VisitorCard extends StatelessWidget {
  final Visitor visitor;
  final VoidCallback onCheckOut;
  final VoidCallback onConvert;

  const _VisitorCard({required this.visitor, required this.onCheckOut, required this.onConvert});

  static const _purposeLabels = {
    'trial': 'Trial',
    'guest': 'Guest',
    'tour': 'Tour',
    'other': 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final timeIn = _fmtTime(visitor.checkedInAt);
    final timeOut = visitor.checkedOutAt != null ? _fmtTime(visitor.checkedOutAt!) : null;

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
                child: Text(visitor.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: visitor.stillInBuilding ? AppColors.successLight : AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  visitor.stillInBuilding ? 'In building' : 'Checked out',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: visitor.stillInBuilding ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            [
              _purposeLabels[visitor.purpose] ?? visitor.purpose,
              if (visitor.phone != null && visitor.phone!.isNotEmpty) visitor.phone!,
              timeOut != null ? '$timeIn – $timeOut' : 'In at $timeIn',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (visitor.hostStaffName != null) ...[
            AppSpacing.gapXs,
            Text('Hosted by ${visitor.hostStaffName}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          AppSpacing.gapMd,
          Row(
            children: [
              if (visitor.convertedLeadId == null)
                TextButton.icon(
                  onPressed: onConvert,
                  icon: const Icon(Icons.person_add_alt, size: 16),
                  label: const Text('Convert to lead'),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Converted to lead', style: TextStyle(fontSize: 12, color: AppColors.success)),
                ),
              const Spacer(),
              if (visitor.stillInBuilding)
                TextButton(onPressed: onCheckOut, child: const Text('Check out')),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

// ─── Check-in dialog ────────────────────────────────────────────────────────

Future<Visitor?> showCheckInDialog(BuildContext context) {
  return showDialog<Visitor>(context: context, builder: (_) => const _CheckInDialog());
}

class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog();

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  final _service = VisitorService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _purpose = 'trial';

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final v = await _service.checkIn(
        name: name,
        phone: _phoneController.text.trim(),
        purpose: _purpose,
      );
      if (!mounted) return;
      Navigator.pop(context, v);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  static const _purposes = [
    ('trial', 'Trial'),
    ('guest', 'Guest'),
    ('tour', 'Tour'),
    ('other', 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: 'Check in visitor',
      subtitle: 'Walk-ins, trials, tours',
      icon: Icons.how_to_reg,
      accent: AppColors.info,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(text: 'Check in', loading: _saving, onPressed: _saving ? null : _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Name'),
          AppSpacing.gapXs,
          TextField(
            controller: _nameController,
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'Full name'),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Phone (optional)'),
          AppSpacing.gapXs,
          TextField(
            controller: _phoneController,
            autofillHints: const [],
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: 'Phone number'),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Purpose'),
          AppSpacing.gapXs,
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in _purposes)
                ChoiceChip(
                  label: Text(label),
                  selected: _purpose == value,
                  onSelected: (_) => setState(() => _purpose = value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
