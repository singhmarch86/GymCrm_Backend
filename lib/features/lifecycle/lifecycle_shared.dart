import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';

/// Shared chrome for the four lifecycle dialogs.
///
/// These operations change a membership's status, expiry and money owed, so
/// every one of them follows the same shape: state what will happen, show the
/// consequence before the button, and never surface a number the server didn't
/// give us.

/// Common shell — header, scrollable body, error line, actions.
class LifecycleDialogShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool loading;
  final String? error;
  final Widget child;
  final List<Widget> actions;

  const LifecycleDialogShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.child,
    required this.actions,
    this.loading = false,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(title: title, subtitle: subtitle, icon: icon, accent: accent),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : child,
              ),
            ),
            if (error != null && error!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: LifecycleNotice(text: error!, tone: LifecycleTone.blocked),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  // By convention the last action is the primary AppButton,
                  // which forces width: double.infinity internally — safe
                  // standalone, but invalid as a plain Row child (Flutter
                  // gives non-flex children unbounded main-axis constraints,
                  // so an unwrapped AppButton here silently lays out at an
                  // effectively infinite width in release builds, pushing it
                  // off-canvas with no error, since assertions are stripped
                  // outside debug mode). Expanded gives it a real bound.
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    i == actions.length - 1 ? Expanded(child: actions[i]) : actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum LifecycleTone { info, warning, blocked, positive }

/// A single-line notice. Tone carries meaning: blocked means the operation
/// cannot proceed, warning means it is irreversible.
class LifecycleNotice extends StatelessWidget {
  final String text;
  final LifecycleTone tone;

  const LifecycleNotice({super.key, required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = switch (tone) {
      LifecycleTone.info => (AppColors.info, AppColors.infoLight, Icons.info_outline),
      LifecycleTone.warning => (AppColors.warning, AppColors.warningLight, Icons.warning_amber_rounded),
      LifecycleTone.blocked => (AppColors.danger, AppColors.dangerLight, Icons.block),
      LifecycleTone.positive => (AppColors.success, AppColors.successLight, Icons.check_circle_outline),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class LifecycleFieldLabel extends StatelessWidget {
  final String text;
  const LifecycleFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// The consequence block: what will actually happen if the button is pressed.
/// Placed immediately above the action so it can't be missed.
class LifecycleOutcome extends StatelessWidget {
  final List<(String, String)> rows;
  final Color? emphasisColor;

  const LifecycleOutcome({super.key, required this.rows, this.emphasisColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) AppSpacing.gapXs,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    rows[i].$1,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  rows[i].$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    // Last row is the headline figure — the amount or the date
                    // that matters most — so it carries the emphasis colour.
                    color: (i == rows.length - 1 && emphasisColor != null)
                        ? emphasisColor
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// dd MMM yyyy — unambiguous for Indian staff, who read 03/04 as either date.
String formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

/// Rupees with thousands separators, Indian grouping (1,23,456).
String formatRupees(double amount) {
  final whole = amount.floor();
  final paise = ((amount - whole) * 100).round();
  final s = whole.toString();

  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }

  return paise > 0
      ? '₹$grouped.${paise.toString().padLeft(2, '0')}'
      : '₹$grouped';
}
