import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'readable_width.dart';

/// A ledger rendered as a table on wide screens and as cards on narrow ones.
///
/// The distinction this encodes is between a **ledger** and a **queue**, and
/// it is not cosmetic:
///
///   * A ledger is a record you scan and compare — payments, members,
///     attendance. Column alignment is what makes "which of these is biggest"
///     answerable at a glance, and cards cannot do that because the eye has no
///     shared baseline to run down.
///   * A queue is work to do — one row, one decision, one button. Its rows
///     carry a sentence ("Spoke to them 3 Aug · Rajeev — said next week") that
///     a column cannot hold without destroying the thing that makes the row
///     actionable.
///
/// So queues keep their cards at every width, and only ledgers get this.
///
/// Below [breakpoint] the table would mean either sideways scrolling or
/// four-point text, both worse than the cards. The desk uses this on a phone
/// far more often than on a laptop, so the narrow path is the default and the
/// table is the enhancement — not the other way round.
class LedgerTable<T> extends StatelessWidget {
  final List<T> rows;

  /// Column headers, in order. Must match the length of what [cells] returns.
  final List<LedgerColumn> columns;

  /// One row's cells, in the same order as [columns].
  final List<Widget> Function(T row) cells;

  /// The narrow-screen rendering. Whatever card the screen already had.
  final Widget Function(T row) card;

  final void Function(T row)? onTap;

  /// Matches the dashboard's existing 700px breakpoint rather than inventing a
  /// second one, so the app changes shape at one width instead of two.
  final double breakpoint;

  const LedgerTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.cells,
    required this.card,
    this.onTap,
    this.breakpoint = 700,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          // Only reachable below the breakpoint, so the cap rarely bites --
          // but a tablet in portrait sits just under it and stretches the
          // same way a monitor does.
          return ReadableWidth(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: rows.length,
              itemBuilder: (_, i) => card(rows[i]),
            ),
          );
        }
        return _table(context);
      },
    );
  }

  Widget _table(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header stays put while the body scrolls. A ledger long enough to
        // need a table is long enough that a header scrolling away leaves the
        // reader guessing which column they are looking at.
        _HeaderRow(columns: columns),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: rows.length,
            itemBuilder: (_, i) => _BodyRow(
              columns: columns,
              cells: cells(rows[i]),
              // Zebra striping, very faint. Across a wide row the eye loses
              // its place between the first and last column, and this is
              // cheaper than a divider for the reader to ignore when they do
              // not need it.
              tinted: i.isOdd,
              onTap: onTap == null ? null : () => onTap!(rows[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// One column: its heading, how much room it takes, and how it aligns.
/// Breathing room between columns.
///
/// Without it cells sit flush, and a right-aligned number against the next
/// column's left-aligned text renders as one word — "-24Sarabha Nagar". Only
/// bites when the content is wide enough to reach the boundary, which is why
/// it survived several tables before showing up.
const _cellGutter = EdgeInsets.symmetric(horizontal: 6);

class LedgerColumn {
  final String label;

  /// Flex within the row. Widths are proportional rather than fixed so the
  /// table fills a 900px laptop and a 1400px monitor equally well.
  final int flex;

  /// Money and counts read right-aligned, so digits line up by place value and
  /// a long number is visibly longer. Text reads left-aligned.
  final bool numeric;

  const LedgerColumn(this.label, {this.flex = 3, this.numeric = false});
}

class _HeaderRow extends StatelessWidget {
  final List<LedgerColumn> columns;

  const _HeaderRow({required this.columns});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          for (final c in columns)
            Expanded(
              flex: c.flex,
              child: Padding(
                padding: _cellGutter,
                child: Text(
                  c.label.toUpperCase(),
                  textAlign: c.numeric ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BodyRow extends StatelessWidget {
  final List<LedgerColumn> columns;
  final List<Widget> cells;
  final bool tinted;
  final VoidCallback? onTap;

  const _BodyRow({
    required this.columns,
    required this.cells,
    required this.tinted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tinted ? Colors.grey.shade50 : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                Expanded(
                  flex: columns[i].flex,
                  child: Padding(
                    padding: _cellGutter,
                    child: Align(
                      alignment: columns[i].numeric
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: i < cells.length ? cells[i] : const SizedBox(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ordinary cell: one line, clipped rather than wrapped.
///
/// Wrapping would make rows different heights, and a table whose rows jump
/// around is harder to scan than the cards it replaced.
class LedgerCell extends StatelessWidget {
  final String text;
  final bool bold;
  final Color? colour;
  final double size;

  const LedgerCell(
    this.text, {
    super.key,
    this.bold = false,
    this.colour,
    this.size = 13,
  });

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
      color: colour ?? AppColors.textPrimary,
    ),
  );
}

/// A status word, coloured. Same vocabulary as the cards use, so a reader
/// moving between widths is not learning two dialects.
class LedgerTag extends StatelessWidget {
  final String text;
  final Color colour;

  const LedgerTag(this.text, this.colour, {super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: colour,
        ),
      ),
    ),
  );
}
