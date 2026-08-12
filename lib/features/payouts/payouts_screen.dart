import 'package:flutter/material.dart';

import '../../models/payout.dart';
import '../../services/api_response.dart';
import '../../services/payout_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import 'payout_new_sheet.dart';

/// Trainer payouts (FR-21 §2) — money the gym owes the people who work in it.
///
/// Drafts sit at the top because they are the ones that need something doing.
/// Paid ones stay visible below rather than disappearing: "did we pay Rohit
/// for August" is the question this screen gets asked most, and an archive you
/// have to go looking for does not answer it.
class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key});

  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends State<PayoutsScreen> {
  final _service = PayoutService();

  bool _loading = true;
  String? _error;
  List<Payout> _payouts = [];
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    StorageService.getRole().then((r) {
      if (mounted) setState(() => _isOwner = r == 'owner');
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await _service.list();
      if (!mounted) return;
      setState(() {
        _payouts = all;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Trainer pay'),
        toolbarHeight: 48,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final made = await showNewPayoutSheet(context);
          if (made == true && mounted) await _load();
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.calculate_rounded, size: 20),
        label: const Text('Work one out'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);

    if (_payouts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              const Text('No payouts yet',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Work one out for a trainer and a month. Nothing is paid '
                'until you say so.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final drafts = _payouts.where((p) => p.isDraft).toList();
    final settled = _payouts.where((p) => !p.isDraft).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          if (drafts.isNotEmpty) ...[
            _heading('Waiting to be paid', drafts.length),
            ...drafts.map((p) => _PayoutCard(
                  payout: p,
                  isOwner: _isOwner,
                  onChanged: _load,
                )),
          ],
          if (settled.isNotEmpty) ...[
            _heading('Already dealt with', settled.length),
            ...settled.map((p) => _PayoutCard(
                  payout: p,
                  isOwner: _isOwner,
                  onChanged: _load,
                )),
          ],
        ],
      ),
    );
  }

  Widget _heading(String text, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Row(
          children: [
            Text(text,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.bold)),
            const SizedBox(width: 7),
            Text('$n',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      );
}

class _PayoutCard extends StatelessWidget {
  final Payout payout;
  final bool isOwner;
  final VoidCallback onChanged;

  const _PayoutCard({
    required this.payout,
    required this.isOwner,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => _openDetail(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(payout.trainer,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(_period(),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_rupees(payout.totalInPaise),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: payout.isDraft
                                    ? AppColors.primary
                                    : Colors.grey.shade700)),
                        _statusTag(),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // The three schemes, on one line. Enough to see at a glance
                // why a figure is what it is without opening anything.
                Text(_composition(),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (payout.isPaid && payout.paidBy != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Paid by ${payout.paidBy}'
                    '${payout.paymentMode == null ? '' : ' · ${payout.paymentMode}'}'
                    '${payout.referenceNumber == null ? '' : ' · ${payout.referenceNumber}'}',
                    style:
                        TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _period() {
    final s = payout.periodStart;
    final e = payout.periodEnd;
    if (s.month == e.month && s.year == e.year) {
      return '${_months[s.month - 1]} ${s.year}';
    }
    return '${s.day} ${_months[s.month - 1]} — ${e.day} ${_months[e.month - 1]}';
  }

  String _composition() {
    final parts = <String>[];
    if (payout.salaryInPaise > 0) {
      parts.add('salary ${_rupees(payout.salaryInPaise)}');
    }
    if (payout.commissionInPaise > 0) {
      parts.add('commission ${_rupees(payout.commissionInPaise)}');
    }
    if (payout.sessionsInPaise > 0) {
      parts.add('sessions ${_rupees(payout.sessionsInPaise)}');
    }
    if (payout.adjustmentInPaise != 0) {
      parts.add('adjustment ${_rupees(payout.adjustmentInPaise)}');
    }
    return parts.isEmpty ? 'nothing earned' : parts.join(' · ');
  }

  Widget _statusTag() {
    final (label, colour) = switch (payout.status) {
      'paid' => ('paid', AppColors.success),
      'cancelled' => ('cancelled', Colors.grey),
      _ => ('draft', AppColors.warning),
    };
    return Text(label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: colour));
  }

  Future<void> _openDetail(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayoutDetailSheet(id: payout.id, isOwner: isOwner),
    );
    if (changed == true) onChanged();
  }
}

/// One payout, with the lines behind its total.
///
/// The lines are the point. A payout figure nobody can check is one neither
/// the owner approving it nor the trainer accepting it should be asked to
/// trust.
class _PayoutDetailSheet extends StatefulWidget {
  final int id;
  final bool isOwner;

  const _PayoutDetailSheet({required this.id, required this.isOwner});

  @override
  State<_PayoutDetailSheet> createState() => _PayoutDetailSheetState();
}

class _PayoutDetailSheetState extends State<_PayoutDetailSheet> {
  final _service = PayoutService();
  final _reference = TextEditingController();

  Payout? _payout;
  String _mode = 'cash';
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _service.get(widget.id);
      if (!mounted) return;
      setState(() {
        _payout = p;
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

  Future<void> _pay() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _service.markPaid(widget.id,
          paymentMode: _mode, referenceNumber: _reference.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _working = false;
      });
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _service.cancel(widget.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _payout;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SafeArea(
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (p == null)
                        Text(_error ?? 'Could not load that payout.')
                      else ...[
                        Text(p.trainer,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        Text(_rupees(p.totalInPaise),
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                        const SizedBox(height: 12),

                        for (final l in p.lines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(l.description,
                                      style: const TextStyle(fontSize: 12.5)),
                                ),
                                const SizedBox(width: 10),
                                Text(_rupees(l.amountInPaise),
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),

                        if (p.isDraft && widget.isOwner) ...[
                          const SizedBox(height: 14),
                          Divider(color: Colors.grey.shade200),
                          const SizedBox(height: 10),
                          const Text('Record the payment',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _mode,
                            decoration: const InputDecoration(
                              labelText: 'How',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'cash', child: Text('Cash')),
                              DropdownMenuItem(
                                  value: 'upi', child: Text('UPI')),
                              DropdownMenuItem(
                                  value: 'bank_transfer',
                                  child: Text('Bank transfer')),
                            ],
                            onChanged: _working
                                ? null
                                : (v) => setState(() => _mode = v ?? 'cash'),
                          ),
                          const SizedBox(height: 9),
                          TextField(
                            controller: _reference,
                            enabled: !_working,
                            decoration: const InputDecoration(
                              labelText: 'Reference (optional)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],

                        if (p.isDraft && !widget.isOwner) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Only an owner can record this as paid. It is the '
                            'one action in the app that moves cash out of the '
                            'gym.',
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Colors.grey.shade600),
                          ),
                        ],

                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.danger)),
                        ],

                        if (p.isDraft) ...[
                          const SizedBox(height: 14),
                          if (widget.isOwner)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _working ? null : _pay,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                ),
                                child: _working
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : Text('Paid ${_rupees(p.totalInPaise)}'),
                              ),
                            ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _working ? null : _cancel,
                              child: const Text('Discard this draft'),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _rupees(int paise) {
  final neg = paise < 0;
  final rupees = (neg ? -paise : paise) ~/ 100;
  final sign = neg ? '-' : '';
  if (rupees >= 100000) {
    return '$sign₹${(rupees / 100000).toStringAsFixed(1)}L';
  }
  if (rupees >= 1000) {
    return '$sign₹${(rupees / 1000).toStringAsFixed(rupees >= 10000 ? 0 : 1)}k';
  }
  return '$sign₹$rupees';
}
