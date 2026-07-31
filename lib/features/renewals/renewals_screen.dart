import 'package:flutter/material.dart';

import '../../models/renewal_due.dart';
import '../../services/api_response.dart';
import '../../services/renewal_service.dart';
import '../../widgets/error_banner.dart';

import 'renew_dialog.dart';
import 'renewal_filter_bar.dart';
import 'renewals_body.dart';

class RenewalsScreen extends StatefulWidget {
  const RenewalsScreen({super.key});

  @override
  State<RenewalsScreen> createState() => _RenewalsScreenState();
}

class _RenewalsScreenState extends State<RenewalsScreen> {
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
    loadRenewals();
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
              onPressed: loadRenewals,
            ),
          ],
        ),
        body: Padding(
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
      ),
    );
  }
}
