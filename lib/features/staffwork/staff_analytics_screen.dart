import 'package:flutter/material.dart';

import '../../models/date_span.dart';
import '../../models/staff_analytics.dart';
import '../../services/staff_work_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/date_span_bar.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/readable_width.dart';

/// Staff work analytics (FR-22).
///
/// The screen FR-13 §1 was written to guard against, so what it refuses to do
/// is as deliberate as what it shows:
///
///   * People appear in the order the server sent — by name. This screen never
///     sorts them, because a list ordered by output is a ranking whatever the
///     heading above it says.
///   * Each person is shown against their OWN previous period and nothing
///     else. There is no column comparing one person to another, because two
///     people on different shifts doing different jobs cannot be compared by
///     counting rows.
///   * A fall is grey, not red. The honest explanations — leave, a fortnight
///     on the desk instead of the phone, a quiet January — are invisible to
///     the query, and colouring a drop tells the owner something the data
///     cannot support.
///
/// What it is actually for sits above the people: is the desk busier than it
/// was, which ledgers carry the work, and did any day go unrecorded.
class StaffAnalyticsScreen extends StatefulWidget {
  /// Inherited from Staff work, so the reader keeps the window they chose
  /// rather than landing on a different period without noticing.
  final DateSpan span;

  const StaffAnalyticsScreen({super.key, required this.span});

  @override
  State<StaffAnalyticsScreen> createState() => _StaffAnalyticsScreenState();
}

class _StaffAnalyticsScreenState extends State<StaffAnalyticsScreen> {
  final _service = StaffWorkService();

  late DateSpan _span = widget.span;
  bool _loading = true;
  String? _error;
  StaffAnalytics? _data;

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
      final data = await _service.getAnalytics(span: _span);
      if (!mounted) return;
      setState(() {
        _data = data;
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
        title: const Text('How the work moved'),
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

    final d = _data;
    if (d == null) return const LoadingView();

    if (d.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'Nothing was recorded in this window.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      // Capped like every other card list: across a wide monitor a name and
      // its amount end up a hand's width apart, which is the scanning
      // problem tables solve reappearing inside the cards.
      child: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            _Totals(data: d),
            const SizedBox(height: 12),
            if (d.trend.length > 1) ...[
              _Rhythm(data: d),
              const SizedBox(height: 12),
            ],
            _Categories(data: d),
            const SizedBox(height: 12),
            _People(data: d, span: _span),
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  final StaffAnalytics data;

  const _Totals({required this.data});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              _figure('${data.totalCount}', 'things recorded'),
              Container(width: 1, height: 32, color: Colors.grey.shade200),
              _figure(_rupees(data.totalAmountInPaise), 'handled at the desk'),
              Container(width: 1, height: 32, color: Colors.grey.shade200),
              _figure('${data.quietDays}', 'days with nothing'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'across ${data.days} ${data.days == 1 ? 'day' : 'days'}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),

          // Said before any per-person number, because it decides how much
          // those numbers are worth. On this gym's data it has been the
          // majority of everything recorded.
          if (data.unattributedCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${data.unattributedPct}% of this was recorded with nobody '
                'signed in (${data.unattributedCount} things). The per-person '
                'figures below cover the rest, so treat them as part of the '
                'picture rather than all of it.',
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
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
        ),
      ],
    ),
  );
}

/// The gym's rhythm. About the gym, not about anybody in it.
class _Rhythm extends StatelessWidget {
  final StaffAnalytics data;

  const _Rhythm({required this.data});

  @override
  Widget build(BuildContext context) {
    final peak = data.peakCount;
    if (peak == 0) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.trendUnit == 'week' ? 'Week by week' : 'Day by day',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'Busiest was $peak in one ${data.trendUnit}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 78,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [for (final t in data.trend) _bar(t, peak)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(TrendPoint t, int peak) {
    final h = t.count / peak * 54;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: Tooltip(
        message:
            '${t.label}: ${t.count} recorded'
            '${t.amountInPaise == 0 ? '' : ' · ${_rupees(t.amountInPaise)}'}',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 7,
              // A quiet day keeps a visible hairline in a different colour
              // rather than disappearing. A day the gym recorded nothing is
              // the most interesting column on the chart.
              height: t.quiet ? 2 : (h < 2 ? 2 : h),
              decoration: BoxDecoration(
                color: t.quiet ? AppColors.danger : AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 11,
              child: Text(
                t.label.split(' ').first,
                style: TextStyle(fontSize: 8.5, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Categories extends StatelessWidget {
  final StaffAnalytics data;

  const _Categories({required this.data});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Where the work went',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final c in data.categories) ...[
            Row(
              children: [
                Expanded(
                  child: Text(c.label, style: const TextStyle(fontSize: 12.5)),
                ),
                Text(
                  '${c.count}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${c.sharePct}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
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

/// Each person against their own previous period. Never against each other.
class _People extends StatelessWidget {
  final StaffAnalytics data;
  final DateSpan span;

  const _People({required this.data, required this.span});

  @override
  Widget build(BuildContext context) {
    if (data.people.isEmpty) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Each person, against their own last period',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          // The heading says what the comparison is, so nobody reads the list
          // as a ranking. Order is the server's, by name, and is never changed
          // here.
          Text(
            'Listed by name. Compared with the ${data.days} '
            '${data.days == 1 ? 'day' : 'days'} before this window — not with '
            'each other.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          for (final p in data.people) ...[
            _PersonRow(person: p),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A change here is a question, not a verdict. Leave, a spell '
                  'on the front desk instead of the phone, or a quiet month '
                  'all look identical to this count.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: Colors.grey.shade600,
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

class _PersonRow extends StatelessWidget {
  final PersonTrend person;

  const _PersonRow({required this.person});

  @override
  Widget build(BuildContext context) {
    final change = person.changePct;

    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: const Icon(
            Icons.person_rounded,
            size: 15,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  if (person.role.isNotEmpty) person.role,
                  'was ${person.previousCount}',
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${person.count}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (change == null)
              Text(
                'first period',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              )
            else
              Text(
                '${change >= 0 ? '+' : ''}$change%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  // Up is quietly positive; down is grey, never red. A fall
                  // has a dozen honest explanations this screen cannot see.
                  color: change >= 0 ? AppColors.success : Colors.grey.shade600,
                ),
              ),
          ],
        ),
      ],
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
