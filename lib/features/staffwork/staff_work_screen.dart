import 'package:flutter/material.dart';

import '../../models/staff_work.dart';
import '../../services/staff_work_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import 'staff_lead_work_view.dart';
import 'staff_work_items_sheet.dart';

/// What each person did on one day (FR-13).
///
/// Deliberately not a leaderboard. The list is ordered by name, there is no
/// score, and no row is ever coloured red for being low — the owner is being
/// shown a record to interpret, not a verdict to act on. A screen that ranks
/// staff gets them optimising for the count instead of the work.
class StaffWorkScreen extends StatefulWidget {
  const StaffWorkScreen({super.key});

  @override
  State<StaffWorkScreen> createState() => _StaffWorkScreenState();
}

class _StaffWorkScreenState extends State<StaffWorkScreen>
    with SingleTickerProviderStateMixin {
  final _service = StaffWorkService();

  late final TabController _tabs;

  bool _loading = true;
  String? _error;
  StaffWorkDay? _day;
  DateTime _date = DateTime.now();

  // Leads (FR-18 §7). Loaded on first visit — the money view is what most
  // people open, and paying for both on entry doubles the wait for nothing.
  LeadWorkReport? _leadWork;
  bool _leadsLoading = false;
  String? _leadsError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tabs.indexIsChanging) return;
        if (_tabs.index == 1 && _leadWork == null) _loadLeadWork();
      });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadLeadWork() async {
    setState(() {
      _leadsLoading = true;
      _leadsError = null;
    });
    try {
      final data = await _service.getLeadWork(date: _date);
      if (!mounted) return;
      setState(() {
        _leadWork = data;
        _leadsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _leadsError = e.toString();
        _leadsLoading = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final day = await _service.getDay(date: _date);
      if (!mounted) return;
      setState(() {
        _day = day;
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

  void _shiftDay(int days) {
    final next = _date.add(Duration(days: days));
    // No future days: the ledgers cannot contain tomorrow, and an empty screen
    // would look like a failure rather than like a date that has not happened.
    if (next.isAfter(DateTime.now())) return;
    setState(() {
      _date = next;
      _leadWork = null;
    });
    _load();
    if (_tabs.index == 1) _loadLeadWork();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Staff work"),
        toolbarHeight: 48,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () {
              _load();
              if (_tabs.index == 1) _loadLeadWork();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Money & work'),
            Tab(icon: Icon(Icons.person_search_rounded, size: 18), text: 'Leads'),
          ],
        ),
      ),
      body: Column(
        children: [
          _DateBar(
            date: _date,
            isToday: _isToday,
            onPrevious: () => _shiftDay(-1),
            onNext: _isToday ? null : () => _shiftDay(1),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_body(), _leadsBody()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorBanner(message: _error!, onRetry: _load);
    }

    final day = _day;
    if (day == null || day.isEmpty) {
      return const EmptyStateView(
        icon: Icons.beach_access_rounded,
        title: 'Nothing recorded',
        body: 'No payments, renewals, sales or member work were logged on this '
            'day. If the gym was open, nobody was signed in.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _DayTotals(day: day),
          const SizedBox(height: 8),
          ...day.staff.map((s) => _StaffCard(
                staff: s,
                date: _date,
                onOpenCategory: (category) => _openItems(s, category),
              )),
          const SizedBox(height: 12),
          const _Caveat(),
        ],
      ),
    );
  }

  Widget _leadsBody() {
    if (_leadsLoading) return const LoadingView();
    if (_leadsError != null) {
      return ErrorBanner(message: _leadsError!, onRetry: _loadLeadWork);
    }
    if (_leadWork == null) return const LoadingView();

    return RefreshIndicator(
      onRefresh: _loadLeadWork,
      child: StaffLeadWorkView(report: _leadWork!),
    );
  }

  void _openItems(StaffDay staff, StaffTally tally) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StaffWorkItemsSheet(
        date: _date,
        userId: staff.userId,
        staffName: staff.name,
        category: tally.category,
        title: tally.label,
      ),
    );
  }
}

/// Date navigation. One day at a time, on purpose — a week view is a different
/// question and would need a different query.
class _DateBar extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  const _DateBar({
    required this.date,
    required this.isToday,
    required this.onPrevious,
    this.onNext,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final label = isToday
        ? 'Today'
        : '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onPrevious,
          ),
          Expanded(
            child: Column(
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                if (!isToday)
                  Text(
                    '${date.day} ${_months[date.month - 1]} ${date.year}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: onNext == null ? 'Already on today' : 'Next day',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _DayTotals extends StatelessWidget {
  final StaffWorkDay day;

  const _DayTotals({required this.day});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: _figure(
              '${day.totalActions}',
              day.totalActions == 1 ? 'thing recorded' : 'things recorded',
            ),
          ),
          Container(width: 1, height: 34, color: Colors.grey.shade200),
          Expanded(
            child: _figure(
              _rupees(day.totalHandledInPaise),
              // "handled", never "earned" — a receptionist taking a ₹40,000
              // renewal did not generate ₹40,000 of value.
              'handled at the desk',
            ),
          ),
        ],
      ),
    );
  }

  Widget _figure(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      );
}

class _StaffCard extends StatelessWidget {
  final StaffDay staff;
  final DateTime date;
  final void Function(StaffTally) onOpenCategory;

  const _StaffCard({
    required this.staff,
    required this.date,
    required this.onOpenCategory,
  });

  @override
  Widget build(BuildContext context) {
    final unattributed = staff.isUnattributed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: unattributed
                      ? Colors.grey.shade200
                      : AppColors.primary.withValues(alpha: 0.12),
                  child: Icon(
                    unattributed
                        ? Icons.help_outline_rounded
                        : Icons.person_rounded,
                    size: 18,
                    color: unattributed
                        ? Colors.grey.shade600
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(),
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (staff.totalHandledInPaise > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_rupees(staff.totalHandledInPaise),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('collected',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ),
              ],
            ),

            if (unattributed) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  'Recorded without a signed-in user. Usually a shared login, '
                  'or data brought in from an import.',
                  style: TextStyle(
                      fontSize: 11.5, height: 1.35, color: Colors.grey.shade700),
                ),
              ),
            ],

            const SizedBox(height: 12),
            ...staff.tallies.map((t) => _TallyRow(
                  tally: t,
                  onTap: () => onOpenCategory(t),
                )),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (staff.role != null && staff.role!.isNotEmpty) parts.add(staff.role!);
    parts.add(staff.totalActions == 1
        ? '1 thing recorded'
        : '${staff.totalActions} things recorded');
    // No time span here on purpose. Several ledgers store a DATE with no clock
    // — a payment's paid_date has none — so those rows land on local midnight
    // and the range renders as "00:00–20:51", which reads as "started at
    // midnight" and is simply false. It would also imply hours worked, which
    // FR-13 §1 says this screen must never claim.
    return parts.join(' · ');
  }
}

class _TallyRow extends StatelessWidget {
  final StaffTally tally;
  final VoidCallback onTap;

  const _TallyRow({required this.tally, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text('${tally.count}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            Expanded(
              child: Text(tally.label,
                  style: const TextStyle(fontSize: 13)),
            ),
            if (tally.hasMoney)
              Text(_rupees(tally.amountInPaise!),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

/// Says out loud what the screen cannot see, where somebody reading it will
/// actually notice. A dashboard that quietly omits the busiest part of the day
/// invites the owner to draw a conclusion the data does not support.
class _Caveat extends StatelessWidget {
  const _Caveat();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This shows what was recorded in the system, not hours worked. '
              'Marking members in at the counter is not counted — check-ins do '
              'not record who served them.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

String _rupees(int paise) {
  final rupees = paise ~/ 100;
  if (rupees >= 100000) {
    return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  }
  if (rupees >= 1000) {
    return '₹${(rupees / 1000).toStringAsFixed(rupees >= 10000 ? 0 : 1)}k';
  }
  return '₹$rupees';
}
