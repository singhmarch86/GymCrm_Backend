import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/class_models.dart';
import '../../models/member.dart';
import '../../services/api_response.dart';
import '../../services/classes_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../lifecycle/lifecycle_shared.dart' show formatDate;

/// Session detail: roster, capacity, and every action a trainer or front-desk
/// member needs — book, cancel a booking (with waitlist promotion), mark
/// attendance, and cancel/complete the session itself.
///
/// Full-page route, not a dialog — this app's detail views always use
/// MaterialPageRoute rather than a side panel (see member_detail_screen.dart
/// for the Flutter desktop MouseTracker bug that rules out the alternative).
/// Returns true via Navigator.pop if anything changed, so the sessions list
/// can refresh its counts.
class SessionDetailScreen extends StatefulWidget {
  final int sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final _service = ClassesService();

  ClassSession? _session;
  List<Booking> _roster = [];
  bool _loading = true;
  String? _error;
  bool _changed = false;

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
      final results = await Future.wait([
        _service.getSession(widget.sessionId),
        _service.sessionBookings(widget.sessionId),
      ]);
      if (!mounted) return;
      setState(() {
        _session = results[0] as ClassSession;
        _roster = results[1] as List<Booking>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _snack(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: isError ? AppColors.danger : null,
    ));
  }

  Future<void> _bookMember() async {
    final member = await _pickMember(context, excludeMemberIds: _activeMemberIds);
    if (member == null) return;
    try {
      final result = await _service.book(widget.sessionId, member.id);
      _changed = true;
      final waitlisted = result.booking.status == 'waitlisted';
      _snack(waitlisted
          ? '${member.firstName} added to the waitlist (#${result.booking.waitlistPosition})'
          : '${member.firstName} booked');
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  Set<int> get _activeMemberIds => _roster
      .where((b) => b.status == 'booked' || b.status == 'waitlisted')
      .map((b) => b.memberId)
      .toSet();

  Future<void> _cancelBooking(Booking b) async {
    try {
      final result = await _service.cancelBooking(b.id);
      _changed = true;
      if (result.promoted != null) {
        _snack('${b.memberName} cancelled — ${result.promoted!.memberName} moved off the waitlist');
      } else {
        _snack('${b.memberName}\'s booking cancelled');
      }
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  Future<void> _markAttendance(Booking b, bool attended) async {
    try {
      await _service.markAttendance(b.id, attended: attended);
      _changed = true;
      _snack(attended ? '${b.memberName} marked attended' : '${b.memberName} marked no-show');
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  Future<void> _cancelSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this session?'),
        content: const Text(
          'Every active booking will be cancelled and the member notified list updated. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.cancelSession(widget.sessionId);
      _changed = true;
      _snack('Session cancelled');
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  Future<void> _completeSession() async {
    try {
      await _service.completeSession(widget.sessionId);
      _changed = true;
      _snack('Session marked completed');
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text(s?.classTypeName ?? 'Session')),
        body: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorBanner(message: _error!, onRetry: _load)
                : s == null
                    ? const SizedBox.shrink()
                    : _body(s),
      ),
    );
  }

  Widget _body(ClassSession s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SessionSummaryCard(session: s),
          AppSpacing.gapLg,

          if (s.status == 'scheduled') ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Book a member'),
                    onPressed: _bookMember,
                  ),
                ),
                AppSpacing.gapMd,
                OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Complete'),
                  onPressed: _completeSession,
                ),
                AppSpacing.gapMd,
                OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel session'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: _cancelSession,
                ),
              ],
            ),
            AppSpacing.gapXl,
          ],

          const Text('Roster', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          AppSpacing.gapMd,

          if (_roster.isEmpty)
            const EmptyStateView(
              icon: Icons.event_seat,
              title: 'No bookings yet',
              body: 'Book a member to fill this session.',
            )
          else
            for (final b in _roster) ...[
              _BookingRow(
                booking: b,
                sessionScheduled: s.status == 'scheduled',
                onCancel: () => _cancelBooking(b),
                onMarkAttendance: (attended) => _markAttendance(b, attended),
              ),
              AppSpacing.gapSm,
            ],
        ],
      ),
    );
  }
}

class _SessionSummaryCard extends StatelessWidget {
  final ClassSession session;

  const _SessionSummaryCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.classTypeName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              StatusChip(status: session.status),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            '${formatDate(session.sessionDate)} · ${session.startTime.substring(0, 5)} · '
            '${session.durationMinutes} min',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          if (session.trainerName != null) ...[
            AppSpacing.gapXs,
            Text('Trainer: ${session.trainerName}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
          AppSpacing.gapMd,
          Row(
            children: [
              Icon(
                session.isFull ? Icons.event_busy : Icons.event_available,
                size: 16,
                color: session.isFull ? AppColors.warning : AppColors.success,
              ),
              const SizedBox(width: 6),
              Text(
                '${session.bookedCount}/${session.capacity} booked',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (session.waitlistCount > 0) ...[
                const SizedBox(width: 12),
                const Icon(Icons.hourglass_bottom, size: 16, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  '${session.waitlistCount} waitlisted',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.warning),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  final Booking booking;
  final bool sessionScheduled;
  final VoidCallback onCancel;
  final void Function(bool attended) onMarkAttendance;

  const _BookingRow({
    required this.booking,
    required this.sessionScheduled,
    required this.onCancel,
    required this.onMarkAttendance,
  });

  bool get _isActive => booking.status == 'booked' || booking.status == 'waitlisted';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  booking.memberName,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                if (booking.status == 'waitlisted' && booking.waitlistPosition != null) ...[
                  const SizedBox(width: 8),
                  Text('#${booking.waitlistPosition}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          StatusChip(status: booking.status),
          const SizedBox(width: 8),

          if (_isActive && sessionScheduled) ...[
            if (booking.status == 'booked') ...[
              IconButton(
                tooltip: 'Mark attended',
                icon: const Icon(Icons.check_circle_outline, size: 20, color: AppColors.success),
                onPressed: () => onMarkAttendance(true),
              ),
              IconButton(
                tooltip: 'Mark no-show',
                icon: const Icon(Icons.person_off_outlined, size: 20, color: AppColors.danger),
                onPressed: () => onMarkAttendance(false),
              ),
            ],
            IconButton(
              tooltip: 'Cancel booking',
              icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
              onPressed: onCancel,
            ),
          ],
        ],
      ),
    );
  }
}

/// Reuses the same debounced-search pattern as transfer_dialog's member
/// picker. Kept local to this screen since booking is the only place classes
/// needs to search members.
Future<Member?> _pickMember(
  BuildContext context, {
  required Set<int> excludeMemberIds,
}) {
  return showDialog<Member>(
    context: context,
    builder: (_) => _MemberPickerDialog(excludeMemberIds: excludeMemberIds),
  );
}

class _MemberPickerDialog extends StatefulWidget {
  final Set<int> excludeMemberIds;
  const _MemberPickerDialog({required this.excludeMemberIds});

  @override
  State<_MemberPickerDialog> createState() => _MemberPickerDialogState();
}

class _MemberPickerDialogState extends State<_MemberPickerDialog> {
  final _memberService = MemberService();
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Member> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final all = await _memberService.searchMembers(q);
      if (!mounted) return;
      setState(() {
        _results = all.where((m) => !widget.excludeMemberIds.contains(m.id)).take(8).toList();
        _searching = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Book a member', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              AppSpacing.gapMd,
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
              AppSpacing.gapMd,
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in _results)
                      ListTile(
                        title: Text('${m.firstName} ${m.lastName}'),
                        subtitle: Text(m.status),
                        onTap: () => Navigator.pop(context, m),
                      ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
