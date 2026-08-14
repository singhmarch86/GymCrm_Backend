/// Money, formatted the way an Indian gym owner reads it.
///
/// Two functions, because there are two genuinely different jobs and the app
/// had been quietly doing both — plus a third, wrong one — from thirteen
/// private copies:
///
///   money()       ₹4,16,500 — exact. For ledgers, invoices, anywhere the
///                 figure is the record and somebody may check it against a
///                 receipt.
///   moneyShort()  ₹4.2L     — approximate. For cards, queues and headline
///                 tiles where space is tight and the reader wants a size,
///                 not a number.
///
/// Never mix them in one column. A table where some rows say ₹13k and others
/// ₹13,240 reads as inconsistent data rather than inconsistent formatting.
///
/// Both take paise, the unit the API speaks in. Both handle negatives, which
/// only the payouts screen's copy used to: everywhere else a large negative
/// fell past the abbreviation thresholds and printed raw.
library;

/// Exact, with Indian digit grouping: 1,500 · 13,000 · 1,50,000.
///
/// Pairs above the last three, not western triples all the way up.
String money(int paise) {
  final negative = paise < 0;
  final rupees = (negative ? -paise : paise) ~/ 100;
  return '${negative ? '-' : ''}₹${_group(rupees)}';
}

/// Abbreviated: ₹950 · ₹1.5k · ₹13k · ₹4.2L.
///
/// One decimal below ten thousand and above a lakh, none between — ₹1.5k
/// carries information, ₹13.2k is noise at the size this is used.
String moneyShort(int paise) {
  final negative = paise < 0;
  final rupees = (negative ? -paise : paise) ~/ 100;
  final sign = negative ? '-' : '';

  if (rupees >= 100000) {
    return '$sign₹${(rupees / 100000).toStringAsFixed(1)}L';
  }
  if (rupees >= 1000) {
    return '$sign₹${(rupees / 1000).toStringAsFixed(rupees >= 10000 ? 0 : 1)}k';
  }
  return '$sign₹$rupees';
}

/// Digits only, no symbol — for a field the reader is about to edit, where a
/// currency mark in the text would be typed over or submitted by accident.
String moneyPlain(int paise) => _group((paise < 0 ? -paise : paise) ~/ 100);

/// [money] for the handful of models that expose rupees as a double rather
/// than paise as an int — plan prices and invoice line items, mostly, from
/// before the paise convention was consistent. Rounds to the nearest paisa
/// rather than truncating, since these values were never fractions of a
/// paisa to begin with and rounding is the more honest read of a double that
/// arrived via JSON.
String moneyR(double rupees) => money((rupees * 100).round());

/// [moneyShort] for the same rupees-as-double fields.
String moneyShortR(double rupees) => moneyShort((rupees * 100).round());

String _group(int rupees) {
  final s = '$rupees';
  if (s.length <= 3) return s;

  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);

  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);

  return '${parts.join(',')},$last3';
}
