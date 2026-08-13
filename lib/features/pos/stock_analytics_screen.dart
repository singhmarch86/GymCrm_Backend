import 'package:flutter/material.dart';

import '../../models/date_span.dart';
import '../../models/stock_report.dart';
import '../../services/stock_report_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/date_span_bar.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/readable_width.dart';

/// Stock analytics (FR-23).
///
/// The Restock queue answers "what is nearly gone" against a reorder level
/// somebody typed in once. This answers the question that decides money: how
/// long will it last at the rate it actually sells, and is it worth restocking
/// at all.
///
/// On the gym's own data those disagree — a product flagged low with 25 days
/// of cover, another unflagged with 23 — which is the reason the screen
/// exists. Days of cover replaces an arbitrary threshold.
///
/// Nothing here writes. The suggested reorder level sits beside the current
/// one so a mismatch is visible, and stays a suggestion: silently editing a
/// threshold somebody set is a change nobody agreed to.
class StockAnalyticsScreen extends StatefulWidget {
  const StockAnalyticsScreen({super.key});

  @override
  State<StockAnalyticsScreen> createState() => _StockAnalyticsScreenState();
}

class _StockAnalyticsScreenState extends State<StockAnalyticsScreen> {
  final _service = StockReportService();

  /// Two months back by default. A week of counter sales is too few to derive
  /// a rate from — one quiet Sunday would halve it — and the whole screen
  /// rests on that rate being believable.
  DateSpan _span = DateSpan.custom(
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
        title: const Text('What the shop is doing'),
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
          child: Text(
            'No products on the shelf yet.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    // Ordered so the two verdicts that cost money come first. A list sorted
    // by profit puts the healthy best-seller at the top, which is pleasant
    // and useless.
    final needsAction =
        r.products.where((p) => p.needsAttention).toList();
    final rest = r.products.where((p) => !p.needsAttention).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            _Totals(report: r),
            const SizedBox(height: 12),
            if (needsAction.isNotEmpty) ...[
              _heading('Worth doing something about', needsAction.length),
              ...needsAction.map((p) => _ProductRow(product: p)),
              const SizedBox(height: 6),
            ],
            _heading('Everything else', rest.length),
            ...rest.map((p) => _ProductRow(product: p)),
            const SizedBox(height: 14),
            _Categories(report: r),
            const SizedBox(height: 12),
            _Caveat(report: r),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Row(
          children: [
            Text(text,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
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
    final asleep = report.deadValueInPaise + report.overstockedValueInPaise;
    final asleepCount = report.deadCount + report.overstockedCount;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              _figure('${report.unitsSold}', 'sold'),
              _divider(),
              _figure(_rupees(report.revenueInPaise), 'taken'),
              _divider(),
              _figure(_rupees(report.profitInPaise), 'profit'),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 10),
          Row(
            children: [
              _figure(_rupees(report.stockValueInPaise), 'on the shelf'),
              _divider(),
              _figure(
                _rupees(asleep),
                'of it asleep',
                colour: asleep > 0 ? AppColors.danger : null,
              ),
            ],
          ),

          // The sentence the screen exists to deliver. Money already spent
          // that is doing nothing is more actionable than money not yet
          // earned, because it can be stopped tomorrow.
          if (asleep > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$asleepCount ${asleepCount == 1 ? 'product holds' : 'products hold'} '
                '${_rupees(asleep)} that will take months to sell, or is not '
                'selling at all. That is stock money already spent — buying '
                'less of it frees cash for what turns over.',
                style: const TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _figure(String value, String label, {Color? colour}) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: colour ?? AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      );

  Widget _divider() =>
      Container(width: 1, height: 30, color: Colors.grey.shade200);
}

class _ProductRow extends StatelessWidget {
  final ProductStock product;

  const _ProductRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final (label, colour) = _verdict(product.verdict);

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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
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
                      // The verdict explains itself in the server's words, so
                      // the reason lives in one place rather than being
                      // re-derived per client.
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
                    Text('${product.stockQty}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('in stock',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _meta('${product.unitsSold} sold'),
                _meta('${product.perDay}/day'),
                _meta('${product.marginPct}% margin'),
                _meta('${_rupees(product.profitInPaise)} profit'),
                // Shown together so a level that disagrees with the rate is
                // visible without arithmetic. Advisory: nothing is rewritten.
                if (product.suggestedReorder > 0)
                  _meta('reorder at ${product.reorderLevel}'
                      ' · suggest ${product.suggestedReorder}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(String text) => Text(text,
      style: TextStyle(fontSize: 11, color: Colors.grey.shade600));

  static (String, Color) _verdict(String v) {
    switch (v) {
      case 'out_of_stock':
        return ('out of stock', AppColors.danger);
      case 'reorder_now':
        return ('order now', AppColors.danger);
      case 'dead':
        return ('not selling', AppColors.warning);
      case 'overstocked':
        return ('overstocked', AppColors.warning);
    }
    return ('healthy', AppColors.success);
  }
}

class _Categories extends StatelessWidget {
  final StockReport report;

  const _Categories({required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.categories.isEmpty) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('By category',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final c in report.categories) ...[
            Row(
              children: [
                Expanded(
                  child:
                      Text(c.category, style: const TextStyle(fontSize: 12.5)),
                ),
                Text(_rupees(c.profitInPaise),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                SizedBox(
                  width: 44,
                  child: Text('${c.sharePct}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade600)),
                ),
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

class _Caveat extends StatelessWidget {
  final StockReport report;

  const _Caveat({required this.report});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Rates are what sold in the window above, not a forecast — a '
              'festival or a closure inside it moves every number here. '
              '"Order now" assumes a restock takes ${report.leadDays} days, '
              'which is an assumption nobody has checked with the supplier '
              'yet. Suggested reorder levels are advice; nothing on this '
              'screen changes a setting.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
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
