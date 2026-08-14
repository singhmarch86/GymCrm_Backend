import 'package:flutter/material.dart';

import '../models/plan.dart';
import '../services/api_response.dart';
import '../services/plan_service.dart';
import '../theme/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/loading_state.dart';
import 'add_plan_screen.dart';
import 'edit_plan_screen.dart';
import '../utils/money.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool isLoading = true;
  String? error;

  List<Plan> plans = [];

  /// Tracks whether ANY mutation (create/edit/delete) happened while this
  /// screen was open. See member_screen.dart for the full rationale behind
  /// the PopScope approach — same pattern, same reasoning, applied here.
  bool _dataChanged = false;

  @override
  void initState() {
    super.initState();
    loadPlans();
  }

  Future<void> loadPlans() async {
    setState(() => error = null);
    try {
      final data = await PlanService().getActivePlans();

      if (!mounted) return;

      setState(() {
        plans = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e is ApiException
            ? e.message
            : "Couldn't load your plans. Please try again.";
        isLoading = false;
      });
    }
  }

  Future<void> _addPlan() async {
    final result = await showAddPlanDialog(context);
    if (result == true) {
      _dataChanged = true;
      loadPlans();
    }
  }

  Future<void> _editPlan(Plan plan) async {
    final updated = await showEditPlanDialog(context, plan);
    if (updated == true) {
      _dataChanged = true;
      loadPlans();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dataChanged,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Membership Plans'),
          actions: [
            IconButton(
              tooltip: 'Add Plan',
              icon: const Icon(Icons.add),
              onPressed: _addPlan,
            ),
          ],
        ),
        body: isLoading
            ? const LoadingView()
            : error != null
            ? ErrorBanner(message: error!, onRetry: loadPlans)
            : plans.isEmpty
            ? const EmptyStateView(
                icon: Icons.workspace_premium_outlined,
                title: 'No Membership Plans Yet',
                body: 'Create your first plan to start enrolling members.',
              )
            : RefreshIndicator(
                onRefresh: loadPlans,
                child: ListView.builder(
                  itemCount: plans.length,
                  itemBuilder: (context, index) {
                    final plan = plans[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      elevation: 2,
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(
                            Icons.workspace_premium,
                            color: AppColors.primary,
                          ),
                        ),
                        title: Text(
                          plan.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Price : ${moneyR(plan.priceInRupees)}'),
                              const SizedBox(height: 4),
                              Text('Duration : ${plan.durationDays} Days'),
                            ],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editPlan(plan),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
