/// A stretch of gym days (FR-18 §9).
///
/// Supersedes the day-at-a-time control FR-13 §4 shipped with. "What did
/// Simran do in July" is a fair question and one day at a time cannot answer
/// it.
///
/// Both ends are inclusive, and both are plain calendar dates — no clock, no
/// timezone conversion. The server applies the IST day boundary; if this class
/// converted to UTC anywhere, a range picked before 05:30 would silently shift
/// by a day.
library;

enum SpanMode { day, month, custom }

class DateSpan {
  final DateTime from;
  final DateTime to;
  final SpanMode mode;

  const DateSpan._(this.from, this.to, this.mode);

  factory DateSpan.day(DateTime d) {
    final x = _dateOnly(d);
    return DateSpan._(x, x, SpanMode.day);
  }

  factory DateSpan.today() => DateSpan.day(DateTime.now());

  /// The whole calendar month containing [d].
  ///
  /// Clamped to today for the current month. Offering the rest of August in
  /// mid-August would return an empty tail and read as "nothing happened"
  /// rather than "it has not happened yet".
  factory DateSpan.month(DateTime d) {
    final start = DateTime(d.year, d.month, 1);
    var end = DateTime(d.year, d.month + 1, 0);
    final today = _dateOnly(DateTime.now());
    if (end.isAfter(today)) end = today;
    if (end.isBefore(start)) end = start;
    return DateSpan._(start, end, SpanMode.month);
  }

  factory DateSpan.custom(DateTime from, DateTime to) {
    final a = _dateOnly(from), b = _dateOnly(to);
    return b.isBefore(a)
        ? DateSpan._(b, a, SpanMode.custom)
        : DateSpan._(a, b, SpanMode.custom);
  }

  bool get isSingleDay => from == to;

  int get days => to.difference(from).inDays + 1;

  bool get isToday => isSingleDay && from == _dateOnly(DateTime.now());

  /// Whether this month is the one we are living through.
  bool get isThisMonth {
    final now = DateTime.now();
    return mode == SpanMode.month &&
        from.year == now.year &&
        from.month == now.month;
  }

  /// Step one unit back or forward, in whatever unit this span is in.
  ///
  /// Custom spans do not shift: a fortnight somebody picked by hand has no
  /// obvious "next", and guessing one would move them somewhere they did not
  /// choose.
  DateSpan? shift(int units) {
    switch (mode) {
      case SpanMode.day:
        final next = from.add(Duration(days: units));
        // The ledgers cannot contain tomorrow, and an empty screen looks like
        // a failure rather than like a day that has not happened.
        if (next.isAfter(_dateOnly(DateTime.now()))) return null;
        return DateSpan.day(next);
      case SpanMode.month:
        final next = DateTime(from.year, from.month + units, 1);
        final now = DateTime.now();
        if (next.isAfter(DateTime(now.year, now.month, 1))) return null;
        return DateSpan.month(next);
      case SpanMode.custom:
        return null;
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _monthsLong = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  /// The headline. Deliberately says "Today" and "This month" rather than a
  /// date — that is how somebody standing at the desk thinks about it.
  String get label {
    switch (mode) {
      case SpanMode.day:
        if (isToday) return 'Today';
        return '${_weekdays[from.weekday - 1]} ${from.day} '
            '${_months[from.month - 1]}';
      case SpanMode.month:
        if (isThisMonth) return 'This month';
        return '${_monthsLong[from.month - 1]} ${from.year}';
      case SpanMode.custom:
        return '${_short(from)} – ${_short(to)}';
    }
  }

  /// The exact dates, for underneath the headline. Always shown for a month
  /// and a custom range: "This month" alone hides that it stops at today.
  String? get sublabel {
    switch (mode) {
      case SpanMode.day:
        return isToday
            ? null
            : '${from.day} ${_months[from.month - 1]} ${from.year}';
      case SpanMode.month:
      case SpanMode.custom:
        return '${_short(from)} to ${_short(to)} · $days days';
    }
  }

  /// What the funnel and tallies are counting, in a sentence fragment that
  /// reads correctly after "Worked".
  String get workedSuffix {
    switch (mode) {
      case SpanMode.day:
        return isToday ? 'today' : 'this day';
      case SpanMode.month:
        return isThisMonth ? 'this month' : 'in ${_monthsLong[from.month - 1]}';
      case SpanMode.custom:
        return 'over these $days days';
    }
  }

  static String _short(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Formats without touching UTC. `toIso8601String()` converts first and would
  /// hand the server yesterday for anything before 05:30 IST.
  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String get fromParam => ymd(from);
  String get toParam => ymd(to);

  @override
  bool operator ==(Object other) =>
      other is DateSpan &&
      other.from == from &&
      other.to == to &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(from, to, mode);
}
