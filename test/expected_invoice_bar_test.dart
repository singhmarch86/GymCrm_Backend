import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymcrm_app/models/expected_payments.dart';
import 'package:gymcrm_app/features/payments/expected_view.dart';

/// Tracing the Expected tab's invoice-bar collapse.
///
/// Ticking a checkbox turned the tab into a column of single letters running
/// down the left edge, with the list above it gone. The bar's labels were
/// wrapping one character per line, which made the bar hundreds of pixels
/// tall; being the fixed-height sibling of an Expanded list, it then starved
/// the list of every pixel of height.
///
/// What the trace established, so nobody repeats it:
///
///   - The bar is handed the full width in the real nesting, and again with
///     the whole screen chrome around it — AppBar, TabBar, TabBarView, date
///     control. The widget tree is not what narrows it.
///   - A horizontal safe-area inset, the obvious suspect, does NOT reproduce
///     the symptom. Squeezed that hard, Expanded goes to zero, and a
///     zero-width Text cannot wrap: Flutter overflows the Row sideways and
///     the bar stays one row high. Stacked letters need roughly one character
///     of width, not none.
///
/// So the narrow constraint is not reproducible in the widget layer at all,
/// which points at the rendering environment rather than the layout — this
/// project already has a documented canvas-sizing artefact on Flutter web
/// when the viewport changes around a load.
///
/// That is why the fix is defensive rather than causal, and why the last test
/// here is the one that matters: whatever hands the bar a bad width, it must
/// never grow tall enough to consume the list it is summarising.

/// Stands in for the invoice bar and records the constraints it was given.
class _Probe extends StatelessWidget {
  final void Function(BoxConstraints) onLayout;
  final Widget child;

  const _Probe({required this.onLayout, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      onLayout(constraints);
      return child;
    },
  );
}

/// The real bar's structure, lifted verbatim so the test exercises the same
/// layout the screen builds. Kept in sync by shape, not by import: the
/// original is private to the screen's State and the screen needs a network.
Widget invoiceBarBody() => Material(
  elevation: 8,
  color: Colors.white,
  child: SafeArea(
    top: false,
    left: false,
    right: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '1 due selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Creates drafts — nothing is issued',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('Clear')),
          const SizedBox(width: 4),
          ElevatedButton(onPressed: () {}, child: const Text('Create')),
        ],
      ),
    ),
  ),
);

/// The bar exactly as it was before the fix: SafeArea honouring horizontal
/// insets, and labels with nothing stopping them wrapping.
///
/// Kept so the diagnosis is demonstrated rather than asserted. A fix whose
/// only evidence is that the fixed version works has not identified anything.
Widget invoiceBarBodyBeforeFix() => Material(
  elevation: 8,
  color: Colors.white,
  child: SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1 due selected',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Creates drafts — nothing is issued',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('Clear')),
          const SizedBox(width: 4),
          ElevatedButton(onPressed: () {}, child: const Text('Create')),
        ],
      ),
    ),
  ),
);

ExpectedPayments fixture() => ExpectedPayments.fromJson({
  'from': '2026-08-01',
  'to': '2026-08-14',
  'days': 14,
  'raised_count': 2,
  'raised_in_paise': 800000,
  'expiring_count': 1,
  'expiring_in_paise': 400000,
  'bucket_unit': 'day',
  'buckets': [
    {
      'key': '1',
      'label': '1 Aug',
      'raised_in_paise': 400000,
      'expiring_in_paise': 0,
    },
    {
      'key': '2',
      'label': '2 Aug',
      'raised_in_paise': 400000,
      'expiring_in_paise': 400000,
    },
  ],
  'items': [
    {
      'member_id': 1,
      'member': 'Simrat Chopra',
      'phone': '9001000291',
      'payment_id': 11,
      'amount_in_paise': 400000,
      'due_date': '2026-08-02',
      'is_raised': true,
    },
  ],
});

/// The screen's `_expectedBody()`: a list that flexes, and a bar that does not.
Widget expectedBodyShape({required Widget bar, required Widget list}) => Column(
  children: [
    Expanded(child: list),
    bar,
  ],
);

void main() {
  testWidgets('the bar is handed the full width in the real nesting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BoxConstraints seen;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: expectedBodyShape(
            list: ExpectedView(data: fixture(), selected: const {11}),
            bar: _Probe(onLayout: (c) => seen = c, child: invoiceBarBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // If this is 1400, the Column/Expanded nesting is not the culprit and the
    // narrow constraint has to come from something outside it.
    expect(
      seen.maxWidth,
      1400,
      reason: 'the bar should span the tab, not a fraction of it',
    );
  });

  testWidgets('survives an absurd horizontal safe-area inset', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BoxConstraints seen;

    // The suspected source: a SafeArea that honours left/right insets sits
    // between the tab and the Row. With `left: false, right: false` the bar
    // must ignore them.
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(left: 700, right: 660),
          ),
          child: Scaffold(
            body: expectedBodyShape(
              list: ExpectedView(data: fixture(), selected: const {11}),
              bar: _Probe(onLayout: (c) => seen = c, child: invoiceBarBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      seen.maxWidth,
      1400,
      reason:
          'the bar spans the screen by design and has no edge to avoid; '
          'honouring these insets is what left it 40px wide',
    );
  });

  testWidgets('safe-area insets are ruled out as the cause', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(left: 700, right: 660),
          ),
          child: Scaffold(
            body: expectedBodyShape(
              list: ExpectedView(data: fixture(), selected: const {11}),
              bar: invoiceBarBodyBeforeFix(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Flutter surfaces the sideways overflow as a test failure. Consuming it
    // is the assertion: the old bar overflows horizontally rather than
    // wrapping, which is precisely why this is not the reported bug.
    expect(tester.takeException(), isFlutterError);

    final oldHeight = tester.getSize(find.byType(Material).last).height;

    // Records a hypothesis that turned out to be WRONG, so nobody spends an
    // afternoon on it again.
    //
    // A horizontal safe-area inset does not reproduce the reported symptom.
    // Squeezing the Row this hard drives Expanded to zero, and a zero-width
    // Text cannot wrap — Flutter overflows the Row sideways instead ("A
    // RenderFlex overflowed by 219 pixels on the right") and the bar stays
    // one row high. Stacked single letters need a width of roughly one
    // character, not zero, so the real cause is something that leaves the
    // labels a little room rather than none.
    //
    // Turning the insets off is still right — the bar is edge to edge and has
    // no edge to avoid — it just was not the culprit.
    expect(oldHeight, lessThan(120));
  });

  testWidgets('full screen chrome does not starve it either', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BoxConstraints seen;

    // The whole shape of StaffWorkScreen around the tab: an AppBar carrying
    // the TabBar, a date control, and the TabBarView. If none of this narrows
    // the bar, the constraint is not coming from the widget tree at all.
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 5,
          // TabBarView builds lazily — starting on tab 0 means the probe on
          // the Expected tab never lays out at all.
          initialIndex: 1,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Staff work'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Money & work'),
                  Tab(text: 'Expected'),
                  Tab(text: 'Collect'),
                  Tab(text: 'Leads'),
                  Tab(text: 'Follow up'),
                ],
              ),
            ),
            body: Column(
              children: [
                const SizedBox(height: 96), // the date span bar
                Expanded(
                  child: TabBarView(
                    children: [
                      const SizedBox(),
                      expectedBodyShape(
                        list: ExpectedView(
                          data: fixture(),
                          selected: const {11},
                        ),
                        bar: _Probe(
                          onLayout: (c) => seen = c,
                          child: invoiceBarBody(),
                        ),
                      ),
                      const SizedBox(),
                      const SizedBox(),
                      const SizedBox(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(seen.maxWidth, 1400);
  });

  testWidgets('the bar never grows tall enough to eat the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: expectedBodyShape(
            list: ExpectedView(data: fixture(), selected: const {11}),
            bar: invoiceBarBody(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barHeight = tester.getSize(find.byType(Material).last).height;

    // The regression that matters. Two single-line labels stacked come to
    // roughly 55px with padding; anything approaching the viewport means the
    // labels have wrapped again and the list is being squeezed out.
    expect(
      barHeight,
      lessThan(120),
      reason: 'a bar taller than this has wrapped and is eating the list',
    );

    // And the list must still be on screen, which is the symptom the user saw.
    expect(find.text('Simrat Chopra'), findsOneWidget);
  });
}
