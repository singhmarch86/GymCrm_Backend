/// Stock analytics (FR-23).
///
/// The Restock queue answers "what is nearly gone" against a reorder level
/// somebody typed in once. This answers the question that decides money: how
/// long will it last at the rate it actually sells, and is it worth restocking
/// at all.
library;

class ProductStock {
  final int productId;
  final String name;
  final String sku;
  final String category;

  final int stockQty;
  final int reorderLevel;

  final int unitsSold;
  final int revenueInPaise;
  final int profitInPaise;
  final int marginPct;

  /// Units per day across the chosen window. The window's own rate, not a
  /// forecast.
  final double perDay;

  /// Null when nothing sold. Never infinity — "infinite cover" reads as
  /// healthy when it means the opposite, so that case becomes a dead verdict
  /// instead.
  final int? daysCover;

  /// What the level would be if set from the sale rate and the lead time.
  /// Advisory: shown beside the current one, never written back.
  final int suggestedReorder;

  final int stockValueInPaise;

  /// out_of_stock | reorder_now | dead | overstocked | healthy
  final String verdict;
  final String note;

  const ProductStock({
    required this.productId,
    required this.name,
    required this.sku,
    required this.category,
    required this.stockQty,
    required this.reorderLevel,
    required this.unitsSold,
    required this.revenueInPaise,
    required this.profitInPaise,
    required this.marginPct,
    required this.perDay,
    this.daysCover,
    required this.suggestedReorder,
    required this.stockValueInPaise,
    required this.verdict,
    required this.note,
  });

  bool get needsAttention =>
      verdict == 'out_of_stock' ||
      verdict == 'reorder_now' ||
      verdict == 'dead' ||
      verdict == 'overstocked';

  factory ProductStock.fromJson(Map<String, dynamic> j) => ProductStock(
        productId: j['product_id'] ?? 0,
        name: j['name'] ?? '',
        sku: j['sku'] ?? '',
        category: j['category'] ?? '',
        stockQty: j['stock_qty'] ?? 0,
        reorderLevel: j['reorder_level'] ?? 0,
        unitsSold: j['units_sold'] ?? 0,
        revenueInPaise: j['revenue_in_paise'] ?? 0,
        profitInPaise: j['profit_in_paise'] ?? 0,
        marginPct: j['margin_pct'] ?? 0,
        perDay: (j['per_day'] ?? 0).toDouble(),
        daysCover: j['days_cover'],
        suggestedReorder: j['suggested_reorder'] ?? 0,
        stockValueInPaise: j['stock_value_in_paise'] ?? 0,
        verdict: j['verdict'] ?? 'healthy',
        note: j['note'] ?? '',
      );
}

class StockCategoryTotal {
  final String category;
  final int unitsSold;
  final int revenueInPaise;
  final int profitInPaise;
  final int sharePct;

  const StockCategoryTotal({
    required this.category,
    required this.unitsSold,
    required this.revenueInPaise,
    required this.profitInPaise,
    required this.sharePct,
  });

  factory StockCategoryTotal.fromJson(Map<String, dynamic> j) =>
      StockCategoryTotal(
        category: j['category'] ?? '',
        unitsSold: j['units_sold'] ?? 0,
        revenueInPaise: j['revenue_in_paise'] ?? 0,
        profitInPaise: j['profit_in_paise'] ?? 0,
        sharePct: j['share_pct'] ?? 0,
      );
}

class StockReport {
  final String from;
  final String to;
  final int days;

  /// How long a restock is assumed to take. Every "order now" verdict is
  /// really "will run out before a delivery arrives", so this number is shown
  /// rather than hidden.
  final int leadDays;

  final int unitsSold;
  final int revenueInPaise;
  final int profitInPaise;

  final int stockValueInPaise;
  final int deadValueInPaise;
  final int deadCount;

  final int mismatchCount;

  final List<ProductStock> products;
  final List<StockCategoryTotal> categories;

  const StockReport({
    required this.from,
    required this.to,
    required this.days,
    required this.leadDays,
    required this.unitsSold,
    required this.revenueInPaise,
    required this.profitInPaise,
    required this.stockValueInPaise,
    required this.deadValueInPaise,
    required this.deadCount,
    required this.mismatchCount,
    required this.products,
    required this.categories,
  });

  bool get isEmpty => products.isEmpty;

  /// Capital in products that will take months to sell. The number worth
  /// acting on: money already spent that is doing nothing.
  int get overstockedValueInPaise => products
      .where((p) => p.verdict == 'overstocked')
      .fold(0, (sum, p) => sum + p.stockValueInPaise);

  int get overstockedCount =>
      products.where((p) => p.verdict == 'overstocked').length;

  factory StockReport.fromJson(Map<String, dynamic> j) => StockReport(
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        days: j['days'] ?? 0,
        leadDays: j['lead_days'] ?? 7,
        unitsSold: j['units_sold'] ?? 0,
        revenueInPaise: j['revenue_in_paise'] ?? 0,
        profitInPaise: j['profit_in_paise'] ?? 0,
        stockValueInPaise: j['stock_value_in_paise'] ?? 0,
        deadValueInPaise: j['dead_value_in_paise'] ?? 0,
        deadCount: j['dead_count'] ?? 0,
        mismatchCount: j['mismatch_count'] ?? 0,
        products: ((j['products'] as List?) ?? [])
            .map((e) => ProductStock.fromJson(e as Map<String, dynamic>))
            .toList(),
        categories: ((j['categories'] as List?) ?? [])
            .map((e) => StockCategoryTotal.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
