import 'package:flutter/material.dart';

import '../../models/collection_queue.dart';
import '../../models/date_span.dart';
import '../../models/lead_pipeline.dart';
import '../../models/staff_work.dart';
import '../../services/lead_service.dart';
import '../../services/queue_service.dart';
import '../../services/staff_work_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/date_span_bar.dart';
import '../../widgets/loading_state.dart';
import '../leads/lead_detail_screen.dart';
import '../payments/collection_action_sheet.dart';
import '../payments/collections_view.dart';
import '../leads/lead_workflow_view.dart';
import '../leads/next_step_sheet.dart';
import 'staff_lead_work_view.dart';
import 'staff_work_items_sheet.dart';

/// What each person did over a day, a month, or a range (FR-13, FR-18 §9).
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
  DateSpan _span = DateSpan.today();

  // Leads (FR-18 §7). Loaded on first visit — the money view is what most
  // people open, and paying for both on entry doubles the wait for nothing.
  LeadWorkReport? _leadWork;
  bool _leadsLoading = false;
  String? _leadsError;

  // The workflow queue, the same one Leads → Workflow shows. Fetched here
  // rather than passed in, because this screen can be reached without going
  // through Leads at all.
  //
  // Deliberately not date-scoped: it is a list of decisions currently owed,
  // and what is owed does not change because the date control moved.
  LeadWorkflow? _workflow;

  // What is still owed in money, alongside what was collected. Same shape as
  // the Leads tab: the record above, the outstanding work below.
  //
  // Not date-scoped. A due is owed now whatever date the bar is showing, the
  // same reason the lead queue ignores it.
  CollectionQueue? _collections;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tabs.indexIsChanging) return;
        if (_tabs.index == 1 && _leadWork == null) _loadLeadWork();
      });
    StorageService.getRole().then((r) {
      if (mounted) setState(() => _isOwner = r == 'owner');
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
      // Both together: the tab is one screen and half of it arriving first
      // would reflow under the reader.
      final results = await Future.wait([
        _service.getLeadWork(span: _span),
        LeadService().getWorkflow(),
      ]);
      if (!mounted) return;
      setState(() {
        _leadWork = results[0] as LeadWorkReport;
        _workflow = results[1] as LeadWorkflow;
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
      // Together, so the tab does not reflow under the reader when the second
      // half lands.
      final results = await Future.wait([
        _service.getDay(span: _span),
        QueueService().getCollections(),
      ]);
      if (!mounted) return;
      setState(() {
        _day = results[0] as StaffWorkDay;
        _collections = results[1] as CollectionQueue;
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

  void _setSpan(DateSpan next) {
    if (next == _span) return;
    setState(() {
      _span = next;
      // Dropped rather than left stale. The Leads tab is not visible right now
      // if we are on the money tab, and showing July's funnel under an August
      // heading for the split second before the reload lands is worse than
      // showing a spinner.
      _leadWork = null;
    });
    _load();
    if (_tabs.index == 1) _loadLeadWork();
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
          DateSpanBar(span: _span, onChanged: _setSpan),
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
      return EmptyStateView(
        icon: Icons.beach_access_rounded,
        title: 'Nothing recorded',
        body: _span.isSingleDay
            ? 'No payments, renewals, sales or member work were logged on this '
                'day. If the gym was open, nobody was signed in.'
            : 'Nothing was logged between ${_span.fromParam} and '
                '${_span.toParam}. For a stretch this long that usually means '
                'the system was not in use yet, rather than a quiet spell.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _DayTotals(day: day, span: _span),
          const SizedBox(height: 8),
          ...day.staff.map((s) => _StaffCard(
                staff: s,
                onOpenCategory: (category) => _openItems(s, category),
              )),
          const SizedBox(height: 12),
          const _Caveat(),

          // What is still owed, under what was collected. Same arrangement as
          // the Leads tab, and the same reason: the record answers "what
          // happened", and the desk still needs "what is outstanding" without
          // changing screens.
          //
          // Grouped by member, never by collector. Nothing below totals money
          // against a staff member's name — a collections list that does is
          // one decision away from the sales leaderboard FR-13 §1 exists to
          // prevent.
          if (_collections != null && !_collections!.isClear) ...[
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                      child: Divider(color: Colors.grey.shade300, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      "MONEY STILL OWED",
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Colors.grey.shade500),
                    ),
                  ),
                  Expanded(
                      child: Divider(color: Colors.grey.shade300, height: 1)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(
                '${_collections!.totalCount} dues from '
                '${_collections!.membersInvolved} members. The same queue as '
                'Payments → Collections, and it ignores the dates above — a '
                'due is owed now whichever day you are looking at.',
                style: TextStyle(
                    fontSize: 11, height: 1.4, color: Colors.grey.shade600),
              ),
            ),
            ...CollectionsView(queue: _collections!, onAct: _actOnDue)
                .sections(showHeadline: false),
          ],
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

    final workflow = _workflow;

    return RefreshIndicator(
      onRefresh: _loadLeadWork,
      child: StaffLeadWorkView(
        report: _leadWork!,
        span: _span,
        onOpenLead: _openLead,
        queueSections: workflow == null
            ? const []
            : LeadWorkflowView(
                workflow: workflow,
                onTap: (item) => _openLead(item.leadId),
                onSetNextStep: _setNextStep,
              ).sections(showHeadline: false),
      ),
    );
  }

  Future<void> _actOnDue(CollectionItem item) async {
    final changed = await showCollectionActionSheet(
      context,
      item: item,
      isOwner: _isOwner,
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openLead(int leadId) async {
    final changed = await showLeadDetailPanel(context, leadId);
    if (!mounted) return;
    if (changed == true) await _loadLeadWork();
  }

  /// The only write on this screen, and always a human confirming.
  Future<void> _setNextStep(WorkflowItem item) async {
    final saved = await showNextStepSheet(
      context,
      leadName: item.name,
      stageLabel: item.stageLabel,
      currentStep: item.nextStep,
      currentDue: item.nextStepDue,
      onSave: (step, due, note) => LeadService()
          .setNextStep(item.leadId, step: step, due: due, note: note),
      // Clearing is deliberate, not a mistake to be prevented: a lead that
      // genuinely needs no next step should go back to Unattended rather than
      // carry a fake date somebody stops believing.
      onClear: item.nextStep == null
          ? null
          : () => LeadService().setNextStep(item.leadId),
    );
    if (saved == true && mounted) await _loadLeadWork();
  }

  void _openItems(StaffDay staff, StaffTally tally) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StaffWorkItemsSheet(
        span: _span,
        userId: staff.userId,
        staffName: staff.name,
        category: tally.category,
        title: tally.label,
      ),
    );
  }
}

class _DayTotals extends StatelessWidget {
  final StaffWorkDay day;
  final DateSpan span;

  const _DayTotals({required this.day, required this.span});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
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
          // Over a span, the window has to be on the card. The heading above
          // scrolls away, and a screenshot of "302 things recorded" with no
          // dates on it is the kind of number that gets quoted at somebody.
          if (!span.isSingleDay) ...[
            const SizedBox(height: 10),
            Text(
              'across ${span.sublabel}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
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
  final void Function(StaffTally) onOpenCategory;

  const _StaffCard({
    required this.staff,
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
