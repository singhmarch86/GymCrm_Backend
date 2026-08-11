import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One column of an [AppDataTable].
class AppColumn<T> {
  final String label;

  /// Relative width. The table divides available space by the total, so
  /// columns stay proportional at any window size instead of being pinned to
  /// pixel widths that only look right on one screen.
  final int flex;

  final Widget Function(T row) cell;
  final Alignment align;

  /// Non-null makes the header tappable. Only the columns somebody actually
  /// sorts by should set it (FR-17 §4) — every sortable header is a click
  /// target that can be hit by accident.
  final String? sortKey;

  const AppColumn({
    required this.label,
    required this.cell,
    this.flex = 2,
    this.align = Alignment.centerLeft,
    this.sortKey,
  });
}

/// A dense table for list screens (FR-17 §7).
///
/// Row height, type scale and padding live here and nowhere else. Five
/// hand-rolled tables drift within a month, and that drift is most of what
/// makes software look unfinished.
///
/// Deliberately not Flutter's DataTable: that widget sizes columns to their
/// content, so the layout shifts every time the page of data changes — a name
/// one character longer moves every column, and the eye has to re-find them.
class AppDataTable<T> extends StatelessWidget {
  final List<AppColumn<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;

  /// Trailing actions, rendered in a fixed-width column on the right so they
  /// line up down the page regardless of what the row contains.
  final List<Widget> Function(T row)? actions;
  final double actionsWidth;

  final String? sortKey;
  final bool sortAscending;
  final void Function(String key)? onSort;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.actions,
    this.actionsWidth = 132,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: rows.length,
            itemBuilder: (context, i) => _row(rows[i], i),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (final c in columns)
            Expanded(
              flex: c.flex,
              child: Align(
                alignment: c.align,
                child: c.sortKey == null
                    ? _headerLabel(c.label, false)
                    : InkWell(
                        onTap: onSort == null ? null : () => onSort!(c.sortKey!),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _headerLabel(c.label, sortKey == c.sortKey),
                            if (sortKey == c.sortKey)
                              Icon(
                                sortAscending
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 13,
                                color: AppColors.primary,
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          if (actions != null) SizedBox(width: actionsWidth),
        ],
      ),
    );
  }

  Widget _headerLabel(String text, bool active) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: active ? AppColors.primary : Colors.grey.shade600,
          ),
        ),
      );

  Widget _row(T row, int index) {
    return Material(
      // Zebra striping rather than a divider per row: at this density a line
      // between every pair of rows is more ink than the data.
      color: index.isEven ? Colors.white : const Color(0xFFFDFAF8),
      child: InkWell(
        onTap: onRowTap == null ? null : () => onRowTap!(row),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              for (final c in columns)
                Expanded(
                  flex: c.flex,
                  child: Align(
                    alignment: c.align,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: c.cell(row),
                    ),
                  ),
                ),
              if (actions != null)
                SizedBox(
                  width: actionsWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!(row),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain cell text at the table's type scale.
class TableText extends StatelessWidget {
  final String value;
  final bool bold;
  final Color? color;

  const TableText(this.value, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: color ?? AppColors.textPrimary,
        ),
      );
}
