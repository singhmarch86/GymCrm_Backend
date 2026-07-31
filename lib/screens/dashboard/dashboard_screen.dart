import 'package:flutter/material.dart';

import '../../login_screen.dart';
import '../../models/dashboard_response.dart';
import '../../models/retention_alert.dart';
import '../../services/api_response.dart';
import '../../services/auth_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/payment_service.dart';
import '../../services/retention_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';

import 'dashboard_body.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool loading = true;
  String? error;

  String token = '';
  String userName = '';
  String role = '';

  int totalMembers = 0;
  int activeMembers = 0;
  int expiredMembers = 0;
  int expiring7Days = 0;
  int expiring30Days = 0;
  int inactive7Days = 0;
  int inactive14Days = 0;
  int inactive30Days = 0;
  int renewalsToday = 0;
  int atRiskHigh = 0;

  // Revenue summary — fetched alongside member stats so
  // a single loadDashboard() call refreshes everything.
  int todayRevenuePaise = 0;
  int monthRevenuePaise = 0;
  int pendingPayments = 0;
  int collectedCount = 0;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    setState(() => error = null);
    try {
      final savedToken = await StorageService.getAccessToken();
      final savedUser = await StorageService.getUserName();
      final savedRole = await StorageService.getRole();

      // Fire both requests in parallel via Future.wait — NOT two separate
      // `final f = future(); await f;` pairs. If the first await throws,
      // a separately-created second future is never awaited and, once it
      // later settles with its own error, Dart reports it as an unhandled
      // Future exception (this crashed the app during testing — a 401 on
      // one request left the other's error with no listener). Future.wait
      // attaches to both immediately regardless of which settles first.
      final results = await Future.wait<Object>([
        DashboardService().getDashboard(),
        PaymentService().getRevenueSummary(),
        RetentionService().getSummary(),
      ]);
      final dashboard = results[0] as DashboardResponse;
      final revenue = results[1] as Map<String, dynamic>;
      final retention = results[2] as RetentionSummary;

      if (!mounted) return;

      setState(() {
        token = savedToken ?? '';
        userName = savedUser ?? '';
        role = savedRole ?? '';

        totalMembers = dashboard.totalMembers;
        activeMembers = dashboard.activeMembers;
        expiredMembers = dashboard.expiredMembers;
        expiring7Days = dashboard.expiring7Days;
        expiring30Days = dashboard.expiring30Days;
        inactive7Days = dashboard.inactive7Days;
        inactive14Days = dashboard.inactive14Days;
        inactive30Days = dashboard.inactive30Days;
        renewalsToday = dashboard.renewalsToday;
        atRiskHigh = retention.high;

        todayRevenuePaise = revenue['today_revenue_in_paise'] as int? ?? 0;
        monthRevenuePaise = revenue['month_revenue_in_paise'] as int? ?? 0;
        pendingPayments = revenue['pending_payments'] as int? ?? 0;
        collectedCount = revenue['collected_count'] as int? ?? 0;

        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      // A 401 here means the stored token is dead (expired or revoked).
      // Retrying with the same token can only fail the same way, so
      // there's nothing useful an ErrorBanner + Retry button can do —
      // clear the stale session and send the user back to log in fresh
      // instead of leaving them stuck on a dead-end error.
      if (e is ApiException && e.statusCode == 401) {
        await StorageService.clearAll();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
      }

      setState(() {
        error = e is ApiException ? e.message : "Couldn't load your dashboard. Please try again.";
        loading = false;
      });
    }
  }

  Future<void> logout() async {
    try {
      final accessToken = await StorageService.getAccessToken();
      if (accessToken != null && accessToken.isNotEmpty) {
        await AuthService().logout(accessToken);
      }
    } catch (_) {}

    await StorageService.clearAll();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: LoadingView(label: 'Loading your dashboard...'),
      );
    }

    if (error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ErrorBanner(message: error!, onRetry: loadDashboard),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadDashboard,
          child: DashboardBody(
            userName: userName,
            role: role,
            totalMembers: totalMembers,
            activeMembers: activeMembers,
            expiredMembers: expiredMembers,
            expiring7Days: expiring7Days,
            expiring30Days: expiring30Days,
            inactive7Days: inactive7Days,
            inactive14Days: inactive14Days,
            inactive30Days: inactive30Days,
            renewalsToday: renewalsToday,
            atRiskHigh: atRiskHigh,
            todayRevenuePaise: todayRevenuePaise,
            monthRevenuePaise: monthRevenuePaise,
            pendingPayments: pendingPayments,
            collectedCount: collectedCount,
            onLogout: logout,
            onDataChanged: loadDashboard,
          ),
        ),
      ),
    );
  }
}
