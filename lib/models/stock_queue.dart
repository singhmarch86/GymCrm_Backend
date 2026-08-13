/// The low-stock work queue (FR-19 §5).
///
/// Not the product catalogue with a filter on it. A queue names what is owed,
/// groups it worst-first, and offers the action in place — the shape the lead
/// workflow proved and the rest of the product lacks.
library;

class StockQueueItem {
  final int productId;
  final String name;
  final String? sku;
  final String? category;

  final int stockQty;
  final int reorderLevel;
  final int priceInPaise;

  /// Units sold in the last 30 days.
  ///
  /// The whole point of the row. Two left is fine for something that moves
  /// twice a year and an emergency for something that moves daily; without
  /// this the reader has to already know the product to read the row.
  final int soldLast30;

  final DateTime? lastRestockedAt;

  /// Only ever set for a product actually at zero — for anything else it is a
  /// countdown that has not started.
  final int? daysOutOfStock;

  const StockQueueItem({
    required this.productId,
    required this.name,
    this.sku,
    this.category,
    required this.stockQty,
    required this.reorderLevel,
    required this.priceInPaise,
    required this.soldLast30,
    this.lastRestockedAt,
    this.daysOutOfStock,
  });

  factory StockQueueItem.fromJson(Map<String, dynamic> j) => StockQueueItem(
    productId: j['product_id'] ?? 0,
    name: j['name'] ?? '',
    sku: j['sku'],
    category: j['category'],
    stockQty: j['stock_qty'] ?? 0,
    reorderLevel: j['reorder_level'] ?? 0,
    priceInPaise: j['price_in_paise'] ?? 0,
    soldLast30: j['sold_last_30'] ?? 0,
    lastRestockedAt: j['last_restocked_at'] == null
        ? null
        : DateTime.tryParse(j['last_restocked_at'])?.toLocal(),
    daysOutOfStock: j['days_out_of_stock'],
  );

  bool get outOfStock => stockQty <= 0;

  /// Roughly how long the shelf lasts at the last 30 days' rate.
  ///
  /// Null when nothing sold — a rate of zero gives an infinite answer, and
  /// "lasts forever" is not a useful thing to print next to a low-stock
  /// warning. The row says "no sales recorded" instead, which is both true and
  /// the more interesting fact.
  int? get daysOfCoverLeft {
    if (soldLast30 <= 0 || stockQty <= 0) return null;
    final perDay = soldLast30 / 30.0;
    return (stockQty / perDay).floor();
  }
}

class StockQueueGroup {
  final String key;
  final String label;
  final String note;
  final String severity; // urgent | warn | normal
  final List<StockQueueItem> items;

  const StockQueueGroup({
    required this.key,
    required this.label,
    required this.note,
    required this.severity,
    required this.items,
  });

  factory StockQueueGroup.fromJson(Map<String, dynamic> j) => StockQueueGroup(
    key: j['key'] ?? '',
    label: j['label'] ?? '',
    note: j['note'] ?? '',
    severity: j['severity'] ?? 'normal',
    items: ((j['items'] as List?) ?? [])
        .map((e) => StockQueueItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class StockQueue {
  final List<StockQueueGroup> groups;
  final int totalProducts;
  final int totalFlagged;
  final int totalOutOfStock;

  const StockQueue({
    required this.groups,
    required this.totalProducts,
    required this.totalFlagged,
    required this.totalOutOfStock,
  });

  factory StockQueue.fromJson(Map<String, dynamic> j) => StockQueue(
    groups: ((j['groups'] as List?) ?? [])
        .map((e) => StockQueueGroup.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalProducts: j['total_products'] ?? 0,
    totalFlagged: j['total_flagged'] ?? 0,
    totalOutOfStock: j['total_out_of_stock'] ?? 0,
  );

  /// The state worth celebrating: nothing owed. Distinct from "no products",
  /// which is a setup problem rather than a clear queue.
  bool get isClear => totalFlagged == 0;
  bool get hasNoProducts => totalProducts == 0;
}
