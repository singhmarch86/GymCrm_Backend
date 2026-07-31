import 'package:flutter/material.dart';

import '../../models/member_report.dart';
import '../../models/payment_report.dart';
import '../../models/plan_report.dart';
import '../../models/renewal_report.dart';
import '../../models/revenue_report.dart';
import '../../services/report_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';

import 'member_growth_chart.dart';
import 'payment_distribution_chart.dart';
import 'plan_distribution_chart.dart';
import 'renewal_trend_chart.dart';
import 'report_section.dart';
import 'revenue_chart.dart';

/// ReportsBody owns the 5 independent API calls.
///
/// Option B architecture: each report section maintains its own
/// loading / success / error state. A failure in one section never
/// affects the others. All 5 requests fire in parallel on load.
///
/// To add a 6th section (e.g. Attendance), simply add:
///   - A new _sectionState field set
///   - A new Future in _loadAll()
///   - A new ReportSection widget in build()
class ReportsBody extends StatefulWidget {
  const ReportsBody({super.key});

  @override
  State<ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends State<ReportsBody> {
  final _svc = ReportService();

  // Revenue
  bool _revLoading = true;
  RevenueReport? _revData;
  String? _revError;

  // Members
  bool _memLoading = true;
  MemberReport? _memData;
  String? _memError;

  // Payments
  bool _payLoading = true;
  PaymentReport? _payData;
  String? _payError;

  // Renewals
  bool _renLoading = true;
  RenewalReport? _renData;
  String? _renError;

  // Plans
  bool _planLoading = true;
  PlanReport? _planData;
  String? _planError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// Fires all 5 requests in parallel. Each one sets its own state
  /// independently — a failure in one never cancels the others.
  Future<void> _loadAll() async {
    // Reset to loading
    if (mounted) {
      setState(() {
        _revLoading = true;  _revError = null;
        _memLoading = true;  _memError = null;
        _payLoading = true;  _payError = null;
        _renLoading = true;  _renError = null;
        _planLoading = true; _planError = null;
      });
    }

    // All 5 fire simultaneously — no serial blocking
    await Future.wait([
      _loadRevenue(),
      _loadMembers(),
      _loadPayments(),
      _loadRenewals(),
      _loadPlans(),
    ]);
  }

  Future<void> _loadRevenue() async {
    try {
      final data = await _svc.getRevenueReport();
      if (!mounted) return;
      setState(() { _revData = data; _revLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _revError = e.toString().replaceFirst('Exception: ', '');
        _revLoading = false;
      });
    }
  }

  Future<void> _loadMembers() async {
    try {
      final data = await _svc.getMemberReport();
      if (!mounted) return;
      setState(() { _memData = data; _memLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memError = e.toString().replaceFirst('Exception: ', '');
        _memLoading = false;
      });
    }
  }

  Future<void> _loadPayments() async {
    try {
      final data = await _svc.getPaymentReport();
      if (!mounted) return;
      setState(() { _payData = data; _payLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _payError = e.toString().replaceFirst('Exception: ', '');
        _payLoading = false;
      });
    }
  }

  Future<void> _loadRenewals() async {
    try {
      final data = await _svc.getRenewalReport();
      if (!mounted) return;
      setState(() { _renData = data; _renLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _renError = e.toString().replaceFirst('Exception: ', '');
        _renLoading = false;
      });
    }
  }

  Future<void> _loadPlans() async {
    try {
      final data = await _svc.getPlanReport();
      if (!mounted) return;
      setState(() { _planData = data; _planLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _planError = e.toString().replaceFirst('Exception: ', '');
        _planLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: AppSpacing.screenPadding,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [

          // ── Revenue ─────────────────────────────────────────────────────
          ReportSection<RevenueReport>(
            title: 'Revenue',
            icon: Icons.attach_money_rounded,
            color: AppColors.success,
            data: _revData,
            isLoading: _revLoading,
            error: _revError,
            builder: (data) => RevenueChart(report: data),
          ),

          AppSpacing.gapLg,

          // ── Members ─────────────────────────────────────────────────────
          ReportSection<MemberReport>(
            title: 'Members',
            icon: Icons.groups_rounded,
            color: AppColors.primary,
            data: _memData,
            isLoading: _memLoading,
            error: _memError,
            builder: (data) => MemberGrowthChart(report: data),
          ),

          AppSpacing.gapLg,

          // ── Payments ────────────────────────────────────────────────────
          ReportSection<PaymentReport>(
            title: 'Payments',
            icon: Icons.payment_rounded,
            color: Colors.deepPurple,
            data: _payData,
            isLoading: _payLoading,
            error: _payError,
            builder: (data) => PaymentDistributionChart(report: data),
          ),

          AppSpacing.gapLg,

          // ── Renewals ────────────────────────────────────────────────────
          ReportSection<RenewalReport>(
            title: 'Renewals',
            icon: Icons.autorenew_rounded,
            color: Colors.orange,
            data: _renData,
            isLoading: _renLoading,
            error: _renError,
            builder: (data) => RenewalTrendChart(report: data),
          ),

          AppSpacing.gapLg,

          // ── Plans ───────────────────────────────────────────────────────
          ReportSection<PlanReport>(
            title: 'Membership Plans',
            icon: Icons.workspace_premium_rounded,
            color: Colors.teal,
            data: _planData,
            isLoading: _planLoading,
            error: _planError,
            builder: (data) => PlanDistributionChart(report: data),
          ),

          AppSpacing.gapXxl,
        ],
      ),
    );
  }
}
