import 'package:flutter/material.dart';

import '../../models/payout.dart';
import '../../models/trainer.dart';
import '../../services/api_response.dart';
import '../../services/payout_service.dart';
import '../../services/trainer_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/money.dart';

/// Work out a trainer's pay for a month, then store it as a draft.
///
/// The preview comes first and is not skippable. Creating a draft to find out
/// what somebody earned, then cancelling it, would leave abandoned rows in a
/// money table — and the person approving the figure should see the lines
/// behind it before anything is written down.
Future<bool?> showNewPayoutSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NewPayoutSheet(),
  );
}

class _NewPayoutSheet extends StatefulWidget {
  const _NewPayoutSheet();

  @override
  State<_NewPayoutSheet> createState() => _NewPayoutSheetState();
}

class _NewPayoutSheetState extends State<_NewPayoutSheet> {
  final _service = PayoutService();

  List<Trainer> _trainers = [];
  Trainer? _trainer;

  /// Defaults to last whole month, which is the one a gym actually pays. This
  /// month is still running, and a payout for a period that has not finished
  /// is a number that will change after it is agreed.
  late DateTime _month = _lastMonth();

  PayoutPreview? _preview;
  bool _loadingTrainers = true;
  bool _previewing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrainers();
  }

  static DateTime _lastMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 1, 1);
  }

  DateTime get _from => DateTime(_month.year, _month.month, 1);
  DateTime get _to => DateTime(_month.year, _month.month + 1, 0);

  Future<void> _loadTrainers() async {
    try {
      final all = await TrainerService().getTrainers();
      if (!mounted) return;
      setState(() {
        _trainers = all.where((t) => t.status == 'active').toList();
        _loadingTrainers = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingTrainers = false;
      });
    }
  }

  Future<void> _runPreview() async {
    final t = _trainer;
    if (t == null) return;

    setState(() {
      _previewing = true;
      _error = null;
      _preview = null;
    });
    try {
      final p = await _service.preview(trainerId: t.id, from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _previewing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _previewing = false;
      });
    }
  }

  Future<void> _save() async {
    final t = _trainer;
    if (t == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.create(trainerId: t.id, from: _from, to: _to);
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
    final p = _preview;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
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
                const Text(
                  'Work out a payout',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nothing is paid here. This stores a draft for review.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 16),
                if (_loadingTrainers)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  DropdownButtonFormField<Trainer>(
                    initialValue: _trainer,
                    decoration: const InputDecoration(
                      labelText: 'Trainer',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in _trainers)
                        DropdownMenuItem(value: t, child: Text(t.fullName)),
                    ],
                    onChanged: _saving
                        ? null
                        : (t) {
                            setState(() {
                              _trainer = t;
                              _preview = null;
                            });
                            _runPreview();
                          },
                  ),
                  const SizedBox(height: 10),
                  _monthPicker(),
                ],

                if (_previewing) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],

                if (p != null) ...[const SizedBox(height: 14), _breakdown(p)],

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        (p == null || p.isEmpty || p.alreadyPaid || _saving)
                        ? null
                        : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save as draft'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthPicker() {
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i, 1),
    ];

    return DropdownButtonFormField<String>(
      initialValue: _key(_month),
      decoration: const InputDecoration(
        labelText: 'Month',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(),
      ),
      items: [
        for (final m in months)
          DropdownMenuItem(
            value: _key(m),
            child: Text(
              '${_monthNames[m.month - 1]} ${m.year}'
              // Naming the running month rather than hiding it: an owner may
              // genuinely want a mid-month figure, and a silently missing
              // option reads as a bug.
              '${m.month == now.month && m.year == now.year ? ' (still running)' : ''}',
            ),
          ),
      ],
      onChanged: _saving
          ? null
          : (k) {
              if (k == null) return;
              final parts = k.split('-');
              setState(() {
                _month = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
                _preview = null;
              });
              _runPreview();
            },
    );
  }

  static String _key(DateTime d) => '${d.year}-${d.month}';

  Widget _breakdown(PayoutPreview p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.alreadyPaid)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'A payout already covers this month for ${p.trainer}.',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),

          // The three schemes stay apart. A trainer asking why this month is
          // lower needs to see which part moved.
          if (p.salaryInPaise > 0) _line('Salary', p.salaryInPaise),
          if (p.commissionInPaise > 0)
            _line('Commission on PT collected', p.commissionInPaise),
          if (p.sessionsInPaise > 0)
            _line('Sessions delivered', p.sessionsInPaise),

          if (p.isEmpty)
            Text(
              'Nothing earned in this period.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),

          if (!p.isEmpty) ...[
            Divider(height: 18, color: Colors.grey.shade200),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  moneyShort(p.totalInPaise),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],

          if (p.lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'WHAT MAKES IT UP',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 5),
            for (final l in p.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        l.description,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      moneyShort(l.amountInPaise),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // Said here because the trainer will ask, and the owner should have
          // the number before the conversation rather than during it.
          if (p.uncollectedCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${moneyShort(p.uncollectedInPaise)} of PT this trainer sold has '
                'not been collected, across ${p.uncollectedCount} '
                '${p.uncollectedCount == 1 ? 'package' : 'packages'}. No '
                'commission is due on it until the money arrives.',
                style: const TextStyle(fontSize: 11, height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(String label, int paise) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
        Text(
          moneyShort(paise),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
