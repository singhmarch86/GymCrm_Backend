import 'package:flutter/material.dart';

import '../../models/renewal_due.dart';
import '../../models/renewal_queue.dart';
import '../../services/api_response.dart';
import '../../services/queue_service.dart';
import '../../services/renewal_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';

import 'renew_dialog.dart';
import 'renewal_action_sheet.dart';
import 'renewal_filter_bar.dart';
import 'renewal_queue_view.dart';
import 'renewals_body.dart';

class RenewalsScreen extends StatefulWidget {
  const RenewalsScreen({super.key});

  @override
  State<RenewalsScreen> createState() => _RenewalsScreenState();
}

class _RenewalsScreenState extends State<RenewalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Due (FR-19 §4). The default tab, so it loads on entry.
  final _queues = QueueService();
  RenewalQueue? _queue;
  bool _queueLoading = true;
  String? _queueError;
  bool _isOwner = false;

  /// Null means the server default (30). Widened from the footnote.
  int? _windowDays;

  bool isLoading = true;
  String? error;

  List<RenewalDue> renewals = [];

  RenewalFilterOption currentFilter = RenewalFilterOption.all;
  String currentSearch = '';

  /// Tracks whether a renewal was successfully collected while this screen
  /// was open. See member_screen.dart for the full PopScope rationale —
  /// same pattern applied here.
  bool _dataChanged = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    StorageService.getRole().then((r) {
      if (mounted) setState(() => _isOwner = r == 'owner');
    });
    _loadQueue();
    loadRenewals();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> loadRenewals() async {
    setState(() => error = null);
    try {
      final data = await RenewalService().getRenewalsDue(
        filter: currentFilter.apiValue,
        search: currentSearch,
      );

      if (!mounted) return;

      setState(() {
        renewals = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e is ApiException ? e.message : "Couldn't load renewals. Please try again.";
        isLoading = false;
      });
    }
  }

  void onQueryChanged({
    required RenewalFilterOption filter,
    required String search,
  }) {
    currentFilter = filter;
    currentSearch = search;

    setState(() {
      isLoading = true;
    });

    loadRenewals();
  }

  Future<void> onRenew(RenewalDue renewal) async {
    final result = await showRenewDialog(context, renewal: renewal);

    if (result == true) {
      if (!mounted) return;

      _dataChanged = true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${renewal.memberName}'s membership renewed",
          ),
        ),
      );

      await loadRenewals();
    }
  }

  Future<void> _loadQueue() async {
    setState(() {
      _queueLoading = true;
      _queueError = null;
    });
    try {
      final q = await _queues.getRenewals(windowDays: _windowDays);
      if (!mounted) return;
      setState(() {
        _queue = q;
        _queueLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _queueError = e.message;
        _queueLoading = false;
      });
    }
  }

  Future<void> _act(RenewalItem item) async {
    final changed = await showRenewalActionSheet(
      context,
      item: item,
      isOwner: _isOwner,
    );
    if (changed == true && mounted) {
      _dataChanged = true;
      await _loadQueue();
      await loadRenewals();
    }
  }

  Widget _queueTab() {
    if (_queueLoading) return const LoadingView();
    if (_queueError != null) {
      return ErrorBanner(message: _queueError!, onRetry: _loadQueue);
    }
    if (_queue == null) return const LoadingView();
    return RefreshIndicator(
      onRefresh: _loadQueue,
      child: RenewalQueueView(
        queue: _queue!,
        onAct: _act,
        onWiden: (days) {
          setState(() => _windowDays = days == 30 ? null : days);
          _loadQueue();
        },
      ),
    );
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
          title: const Text("Renewals"),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                _loadQueue();
                loadRenewals();
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: const [
              // Due is the worklist, All is the searchable list. Separate
              // tabs rather than a filter, for the same reason Collections
              // sits beside Ledger (FR-19 §1).
              Tab(icon: Icon(Icons.event_repeat_rounded, size: 18), text: 'Due'),
              Tab(icon: Icon(Icons.list_rounded, size: 18), text: 'All'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _queueTab(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: error != null
                  ? ErrorBanner(message: error!, onRetry: loadRenewals)
                  : RenewalsBody(
                      renewals: renewals,
                      isLoading: isLoading,
                      onQueryChanged: onQueryChanged,
                      onRefresh: loadRenewals,
                      onRenew: onRenew,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
