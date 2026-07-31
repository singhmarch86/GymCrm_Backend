import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

/// Wraps a single report section with independent loading / error / success
/// state. Each section on the Reports screen is wrapped in this widget so
/// that one failing API never affects the others.
///
/// Usage:
///   ReportSection<RevenueReport>(
///     title: 'Revenue',
///     icon: Icons.attach_money_rounded,
///     data: _revenueReport,
///     isLoading: _revenueLoading,
///     error: _revenueError,
///     builder: (report) => RevenueChart(report: report),
///   )
class ReportSection<T> extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final T? data;
  final bool isLoading;
  final String? error;
  final Widget Function(T data) builder;

  const ReportSection({
    super.key,
    required this.title,
    required this.icon,
    required this.builder,
    this.data,
    this.isLoading = false,
    this.error,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Content
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (error != null)
            _ErrorState(message: error!)
          else if (data == null)
            const _EmptyState()
          else
            builder(data as T),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'No data available',
        style: TextStyle(color: Colors.grey.shade500),
      ),
    );
  }
}
