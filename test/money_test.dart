import 'package:flutter_test/flutter_test.dart';
import 'package:gymcrm_app/utils/money.dart';

void main() {
  group('money — exact, Indian grouping', () {
    test('leaves three digits and under alone', () {
      expect(money(0), '₹0');
      expect(money(95000), '₹950');
    });

    test('groups the last three, then pairs', () {
      expect(money(150000), '₹1,500');
      expect(money(1300000), '₹13,000');
      expect(money(15000000), '₹1,50,000');
      expect(money(41650000), '₹4,16,500');
      expect(money(1234567800), '₹1,23,45,678');
    });

    test('is not western grouping', () {
      // The whole reason this exists: 1,50,000 not 150,000.
      expect(money(15000000), isNot(contains('150,000')));
    });

    test('shows a paise remainder rather than hiding it', () {
      // This is the "exact" formatter — a figure somebody may check against
      // a receipt. ₹1,500 when ₹1,500.99 was charged is wrong in the same
      // direction as ₹1,501 would be; it just looks safer. GST splits land
      // on paise in practice, so this branch is not hypothetical.
      expect(money(150099), '₹1,500.99');
    });

    test('pads a single paise digit', () {
      expect(money(150005), '₹1,500.05');
    });

    test('a whole rupee amount carries no decimal at all', () {
      expect(money(150000), '₹1,500');
    });

    test('signs negatives outside the symbol', () {
      expect(money(-41650000), '-₹4,16,500');
    });
  });

  group('moneyShort — abbreviated', () {
    test('plain rupees below a thousand', () {
      expect(moneyShort(0), '₹0');
      expect(moneyShort(95000), '₹950');
    });

    test('one decimal between 1k and 10k', () {
      expect(moneyShort(150000), '₹1.5k');
      expect(moneyShort(950000), '₹9.5k');
    });

    test('the threshold rounds before it switches', () {
      // 9,999 sits under the 10k cutoff, so it takes the one-decimal branch
      // and rounds up to ₹10.0k, while 10,000 prints ₹10k. Carried over from
      // the copies this replaced rather than fixed: it is a hair's-width
      // cosmetic seam, and changing it would silently alter figures on ten
      // screens that have already been read and signed off.
      expect(moneyShort(999900), '₹10.0k');
      expect(moneyShort(1000000), '₹10k');
    });

    test('no decimal from 10k to a lakh', () {
      expect(moneyShort(1300000), '₹13k');
      expect(moneyShort(9900000), '₹99k');
    });

    test('lakhs with one decimal', () {
      expect(moneyShort(15000000), '₹1.5L');
      expect(moneyShort(41650000), '₹4.2L');
    });

    test('negatives keep their abbreviation', () {
      // The bug in twelve of the thirteen copies this replaced: a large
      // negative fell past both thresholds and printed raw.
      expect(moneyShort(-41650000), '-₹4.2L');
      expect(moneyShort(-1300000), '-₹13k');
    });
  });

  test('moneyPlain omits the symbol for editable fields', () {
    expect(moneyPlain(41650000), '4,16,500');
    expect(moneyPlain(95000), '950');
  });

  group('moneyR / moneyShortR — the rupees-as-double models', () {
    test('moneyR matches money() for a whole-rupee value', () {
      expect(moneyR(1500), '₹1,500');
    });

    test('moneyR recovers a paise fraction from the double', () {
      // GST math and per-unit line totals are exactly where this shows up:
      // 17.82 arrived as a double, not as an int paise value, and the old
      // formatRupees() this replaces got it right — the fold-in must too.
      expect(moneyR(17.82), '₹17.82');
    });

    test('moneyShortR abbreviates the same as moneyShort', () {
      expect(moneyShortR(416500), '₹4.2L');
    });
  });
}
