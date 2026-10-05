import 'package:flutter/material.dart';

import '../../models/collection_queue.dart';
import '../../models/date_span.dart';
import '../../models/expected_payments.dart';
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
import '../../widgets/readable_width.dart';
import '../leads/lead_detail_screen.dart';
import '../payments/collection_action_sheet.dart';
import '../payments/collections_view.dart';
import '../payments/expected_view.dart';
import '../payments/raise_due_sheet.dart';
import '../leads/lead_workflow_view.dart';
import '../leads/next_step_sheet.dart';
import 'staff_analytics_screen.dart';
import 'staff_lead_work_view.dart';
import 'staff_work_items_sheet.dart';
import '../../utils/money.dart';

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

  // What is coming, as opposed to what came in. The only date-scoped queue:
  // "expected" is a question about a window by definition, so unlike the
  // other two this one reloads when the date control moves.
  ExpectedPayments? _expected;
  bool _expectedLoading = false;
  String? _expectedError;

  // Raised dues ticked for invoicing. Cleared whenever the span changes: the
  // rows underneath are about to be different ones, and a selection that
  // survives a reload would invoice something the reader is no longer looking
  // at.
  final Set<int> _toInvoice = {};
  bool _invoicing = false;

  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this)
      ..addListener(() {
        if (_tabs.indexIsChanging) return;
        // Rebuild on every settled tab change: the date bar and the button
        // below both depend on which tab is showing.
        setState(() {});
        if (_tabs.index == 1 && _expected == null) _loadExpected();
        if (_tabs.index >= 3 && _leadWork == null) _loadLeadWork();
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

  Future<void> _loadExpected() async {
    setState(() {
      _expectedLoading = true;
      _expectedError = null;
      _toInvoice.clear();
    });
    try {
      final data = await QueueService().getExpected(span: _span);
      if (!mounted) return;
      setState(() {
        _expected = data;
        _expectedLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _expectedError = e.toString();
        _expectedLoading = false;
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
      // Dropped for the same reason, and it matters more here: this is the one
      // view whose every number is scoped to the range, so a stale copy under
      // a new heading would be wrong rather than merely old.
      _expected = null;
    });
    _load();
    if (_tabs.index == 1) _loadExpected();
    if (_tabs.index >= 3) _loadLeadWork();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Staff work"),
        toolbarHeight: 48,
        actions: [
          // Analytics rather than a sixth tab. It answers a different
          // question — how the work moved over time, not what happened — and
          // it carries the chosen window across so the reader does not land
          // on a different period without noticing.
          IconButton(
            tooltip: 'How the work moved',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StaffAnalyticsScreen(span: _span),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading
                ? null
                : () {
                    _load();
                    if (_tabs.index == 1) _loadExpected();
                    if (_tabs.index >= 3) _loadLeadWork();
                  },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(
              icon: Icon(Icons.receipt_long_rounded, size: 18),
              text: 'Money & work',
            ),
            // Next to the record of what came in, because it is the same
            // question pointed the other way down the calendar.
            Tab(
              icon: Icon(Icons.trending_up_rounded, size: 18),
              text: 'Expected',
            ),
            Tab(
              icon: Icon(Icons.request_quote_rounded, size: 18),
              text: 'Collect',
            ),
            Tab(
              icon: Icon(Icons.person_search_rounded, size: 18),
              text: 'Leads',
            ),
            Tab(
              icon: Icon(Icons.checklist_rounded, size: 18),
              text: 'Follow up',
            ),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 2
          ? FloatingActionButton.extended(
              onPressed: _raiseDue,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Raise a due'),
            )
          : null,
      body: Column(
        children: [
          // Hidden on the two queues. Both are lists of what is owed right
          // now, neither is date-scoped, and a date control sitting above a
          // list it does not filter invites the reader to trust a narrowing
          // that never happened.
          if (_tabs.index != 2 && _tabs.index != 4)
            DateSpanBar(span: _span, onChanged: _setSpan),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _body(),
                _expectedBody(),
                _collectBody(),
                _leadsBody(),
                _followUpBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What the gym has reason to expect over the chosen span.
  ///
  /// The mirror of Money & work: that answers "what came in", this answers
  /// "what is coming". It is the one tab where the date control changes every
  /// number on screen rather than just the record above a queue.
  Widget _expectedBody() {
    if (_expectedLoading) return const LoadingView();
    if (_expectedError != null) {
      return ErrorBanner(message: _expectedError!, onRetry: _loadExpected);
    }
    final data = _expected;
    if (data == null) return const LoadingView();

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadExpected,
            child: ExpectedView(
              data: data,
              selected: _toInvoice,
              onToggle: (paymentId) => setState(() {
                if (!_toInvoice.remove(paymentId)) _toInvoice.add(paymentId);
              }),
              onRaiseDue: _agreeAndRaise,
            ),
          ),
        ),
        if (_toInvoice.isNotEmpty) _invoiceBar(),
      ],
    );
  }

  /// Only appears once something is ticked, and says the two things a person
  /// needs before pressing it: how many documents this makes, and that they
  /// are drafts.
  // The tallest this bar is ever allowed to be. Chosen to comfortably fit two
  // lines of text and a full-height button with the surrounding padding —
  // see the sizing note below.
  static const _barHeight = 72.0;

  Widget _invoiceBar() {
    final n = _toInvoice.length;
    // A hard height cap, not a hint. Two rebuilds fixed the wrapping labels
    // that were once reported here — maxLines, no left/right SafeArea inset —
    // and the tab still collapsed on a live device after the fix was
    // confirmed deployed. Whatever is narrowing this Row is happening
    // somewhere this codebase does not reach: not the widget tree tests can
    // probe, not stale caching, ruled out on the running build. Rather than
    // keep chasing an environment that cannot be reproduced, the box itself
    // now refuses to grow. Content that still overflows a too-narrow width
    // clips silently inside it; the Expanded list above always gets
    // `available height − _barHeight`, full stop, whatever the Row inside is
    // doing.
    return SizedBox(
      height: _barHeight,
      child: ClipRect(
        child: Material(
          elevation: 8,
          color: Colors.white,
          // Bottom inset only. Left and right are deliberately off: this bar
          // sits edge to edge and has no edge to avoid.
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Both labels are single-line and clip. A summary bar must
                        // stay one row high whatever width it is handed — if it
                        // grows instead, it eats the list it is summarising.
                        Text(
                          '$n ${n == 1 ? 'due' : 'dues'} selected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Creates drafts — nothing is issued',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _invoicing
                        ? null
                        : () => setState(_toInvoice.clear),
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: _invoicing ? null : _createInvoices,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _invoicing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create invoices'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createInvoices() async {
    setState(() => _invoicing = true);
    try {
      final result = await QueueService().invoiceDues(
        paymentIds: _toInvoice.toList(),
      );
      if (!mounted) return;

      // Both halves reported. A batch that says only what it created lets an
      // already-invoiced due look handled.
      final parts = <String>[
        '${result.invoiceCount} '
            '${result.invoiceCount == 1 ? 'draft invoice' : 'draft invoices'}',
        if (result.skipped.isNotEmpty) '${result.skipped.length} skipped',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${parts.join(' · ')}. '
            'Find them under Invoices to check and issue.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      setState(() => _invoicing = false);
      await _loadExpected();
    } catch (e) {
      if (!mounted) return;
      setState(() => _invoicing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// An expiring membership becomes invoiceable only once somebody records
  /// that the member agreed to renew. That is what this does — it raises a
  /// real due, which the next refresh shows as a tickable row.
  Future<void> _agreeAndRaise(ExpectedItem item) async {
    final raised = await showRaiseDueSheet(
      context,
      member: RaiseDuePrefill(
        memberId: item.memberId,
        name: item.member,
        phone: item.phone,
        amountInPaise: item.amountInPaise,
      ),
    );
    if (raised == true && mounted) await _loadExpected();
  }

  /// Everything still owed, as its own tab rather than a footer under the
  /// record. Money & work answers "what happened"; this answers "what is left
  /// to do" — different readers, different times of day, and the queue was
  /// nine tenths of the tab it used to be buried in.
  Widget _collectBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorBanner(message: _error!, onRetry: _load);
    }
    final queue = _collections;
    if (queue == null) return const LoadingView();

    return RefreshIndicator(
      onRefresh: _load,
      child: CollectionsView(queue: queue, onAct: _actOnDue),
    );
  }

  Future<void> _raiseDue() async {
    final raised = await showRaiseDueSheet(context);
    if (raised == true && mounted) await _load();
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
      // Capped like every other card list. Left uncapped, a person's name and
      // their counts end up a hand's width apart on a wide monitor.
      child: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _DayTotals(day: day, span: _span),
            const SizedBox(height: 8),
            ...day.staff.map(
              (s) => _StaffCard(
                staff: s,
                onOpenCategory: (category) => _openItems(s, category),
              ),
            ),
            const SizedBox(height: 12),
            const _Caveat(),

            // What is still owed lives in the Collect tab next door, not here.
            // This card is a record of a chosen day; that is a worklist owed
            // now. Pointed at rather than duplicated, so the desk never works
            // the same due from two places.
            if (_collections != null && !_collections!.isClear) ...[
              const SizedBox(height: 14),
              _QueuePointer(
                icon: Icons.request_quote_rounded,
                headline:
                    '${moneyShort(_collections!.totalInPaise)} still owed',
                detail:
                    '${_collections!.totalCount} dues from '
                    '${_collections!.membersInvolved} members'
                    '${_collections!.unchasedCount == 0 ? '' : ' · ${_collections!.unchasedCount} with nobody on them'}'
                    '. Not tied to the dates above.',
                alarming: _collections!.unchasedCount > 0,
                onOpen: () => _tabs.animateTo(2),
              ),
            ],
          ],
        ),
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
        footer: workflow == null || workflow.isEmpty
            ? null
            : _QueuePointer(
                icon: Icons.checklist_rounded,
                headline: workflow.unattended == 0
                    ? '${workflow.totalOpen} open leads'
                    : '${workflow.unattended} leads nobody has picked up',
                detail:
                    '${workflow.totalOpen} open · '
                    '${workflow.overdue} overdue · '
                    '${workflow.dueToday} due today. Counted as it stands '
                    'now, not for the dates above.',
                alarming: workflow.unattended > 0,
                onOpen: () => _tabs.animateTo(4),
              ),
      ),
    );
  }

  /// The decisions owed on open leads. The tab next door is the record — who
  /// is carrying what, and how they are coping. This is the worklist, and it
  /// was nine tenths of that tab when the two shared one.
  Widget _followUpBody() {
    if (_leadsLoading) return const LoadingView();
    if (_leadsError != null) {
      return ErrorBanner(message: _leadsError!, onRetry: _loadLeadWork);
    }
    final workflow = _workflow;
    if (workflow == null) return const LoadingView();

    return RefreshIndicator(
      onRefresh: _loadLeadWork,
      child: LeadWorkflowView(
        workflow: workflow,
        onTap: (item) => _openLead(item.leadId),
        onSetNextStep: _setNextStep,
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
      onSave: (step, due, note) => LeadService().setNextStep(
        item.leadId,
        step: step,
        due: due,
        note: note,
      ),
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

/// A signpost to a queue tab, not a second copy of it.
///
/// The record above it is about a chosen day. What is owed is not — so it gets
/// a headline figure and a way through, and the rows stay in one place where
/// two people cannot work the same item from two screens.
class _QueuePointer extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String detail;

  /// Colours the icon and nothing else. The card must never turn into a
  /// warning banner — it is a doorway, and the queue behind it does the
  /// arguing.
  final bool alarming;
  final VoidCallback onOpen;

  const _QueuePointer({
    required this.icon,
    required this.headline,
    required this.detail,
    required this.alarming,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: alarming ? AppColors.danger : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
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
                  moneyShort(day.totalHandledInPaise),
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
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ],
  );
}

class _StaffCard extends StatelessWidget {
  final StaffDay staff;
  final void Function(StaffTally) onOpenCategory;

  const _StaffCard({required this.staff, required this.onOpenCategory});

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
                      Text(
                        staff.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (staff.totalHandledInPaise > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        moneyShort(staff.totalHandledInPaise),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'collected',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
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
                    fontSize: 11.5,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),
            ...staff.tallies.map(
              (t) => _TallyRow(tally: t, onTap: () => onOpenCategory(t)),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (staff.role != null && staff.role!.isNotEmpty) parts.add(staff.role!);
    parts.add(
      staff.totalActions == 1
          ? '1 thing recorded'
          : '${staff.totalActions} things recorded',
    );
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
              child: Text(
                '${tally.count}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            Expanded(
              child: Text(tally.label, style: const TextStyle(fontSize: 13)),
            ),
            if (tally.hasMoney)
              Text(
                moneyShort(tally.amountInPaise!),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.grey.shade400,
            ),
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
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: Colors.grey.shade500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This shows what was recorded in the system, not hours worked. '
              'Marking members in at the counter is not counted — check-ins do '
              'not record who served them.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
