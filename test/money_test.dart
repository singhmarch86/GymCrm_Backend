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

    test('truncates paise rather than rounding', () {
      // A displayed figure must never exceed what was actually charged.
      expect(money(150099), '₹1,500');
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
}
