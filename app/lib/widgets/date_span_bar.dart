import 'package:flutter/material.dart';

import '../models/date_span.dart';
import '../theme/app_colors.dart';

/// Day · Month · Custom, with a calendar (FR-18 §9).
///
/// Replaces the day-only control FR-13 §4 shipped with. An owner asking "what
/// did Simran do in July" is asking something reasonable that one day at a
/// time cannot answer.
///
/// The arrows are the fast path and stay in the same place in every mode; the
/// calendar is for the question the arrows cannot reach. Custom has no arrows,
/// because a fortnight somebody picked by hand has no obvious "next" and
/// guessing one moves them somewhere they did not choose.
class DateSpanBar extends StatelessWidget {
  final DateSpan span;
  final ValueChanged<DateSpan> onChanged;

  /// Adds an "All" segment. Used where a date filter is optional and the
  /// unfiltered view is the safe default — collections, where narrowing by due
  /// date hides the oldest and worst debt.
  final bool allowAll;

  /// True when "All" is the current selection.
  final bool showingAll;

  final VoidCallback? onShowAll;

  const DateSpanBar({
    super.key,
    required this.span,
    required this.onChanged,
    this.allowAll = false,
    this.showingAll = false,
    this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final back = showingAll ? null : span.shift(-1);
    final forward = showingAll ? null : span.shift(1);
    final sub = showingAll ? null : span.sublabel;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: back == null ? 'Pick dates to move' : 'Previous',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: back == null ? null : () => onChanged(back),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      showingAll ? 'Everything outstanding' : span.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: forward == null ? 'Nothing later to show' : 'Next',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: forward == null ? null : () => onChanged(forward),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                // Keyed by string rather than SpanMode: "All" is a state of
                // this control, not a kind of DateSpan, and adding it to the
                // enum would force every DateSpan consumer to handle a mode
                // that can never be constructed.
                child: SegmentedButton<String>(
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontSize: 12.5),
                    ),
                  ),
                  segments: [
                    if (allowAll)
                      const ButtonSegment(value: 'all', label: Text('All')),
                    const ButtonSegment(value: 'day', label: Text('Day')),
                    const ButtonSegment(value: 'month', label: Text('Month')),
                    const ButtonSegment(value: 'custom', label: Text('Custom')),
                  ],
                  selected: {showingAll ? 'all' : span.mode.name},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    final picked = s.first;
                    if (picked == 'all') {
                      onShowAll?.call();
                      return;
                    }
                    _switchTo(context, SpanMode.values.byName(picked));
                  },
                ),
              ),
              IconButton(
                tooltip: 'Pick dates',
                icon: const Icon(Icons.calendar_month_rounded, size: 20),
                color: AppColors.primary,
                onPressed: () => _pick(context, span.mode),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Switching mode keeps you where you were rather than jumping to today.
  /// Somebody looking at 3 July who taps Month means July, not August.
  void _switchTo(BuildContext context, SpanMode mode) {
    // Coming back from "All" always re-applies, even if the mode matches the
    // span we were holding — otherwise the tap would do nothing visible.
    if (mode == span.mode && !showingAll) return;
    switch (mode) {
      case SpanMode.day:
        // From a month, the anchor day is its end — the last day with data,
        // and today for the current month.
        onChanged(DateSpan.day(span.to));
      case SpanMode.month:
        onChanged(DateSpan.month(span.from));
      case SpanMode.custom:
        // Custom has nothing sensible to default to, so it asks.
        _pick(context, SpanMode.custom);
    }
  }

  Future<void> _pick(BuildContext context, SpanMode mode) async {
    final today = DateTime.now();
    // Five years back is further than any gym on this system has records for,
    // and the server refuses anything over a year anyway.
    final first = DateTime(today.year - 5, 1, 1);

    if (mode == SpanMode.day) {
      final picked = await showDatePicker(
        context: context,
        initialDate: span.from,
        firstDate: first,
        lastDate: today,
      );
      if (picked != null) onChanged(DateSpan.day(picked));
      return;
    }

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: span.from, end: span.to),
      firstDate: first,
      lastDate: today,
      helpText: 'Pick a range',
    );
    if (picked == null) return;

    // A one-day range picked from the calendar is a day, not a "custom range
    // of 1" — labelling it "3 Jul – 3 Jul" would be silly.
    if (picked.start == picked.end) {
      onChanged(DateSpan.day(picked.start));
      return;
    }
    onChanged(DateSpan.custom(picked.start, picked.end));
  }
}
