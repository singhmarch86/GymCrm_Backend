import 'package:flutter/material.dart';

import '../../models/lifecycle_event.dart';
import '../../services/api_response.dart';
import '../../services/lifecycle_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import 'lifecycle_shared.dart';
import '../../utils/money.dart';

/// A member's membership history — every freeze, plan change, transfer and
/// termination, with who did it and what money it moved.
///
/// Labels come from the server so wording never drifts between clients.
class LifecycleTimeline extends StatefulWidget {
  final int memberId;

  /// Bumped by the parent after an operation to force a reload.
  final int refreshToken;

  const LifecycleTimeline({
    super.key,
    required this.memberId,
    this.refreshToken = 0,
  });

  @override
  State<LifecycleTimeline> createState() => _LifecycleTimelineState();
}

class _LifecycleTimelineState extends State<LifecycleTimeline> {
  final _service = LifecycleService();

  List<LifecycleEvent> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LifecycleTimeline old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await _service.timeline(widget.memberId);
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return ErrorBanner(message: _error!, onRetry: _load);
    }
    if (_events.isEmpty) {
      return const EmptyStateView(
        icon: Icons.history,
        title: 'No membership changes yet',
        body: 'Freezes, plan changes and transfers will appear here.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _events.length; i++)
          _TimelineRow(event: _events[i], isLast: i == _events.length - 1),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final LifecycleEvent event;
  final bool isLast;

  const _TimelineRow({required this.event, required this.isLast});

  /// Icon and colour per event type. Colour is semantic, not decorative:
  /// terminations and transfers read as consequential at a glance.
  (IconData, Color) get _marker => switch (event.eventType) {
    'freeze' => (Icons.ac_unit, AppColors.info),
    'unfreeze' => (Icons.play_arrow_rounded, AppColors.success),
    'upgrade' => (Icons.swap_horiz, AppColors.primary),
    'transfer_out' => (Icons.call_made, AppColors.warning),
    'transfer_in' => (Icons.call_received, AppColors.warning),
    'terminate' => (Icons.cancel_outlined, AppColors.danger),
    _ => (Icons.circle, AppColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _marker;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail: marker plus the connector to the next entry.
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              if (!isLast)
                Expanded(child: Container(width: 1.5, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          event.label,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatDate(event.effectiveDate),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),

                  if (event.hasMoney) ...[
                    AppSpacing.gapXs,
                    Text(
                      event.amountCreditInPaise > 0
                          ? 'Credit ${moneyR(event.amountCreditInRupees)}'
                          : 'Due ${moneyR(event.amountDueInRupees)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: event.amountCreditInPaise > 0
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                    ),
                  ],

                  if (event.relatedMemberName != null) ...[
                    AppSpacing.gapXs,
                    Text(
                      event.eventType == 'transfer_out'
                          ? 'to ${event.relatedMemberName}'
                          : 'from ${event.relatedMemberName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],

                  if (event.reason != null && event.reason!.isNotEmpty) ...[
                    AppSpacing.gapXs,
                    Text(
                      '"${event.reason}"',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],

                  AppSpacing.gapXs,
                  Text(
                    event.performedByUserName,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
