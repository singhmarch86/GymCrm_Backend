import 'package:flutter/material.dart';

import '../../models/stock_queue.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

/// The low-stock queue (FR-19 §5).
///
/// The Stock tab next door is the catalogue — everything, searchable, with a
/// filter. This is the worklist: only what needs a decision, worst first, with
/// the action on the row.
///
/// Groups render even when empty. "0 out of stock" is the most useful sentence
/// this screen can say, and a heading that disappears at zero leaves the reader
/// unable to tell "nothing is wrong" from "it did not load".
class StockQueueView extends StatelessWidget {
  final StockQueue queue;
  final void Function(StockQueueItem) onRestock;

  const StockQueueView({
    super.key,
    required this.queue,
    required this.onRestock,
  });

  @override
  Widget build(BuildContext context) {
    if (queue.hasNoProducts) {
      return _centered(
        icon: Icons.inventory_2_outlined,
        colour: Colors.grey.shade400,
        title: 'No products yet',
        body: 'Add what the gym sells on the Stock tab and this queue starts '
            'watching it.',
      );
    }

    if (queue.isClear) {
      return _centered(
        icon: Icons.check_circle_outline_rounded,
        colour: AppColors.success,
        title: 'Everything is stocked',
        body: 'All ${queue.totalProducts} products are above their reorder '
            'level.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        _Headline(queue: queue),
        const SizedBox(height: 6),
        for (final g in queue.groups) ..._group(g),
        const SizedBox(height: 16),
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
                  'A product is listed when its stock reaches its reorder '
                  'level. If the wrong things keep appearing here, the reorder '
                  'level is wrong, not the product — change it on the Stock '
                  'tab.',
                  style: TextStyle(
                      fontSize: 11, height: 1.4, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _group(StockQueueGroup g) {
    if (g.items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 2),
          child: Row(
            children: [
              Icon(Icons.check_rounded, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text('${g.label} — none',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ];
    }

    final colour = _severityColour(g.severity);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: colour, shape: BoxShape.circle),
                ),
                const SizedBox(width: 9),
                Text(g.label,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: colour)),
                const SizedBox(width: 8),
                Text('${g.items.length}',
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Text(g.note,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Colors.grey.shade600)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      ...g.items.map((i) => _StockRow(
            item: i,
            colour: colour,
            onRestock: () => onRestock(i),
          )),
    ];
  }

  static Color _severityColour(String s) {
    switch (s) {
      case 'urgent':
        return AppColors.danger;
      case 'warn':
        return AppColors.warning;
    }
    return AppColors.primary;
  }

  static Widget _centered({
    required IconData icon,
    required Color colour,
    required String title,
    required String body,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 60, color: colour),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
}

class _Headline extends StatelessWidget {
  final StockQueue queue;

  const _Headline({required this.queue});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _figure(
            '${queue.totalOutOfStock}',
            'out of stock',
            queue.totalOutOfStock > 0 ? AppColors.danger : null,
          ),
          Container(width: 1, height: 30, color: Colors.grey.shade200),
          _figure(
            '${queue.totalFlagged}',
            'need restocking',
            queue.totalFlagged > 0 ? AppColors.warning : null,
          ),
          Container(width: 1, height: 30, color: Colors.grey.shade200),
          // The denominator. "2" alone means nothing; "2 of 11" is a fact.
          _figure('${queue.totalProducts}', 'products', null),
        ],
      ),
    );
  }

  Widget _figure(String value, String label, Color? colour) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colour ?? AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      );
}

class _StockRow extends StatelessWidget {
  final StockQueueItem item;
  final Color colour;
  final VoidCallback onRestock;

  const _StockRow({
    required this.item,
    required this.colour,
    required this.onRestock,
  });

  @override
  Widget build(BuildContext context) {
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
                      Text(item.name,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (item.category != null) item.category!,
                          '${item.stockQty} left · reorder at '
                              '${item.reorderLevel}',
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${item.stockQty}',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colour),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _context()),
                TextButton.icon(
                  onPressed: onRestock,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Restock'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The line that makes the number mean something.
  Widget _context() {
    final style = TextStyle(fontSize: 11.5, color: Colors.grey.shade600);

    if (item.daysOutOfStock != null) {
      return Text(
        'Empty for ${item.daysOutOfStock} '
        '${item.daysOutOfStock == 1 ? 'day' : 'days'}',
        style: style.copyWith(
            color: AppColors.danger, fontWeight: FontWeight.w600),
      );
    }

    final cover = item.daysOfCoverLeft;
    if (cover != null) {
      return Text(
        'Sold ${item.soldLast30} in 30 days · about $cover '
        '${cover == 1 ? 'day' : 'days'} left at that rate',
        style: style,
      );
    }

    // No sales is not a non-answer — it is the more interesting fact, and it
    // usually means the reorder level is wrong rather than the shelf.
    return Text(
      item.lastRestockedAt == null
          ? 'No sales recorded'
          : 'No sales in 30 days · last restocked '
              '${_date(item.lastRestockedAt!)}',
      style: style,
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';
}
