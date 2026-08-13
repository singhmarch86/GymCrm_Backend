import 'dart:async';

import 'package:flutter/material.dart';

import '../features/lifecycle/lifecycle_shared.dart';
import '../models/member.dart';
import '../services/api_response.dart';
import '../services/member_service.dart';
import '../theme/app_colors.dart';
import 'app_spacing.dart';

/// Find a member by name or phone.
///
/// Extracted from four near-identical private copies (POS, referrals, class
/// sessions, and now raising a due). They differed only in wording and in
/// which members to leave out — everything else, including the 350ms debounce
/// and the two-character minimum, was duplicated.
///
/// Returns the chosen member, or null if the sheet was dismissed. Callers that
/// treat "no member" as a real answer — a walk-in sale, for instance — say so
/// in [emptyHint] rather than inventing a second return value.
Future<Member?> showMemberPicker(
  BuildContext context, {
  String title = 'Find a member',
  String subtitle = 'Search by name or phone',
  IconData icon = Icons.person_search,
  String emptyHint = 'No matching member.',

  /// Members already spoken for — the other side of a referral, people already
  /// booked into a session. Excluded from results rather than shown and then
  /// rejected on tap.
  Set<int> excludeIds = const {},
  String initialQuery = '',
  int maxResults = 6,
}) {
  return showDialog<Member>(
    context: context,
    builder: (_) => _MemberPicker(
      title: title,
      subtitle: subtitle,
      icon: icon,
      emptyHint: emptyHint,
      excludeIds: excludeIds,
      initialQuery: initialQuery,
      maxResults: maxResults,
    ),
  );
}

class _MemberPicker extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String emptyHint;
  final Set<int> excludeIds;
  final String initialQuery;
  final int maxResults;

  const _MemberPicker({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.emptyHint,
    required this.excludeIds,
    required this.initialQuery,
    required this.maxResults,
  });

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  final _service = MemberService();
  late final _controller = TextEditingController(text: widget.initialQuery);

  Timer? _debounce;
  List<Member> _results = [];
  bool _searching = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().length >= 2) {
      _search(widget.initialQuery.trim());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Two characters minimum, 350ms debounce. A single letter matches most of
  /// the gym and makes the list useless while costing a round trip per
  /// keystroke.
  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(q.trim()),
    );
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final all = await _service.searchMembers(q);
      if (!mounted) return;
      setState(() {
        _results = all
            .where((m) => !widget.excludeIds.contains(m.id))
            .take(widget.maxResults)
            .toList();
        _searching = false;
        _searched = true;
      });
    } on ApiException {
      // A failed search leaves the box usable rather than throwing a banner
      // over a dialog the reader can simply retype into.
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      accent: AppColors.primary,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            autofocus: true,
            autofillHints: const [],
            decoration: InputDecoration(
              hintText: 'Search by name or phone…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          AppSpacing.gapSm,
          if (!_searching && _searched && _results.isEmpty)
            LifecycleNotice(tone: LifecycleTone.info, text: widget.emptyHint),
          for (final m in _results) ...[
            InkWell(
              onTap: () => Navigator.pop(context, m),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '${m.firstName} ${m.lastName} · ${m.phone}',
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
            ),
            AppSpacing.gapXs,
          ],
        ],
      ),
    );
  }
}
