import 'package:flutter/material.dart';

import '../../models/payment.dart';
import '../../services/api_response.dart';
import '../../services/payment_service.dart';
import '../../widgets/error_banner.dart';

import 'payment_filter_bar.dart';
import 'payments_body.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
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
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              onPressed: _load,
            ),
          ],
        ),
        body: Padding(
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
      ),
    );
  }
}
