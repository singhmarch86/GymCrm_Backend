import 'package:flutter/material.dart';

import '../../models/date_span.dart';
import '../../models/staff_work.dart';
import '../../services/staff_work_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';

/// The rows behind one number (FR-13 §8).
///
/// An aggregate nobody can open is an accusation. Before an owner raises
/// "you only took three payments" with somebody, they should be able to see
/// which three — and the staff member should be able to show their work.
class StaffWorkItemsSheet extends StatefulWidget {
  final DateSpan span;
  final int? userId;
  final String staffName;
  final String category;
  final String title;

  const StaffWorkItemsSheet({
    super.key,
    required this.span,
    required this.userId,
    required this.staffName,
    required this.category,
    required this.title,
  });

  @override
  State<StaffWorkItemsSheet> createState() => _StaffWorkItemsSheetState();
}

class _StaffWorkItemsSheetState extends State<StaffWorkItemsSheet> {
  final _service = StaffWorkService();

  bool _loading = true;
  String? _error;
  StaffWorkItems? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.getItems(
        span: widget.span,
        category: widget.category,
        userId: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('${widget.staffName} · ${widget.span.label}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Expanded(child: _body(controller)),
          ],
        ),
      ),
    );
  }

  Widget _body(ScrollController controller) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);

    final result = _result;
    if (result == null || result.items.isEmpty) {
      return Center(
        child: Text('Nothing to show',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    final items = result.items;

    return Column(
      children: [
        // Said before the list, not after it. A notice under a 200-row scroll
        // is a notice nobody reads, and the whole point is that the reader
        // should not mistake this for the complete record.
        if (result.truncated)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 15, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Showing the most recent ${result.limit}. There were more '
                    'over ${widget.span.label.toLowerCase()} — narrow the '
                    'dates to see the rest.',
                    style: const TextStyle(fontSize: 11.5, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        Expanded(child: _list(controller, items)),
      ],
    );
  }

  Widget _list(ScrollController controller, List<StaffWorkItem> items) {
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          title: Text(item.who,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: Text(item.what,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (item.amountInPaise != null)
                Text('₹${item.amountInPaise! ~/ 100}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
              // Across a span the clock alone is ambiguous — three rows at
              // 18:30 could be three days or three minutes apart.
              Text(
                  widget.span.isSingleDay
                      ? _hhmm(item.at)
                      : '${_dayMon(item.at)} · ${_hhmm(item.at)}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
            ],
          ),
        );
      },
    );
  }
}

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dayMon(DateTime d) => '${d.day} ${_months[d.month - 1]}';
