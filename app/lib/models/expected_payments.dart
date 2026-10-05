/// Expected payments (FR-19 §5) — money the gym has reason to think is coming.
///
/// Two figures that must never be added together on screen:
///
///   * **Raised** — a due already written down, falling in the chosen span.
///     The gym decided this was owed.
///   * **Expiring** — a membership whose expiry falls in the span, valued at
///     the plan's price today. Nobody has agreed to pay it.
///
/// On live data the estimate runs about thirteen times the raised amount. One
/// combined "expected" number would bury the real figure inside a guess, so
/// this model keeps them in separate fields and there is deliberately no
/// `total` getter to reach for.
library;

class ExpectedItem {
  /// `raised` or `expiring`.
  final String kind;

  final int memberId;
  final String member;
  final String phone;

  final int amountInPaise;

  /// True for expiring memberships: the plan price today, not an agreement.
  final bool estimated;

  /// Due date for a raised due, expiry date for a membership.
  final DateTime? date;

  /// Raised dues only — the handle the Collect queue acts on.
  final int? paymentId;

  final String? planName;
  final DateTime? lastVisitAt;

  /// What this member already owes, whichever kind of row this is. Expecting a
  /// renewal from somebody sitting on an unpaid due is a different
  /// conversation, and it should not be a mid-call surprise.
  final int owedInPaise;

  const ExpectedItem({
    required this.kind,
    required this.memberId,
    required this.member,
    required this.phone,
    required this.amountInPaise,
    required this.estimated,
    this.date,
    this.paymentId,
    this.planName,
    this.lastVisitAt,
    required this.owedInPaise,
  });

  bool get isRaised => kind == 'raised';

  factory ExpectedItem.fromJson(Map<String, dynamic> j) => ExpectedItem(
    kind: j['kind'] ?? 'expiring',
    memberId: j['member_id'] ?? 0,
    member: j['member'] ?? '',
    phone: j['phone'] ?? '',
    amountInPaise: j['amount_in_paise'] ?? 0,
    estimated: j['estimated'] ?? false,
    date: _date(j['date']),
    paymentId: j['payment_id'],
    planName: j['plan_name'],
    lastVisitAt: _date(j['last_visit_at']),
    owedInPaise: j['owed_in_paise'] ?? 0,
  );

  static DateTime? _date(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
}

/// One column of the span's shape — a day, or a month for longer spans.
class ExpectedBucket {
  final String key;
  final String label;
  final int raisedInPaise;
  final int expiringInPaise;
  final int raisedCount;
  final int expiringCount;

  const ExpectedBucket({
    required this.key,
    required this.label,
    required this.raisedInPaise,
    required this.expiringInPaise,
    required this.raisedCount,
    required this.expiringCount,
  });

  bool get isEmpty => raisedCount == 0 && expiringCount == 0;

  factory ExpectedBucket.fromJson(Map<String, dynamic> j) => ExpectedBucket(
    key: j['key'] ?? '',
    label: j['label'] ?? '',
    raisedInPaise: j['raised_in_paise'] ?? 0,
    expiringInPaise: j['expiring_in_paise'] ?? 0,
    raisedCount: j['raised_count'] ?? 0,
    expiringCount: j['expiring_count'] ?? 0,
  );
}

class ExpectedPayments {
  final String from;
  final String to;
  final int days;
  final bool isSingleDay;

  final int raisedCount;
  final int raisedInPaise;

  final int expiringCount;
  final int expiringInPaise;

  /// `day` or `month`.
  final String bucketUnit;
  final List<ExpectedBucket> buckets;

  final List<ExpectedItem> items;

  /// The list is capped; the totals above are not. Said on screen, because a
  /// reader who scrolls to the end of a truncated list will otherwise add it
  /// up and find it short.
  final bool truncated;

  const ExpectedPayments({
    required this.from,
    required this.to,
    required this.days,
    required this.isSingleDay,
    required this.raisedCount,
    required this.raisedInPaise,
    required this.expiringCount,
    required this.expiringInPaise,
    required this.bucketUnit,
    required this.buckets,
    required this.items,
    required this.truncated,
  });

  bool get isEmpty => raisedCount == 0 && expiringCount == 0;

  /// The tallest column, for scaling the shape. Compares the two kinds
  /// separately and takes the larger — the bars are drawn side by side, not
  /// stacked, for the same reason the totals are not summed.
  int get peakInPaise {
    var peak = 0;
    for (final b in buckets) {
      if (b.raisedInPaise > peak) peak = b.raisedInPaise;
      if (b.expiringInPaise > peak) peak = b.expiringInPaise;
    }
    return peak;
  }

  factory ExpectedPayments.fromJson(Map<String, dynamic> j) => ExpectedPayments(
    from: j['from'] ?? '',
    to: j['to'] ?? '',
    days: j['days'] ?? 1,
    isSingleDay: j['is_single_day'] ?? false,
    raisedCount: j['raised_count'] ?? 0,
    raisedInPaise: j['raised_in_paise'] ?? 0,
    expiringCount: j['expiring_count'] ?? 0,
    expiringInPaise: j['expiring_in_paise'] ?? 0,
    bucketUnit: j['bucket_unit'] ?? 'day',
    buckets: ((j['buckets'] as List?) ?? [])
        .map((e) => ExpectedBucket.fromJson(e as Map<String, dynamic>))
        .toList(),
    items: ((j['items'] as List?) ?? [])
        .map((e) => ExpectedItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    truncated: j['truncated'] ?? false,
  );
}
