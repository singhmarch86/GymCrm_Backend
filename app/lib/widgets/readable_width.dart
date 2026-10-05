import 'package:flutter/material.dart';

/// Caps how wide a column of cards is allowed to grow.
///
/// A queue row puts a name on the left and an amount on the right. On a phone
/// those sit close enough to read as one line. Stretched across a 2000px
/// monitor they end up a hand's width apart, and the eye has to travel the
/// whole screen to connect "Yuvika Sidhu" to "₹1.5k" — which is precisely the
/// failure that makes tables better than cards for scanning, reintroduced into
/// the cards.
///
/// So cards stay cards at every width, as the queue/ledger split intends, but
/// they stop growing at a width a person can still read across. Tables are
/// exempt: a table's columns are what carry the eye, and they genuinely want
/// the whole monitor.
///
/// 900 rather than a smaller number because these rows do carry real content —
/// a name, a status, a phone, a note — and squeezing them into a phone-width
/// column on a laptop wastes the screen in the other direction.
class ReadableWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ReadableWidth({super.key, required this.child, this.maxWidth = 900});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
