// Retail models. See docs/FR-07-pos-inventory.md in the backend repo.
//
// Stock is never edited directly — it moves only through recorded movements,
// so a discrepancy always has a trail.

class Product {
  final int id;
  final String? sku;
  final String name;
  final String? category;
  final int priceInPaise;
  final int costInPaise;
  final double taxRatePct;
  final int stockQty;
  final int reorderLevel;
  final bool isActive;

  Product({
    required this.id,
    this.sku,
    required this.name,
    this.category,
    required this.priceInPaise,
    required this.costInPaise,
    required this.taxRatePct,
    required this.stockQty,
    required this.reorderLevel,
    required this.isActive,
  });

  bool get isLowStock => stockQty <= reorderLevel;
  bool get isOutOfStock => stockQty <= 0;
  double get priceInRupees => priceInPaise / 100;

  /// What the gym makes on each unit — the reason cost is captured at all.
  int get marginInPaise => priceInPaise - costInPaise;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] ?? 0,
        sku: j['sku'],
        name: j['name'] ?? '',
        category: j['category'],
        priceInPaise: j['price_in_paise'] ?? 0,
        costInPaise: j['cost_in_paise'] ?? 0,
        taxRatePct: (j['tax_rate_pct'] as num?)?.toDouble() ?? 18,
        stockQty: j['stock_qty'] ?? 0,
        reorderLevel: j['reorder_level'] ?? 0,
        isActive: j['is_active'] ?? true,
      );
}

class SaleLine {
  final int productId;
  final String productName;
  final int quantity;
  final int unitPriceInPaise;
  final int lineTotalInPaise;

  SaleLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceInPaise,
    required this.lineTotalInPaise,
  });

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
        productId: j['product_id'] ?? 0,
        productName: j['product_name'] ?? '',
        quantity: j['quantity'] ?? 0,
        unitPriceInPaise: j['unit_price_in_paise'] ?? 0,
        lineTotalInPaise: j['line_total_in_paise'] ?? 0,
      );
}

class Sale {
  final int id;
  final int? memberId;
  final String? memberName;
  final int subtotalInPaise;
  final int taxInPaise;
  final int discountInPaise;
  final int totalInPaise;
  final double totalInRupees;
  final String paymentMode;
  final bool isRefund;
  final int? refundOfSaleId;
  final String? reason;
  final String createdAt;
  final List<SaleLine> items;

  Sale({
    required this.id,
    this.memberId,
    this.memberName,
    required this.subtotalInPaise,
    required this.taxInPaise,
    required this.discountInPaise,
    required this.totalInPaise,
    required this.totalInRupees,
    required this.paymentMode,
    required this.isRefund,
    this.refundOfSaleId,
    this.reason,
    required this.createdAt,
    required this.items,
  });

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'] ?? 0,
        memberId: j['member_id'],
        memberName: j['member_name'],
        subtotalInPaise: j['subtotal_in_paise'] ?? 0,
        taxInPaise: j['tax_in_paise'] ?? 0,
        discountInPaise: j['discount_in_paise'] ?? 0,
        totalInPaise: j['total_in_paise'] ?? 0,
        totalInRupees: (j['total_in_rupees'] as num?)?.toDouble() ?? 0,
        paymentMode: j['payment_mode'] ?? 'cash',
        isRefund: j['is_refund'] ?? false,
        refundOfSaleId: j['refund_of_sale_id'],
        reason: j['reason'],
        createdAt: j['created_at'] ?? '',
        items: ((j['items'] as List?) ?? [])
            .map((e) => SaleLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class StockMovement {
  final int id;
  final String movementType;
  final int quantity;
  final int qtyAfter;
  final String? reason;
  final String createdAt;

  StockMovement({
    required this.id,
    required this.movementType,
    required this.quantity,
    required this.qtyAfter,
    this.reason,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
        id: j['id'] ?? 0,
        movementType: j['movement_type'] ?? 'adjustment',
        quantity: j['quantity'] ?? 0,
        qtyAfter: j['qty_after'] ?? 0,
        reason: j['reason'],
        createdAt: j['created_at'] ?? '',
      );
}

class RetailSummary {
  final int saleCount;
  final int unitsSold;
  final int revenueInPaise;
  final int costInPaise;
  final int marginInPaise;
  final int stockValueInPaise;
  final int lowStockCount;

  RetailSummary({
    required this.saleCount,
    required this.unitsSold,
    required this.revenueInPaise,
    required this.costInPaise,
    required this.marginInPaise,
    required this.stockValueInPaise,
    required this.lowStockCount,
  });

  factory RetailSummary.fromJson(Map<String, dynamic> j) => RetailSummary(
        saleCount: j['sale_count'] ?? 0,
        unitsSold: j['units_sold'] ?? 0,
        revenueInPaise: j['revenue_in_paise'] ?? 0,
        costInPaise: j['cost_in_paise'] ?? 0,
        marginInPaise: j['margin_in_paise'] ?? 0,
        stockValueInPaise: j['stock_value_in_paise'] ?? 0,
        lowStockCount: j['low_stock_count'] ?? 0,
      );
}

/// A line in the counter cart, before the sale is recorded. Local only —
/// nothing exists server-side until the sale is completed in one step.
class CartLine {
  final Product product;
  int quantity;

  CartLine({required this.product, this.quantity = 1});

  int get lineTotalInPaise => product.priceInPaise * quantity;
}
