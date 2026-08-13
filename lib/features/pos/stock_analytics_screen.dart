import 'package:flutter/material.dart';

import '../../models/date_span.dart';
import '../../models/stock_report.dart';
import '../../services/stock_report_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/date_span_bar.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';

/// Stock analytics (FR-23).
///
/// The Restock queue next door answers "what is nearly gone" against a reorder
/// level somebody typed in once. This answers what that cannot: how long each
/// product lasts at the rate it actually sells, what it earns, and how much
/// money is asleep on the shelf.
///
/// On the gym's own data the two disagree — a product flagged low has
/// twenty-five days of cover while an unflagged one has twenty-three — which
/// is exactly why days of cover leads here and the reorder level is shown
/// beside it rather than instead of it.
///
/// Nothing here reorders anything or edits a threshold. The suggested level is
/// advisory, because a suggestion that silently rewrites somebody's setting is
/// a change nobody agreed to.
class StockAnalyticsScreen extends StatefulWidget {
  const StockAnalyticsScreen({super.key});

  @override
  State<StockAnalyticsScreen> createState() => _StockAnalyticsScreenState();
}

class _StockAnalyticsScreenState extends State<StockAnalyticsScreen> {
  final _service = StockReportService();

  /// Two months by default. A shop this size sells a handful of most lines a
  /// week, and a shorter window turns one quiet fortnight into a rate that
  /// says a product is dying.
  late DateSpan _span = DateSpan.custom(
    DateTime.now().subtract(const Duration(days: 59)),
    DateTime.now(),
  );

  bool _loading = true;
  String? _error;
  StockReport? _report;

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
      final data = await _service.getReport(span: _span);
      if (!mounted) return;
      setState(() {
        _report = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _setSpan(DateSpan next) {
    if (next == _span) return;
    setState(() => _span = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Short enough to survive a phone's app bar. The longer version --
        // "What the shop is doing" -- truncated to "What the shop is …" at
        // 638px and collided with the refresh button.
        title: const Text('Shop performance'),
        toolbarHeight: 48,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          DateSpanBar(span: _span, onChanged: _setSpan),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);

    final r = _report;
    if (r == null) return const LoadingView();

    if (r.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text('No products in the shop yet.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
      );
    }

    // Products needing a decision come first; the rest are the reference
    // below. Sorted by what it costs to ignore them, not alphabetically —
    // this is a list of products, and unlike a list of people a shelf can be
    // ranked without implying anything about anybody.
    final attention = r.products.where((p) => p.needsAttention).toList()
      ..sort((a, b) => b.stockValueInPaise.compareTo(a.stockValueInPaise));
    final rest = r.products.where((p) => !p.needsAttention).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          _Totals(report: r),
          const SizedBox(height: 12),
          if (r.categories.length > 1) ...[
            _Categories(report: r),
            const SizedBox(height: 12),
          ],
          if (attention.isNotEmpty) ...[
            _heading('Worth a decision', attention.length),
            ...attention.map((p) => _ProductRow(product: p, report: r)),
            const SizedBox(height: 8),
          ],
          if (rest.isNotEmpty) ...[
            _heading('Ticking along', rest.length),
            ...rest.map((p) => _ProductRow(product: p, report: r)),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rates come from what sold in this window, so a festival '
                    'or a closure inside it moves every figure. "Order now" '
                    'assumes a restock takes ${r.leadDays} days — an '
                    'assumption, not a measurement. Nothing here reorders '
                    'anything or changes a reorder level.',
                    style: TextStyle(
                        fontSize: 11, height: 1.4, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String text, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Row(
          children: [
            Text(text,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.bold)),
            const SizedBox(width: 7),
            Text('$n',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      );
}

class _Totals extends StatelessWidget {
  final StockReport report;

  const _Totals({required this.report});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              _figure(_rupees(report.revenueInPaise), 'sold'),
              Container(width: 1, height: 32, color: Colors.grey.shade200),
              _figure(_rupees(report.profitInPaise), 'profit'),
              Container(width: 1, height: 32, color: Colors.grey.shade200),
              _figure(_rupees(report.stockValueInPaise), 'on the shelf'),
            ],
          ),
          const SizedBox(height: 6),
          Text('${report.unitsSold} units over ${report.days} days',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),

          // The number worth acting on. Said as money rather than as a count,
          // because "four products" is not a reason to do anything and
          // "Rs 62,000 asleep" is.
          if (report.overstockedValueInPaise > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_rupees(report.overstockedValueInPaise)} is tied up in '
                '${report.overstockedCount} '
                '${report.overstockedCount == 1 ? 'product that will take' : 'products that will take'} '
                'months to sell. That is money already spent, sitting still.',
                style: const TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),
          ],

          if (report.deadCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${report.deadCount} '
                '${report.deadCount == 1 ? 'product sold' : 'products sold'} '
                'nothing at all in this window — '
                '${_rupees(report.deadValueInPaise)} of stock.',
                style: const TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _figure(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      );
}

class _Categories extends StatelessWidget {
  final StockReport report;

  const _Categories({required this.report});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Where the money came from',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final c in report.categories) ...[
            Row(
              children: [
                Expanded(
                    child: Text(c.category,
                        style: const TextStyle(fontSize: 12.5))),
                // Profit beside revenue, because they disagree: the biggest
                // seller by revenue is rarely the biggest earner.
                Text('${_rupees(c.revenueInPaise)} · ',
                    style: TextStyle(
                        fontSize: 11.5, color: Colors.grey.shade600)),
                Text(_rupees(c.profitInPaise),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: c.sharePct / 100,
                minHeight: 5,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final ProductStock product;
  final StockReport report;

  const _ProductRow({required this.product, required this.report});

  @override
  Widget build(BuildContext context) {
    final (label, colour) = _verdict();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(product.name,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colour.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: colour)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(product.note,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.3,
                              color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Days of cover leads, because it is the number that
                    // decides whether to order. The unit count is context.
                    Text(
                      product.daysCover == null
                          ? '—'
                          : '${product.daysCover}d',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colour),
                    ),
                    Text('${product.stockQty} left',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _meta('${product.unitsSold} sold'),
                _meta('${product.perDay.toStringAsFixed(2)}/day'),
                _meta('${_rupees(product.profitInPaise)} profit'),
                _meta('${product.marginPct}% margin'),
                // The current level next to what the rate implies, so a
                // mismatch is visible without the screen editing anything.
                if (product.suggestedReorder > 0)
                  _meta(
                    'reorder at ${product.reorderLevel} '
                    '(rate suggests ${product.suggestedReorder})',
                    dim: product.reorderLevel == product.suggestedReorder,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(String text, {bool dim = true}) => Text(
        text,
        style: TextStyle(
            fontSize: 11,
            color: dim ? Colors.grey.shade600 : Colors.grey.shade700),
      );

  (String, Color) _verdict() {
    switch (product.verdict) {
      case 'out_of_stock':
        return ('out of stock', AppColors.danger);
      case 'reorder_now':
        return ('order now', AppColors.danger);
      case 'dead':
        return ('not selling', AppColors.danger);
      case 'overstocked':
        return ('overstocked', AppColors.warning);
    }
    return ('fine', AppColors.success);
  }
}

String _rupees(int paise) {
  final rupees = paise ~/ 100;
  if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  if (rupees >= 1000) {
    return '₹${(rupees / 1000).toStringAsFixed(rupees >= 10000 ? 0 : 1)}k';
  }
  return '₹$rupees';
}
