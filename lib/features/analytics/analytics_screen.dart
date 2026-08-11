import 'package:flutter/material.dart';

import '../../models/lead_pipeline.dart';
import '../../models/retention_alert.dart';
import '../../services/lead_service.dart';
import '../../services/retention_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../leads/lead_analytics_view.dart';
import '../reports/reports_body.dart';
import '../staffwork/staff_work_screen.dart';

/// Every number the product computes, under one heading (FR-15).
///
/// The metrics here are not new — they were spread across Reports, a tab inside
/// Leads, the At Risk worklist and Staff work, which is why the product read as
/// thinner than it is. An owner comparing us to FitnessForce saw one Analytics
/// menu against four scattered screens and drew the obvious conclusion.
///
/// Nothing was moved out of where it already lived (FR-15 §2). This is an
/// additional door onto the same rooms — somebody who learned to find the
/// funnel inside Leads must not find it gone one morning.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  /// Which sub-tabs have ever been opened.
  ///
  /// Views fetch on first visit, not on section entry (FR-15 §4). Loading all
  /// four — a funnel scan and a day of staff ledgers among them — because
  /// somebody tapped Analytics would make the section slow to open and hit the
  /// API three times for views nobody looked at.
  final Set<int> _visited = {0};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (_tabs.indexIsChanging) return;
        if (_visited.add(_tabs.index)) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analytics'),
        // A section, not a pushed screen — an arrow here would pop the shell.
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.insights_rounded, size: 18), text: 'Business'),
            Tab(icon: Icon(Icons.filter_alt_rounded, size: 18), text: 'Leads'),
            Tab(
                icon: Icon(Icons.health_and_safety_rounded, size: 18),
                text: 'Retention'),
            Tab(icon: Icon(Icons.badge_rounded, size: 18), text: 'Staff'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const ReportsBody(),
          _lazy(1, const _LeadsAnalyticsTab()),
          _lazy(2, const _RetentionAnalyticsTab()),
          _lazy(3, const StaffWorkScreen()),
        ],
      ),
    );
  }

  /// Renders nothing until the tab has been opened once; keeps it alive after.
  Widget _lazy(int index, Widget child) =>
      _visited.contains(index) ? child : const SizedBox.shrink();
}

/// The funnel, sources and lost reasons — the same view Leads renders, fed by
/// the same service call (FR-15 §3). A second copy of this chart would be one
/// more thing to keep in sync and it would always be the stale one.
class _LeadsAnalyticsTab extends StatefulWidget {
  const _LeadsAnalyticsTab();

  @override
  State<_LeadsAnalyticsTab> createState() => _LeadsAnalyticsTabState();
}

class _LeadsAnalyticsTabState extends State<_LeadsAnalyticsTab>
    with AutomaticKeepAliveClientMixin {
  final _service = LeadService();
  bool _loading = true;
  String? _error;
  LeadAnalytics? _analytics;

  @override
  bool get wantKeepAlive => true;

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
      final a = await _service.getAnalytics();
      if (!mounted) return;
      setState(() {
        _analytics = a;
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
    super.build(context);
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: LeadAnalyticsView(analytics: _analytics!),
    );
  }
}

/// What the retention scans are finding, as counts.
///
/// Deliberately no resolve buttons (FR-15 §5): reading numbers and working a
/// list are different modes, and an action button on a reporting screen is how
/// somebody closes an alert they meant to investigate.
class _RetentionAnalyticsTab extends StatefulWidget {
  const _RetentionAnalyticsTab();

  @override
  State<_RetentionAnalyticsTab> createState() => _RetentionAnalyticsTabState();
}

class _RetentionAnalyticsTabState extends State<_RetentionAnalyticsTab>
    with AutomaticKeepAliveClientMixin {
  final _service = RetentionService();
  bool _loading = true;
  String? _error;
  RetentionSummary? _summary;

  @override
  bool get wantKeepAlive => true;

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
      final s = await _service.getSummary();
      if (!mounted) return;
      setState(() {
        _summary = s;
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
    super.build(context);
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);

    final s = _summary!;

    // Says what is missing rather than drawing an empty chart (FR-15 §6). A
    // chart with no bars looks broken and gets reported as a bug; "no scan has
    // run" is the actual, actionable fact.
    if (s.lastScanAt == null && s.total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'No retention scan has run yet.\n\n'
            'Open At Risk and run a scan — until then there is nothing to '
            'measure here.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, height: 1.5, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.total}',
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.bold)),
                Text('members flagged as at risk',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 14),
                _bar('Needs attention now', s.high, s.total, AppColors.danger),
                const SizedBox(height: 8),
                _bar('Worth a call', s.medium, s.total, AppColors.warning),
                const SizedBox(height: 8),
                _bar('Keep an eye on', s.low, s.total, AppColors.info),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              s.lastScanAt == null
                  ? 'No scan has been run yet.'
                  : 'Last scan: ${s.lastScanAt}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Work these on the At Risk screen — this view only reports.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(String label, int value, int total, Color color) {
    final fraction = total == 0 ? 0.0 : value / total;
    return Row(
      children: [
        SizedBox(
          width: 132,
          child: Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text('$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
