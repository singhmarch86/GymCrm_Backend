import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/retention_alert.dart';
import '../../models/rhythm.dart';
import '../../services/api_response.dart';
import '../../services/retention_service.dart';
import '../../services/rhythm_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import 'rhythm_break_section.dart';

/// Members at risk of churning, grouped by severity.
///
/// This is a worklist, not a report: every row carries the action you would
/// actually take (copy the reminder, mark handled), because a list of problems
/// with nothing to do about them just becomes wallpaper.
class AtRiskScreen extends StatefulWidget {
  const AtRiskScreen({super.key});

  @override
  State<AtRiskScreen> createState() => _AtRiskScreenState();
}

class _AtRiskScreenState extends State<AtRiskScreen> {
  bool _loading = true;
  bool _scanning = false;
  String? _error;

  List<RetentionAlert> _alerts = [];
  RetentionSummary? _summary;
  List<StaffActivity> _staffActivity = [];
  List<RhythmBreak> _breaks = [];
  bool _dataChanged = false;

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
      // Both in one Future.wait so a failure in either is caught here rather
      // than surfacing later as an unhandled Future error.
      final results = await Future.wait<Object>([
        RetentionService().getAlerts(),
        RetentionService().getSummary(),
        RetentionService().getStaffActivity(days: 7),
        RhythmService().getBreaks(),
      ]);
      if (!mounted) return;
      setState(() {
        _alerts = results[0] as List<RetentionAlert>;
        _summary = results[1] as RetentionSummary;
        _staffActivity = results[2] as List<StaffActivity>;
        _breaks = results[3] as List<RhythmBreak>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : "Couldn't load at-risk members. Please try again.";
        _loading = false;
      });
    }
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      // One button runs both engines. Staff have no reason to know that
      // "who stopped coming" and "whose routine broke" are separate passes —
      // and a second button would just be a second thing to forget.
      final result = await RetentionService().scan();
      final rhythmResult = await RhythmService().scan();
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.summaryLine}\n${rhythmResult.summaryLine}'),
          backgroundColor: result.raised > 0 || rhythmResult.alertsRaised > 0
              ? AppColors.warning
              : AppColors.success,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : "Couldn't run the scan."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  /// Asks what was actually done before closing the alert.
  ///
  /// The note is optional and "Just mark done" is one tap away: forcing a note
  /// would only teach staff to type "." to clear the list, which is worse than
  /// no note because it looks like a record when it isn't.
  Future<void> _resolve(RetentionAlert a) async {
    final note = await _askActionNote(
      a.memberName,
      hint: 'e.g. Called — will renew Friday',
    );
    if (note == null || !mounted) return;

    try {
      await RetentionService().resolve(a.id, actionNote: note);
      _dataChanged = true;
      if (!mounted) return;
      // The staff tally just changed; refresh it in the background rather than
      // refetching the whole 70+ row list.
      _refreshStaffActivity();
      // Drop it locally so the row disappears immediately rather than after a
      // full refetch — the list can be 70+ rows.
      setState(() => _alerts.removeWhere((x) => x.id == a.id));
      final s = _summary;
      if (s != null) {
        setState(() {
          _summary = RetentionSummary(
            high: a.severity == 'high' ? s.high - 1 : s.high,
            medium: a.severity == 'medium' ? s.medium - 1 : s.medium,
            low: a.severity == 'low' ? s.low - 1 : s.low,
            total: s.total - 1,
            lastScanAt: s.lastScanAt,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : "Couldn't resolve that alert."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  /// Rhythm breaks resolve through the same endpoint, note and attribution as
  /// every other alert — there is only one queue and one way to close a row.
  Future<void> _resolveBreak(RhythmBreak b) async {
    final note = await _askActionNote(
      b.memberName,
      hint: 'e.g. Called — new work shift, moved to the 7pm slot',
    );
    if (note == null || !mounted) return;

    try {
      await RetentionService().resolve(b.alertId, actionNote: note);
      _dataChanged = true;
      if (!mounted) return;
      _refreshStaffActivity();
      setState(() {
        _breaks.removeWhere((x) => x.alertId == b.alertId);
        _alerts.removeWhere((x) => x.id == b.alertId);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              e is ApiException ? e.message : "Couldn't resolve that alert."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _copyBreak(RhythmBreak b) async {
    await Clipboard.setData(ClipboardData(text: b.message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Details for ${b.memberName} copied'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  /// Returns the note to record, or null if the staff member backed out.
  /// An empty string means "just mark done" — still a real resolution, just
  /// without detail.
  Future<String?> _askActionNote(String memberName, {required String hint}) async {
    final controller = TextEditingController();

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark handled — $memberName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What did you do? This is recorded against your name.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(hintText: hint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'bare'),
            child: const Text('Just mark done'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'note'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return null;
    return choice == 'note' ? controller.text : '';
  }

  Future<void> _refreshStaffActivity() async {
    try {
      final data = await RetentionService().getStaffActivity(days: 7);
      if (!mounted) return;
      setState(() => _staffActivity = data);
    } catch (_) {
      // Non-fatal — the tally is informational, not part of the workflow.
    }
  }

  Future<void> _copyMessage(RetentionAlert a) async {
    await Clipboard.setData(ClipboardData(text: a.message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message for ${a.memberName} copied'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dataChanged,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('At Risk'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _scanning ? null : _scan,
          icon: _scanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.radar_rounded),
          label: Text(_scanning ? 'Scanning...' : 'Run scan'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView(label: 'Checking who needs attention...');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);

    if (_alerts.isEmpty && _breaks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user_rounded, size: 72, color: AppColors.success),
              const SizedBox(height: 18),
              const Text('Nobody at risk',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                _summary?.lastScanAt == null
                    ? 'Run a scan to check for expiring memberships and members who have stopped coming in.'
                    : 'No open alerts. Run a scan again to re-check.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    // Rhythm breaks have their own section with the numbers behind them, so
    // they are excluded here — otherwise the same member appears twice.
    final counted =
        _alerts.where((a) => a.alertType != 'rhythm_break').toList();
    final high = counted.where((a) => a.severity == 'high').toList();
    final medium = counted.where((a) => a.severity == 'medium').toList();
    final low = counted.where((a) => a.severity == 'low').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _summaryBar(),
          _staffActivityPanel(),
          RhythmBreakSection(
            breaks: _breaks,
            onResolve: _resolveBreak,
            onCopy: _copyBreak,
          ),
          _section('Needs attention now', high, AppColors.danger,
              'Lapsed or lapsing today, and long absences'),
          _section('Worth a nudge', medium, AppColors.warning,
              'Drifting — a reminder now usually works'),
          _section('Keep an eye on', low, AppColors.info,
              'Early signals, no action strictly required yet'),
        ],
      ),
    );
  }

  Widget _summaryBar() {
    final s = _summary;
    if (s == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            _stat('${s.high}', 'High', AppColors.danger),
            _divider(),
            _stat('${s.medium}', 'Medium', AppColors.warning),
            _divider(),
            _stat('${s.low}', 'Low', AppColors.info),
            _divider(),
            _stat('${s.total}', 'Total', AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Who has actually been working the list this week.
  ///
  /// Hidden entirely when nobody has resolved anything — an empty
  /// "Handled this week" card would just be noise on a fresh install.
  Widget _staffActivityPanel() {
    if (_staffActivity.isEmpty) return const SizedBox.shrink();

    final total =
        _staffActivity.fold<int>(0, (sum, s) => sum + s.resolvedCount);
    if (total == 0) return const SizedBox.shrink();

    // People first, the automatic bucket last — it is context, not a competitor.
    final sorted = [..._staffActivity]..sort((a, b) {
        if (a.isSystem != b.isSystem) return a.isSystem ? 1 : -1;
        return b.resolvedCount.compareTo(a.resolvedCount);
      });

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_reg_rounded,
                    size: 17, color: AppColors.success),
                const SizedBox(width: 8),
                const Text('Handled this week',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                Text('$total total',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 12),
            ...sorted.map((s) => _staffRow(s, total)),
          ],
        ),
      ),
    );
  }

  Widget _staffRow(StaffActivity s, int total) {
    final share = total > 0 ? s.resolvedCount / total : 0.0;
    final color = s.isSystem ? Colors.grey.shade400 : AppColors.success;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                child: s.isSystem
                    ? Icon(Icons.settings_suggest_rounded,
                        size: 16, color: Colors.grey.shade400)
                    : CircleAvatar(
                        radius: 11,
                        backgroundColor:
                            AppColors.success.withValues(alpha: 0.15),
                        child: Text(
                          s.label[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: Text(
                  s.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: s.isSystem ? FontStyle.italic : FontStyle.normal,
                    color: s.isSystem ? Colors.grey.shade600 : null,
                    fontWeight: s.isSystem ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 26,
                child: Text('${s.resolvedCount}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ),

          // The members behind the number. A bare count is unverifiable; naming
          // who was contacted lets an owner spot-check the work at a glance.
          if (s.recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...s.recent.map(_handledLine),
                  // recent is capped server-side, so say so rather than
                  // implying the list is complete.
                  if (s.resolvedCount > s.recent.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '+${s.resolvedCount - s.recent.length} more',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _handledLine(HandledItem h) {
    final note = h.actionNote?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 6),
            child: Icon(Icons.check_rounded,
                size: 11, color: AppColors.success.withValues(alpha: 0.7)),
          ),
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                children: [
                  TextSpan(
                    text: h.memberName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '  ${h.typeLabel}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                  ),
                  if (note.isNotEmpty)
                    TextSpan(
                      text: '  · "$note"',
                      style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(h.relativeTime,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _divider() =>
      Container(width: 1, height: 34, color: Colors.grey.shade200);

  Widget _section(
      String title, List<RetentionAlert> items, Color color, String hint) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15, color: color)),
              const SizedBox(width: 8),
              Text('${items.length}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade500)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 10),
          child: Text(hint,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ),
        ...items.map((a) => _row(a, color)),
      ],
    );
  }

  Widget _row(RetentionAlert a, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    a.isExpiryRelated
                        ? Icons.event_busy_rounded
                        : Icons.directions_run_rounded,
                    size: 17,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.memberName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('${a.phone} · ${a.typeLabel}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy reminder message',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: AppColors.primary,
                  onPressed: () => _copyMessage(a),
                ),
                IconButton(
                  tooltip: 'Mark as handled',
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                  color: AppColors.success,
                  onPressed: () => _resolve(a),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // The pre-rendered message, shown so staff can read it before
            // sending rather than copying blind.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                a.message,
                style: TextStyle(
                    fontSize: 12, height: 1.45, color: Colors.grey.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
