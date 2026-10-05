import 'package:flutter/material.dart';

import '../../models/attendance_record.dart';
import '../../services/api_response.dart';
import '../../services/attendance_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_banner.dart';

import 'attendance_body.dart';
import 'check_in_dialog.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _isLoading = true;
  String? _error;

  List<AttendanceRecord> _todayRecords = [];
  List<AttendanceRecord> _recentRecords = [];

  /// PopScope dashboard contract — same pattern as Members/Renewals/Payments.
  bool _dataChanged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Fire both in parallel
      final results = await Future.wait([
        AttendanceService().getToday(),
        AttendanceService().getRecent(limit: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _todayRecords = results[0];
        _recentRecords = results[1];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : "Couldn't load attendance. Please try again.";
        _isLoading = false;
      });
    }
  }

  Future<void> _openCheckIn() async {
    final result = await showCheckInDialog(context);
    if (result == true) {
      _dataChanged = true;
      await _load();
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
          title: const Text('Attendance'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: _load,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openCheckIn,
          icon: const Icon(Icons.how_to_reg_rounded),
          label: const Text('Check In'),
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _error != null
              ? ErrorBanner(message: _error!, onRetry: _load)
              : AttendanceBody(
                  todayRecords: _todayRecords,
                  recentRecords: _recentRecords,
                  isLoading: _isLoading,
                  onRefresh: _load,
                ),
        ),
      ),
    );
  }
}
