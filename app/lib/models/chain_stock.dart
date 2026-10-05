/// Inventory across branches (FR-22).
///
/// Mirrors the server's shape rather than flattening it. The per-branch rows
/// stay a list because the screen needs to render one column per branch, and
/// a chain can have two or six.
class ChainStock {
  final List<BranchRef> branches;
  final List<ChainItem> items;

  /// Items short at one branch while another has a surplus — the ones a
  /// transfer can actually fix.
  final int movableCount;

  /// Items short at every branch that carries them. No transfer helps; these
  /// need a purchase order, which is why they are kept out of the queue.
  final List<String> shortEverywhere;

  const ChainStock({
    required this.branches,
    required this.items,
    required this.movableCount,
    required this.shortEverywhere,
  });

  bool get isSingleBranch => branches.length < 2;

  List<ChainItem> get movable => items.where((i) => i.movable).toList();

  factory ChainStock.fromJson(Map<String, dynamic> json) => ChainStock(
    branches: ((json['branches'] as List?) ?? [])
        .map((b) => BranchRef.fromJson(b as Map<String, dynamic>))
        .toList(),
    items: ((json['items'] as List?) ?? [])
        .map((i) => ChainItem.fromJson(i as Map<String, dynamic>))
        .toList(),
    movableCount: json['movable_count'] as int? ?? 0,
    shortEverywhere: ((json['short_everywhere'] as List?) ?? [])
        .map((s) => s.toString())
        .toList(),
  );
}

class BranchRef {
  final int gymId;
  final String name;

  const BranchRef({required this.gymId, required this.name});

  factory BranchRef.fromJson(Map<String, dynamic> json) =>
      BranchRef(gymId: json['gym_id'] as int, name: json['name'] as String);
}

class ChainItem {
  final String key;

  /// "sku" or "name". Surfaced rather than hidden: an item matched by name is
  /// a guess, and a reader who sees the same tub listed twice needs to know
  /// that setting a SKU is the fix.
  final String matchedBy;

  final String name;
  final String? sku;
  final String? category;

  final List<BranchStock> branches;
  final int totalQty;
  final int shortBranches;
  final int longBranches;
  final bool movable;

  const ChainItem({
    required this.key,
    required this.matchedBy,
    required this.name,
    required this.sku,
    required this.category,
    required this.branches,
    required this.totalQty,
    required this.shortBranches,
    required this.longBranches,
    required this.movable,
  });

  bool get matchedByName => matchedBy == 'name';

  /// The branch with the deepest surplus, which is where a transfer would
  /// sensibly draw from. A suggestion of source, not of route — the screen
  /// still makes a person choose.
  BranchStock? get fullest {
    final surplus = branches.where((b) => b.isLong).toList();
    if (surplus.isEmpty) return null;
    surplus.sort((a, b) => b.stockQty.compareTo(a.stockQty));
    return surplus.first;
  }

  BranchStock? get emptiest {
    final short = branches.where((b) => b.isShort).toList();
    if (short.isEmpty) return null;
    short.sort((a, b) => a.stockQty.compareTo(b.stockQty));
    return short.first;
  }

  /// The branch's row for a given gym, or null when it does not carry the
  /// item. Null and zero are different facts and the table shows them
  /// differently: "—" means not stocked, "0" means stocked and run out.
  BranchStock? at(int gymId) {
    for (final b in branches) {
      if (b.gymId == gymId) return b;
    }
    return null;
  }

  factory ChainItem.fromJson(Map<String, dynamic> json) => ChainItem(
    key: json['key'] as String,
    matchedBy: json['matched_by'] as String? ?? 'name',
    name: json['name'] as String,
    sku: json['sku'] as String?,
    category: json['category'] as String?,
    branches: ((json['branches'] as List?) ?? [])
        .map((b) => BranchStock.fromJson(b as Map<String, dynamic>))
        .toList(),
    totalQty: json['total_qty'] as int? ?? 0,
    shortBranches: json['short_branches'] as int? ?? 0,
    longBranches: json['long_branches'] as int? ?? 0,
    movable: json['movable'] as bool? ?? false,
  );
}

class BranchStock {
  final int gymId;
  final String branch;
  final int productId;
  final int stockQty;
  final int reorderLevel;
  final int costInPaise;
  final int priceInPaise;
  final bool isShort;
  final bool isLong;

  const BranchStock({
    required this.gymId,
    required this.branch,
    required this.productId,
    required this.stockQty,
    required this.reorderLevel,
    required this.costInPaise,
    required this.priceInPaise,
    required this.isShort,
    required this.isLong,
  });

  /// How many units could leave without dropping this branch below its own
  /// reorder level. The cap the send sheet offers, so helping one branch
  /// never creates the same problem at another.
  int get spare {
    final n = stockQty - reorderLevel;
    return n > 0 ? n : 0;
  }

  factory BranchStock.fromJson(Map<String, dynamic> json) => BranchStock(
    gymId: json['gym_id'] as int,
    branch: json['branch'] as String,
    productId: json['product_id'] as int,
    stockQty: json['stock_qty'] as int? ?? 0,
    reorderLevel: json['reorder_level'] as int? ?? 0,
    costInPaise: json['cost_in_paise'] as int? ?? 0,
    priceInPaise: json['price_in_paise'] as int? ?? 0,
    isShort: json['is_short'] as bool? ?? false,
    isLong: json['is_long'] as bool? ?? false,
  );
}

/// One row of the transfer ledger.
class TransferRow {
  final int id;
  final String product;
  final int quantity;
  final int fromGymId;
  final int toGymId;
  final String fromBranch;
  final String toBranch;

  /// "out" or "in", relative to the branch the reader is signed in to.
  final String direction;

  final int valueInPaise;
  final String? reason;
  final String by;
  final DateTime at;

  const TransferRow({
    required this.id,
    required this.product,
    required this.quantity,
    required this.fromGymId,
    required this.toGymId,
    required this.fromBranch,
    required this.toBranch,
    required this.direction,
    required this.valueInPaise,
    required this.reason,
    required this.by,
    required this.at,
  });

  bool get isOutbound => direction == 'out';

  factory TransferRow.fromJson(Map<String, dynamic> json) => TransferRow(
    id: json['id'] as int,
    product: json['product'] as String? ?? '',
    quantity: json['quantity'] as int? ?? 0,
    fromGymId: json['from_gym_id'] as int? ?? 0,
    toGymId: json['to_gym_id'] as int? ?? 0,
    fromBranch: json['from_branch'] as String? ?? '',
    toBranch: json['to_branch'] as String? ?? '',
    direction: json['direction'] as String? ?? 'in',
    valueInPaise: json['value_in_paise'] as int? ?? 0,
    reason: json['reason'] as String?,
    by: json['by'] as String? ?? '',
    at: DateTime.parse(json['at'] as String).toLocal(),
  );
}
