import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Shows the first few cards in a group, with everything else behind a tap.
///
/// The At Risk list is a worklist, and a worklist has to be *reachable*. With
/// 800 members the "never walked in" group alone ran to 125 cards, which
/// pushed the rhythm-break section — the most useful thing on the screen —
/// about forty thousand pixels down the page. Every section below the first
/// was effectively invisible.
///
/// Capping each group keeps every section within a screen or two of the top.
/// Nothing is hidden: the count is on the button, and one tap shows the rest.
class CollapsibleGroup extends StatefulWidget {
  final List<Widget> children;

  /// How many to show before collapsing. Five is enough to see the shape of a
  /// group and start working it without burying what comes next.
  final int visible;

  /// What the hidden rows are, for the button label — "more to call".
  final String noun;

  const CollapsibleGroup({
    super.key,
    required this.children,
    this.visible = 5,
    this.noun = 'more',
  });

  @override
  State<CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<CollapsibleGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.children.length;
    final hidden = total - widget.visible;

    if (hidden <= 0) {
      return Column(children: widget.children);
    }

    final shown =
        _expanded ? widget.children : widget.children.take(widget.visible).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...shown,
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
            ),
            label: Text(
              _expanded ? 'Show fewer' : 'Show $hidden ${widget.noun}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}
