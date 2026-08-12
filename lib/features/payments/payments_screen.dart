import 'package:flutter/material.dart';

import '../../models/collection_queue.dart';
import '../../models/payment.dart';
import '../../services/api_response.dart';
import '../../services/payment_service.dart';
import '../../services/queue_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';

import 'collection_action_sheet.dart';
import 'collections_view.dart';
import 'payment_filter_bar.dart';
import 'payments_body.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Collections (FR-19 §3). Loaded lazily — the ledger is what most people
  // open, and paying for both on entry doubles the wait for nothing.
  final _queues = QueueService();
  CollectionQueue? _collections;
  bool _collectionsLoading = false;
  String? _collectionsError;
  bool _isOwner = false;

  bool _isLoading = true;
  String? _error;
  List<Payment> _payments = [];
  bool _dataChanged = false;

  // Filter and search state lives here — not in PaymentsBody — so that
  // _load() always reads the current values without a second widget's
  // initState or build triggering an extra fetch.
  PaymentFilterOption _currentFilter = PaymentFilterOption.all;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Collections is the default tab, so it loads on entry. The lazy-load
    // belongs on whichever tab is not shown first, and that is now the ledger.
    _tabs = TabController(length: 2, vsync: this);
    _loadCollections();
    // Write-off is owner-only and the server enforces it. This only decides
    // whether to offer the button, so a stale role cannot grant anything.
    StorageService.getRole().then((r) {
      if (mounted) setState(() => _isOwner = r == 'owner');
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCollections() async {
    setState(() {
      _collectionsLoading = true;
      _collectionsError = null;
    });
    try {
      final q = await _queues.getCollections();
      if (!mounted) return;
      setState(() {
        _collections = q;
        _collectionsLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _collectionsError = e.message;
        _collectionsLoading = false;
      });
    }
  }

  Future<void> _act(CollectionItem item) async {
    final changed = await showCollectionActionSheet(
      context,
      item: item,
      isOwner: _isOwner,
    );
    if (changed == true && mounted) {
      _dataChanged = true;
      await _loadCollections();
      await _load();
    }
  }

  Widget _collectionsTab() {
    if (_collectionsLoading) return const LoadingView();
    if (_collectionsError != null) {
      return ErrorBanner(message: _collectionsError!, onRetry: _loadCollections);
    }
    if (_collections == null) return const LoadingView();
    return RefreshIndicator(
      onRefresh: _loadCollections,
      child: CollectionsView(queue: _collections!, onAct: _act),
    );
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await PaymentService().getPayments(
        status: _currentFilter.apiValue,
        search: _searchController.text.trim(),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted) return;
      setState(() {
        _payments = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : "Couldn't load payments. Please try again.";
        _isLoading = false;
      });
    }
  }

  void _onQueryChanged({
    required PaymentFilterOption filter,
    required String search,
  }) {
    setState(() {
      _currentFilter = filter;
      _isLoading = true;
    });
    _load();
  }

  /// Today / This Month filters send date range params to the backend.
  String get _dateFrom {
    final now = DateTime.now();
    if (_currentFilter == PaymentFilterOption.today) {
      return _iso(now);
    }
    if (_currentFilter == PaymentFilterOption.thisMonth) {
      return _iso(DateTime(now.year, now.month, 1));
    }
    return '';
  }

  String get _dateTo {
    if (_currentFilter == PaymentFilterOption.today ||
        _currentFilter == PaymentFilterOption.thisMonth) {
      return _iso(DateTime.now());
    }
    return '';
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
          title: const Text('Payments'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                _load();
                if (_tabs.index == 1) _loadCollections();
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: const [
              // Collections is a worklist; Ledger is the record. Keeping them
              // as separate tabs rather than a filter is the whole point of
              // FR-19 — a worklist behind a filter stops being one.
              Tab(icon: Icon(Icons.gavel_rounded, size: 18), text: 'Collections'),
              Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Ledger'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _collectionsTab(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _error != null
                  ? ErrorBanner(message: _error!, onRetry: _load)
                  : PaymentsBody(
                      payments: _payments,
                      isLoading: _isLoading,
                      onRefresh: _load,
                      onQueryChanged: _onQueryChanged,
                      selectedFilter: _currentFilter,
                      searchController: _searchController,
                      onPaymentCollected: () {
                        _dataChanged = true;
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
