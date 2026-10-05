import 'package:flutter/material.dart';

import '../../models/counter_prompt.dart';
import '../../models/member.dart';
import '../../services/attendance_service.dart';
import '../../services/counter_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';

/// Shows a manual check-in dialog — search for a member, tap to check them in.
Future<bool?> showCheckInDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const CheckInDialog(),
  );
}

class CheckInDialog extends StatefulWidget {
  const CheckInDialog({super.key});

  @override
  State<CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<CheckInDialog> {
  final _searchController = TextEditingController();

  List<Member> _results = [];
  bool _searching = false;
  bool _checkingIn = false;
  String? _error;

  // Set only when the check-in produced something worth saying. Most
  // check-ins produce nothing and the dialog closes immediately, which is the
  // design (FR-11 §2) — a panel that always has something on it stops being
  // read within a week.
  CounterPrompt? _prompt;
  Member? _promptMember;
  bool _acting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _promptDialog(CounterPrompt p) {
    final name = _promptMember == null
        ? 'They'
        : '${_promptMember!.firstName} ${_promptMember!.lastName}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(
                      '$name checked in',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.gapLg,

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      p.text,
                      style: const TextStyle(fontSize: 14, height: 1.45),
                    ),
                  ],
                ),
              ),

              AppSpacing.gapSm,
              Text(
                'A note for you, not for them — say it however fits.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),

              AppSpacing.gapLg,
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _acting
                          ? null
                          : () => Navigator.pop(context, true),
                      child: const Text('Not now'),
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: FilledButton(
                      onPressed: _acting ? null : _markHandled,
                      child: _acting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Did it'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final all = await MemberService().getMembers();
      final q = query.toLowerCase();
      setState(() {
        _results = all
            .where(
              (m) =>
                  m.firstName.toLowerCase().contains(q) ||
                  m.lastName.toLowerCase().contains(q) ||
                  m.phone.contains(q),
            )
            .take(8)
            .toList();
        _searching = false;
      });
    } catch (_) {
      setState(() => _searching = false);
    }
  }

  Future<void> _checkIn(Member member) async {
    setState(() {
      _checkingIn = true;
      _error = null;
    });
    try {
      await AttendanceService().checkIn(member.id);

      // The check-in itself has already succeeded at this point. If fetching
      // the prompt fails, the member is still checked in — so this is caught
      // separately and swallowed rather than reported as a failed check-in.
      CounterPrompt? prompt;
      try {
        prompt = await CounterService().forCheckIn(member.id);
      } catch (_) {
        prompt = null;
      }
      if (!mounted) return;

      if (prompt == null) {
        // The common path stays exactly one tap.
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.firstName} checked in ✓'),
            backgroundColor: AppColors.success,
          ),
        );
        return;
      }

      setState(() {
        _checkingIn = false;
        _prompt = prompt;
        _promptMember = member;
      });
    } catch (e) {
      setState(() {
        _checkingIn = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Optional by design (FR-11 §5) — mandatory logging at a busy counter gets
  /// clicked through meaninglessly, which is worse than no data.
  Future<void> _markHandled() async {
    final p = _prompt;
    if (p?.promptId == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _acting = true);
    try {
      await CounterService().markActed(p!.promptId!);
    } catch (_) {
      // Not worth blocking the desk over — the prompt was still shown and the
      // member is still checked in.
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_prompt != null) return _promptDialog(_prompt!);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.how_to_reg_rounded,
                    color: AppColors.success,
                  ),
                  AppSpacing.hGapSm,
                  const Text(
                    'Manual Check-In',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              AppSpacing.gapLg,

              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              if (_error != null) ...[
                AppSpacing.gapSm,
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],

              AppSpacing.gapMd,

              if (_results.isNotEmpty)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: Colors.grey.shade100, height: 1),
                    itemBuilder: (_, i) {
                      final m = _results[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.1,
                          ),
                          child: Text(
                            m.firstName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          '${m.firstName} ${m.lastName}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(m.phone),
                        trailing: _checkingIn
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.check_circle_outline_rounded,
                                color: AppColors.success,
                              ),
                        onTap: _checkingIn ? null : () => _checkIn(m),
                      );
                    },
                  ),
                )
              else if (_searchController.text.isNotEmpty && !_searching)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No members found',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),

              AppSpacing.gapLg,

              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
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
