import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../services/attendance_service.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            .where((m) =>
                m.firstName.toLowerCase().contains(q) ||
                m.lastName.toLowerCase().contains(q) ||
                m.phone.contains(q))
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
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${member.firstName} checked in ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      setState(() {
        _checkingIn = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                  ),
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
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
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
