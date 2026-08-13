import 'package:flutter_test/flutter_test.dart';
import 'package:gymcrm_app/models/date_span.dart';

void main() {
  group('DateSpan', () {
    test('a day is one day, not zero', () {
      final s = DateSpan.day(DateTime(2026, 8, 11));
      expect(s.days, 1);
      expect(s.isSingleDay, isTrue);
    });

    test('a past month covers the whole month', () {
      final s = DateSpan.month(DateTime(2026, 2, 15));
      expect(s.fromParam, '2026-02-01');
      expect(s.toParam, '2026-02-28');
      expect(s.days, 28);
    });

    // Offering the rest of the month would return an empty tail, which reads
    // as "nothing happened" rather than "it has not happened yet".
    test('the current month stops at today', () {
      final now = DateTime.now();
      final s = DateSpan.month(now);
      expect(s.to, DateTime(now.year, now.month, now.day));
      expect(s.isThisMonth, isTrue);
    });

    test('a day cannot step into the future', () {
      final today = DateSpan.today();
      expect(today.shift(1), isNull);
      expect(today.shift(-1), isNotNull);
    });

    test('a month cannot step past the current month', () {
      final thisMonth = DateSpan.month(DateTime.now());
      expect(thisMonth.shift(1), isNull);

      final back = thisMonth.shift(-1);
      expect(back, isNotNull);
      expect(back!.days, greaterThan(27));
    });

    // A fortnight picked by hand has no obvious "next", and guessing one moves
    // the reader somewhere they did not choose.
    test('a custom span does not shift in either direction', () {
      final s = DateSpan.custom(DateTime(2026, 7, 26), DateTime(2026, 8, 5));
      expect(s.shift(1), isNull);
      expect(s.shift(-1), isNull);
      expect(s.days, 11);
    });

    test('a backwards custom span is put the right way round', () {
      final s = DateSpan.custom(DateTime(2026, 8, 5), DateTime(2026, 7, 26));
      expect(s.fromParam, '2026-07-26');
      expect(s.toParam, '2026-08-05');
    });

    test('a span crossing a month boundary counts calendar days', () {
      final s = DateSpan.custom(DateTime(2026, 7, 26), DateTime(2026, 8, 5));
      expect(s.days, 11);
    });

    // toIso8601String() converts to UTC first and would hand the server
    // yesterday for anything before 05:30 IST.
    test('date parameters never go through UTC', () {
      final s = DateSpan.day(DateTime(2026, 8, 11, 2, 15));
      expect(s.fromParam, '2026-08-11');
      expect(s.toParam, '2026-08-11');
    });

    test('single-digit months and days are padded', () {
      expect(DateSpan.ymd(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('labels read the way somebody at the desk would say it', () {
      expect(DateSpan.today().label, 'Today');
      expect(DateSpan.month(DateTime.now()).label, 'This month');
      expect(DateSpan.month(DateTime(2026, 3, 4)).label, 'March 2026');
      expect(
        DateSpan.custom(DateTime(2026, 7, 26), DateTime(2026, 8, 5)).label,
        '26 Jul – 5 Aug',
      );
    });

    // "Worked ___" has to read correctly in every mode, because the funnel
    // heading is built from it.
    test('the worked suffix completes the sentence in every mode', () {
      expect(DateSpan.today().workedSuffix, 'today');
      expect(DateSpan.day(DateTime(2026, 3, 4)).workedSuffix, 'this day');
      expect(DateSpan.month(DateTime.now()).workedSuffix, 'this month');
      expect(DateSpan.month(DateTime(2026, 3, 4)).workedSuffix, 'in March');
      expect(
        DateSpan.custom(
          DateTime(2026, 7, 26),
          DateTime(2026, 8, 5),
        ).workedSuffix,
        'over these 11 days',
      );
    });

    // A month is always spelled out, because "This month" alone hides that it
    // stops at today.
    test('a span always shows its exact dates underneath', () {
      expect(DateSpan.today().sublabel, isNull);
      expect(DateSpan.month(DateTime.now()).sublabel, isNotNull);
      expect(
        DateSpan.custom(DateTime(2026, 7, 26), DateTime(2026, 8, 5)).sublabel,
        '26 Jul to 5 Aug · 11 days',
      );
    });
  });
}
