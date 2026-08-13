import 'package:flutter/material.dart';

import '../../models/lead.dart';
import '../../models/lead_pipeline.dart';
import '../../services/api_response.dart';
import '../../services/lead_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';

import 'add_lead_screen.dart';
import 'convert_lead_screen.dart';
import 'lead_analytics_view.dart';
import 'lead_detail_screen.dart';
import 'lead_followups_view.dart';
import 'lead_kanban_board.dart';
import 'lead_workflow_view.dart';
import 'next_step_sheet.dart';
import 'stage_note_sheet.dart';
import 'leads_body.dart';

/// Lead CRM. Four views over the same pipeline:
///   List      — filter/search the leads themselves
///   Board     — the whole funnel at once, one column per stage
///   Follow-ups— the daily action queue (overdue first)
///   Analytics — conversion, source performance, loss reasons
///
/// Each tab owns its own fetch and loads lazily on first visit, so opening the
/// screen costs exactly one request rather than four.
class LeadsScreen extends StatefulWidget {
  /// Which sub-tab to open on: 0 List, 1 Board, 2 Follow-ups, 3 Analytics.
  final int initialTab;

  /// The board. Named rather than a bare `1` because the shell opens Leads
  /// here by default (FR-14 §2), and a reordered TabBar should not silently
  /// land every user on Analytics instead.
  static const int boardTab = 1;

  /// The workflow queue (FR-18) — what is owed, unattended first.
  static const int workflowTab = 2;

  const LeadsScreen({super.key, this.initialTab = 0});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // List / Board
  bool _isLoading = true;
  String? _error;
  List<Lead> _leads = [];

  // Follow-ups
  FollowUpQueue? _followUps;
  bool _followUpsLoading = false;
  String? _followUpsError;

  // Workflow (FR-18)
  LeadWorkflow? _workflow;
  bool _workflowLoading = false;
  String? _workflowError;

  // Analytics
  LeadAnalytics? _analytics;
  bool _analyticsLoading = false;
  String? _analyticsError;

  // Assignment
  List<Assignee> _assignees = [];
  String _assignedTo = ''; // '' | 'unassigned' | '<userId>'

  bool _dataChanged = false;
  String _selectedStatus = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 5,
      initialIndex: widget.initialTab.clamp(0, 4),
      vsync: this,
    )..addListener(_onTabChanged);
    _load();
    _loadAssignees();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    // Fetch on first visit only; pull-to-refresh and mutations handle the rest.
    if (_tabs.index == 2 && _workflow == null) _loadWorkflow();
    if (_tabs.index == 3 && _followUps == null) _loadFollowUps();
    if (_tabs.index == 4 && _analytics == null) _loadAnalytics();
  }

  // ─── Loads ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await LeadService().getLeads(
        status: _selectedStatus,
        search: _searchController.text.trim(),
        assignedTo: _assignedTo,
        // The board needs every lead at once — a 30-row page would silently
        // truncate the columns and misrepresent the funnel.
        perPage: 200,
      );
      if (!mounted) return;
      setState(() {
        _leads = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : "Couldn't load your leads. Please try again.";
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAssignees() async {
    try {
      final data = await LeadService().getAssignees();
      if (!mounted) return;
      setState(() => _assignees = data);
    } catch (_) {
      // Non-fatal: the owner filter just won't offer names.
    }
  }

  Future<void> _loadFollowUps() async {
    setState(() {
      _followUpsLoading = true;
      _followUpsError = null;
    });
    try {
      final data = await LeadService().getFollowUps();
      if (!mounted) return;
      setState(() {
        _followUps = data;
        _followUpsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _followUpsError = e is ApiException
            ? e.message
            : "Couldn't load follow-ups.";
        _followUpsLoading = false;
      });
    }
  }

  /// Which axis the follow-up queue is cut along (FR-24). Timing is the
  /// default because "what is late" is the question the desk opens this
  /// screen to answer; the others are for the person deciding where effort
  /// goes.
  String _workflowAxis = 'timing';

  Future<void> _loadWorkflow() async {
    setState(() {
      _workflowLoading = true;
      _workflowError = null;
    });
    try {
      final data = await LeadService().getWorkflow(groupBy: _workflowAxis);
      if (!mounted) return;
      setState(() {
        _workflow = data;
        _workflowLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _workflowError = e is ApiException
            ? e.message
            : "Couldn't load the workflow.";
        _workflowLoading = false;
      });
    }
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _analyticsLoading = true;
      _analyticsError = null;
    });
    try {
      final data = await LeadService().getAnalytics();
      if (!mounted) return;
      setState(() {
        _analytics = data;
        _analyticsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyticsError = e is ApiException
            ? e.message
            : "Couldn't load analytics.";
        _analyticsLoading = false;
      });
    }
  }

  /// After any mutation, refresh the active view and invalidate the others so
  /// a stale funnel or queue can't linger behind a tab.
  void _invalidateDerived() {
    _workflow = null;
    _followUps = null;
    _analytics = null;
    if (_tabs.index == 2) _loadWorkflow();
    if (_tabs.index == 3) _loadFollowUps();
    if (_tabs.index == 4) _loadAnalytics();
  }

  Future<void> _refreshAll() async {
    _dataChanged = true;
    await _load();
    _invalidateDerived();
  }

  // ─── Filters ────────────────────────────────────────────────────────────────

  void _onStatusChanged(String status) {
    setState(() => _selectedStatus = status);
    _load();
  }

  void _onSearchChanged(String _) => _load();

  void _onAssignedToChanged(String? value) {
    setState(() => _assignedTo = value ?? '');
    _load();
  }

  // ─── Lead actions ───────────────────────────────────────────────────────────

  Future<void> _openAddLead() async {
    final result = await showAddLeadDialog(context);
    if (result == true) await _refreshAll();
  }

  Future<void> _openDetail(Lead lead) async {
    final result = await showLeadDetailPanel(context, lead.id);
    if (!mounted) return;

    if (result == true) {
      await _refreshAll();
    } else if (result == 'convert') {
      await _openConvert(lead);
    } else if (result == 'lost') {
      await _markLost(lead);
    } else if (result == 'delete') {
      await _confirmDeleteLead(lead);
    }
  }

  Future<void> _openConvert(Lead lead) async {
    Lead current;
    try {
      current = await LeadService().getLead(lead.id);
    } catch (_) {
      current = lead;
    }
    if (!mounted) return;

    final memberId = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => ConvertLeadScreen(lead: current)),
    );
    if (memberId != null && memberId > 0) {
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${current.name} is now a member'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  /// Moving a lead to any stage. 'lost' is special-cased because the backend
  /// requires a reason, and that reason is what powers the loss analytics.
  Future<void> _moveStage(Lead lead, String newStatus) async {
    if (newStatus == 'lost') {
      await _markLost(lead);
      return;
    }
    await _advance(lead, newStatus);
  }

  Future<void> _markLost(Lead lead) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark as Lost'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            hintText: 'e.g. Price too high, joined another gym',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Confirm',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) return;

    try {
      await LeadService().advanceStatus(lead.id, 'lost', lostReason: reason);
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : "Couldn't mark this lead as lost.",
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteLead(Lead lead) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Lead'),
        content: Text('Delete ${lead.name}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await LeadService().deleteLead(lead.id);
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : "Couldn't delete this lead.",
          ),
        ),
      );
    }
  }

  Future<void> _advance(Lead lead, String newStatus) async {
    // Ask why before moving. Dismissing the sheet cancels the move entirely,
    // so a mis-drag is undone by swiping the sheet away rather than dragging
    // the card back.
    final result = await showStageNoteSheet(
      context,
      leadName: lead.name,
      fromStatus: lead.status,
      toStatus: newStatus,
    );
    if (result == null || !mounted) return;

    try {
      await LeadService().advanceStatus(lead.id, newStatus, note: result.note);
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.message
                : "Couldn't update this lead's status.",
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ─── Follow-up quick actions ────────────────────────────────────────────────

  Future<void> _logCall(Lead lead) async {
    final noteController = TextEditingController();
    // What came of it (FR-16). Chosen first because it is the answer staff
    // actually have the moment they hang up — the note is often skipped, the
    // outcome almost never is.
    String? outcome;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Log call — ${lead.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What happened?',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in FollowUpOutcome.all)
                    ChoiceChip(
                      label: Text(
                        o.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: outcome == o.value,
                      onSelected: (sel) =>
                          setLocal(() => outcome = sel ? o.value : null),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Anything worth remembering?',
                  hintText: 'e.g. Asked about pricing, will decide this week',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            // Deliberately enabled with no outcome selected: a staff member
            // mid-shift must never be blocked by a dropdown (FR-16 §3).
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    try {
      await LeadService().addActivity(
        lead.id,
        type: 'call',
        note: noteController.text.trim(),
        outcome: outcome ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Call logged for ${lead.name}'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadFollowUps();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : "Couldn't log the call.",
          ),
        ),
      );
    }
  }

  Future<void> _reschedule(Lead lead) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Next follow-up for ${lead.name}',
    );
    if (picked == null || !mounted) return;

    final iso =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';

    try {
      await LeadService().addActivity(
        lead.id,
        type: 'follow_up_set',
        note: 'Follow-up rescheduled',
        date: iso,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Follow-up set for ${lead.name}'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadFollowUps();
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : "Couldn't reschedule."),
        ),
      );
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dataChanged,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lead CRM'),
          actions: [
            _ownerFilter(),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                _load();
                _invalidateDerived();
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: [
              const Tab(icon: Icon(Icons.list_rounded, size: 18), text: 'List'),
              const Tab(
                icon: Icon(Icons.view_kanban_rounded, size: 18),
                text: 'Board',
              ),
              Tab(
                icon: const Icon(Icons.checklist_rounded, size: 18),
                // The unattended count rides on the tab because it is the one
                // number somebody should react to without opening anything.
                text: _workflow != null && _workflow!.unattended > 0
                    ? 'Workflow (${_workflow!.unattended})'
                    : 'Workflow',
              ),
              Tab(
                icon: const Icon(Icons.notifications_active_rounded, size: 18),
                text: _followUps != null && _followUps!.actionableCount > 0
                    ? 'Follow-ups (${_followUps!.actionableCount})'
                    : 'Follow-ups',
              ),
              const Tab(
                icon: Icon(Icons.insights_rounded, size: 18),
                text: 'Analytics',
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddLead,
          icon: const Icon(Icons.person_add_rounded),
          label: const Text('New Lead'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TabBarView(
            controller: _tabs,
            children: [
              _listTab(),
              _boardTab(),
              _workflowTab(),
              _followUpsTab(),
              _analyticsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ownerFilter() {
    if (_assignees.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: 'Filter by owner',
        icon: Icon(
          Icons.person_search_rounded,
          color: _assignedTo.isEmpty ? null : AppColors.primary,
        ),
        onSelected: _onAssignedToChanged,
        itemBuilder: (_) => [
          const PopupMenuItem(value: '', child: Text('All owners')),
          const PopupMenuItem(value: 'unassigned', child: Text('Unassigned')),
          const PopupMenuDivider(),
          ..._assignees.map(
            (a) => PopupMenuItem(
              value: '${a.id}',
              child: Text('${a.name} (${a.leadCount})'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listTab() {
    if (_error != null) {
      return ErrorBanner(message: _error!, onRetry: _load);
    }
    return LeadsBody(
      leads: _leads,
      isLoading: _isLoading,
      onRefresh: _load,
      selectedStatus: _selectedStatus,
      searchController: _searchController,
      onStatusChanged: _onStatusChanged,
      onSearchChanged: _onSearchChanged,
      onTap: _openDetail,
      onAdvance: _advance,
      onAddLead: _openAddLead,
    );
  }

  Widget _workflowTab() {
    if (_workflowLoading) return const LoadingView();
    if (_workflowError != null) {
      return ErrorBanner(message: _workflowError!, onRetry: _loadWorkflow);
    }
    if (_workflow == null) return const LoadingView();

    return Column(
      children: [
        _axisPicker(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadWorkflow,
            child: LeadWorkflowView(
              workflow: _workflow!,
              onTap: (item) => _openDetailById(item.leadId),
              onSetNextStep: _setNextStep,
            ),
          ),
        ),
      ],
    );
  }

  /// Cuts the same queue a different way. The rows never change — only how
  /// they are gathered — so the headline counts above stay put and switching
  /// axis can never look like work appearing or vanishing.
  Widget _axisPicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final axis in WorkflowAxis.all) ...[
              ChoiceChip(
                label: Text(axis.label),
                selected: _workflowAxis == axis.key,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: _workflowAxis == axis.key
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: _workflowAxis == axis.key
                      ? Colors.white
                      : AppColors.textPrimary,
                ),
                selectedColor: AppColors.primary,
                onSelected: (_) {
                  if (_workflowAxis == axis.key) return;
                  setState(() => _workflowAxis = axis.key);
                  _loadWorkflow();
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openDetailById(int leadId) async {
    final result = await showLeadDetailPanel(context, leadId);
    if (!mounted) return;
    if (result == true) await _refreshAll();
  }

  /// The only write on the workflow screen, and always a human confirming.
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
      // genuinely needs no next step should be closable back to Unattended
      // rather than carrying a fake date somebody stops believing.
      onClear: item.nextStep == null
          ? null
          : () => LeadService().setNextStep(item.leadId),
    );
    if (saved == true && mounted) {
      _dataChanged = true;
      await _loadWorkflow();
    }
  }

  Widget _boardTab() {
    if (_error != null) {
      return ErrorBanner(message: _error!, onRetry: _load);
    }
    if (_isLoading) {
      return const LoadingView(label: 'Loading pipeline...');
    }
    return LeadKanbanBoard(
      leads: _leads,
      onTap: _openDetail,
      onMove: _moveStage,
    );
  }

  Widget _followUpsTab() {
    if (_followUpsError != null) {
      return ErrorBanner(message: _followUpsError!, onRetry: _loadFollowUps);
    }
    if (_followUpsLoading || _followUps == null) {
      return const LoadingView(label: 'Loading follow-ups...');
    }
    return RefreshIndicator(
      onRefresh: _loadFollowUps,
      child: LeadFollowUpsView(
        queue: _followUps!,
        onTap: _openDetail,
        onLogCall: _logCall,
        onReschedule: _reschedule,
      ),
    );
  }

  Widget _analyticsTab() {
    if (_analyticsError != null) {
      return ErrorBanner(message: _analyticsError!, onRetry: _loadAnalytics);
    }
    if (_analyticsLoading || _analytics == null) {
      return const LoadingView(label: 'Crunching pipeline numbers...');
    }
    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: LeadAnalyticsView(analytics: _analytics!),
    );
  }
}
