import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/product.dart';
import '../../models/stock_queue.dart';
import '../../models/wallet.dart';
import '../../services/api_response.dart';
import '../../services/pos_service.dart';
import '../../services/queue_service.dart';
import '../../services/wallet_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../lifecycle/lifecycle_shared.dart';
import '../../widgets/member_picker.dart';
import 'stock_queue_view.dart';
import 'stock_analytics_screen.dart';

/// Retail: the counter, the shelf, and what was sold.
/// See docs/FR-07-pos-inventory.md.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  bool _changed = false;
  void _markChanged() => _changed = true;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Shop'),
            actions: [
              // The queue in Restock says what is nearly gone against a
              // typed-in threshold. This says how long things actually last
              // and what they earn — a different question, so a separate
              // screen rather than a fifth tab.
              IconButton(
                tooltip: 'Shop performance',
                icon: const Icon(Icons.insights_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StockAnalyticsScreen(),
                  ),
                ),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Sell'),
                // Restock sits beside Stock, not inside it. Stock is the
                // catalogue — everything, searchable, with a filter. Restock
                // is the worklist (FR-19 §5), and burying a worklist behind a
                // filter on a catalogue is how it stops being one.
                Tab(text: 'Restock'),
                Tab(text: 'Stock'),
                Tab(text: 'Sales'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _SellTab(onSold: _markChanged),
              _RestockTab(onChanged: _markChanged),
              _StockTab(onChanged: _markChanged),
              _SalesTab(onChanged: _markChanged),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Restock (FR-19 §5) ──────────────────────────────────────────────────────

/// The low-stock worklist.
///
/// Reads the queue endpoint rather than filtering the product list client-side:
/// the grouping, the ordering and the "sold in 30 days" figure are decisions
/// about what matters, and they belong in one place so every caller agrees.
class _RestockTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _RestockTab({required this.onChanged});

  @override
  State<_RestockTab> createState() => _RestockTabState();
}

class _RestockTabState extends State<_RestockTab> {
  final _queues = QueueService();
  final _pos = PosService();

  StockQueue? _queue;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final queue = await _queues.getStock();
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Restocking goes through the same dialog and the same endpoint as the
  /// Stock tab, so the movements ledger stays the only writer of stock levels
  /// (FR-07 §1). A queue that corrected stock itself would be a second source
  /// of truth for the same number.
  Future<void> _restock(StockQueueItem item) async {
    // The dialog only reads name and current quantity. Cost and tax are not
    // on the queue row and are not needed to add stock, so they are zeroed
    // rather than guessed — a wrong cost written into a movement would be
    // worse than an absent one.
    final product = Product(
      id: item.productId,
      name: item.name,
      sku: item.sku,
      category: item.category,
      priceInPaise: item.priceInPaise,
      costInPaise: 0,
      taxRatePct: 0,
      stockQty: item.stockQty,
      reorderLevel: item.reorderLevel,
      isActive: true,
    );

    final result = await showDialog<_Adjustment>(
      context: context,
      builder: (_) => _AdjustStockDialog(product: product),
    );
    if (result == null) return;

    try {
      await _pos.adjustStock(
        item.productId,
        quantity: result.quantity,
        movementType: result.movementType,
        reason: result.reason,
      );
      widget.onChanged();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);
    if (_queue == null) return const LoadingView();

    return RefreshIndicator(
      onRefresh: _load,
      child: StockQueueView(queue: _queue!, onRestock: _restock),
    );
  }
}

// ─── Sell ────────────────────────────────────────────────────────────────────

class _SellTab extends StatefulWidget {
  final VoidCallback onSold;
  const _SellTab({required this.onSold});

  @override
  State<_SellTab> createState() => _SellTabState();
}

class _SellTabState extends State<_SellTab> {
  final _service = PosService();
  final _searchController = TextEditingController();

  List<Product> _products = [];
  final List<CartLine> _cart = [];
  String _paymentMode = 'cash';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Optional: a walk-in has no member. Required only to pay from a wallet.
  Member? _member;
  Wallet? _wallet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.getProducts(search: _searchController.text.trim());
      if (!mounted) return;
      setState(() {
        _products = list.where((p) => p.isActive).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _add(Product p) {
    setState(() {
      final existing = _cart.indexWhere((l) => l.product.id == p.id);
      if (existing >= 0) {
        _cart[existing].quantity++;
      } else {
        _cart.add(CartLine(product: p));
      }
    });
  }

  void _remove(CartLine line) {
    setState(() {
      if (line.quantity > 1) {
        line.quantity--;
      } else {
        _cart.remove(line);
      }
    });
  }

  int get _cartTotal => _cart.fold(0, (a, l) => a + l.lineTotalInPaise);

  /// Wallet is only offerable when we know whose wallet it is and it holds
  /// enough. The server enforces both too — this just avoids offering a button
  /// that is certain to fail.
  bool get _canPayFromWallet =>
      _member != null && _wallet != null && _wallet!.balanceInPaise >= _cartTotal && _cartTotal > 0;

  Future<void> _pickMember() async {
    final picked = await showMemberPicker(
      context,
      title: 'Who is buying?',
      subtitle: 'Attach a member, or cancel for a walk-in',
      emptyHint: 'No matching member. Cancel to sell as a walk-in.',
    );
    // The dialog returns null when dismissed and a sentinel-free null member is
    // indistinguishable, so "clear" is handled by its own button below.
    if (picked == null) return;

    setState(() {
      _member = picked;
      _wallet = null;
    });
    try {
      final w = await WalletService().get(picked.id);
      if (!mounted) return;
      setState(() => _wallet = w);
    } on ApiException {
      // A wallet we cannot read simply means wallet payment isn't offered;
      // the sale can still be taken by cash or card.
    }
  }

  void _clearMember() {
    setState(() {
      _member = null;
      _wallet = null;
      if (_paymentMode == 'account') _paymentMode = 'cash';
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sale = await _service.recordSale(
        lines: _cart,
        paymentMode: _paymentMode,
        memberId: _member?.id,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _saving = false;
      });
      widget.onSold();

      // Confirm the sale before any follow-up work: the sale is already
      // committed, so the receipt message must not depend on what happens next.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sold — ${formatRupees(sale.totalInRupees)}')),
      );
      _load();

      // The wallet balance moved as part of that same transaction, so refresh
      // it rather than showing a stale figure on the next sale.
      if (_paymentMode == 'account' && _member != null) {
        try {
          final w = await WalletService().get(_member!.id);
          if (mounted) setState(() => _wallet = w);
        } on ApiException {
          // Non-fatal: the sale succeeded either way.
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Stock shortfalls come back as a specific, actionable message.
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => _load(),
            autofillHints: const [],
            decoration: const InputDecoration(
              hintText: 'Search products, or scan a barcode…',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorBanner(message: _error!),
          ),

        Expanded(
          child: _loading
              ? const LoadingView()
              : _products.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.inventory_2_outlined,
                      title: 'Nothing on the shelf',
                      body: 'Add products from the Stock tab before selling.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisExtent: 104,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _products.length,
                      itemBuilder: (_, i) => _ProductTile(
                        product: _products[i],
                        onTap: () => _add(_products[i]),
                      ),
                    ),
        ),

        if (_cart.isNotEmpty) _cartPanel(),
      ],
    );
  }

  Widget _cartPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final line in _cart)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${line.product.name} × ${line.quantity}',
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(formatRupees(line.lineTotalInPaise / 100),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          IconButton(
                            tooltip: 'Remove one',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            onPressed: () => _remove(line),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(),
          Row(
            children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(formatRupees(_cartTotal / 100),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          AppSpacing.gapSm,

          // Who is buying. Optional for cash sales — a walk-in buying a shaker
          // has no member record — but required to pay from a wallet.
          InkWell(
            onTap: _pickMember,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(_member == null ? Icons.person_outline : Icons.person,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _member == null
                          ? 'Walk-in — tap to attach a member'
                          : '${_member!.firstName} ${_member!.lastName}'
                              '${_wallet != null ? ' · wallet ${formatRupees(_wallet!.balanceInRupees)}' : ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _member == null ? AppColors.textSecondary : AppColors.textPrimary,
                        fontWeight: _member == null ? FontWeight.w400 : FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_member != null)
                    IconButton(
                      tooltip: 'Remove member',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: _clearMember,
                    ),
                ],
              ),
            ),
          ),
          AppSpacing.gapSm,

          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'cash', label: Text('Cash')),
              const ButtonSegment(value: 'upi', label: Text('UPI')),
              const ButtonSegment(value: 'credit_card', label: Text('Card')),
              ButtonSegment(
                value: 'account',
                label: const Text('Wallet'),
                // Disabled rather than hidden, so staff can see the option
                // exists and why it isn't available.
                enabled: _canPayFromWallet,
              ),
            ],
            selected: {_paymentMode},
            onSelectionChanged: (s) => setState(() => _paymentMode = s.first),
          ),

          if (_member != null && _wallet != null && !_canPayFromWallet && _cartTotal > 0) ...[
            AppSpacing.gapXs,
            Text(
              'Wallet has ${formatRupees(_wallet!.balanceInRupees)} — not enough for this sale.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
          if (_member == null) ...[
            AppSpacing.gapXs,
            const Text('Attach a member to pay from their wallet.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ],
          AppSpacing.gapSm,
          AppButton(
            text: 'Complete sale',
            loading: _saving,
            onPressed: _saving ? null : _checkout,
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final blocked = product.isOutOfStock;
    return InkWell(
      // Out of stock is disabled rather than hidden: staff need to see that the
      // gym stocks it at all, otherwise they assume it was never carried.
      onTap: blocked ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: blocked ? AppColors.background : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: product.isLowStock ? AppColors.warning : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: blocked ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
            Row(
              children: [
                Text(formatRupees(product.priceInRupees),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const Spacer(),
                Text(
                  blocked ? 'Out of stock' : '${product.stockQty} left',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: blocked
                        ? AppColors.danger
                        : (product.isLowStock ? AppColors.warning : AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stock ───────────────────────────────────────────────────────────────────

class _StockTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _StockTab({required this.onChanged});

  @override
  State<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<_StockTab> {
  final _service = PosService();
  List<Product> _products = [];
  RetailSummary? _summary;
  bool _lowOnly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await _service.getProducts(lowStockOnly: _lowOnly);
      final summary = await _service.summary();
      if (!mounted) return;
      setState(() {
        _products = products;
        _summary = summary;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _addProduct() async {
    final created = await showDialog<Product>(
      context: context,
      builder: (_) => const _AddProductDialog(),
    );
    if (created != null) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _adjust(Product p) async {
    final result = await showDialog<_Adjustment>(
      context: context,
      builder: (_) => _AdjustStockDialog(product: p),
    );
    if (result == null) return;
    try {
      await _service.adjustStock(
        p.id,
        quantity: result.quantity,
        movementType: result.movementType,
        reason: result.reason,
      );
      widget.onChanged();
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProduct,
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorBanner(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  children: [
                    if (s != null) ...[
                      LifecycleOutcome(
                        emphasisColor: AppColors.primary,
                        rows: [
                          ('Stock value (at cost)', formatRupees(s.stockValueInPaise / 100)),
                          ('Sold (30 days)', '${s.unitsSold} units'),
                          ('Margin (30 days)', formatRupees(s.marginInPaise / 100)),
                          ('Revenue (30 days)', formatRupees(s.revenueInPaise / 100)),
                        ],
                      ),
                      if (s.lowStockCount > 0) ...[
                        AppSpacing.gapSm,
                        LifecycleNotice(
                          tone: LifecycleTone.warning,
                          text: '${s.lowStockCount} product${s.lowStockCount == 1 ? ' is' : 's are'} '
                              'at or below the reorder level.',
                        ),
                      ],
                      AppSpacing.gapMd,
                    ],

                    Row(
                      children: [
                        FilterChip(
                          label: const Text('Low stock only'),
                          selected: _lowOnly,
                          onSelected: (v) {
                            setState(() => _lowOnly = v);
                            _load();
                          },
                        ),
                      ],
                    ),
                    AppSpacing.gapSm,

                    if (_products.isEmpty)
                      const EmptyStateView(
                        icon: Icons.inventory_2_outlined,
                        title: 'No products',
                        body: 'Add what your gym sells — supplements, shakers, gloves.',
                      )
                    else
                      for (final p in _products) ...[
                        _StockCard(product: p, onAdjust: () => _adjust(p)),
                        AppSpacing.gapSm,
                      ],
                  ],
                ),
    );
  }
}

class _StockCard extends StatelessWidget {
  final Product product;
  final VoidCallback onAdjust;
  const _StockCard({required this.product, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: product.isLowStock ? AppColors.warning : AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${formatRupees(product.priceInRupees)}'
                  '${product.costInPaise > 0 ? ' · cost ${formatRupees(product.costInPaise / 100)}' : ''}'
                  '${product.sku != null ? ' · ${product.sku}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${product.stockQty}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: product.isOutOfStock
                        ? AppColors.danger
                        : (product.isLowStock ? AppColors.warning : AppColors.textPrimary),
                  )),
              const Text('in stock',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
            ],
          ),
          IconButton(
            tooltip: 'Adjust stock',
            icon: const Icon(Icons.tune, size: 18),
            onPressed: onAdjust,
          ),
        ],
      ),
    );
  }
}

// ─── Sales history ───────────────────────────────────────────────────────────

class _SalesTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _SalesTab({required this.onChanged});

  @override
  State<_SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<_SalesTab> {
  final _service = PosService();
  List<Sale> _sales = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.getSales();
      if (!mounted) return;
      setState(() {
        _sales = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _refund(Sale sale) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => LifecycleDialogShell(
        title: 'Refund this sale?',
        subtitle: formatRupees(sale.totalInRupees),
        icon: Icons.undo,
        accent: AppColors.danger,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep it')),
          AppButton(
            text: 'Refund',
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LifecycleNotice(
              tone: LifecycleTone.warning,
              text: 'The original sale is kept exactly as it is. A reversing sale is recorded '
                  'and the stock goes back on the shelf. A reason is required.',
            ),
            AppSpacing.gapLg,
            const LifecycleFieldLabel('Reason'),
            AppSpacing.gapXs,
            TextField(
              controller: controller,
              autofillHints: const [],
              decoration: const InputDecoration(hintText: 'e.g. unopened, member changed mind'),
            ),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      await _service.refund(sale.id, reason: reason);
      widget.onChanged();
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);
    if (_sales.isEmpty) {
      return const EmptyStateView(
        icon: Icons.receipt_outlined,
        title: 'No sales yet',
        body: 'Counter sales from the last 30 days appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sales.length,
        separatorBuilder: (_, __) => AppSpacing.gapSm,
        itemBuilder: (_, i) {
          final s = _sales[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isRefund ? 'Refund of #${s.refundOfSaleId}' : 'Sale #${s.id}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: s.isRefund ? AppColors.danger : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (s.memberName != null) s.memberName!,
                          s.paymentMode.replaceAll('_', ' '),
                          if (s.createdAt.isNotEmpty)
                            formatDate(DateTime.parse(s.createdAt).toLocal()),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      if (s.reason != null) ...[
                        const SizedBox(height: 2),
                        Text('"${s.reason}"',
                            style: const TextStyle(
                                fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                Text(
                  formatRupees(s.totalInRupees),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: s.isRefund ? AppColors.danger : AppColors.textPrimary,
                  ),
                ),
                if (!s.isRefund)
                  IconButton(
                    tooltip: 'Refund',
                    icon: const Icon(Icons.undo, size: 18),
                    onPressed: () => _refund(s),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Dialogs ─────────────────────────────────────────────────────────────────

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog();

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _service = PosService();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _reorderController = TextEditingController(text: '5');

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim()) ?? -1;
    if (name.isEmpty) {
      setState(() => _error = 'Product name is required');
      return;
    }
    if (price < 0) {
      setState(() => _error = 'Enter a selling price');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final p = await _service.createProduct(
        name: name,
        priceInPaise: (price * 100).round(),
        costInPaise: ((double.tryParse(_costController.text.trim()) ?? 0) * 100).round(),
        reorderLevel: int.tryParse(_reorderController.text.trim()) ?? 0,
        openingStock: int.tryParse(_stockController.text.trim()) ?? 0,
      );
      if (!mounted) return;
      Navigator.pop(context, p);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: 'Add a product',
      subtitle: 'Something the gym sells',
      icon: Icons.inventory_2_outlined,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(text: 'Add', loading: _saving, onPressed: _saving ? null : _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Name'),
          AppSpacing.gapXs,
          TextField(
            controller: _nameController,
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'e.g. Whey Protein 1kg'),
          ),
          AppSpacing.gapLg,

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Sell price (₹)'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Cost (₹)'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapXs,
          const Text('Cost is what you paid — it is what makes the margin report meaningful.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          AppSpacing.gapLg,

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Opening stock'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _stockController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Warn below'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _reorderController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Attaches a member to a counter sale — which is what makes wallet payment,
/// and per-member purchase history, possible.
class _Adjustment {
  final int quantity;
  final String movementType;
  final String reason;
  _Adjustment(this.quantity, this.movementType, this.reason);
}

class _AdjustStockDialog extends StatefulWidget {
  final Product product;
  const _AdjustStockDialog({required this.product});

  @override
  State<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends State<_AdjustStockDialog> {
  final _qtyController = TextEditingController(text: '1');
  final _reasonController = TextEditingController();
  String _type = 'purchase';
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    if (qty <= 0) {
      setState(() => _error = 'Enter a quantity greater than 0');
      return;
    }
    // 'purchase' and 'return' add stock; 'wastage' removes it. 'adjustment'
    // takes the sign the user typed, so a correction can go either way.
    final signed = (_type == 'wastage') ? -qty : qty;
    Navigator.pop(context, _Adjustment(signed, _type, _reasonController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: 'Adjust stock',
      subtitle: '${widget.product.name} · ${widget.product.stockQty} in stock',
      icon: Icons.tune,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        AppButton(text: 'Record', onPressed: _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('What happened?'),
          AppSpacing.gapXs,
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'purchase', label: Text('Stock in')),
              ButtonSegment(value: 'wastage', label: Text('Damaged')),
              ButtonSegment(value: 'adjustment', label: Text('Recount')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Quantity'),
          AppSpacing.gapXs,
          TextField(
            controller: _qtyController,
            keyboardType: TextInputType.number,
            autofillHints: const [],
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Reason (optional)'),
          AppSpacing.gapXs,
          TextField(
            controller: _reasonController,
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'e.g. delivery from supplier'),
          ),
          AppSpacing.gapMd,

          const LifecycleNotice(
            tone: LifecycleTone.info,
            text: 'Every change is recorded with its reason, so a stock discrepancy '
                'can always be traced back.',
          ),
        ],
      ),
    );
  }
}
