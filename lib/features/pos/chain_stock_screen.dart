import 'package:flutter/material.dart';

import '../../models/chain_stock.dart';
import '../../services/chain_stock_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/ledger_table.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/readable_width.dart';
import 'send_stock_sheet.dart';

/// Inventory across branches (FR-22).
///
/// Three tabs, because there are three different questions and they want
/// different shapes:
///
///   Move    — the queue. One card per item that could be rebalanced, each
///             with one decision and one button.
///   Stock   — the matrix. Every item against every branch; a table, because
///             the whole point is comparing a row across columns.
///   Sent    — the ledger. What moved, both directions; also a table.
///
/// Nothing on this screen moves stock by itself. The chain view reports the
/// imbalance and stops: which way the van drives depends on delivery cost,
/// footfall and who is free to drive, and none of that is in the database.
class ChainStockScreen extends StatefulWidget {
  const ChainStockScreen({super.key});

  @override
  State<ChainStockScreen> createState() => _ChainStockScreenState();
}

class _ChainStockScreenState extends State<ChainStockScreen>
    with SingleTickerProviderStateMixin {
  final _service = ChainStockService();

  late final TabController _tabs;

  bool _loading = true;
  String? _error;
  ChainStock? _chain;

  // The ledger, loaded on first visit. Most people open this screen to move
  // something, not to read history, and paying for both up front doubles the
  // wait for nothing.
  List<TransferRow>? _history;
  bool _historyLoading = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (_tabs.indexIsChanging) return;
        if (_tabs.index == 2 && _history == null) _loadHistory();
      });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getChain();
      if (!mounted) return;
      setState(() {
        _chain = data;
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

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final rows = await _service.history();
      if (!mounted) return;
      setState(() {
        _history = rows;
        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.toString();
        _historyLoading = false;
      });
    }
  }

  Future<void> _send(ChainItem item, BranchStock from, BranchStock? to) async {
    final chain = _chain;
    if (chain == null) return;

    final sent = await showSendStockSheet(
      context,
      item: item,
      from: from,
      branches: chain.branches,
      suggestedTo: to,
    );
    if (!sent || !mounted) return;

    // Both views are now stale — the levels moved and there is a new ledger
    // row. Dropping the history rather than refetching it: the tab may not be
    // open, and it reloads on next visit.
    setState(() => _history = null);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Stock moved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Across branches'),
        toolbarHeight: 48,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Move'),
            Tab(text: 'Stock'),
            Tab(text: 'Sent'),
          ],
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);

    final chain = _chain;
    if (chain == null) return const LoadingView();

    // A gym with one branch is the common case and must not look broken. It
    // gets a straight answer rather than an empty screen: there is nowhere to
    // move stock to, and that is a fact about the gym, not a failure.
    if (chain.isSingleBranch) {
      return ReadableWidth(
        child: EmptyStateView(
          icon: Icons.store_rounded,
          title: 'One branch',
          body:
              'Transfers need somewhere to send stock to. This view fills '
              'in once a second branch exists — until then the stock report '
              'covers everything this gym holds.',
        ),
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [_moveTab(chain), _stockTab(chain), _sentTab()],
    );
  }

  // ─── Move: the queue ────────────────────────────────────────────────────────

  Widget _moveTab(ChainStock chain) {
    final movable = chain.movable;

    return RefreshIndicator(
      onRefresh: _load,
      child: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            if (movable.isEmpty)
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 40,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Nothing worth moving',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No item is short at one branch while another has a '
                      'surplus of it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                child: Text(
                  movable.length == 1
                      ? '1 item could be rebalanced without buying anything'
                      : '${movable.length} items could be rebalanced without '
                            'buying anything',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ),
              ...movable.map((i) => _MovableCard(item: i, onSend: _send)),
            ],

            // Kept out of the queue above on purpose. These are short
            // everywhere, so no transfer fixes them — putting them in the same
            // list would send somebody hunting for stock the chain does not
            // have.
            if (chain.shortEverywhere.isNotEmpty) ...[
              const SizedBox(height: 20),
              _ShortEverywhereCard(names: chain.shortEverywhere),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Stock: the matrix ──────────────────────────────────────────────────────

  Widget _stockTab(ChainStock chain) {
    if (chain.items.isEmpty) {
      return const EmptyStateView(
        icon: Icons.inventory_2_outlined,
        title: 'No products',
        body: 'Nothing is stocked at any branch you can see.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      // Not capped. This is a matrix, and one column per branch needs the
      // width — the cap exists to stop a name and its figure drifting apart,
      // which is not what a table does.
      child: LedgerTable<ChainItem>(
        rows: chain.items,
        columns: [
          const LedgerColumn('Item', flex: 3),
          for (final b in chain.branches)
            LedgerColumn(b.name, flex: 2, numeric: true),
          const LedgerColumn('Total', flex: 1, numeric: true),
        ],
        cells: (item) => [
          _itemNameCell(item),
          for (final b in chain.branches) _qtyCell(item.at(b.gymId)),
          LedgerCell('${item.totalQty}', bold: true),
        ],
        card: (item) => _ItemCard(item: item, branches: chain.branches),
      ),
    );
  }

  Widget _itemNameCell(ChainItem item) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      LedgerCell(item.name, bold: true),
      // Only shown when it matters. An item matched by name might be two
      // branches labelling the same tub differently, and the fix is a SKU.
      if (item.matchedByName)
        Text(
          'matched by name',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
    ],
  );

  /// Null and zero are different facts. "—" means the branch does not carry
  /// the item at all; "0" means it carries it and has run out. Collapsing
  /// them would hide the second, which is the one somebody has to act on.
  Widget _qtyCell(BranchStock? b) {
    if (b == null) {
      return Text(
        '—',
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
      );
    }
    return LedgerCell(
      '${b.stockQty}',
      bold: b.isShort,
      colour: b.isShort
          ? AppColors.danger
          : b.isLong
          ? AppColors.warning
          : null,
    );
  }

  // ─── Sent: the ledger ───────────────────────────────────────────────────────

  Widget _sentTab() {
    if (_historyLoading) return const LoadingView();
    if (_historyError != null) {
      return ErrorBanner(message: _historyError!, onRetry: _loadHistory);
    }

    final rows = _history;
    if (rows == null) return const LoadingView();
    if (rows.isEmpty) {
      return const EmptyStateView(
        icon: Icons.swap_horiz_rounded,
        title: 'Nothing moved yet',
        body: 'Transfers into and out of this branch will be listed here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: LedgerTable<TransferRow>(
        rows: rows,
        columns: const [
          LedgerColumn('Item', flex: 3),
          LedgerColumn('Qty', flex: 1, numeric: true),
          LedgerColumn('From', flex: 2),
          LedgerColumn('To', flex: 2),
          LedgerColumn('By', flex: 2),
          LedgerColumn('When', flex: 2),
          LedgerColumn('Value', flex: 2, numeric: true),
        ],
        cells: (r) => [
          LedgerCell(r.product, bold: true),
          LedgerCell(
            r.isOutbound ? '−${r.quantity}' : '+${r.quantity}',
            bold: true,
            colour: r.isOutbound ? AppColors.warning : AppColors.success,
          ),
          LedgerCell(r.fromBranch),
          LedgerCell(r.toBranch),
          LedgerCell(r.by),
          LedgerCell(_date(r.at)),
          LedgerCell(_money(r.valueInPaise)),
        ],
        card: (r) => _TransferCard(row: r),
      ),
    );
  }
}

// ─── Cards ────────────────────────────────────────────────────────────────────

class _MovableCard extends StatelessWidget {
  final ChainItem item;
  final Future<void> Function(ChainItem, BranchStock, BranchStock?) onSend;

  const _MovableCard({required this.item, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final from = item.fullest;
    final to = item.emptiest;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${item.totalQty} in the chain',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),

            const SizedBox(height: 11),

            // Every branch, not just the two ends. An owner deciding where to
            // send from wants to see the whole picture, and the deepest
            // surplus is not always the sensible source.
            ...item.branches.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: b.isShort
                            ? AppColors.danger
                            : b.isLong
                            ? AppColors.warning
                            : Colors.grey.shade300,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        b.branch,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      '${b.stockQty}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: b.isShort ? AppColors.danger : null,
                      ),
                    ),
                    Text(
                      ' / ${b.reorderLevel}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),
            Text(
              'Stock shown against each branch\'s own reorder level.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
            ),

            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    from == null || to == null
                        ? ''
                        : '${from.branch} has ${from.spare} to spare · '
                              '${to.branch} is ${to.reorderLevel - to.stockQty} '
                              'under',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Disabled when the surplus is not at the branch the reader is
                // signed in to: you can only send stock you are standing next
                // to, and the server enforces it too.
                FilledButton.tonal(
                  onPressed: from == null ? null : () => onSend(item, from, to),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('Send', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortEverywhereCard extends StatelessWidget {
  final List<String> names;

  const _ShortEverywhereCard({required this.names});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                size: 16,
                color: AppColors.danger,
              ),
              const SizedBox(width: 9),
              Text(
                names.length == 1
                    ? '1 item is short everywhere'
                    : '${names.length} items are short everywhere',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'No transfer fixes these — every branch that carries them is at or '
            'below its reorder level. They need ordering in.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final n in names)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    n,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The narrow-screen rendering of one matrix row.
class _ItemCard extends StatelessWidget {
  final ChainItem item;
  final List<BranchRef> branches;

  const _ItemCard({required this.item, required this.branches});

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
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${item.totalQty}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...branches.map((ref) {
              final b = item.at(ref.gymId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ref.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Text(
                      b == null ? 'not stocked' : '${b.stockQty}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: b != null && b.isShort
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: b == null
                            ? Colors.grey.shade400
                            : b.isShort
                            ? AppColors.danger
                            : b.isLong
                            ? AppColors.warning
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final TransferRow row;

  const _TransferCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final colour = row.isOutbound ? AppColors.warning : AppColors.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.product,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  row.isOutbound ? '−${row.quantity}' : '+${row.quantity}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colour,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${row.fromBranch} → ${row.toBranch}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              '${_date(row.at)} · ${row.by} · ${_money(row.valueInPaise)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            if (row.reason != null && row.reason!.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                row.reason!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Formatting ───────────────────────────────────────────────────────────────

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Indian digit grouping: 1,500 then 1,50,000. Pairs above the last three,
/// not the western triples.
String _money(int paise) {
  final rupees = paise ~/ 100;
  final s = '$rupees';
  if (s.length <= 3) return '₹$s';

  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}
