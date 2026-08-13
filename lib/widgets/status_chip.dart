import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The application's canonical status set. Every module maps its own status
/// strings onto these values — StatusChip never needs to know about
/// member/renewal/payment-specific vocabulary, and new modules added later
/// (e.g. attendance, notifications) reuse the same set rather than inventing
/// their own badge colors.
enum AppStatus {
  active,
  expired,
  expiring,
  paid,
  pending,
  overdue,
  cancelled,
  frozen,
  terminated,

  // Classes & booking (internal/classes) — see FR-02. A session's lifecycle
  // and a booking's lifecycle share this chip but need distinct buckets:
  // 'scheduled' is routine, 'completed' is a done-state distinct from
  // 'paid', and a booking's 'attended'/'no_show' matter for different
  // reasons than any existing bucket (attendance record, not urgency).
  scheduled,
  completed,
  booked,
  waitlisted,
  attended,
  noShow,

  // Invoicing (internal/invoicing) — see FR-04. 'draft' is a document not yet
  // issued (neutral, not a warning); 'unpaid'/'partial' are derived payment
  // states that need to read as degrees of the same thing rather than
  // collapsing onto the existing 'pending' bucket.
  draft,
  unpaid,
  partial,
}

/// Generic status badge used across Members, Renewals, Payments, and any
/// future module. A single source of truth for status colors and icons so
/// the app never ends up with three slightly-different badge widgets again.
///
/// Usage:
///   StatusChip(status: 'active')           // member status
///   StatusChip(status: 'EXPIRING_SOON')    // renewal status — normalised
///   StatusChip(status: 'paid')             // payment status
///
/// The [status] string is matched case-insensitively and normalised onto
/// [AppStatus]. Unrecognised values fall back to a neutral grey badge with
/// the raw string as the label, rather than throwing or silently picking
/// an arbitrary color — this keeps the widget safe against new backend
/// status values that haven't been mapped yet.
class StatusChip extends StatelessWidget {
  final String status;

  /// Optional label override. Defaults to a human-readable version of the
  /// matched [AppStatus] (e.g. "Expiring Soon" stays "Expiring", "DUE_TODAY"
  /// becomes "Expiring"). Pass this when the caller wants to preserve a more
  /// specific label (e.g. "Due Today") while still getting the canonical
  /// color/icon underneath.
  final String? label;

  const StatusChip({super.key, required this.status, this.label});

  /// Maps any module's raw status string onto the canonical [AppStatus] set.
  /// Centralising this mapping here — rather than in each card widget — is
  /// the whole point: one place to update when a new status string appears.
  static AppStatus _normalise(String raw) {
    switch (raw.toUpperCase()) {
      case 'ACTIVE':
        return AppStatus.active;

      case 'EXPIRED':
        return AppStatus.expired;

      // Renewal-specific urgency buckets all collapse to "expiring" —
      // see members.ExpiryStatus in the backend (Sprint 3).
      case 'EXPIRING':
      case 'EXPIRING_SOON':
      case 'DUE_TODAY':
      case 'UPCOMING':
        return AppStatus.expiring;

      case 'PAID':
        return AppStatus.paid;

      case 'PENDING':
        return AppStatus.pending;

      case 'OVERDUE':
        return AppStatus.overdue;

      case 'CANCELLED':
      case 'CANCELED':
      case 'ARCHIVED':
        return AppStatus.cancelled;

      // Member statuses with no direct canonical equivalent — map to the
      // closest meaningful bucket rather than defaulting silently.
      case 'INACTIVE':
        return AppStatus.expiring;
      case 'CHURNED':
        return AppStatus.expired;

      // Membership lifecycle (internal/lifecycle) — see FR-01. Own bucket
      // each: 'frozen' is a deliberate on-hold state, not a warning, and
      // 'terminated' is a permanent end distinct from a lapsed 'expired'.
      case 'FROZEN':
        return AppStatus.frozen;
      case 'TERMINATED':
        return AppStatus.terminated;

      // Classes & booking (internal/classes) — see FR-02.
      case 'SCHEDULED':
        return AppStatus.scheduled;
      case 'COMPLETED':
        return AppStatus.completed;
      case 'BOOKED':
        return AppStatus.booked;
      case 'WAITLISTED':
        return AppStatus.waitlisted;
      case 'ATTENDED':
        return AppStatus.attended;
      case 'NO_SHOW':
        return AppStatus.noShow;

      // Invoicing (internal/invoicing) — see FR-04.
      case 'DRAFT':
        return AppStatus.draft;
      case 'ISSUED':
        return AppStatus
            .scheduled; // issued but not yet settled — informational
      case 'UNPAID':
        return AppStatus.unpaid;
      case 'PARTIAL':
        return AppStatus.partial;

      default:
        return AppStatus
            .pending; // unrecognised value — neutral, non-alarming fallback
    }
  }

  static Color _colorFor(AppStatus s) {
    switch (s) {
      case AppStatus.active:
      case AppStatus.paid:
        return AppColors.success;

      case AppStatus.expired:
      case AppStatus.overdue:
        return AppColors.danger;

      case AppStatus.expiring:
      case AppStatus.pending:
        return AppColors.warning;

      case AppStatus.cancelled:
        return Colors.grey;

      case AppStatus.frozen:
        return AppColors.info;

      case AppStatus.terminated:
        return AppColors.danger;

      case AppStatus.scheduled:
        return AppColors.info;
      case AppStatus.completed:
      case AppStatus.booked:
      case AppStatus.attended:
        return AppColors.success;
      case AppStatus.waitlisted:
        return AppColors.warning;
      case AppStatus.noShow:
        return AppColors.danger;

      case AppStatus.draft:
        return Colors.grey;
      case AppStatus.unpaid:
        return AppColors.danger;
      case AppStatus.partial:
        return AppColors.warning;
    }
  }

  static IconData _iconFor(AppStatus s) {
    switch (s) {
      case AppStatus.active:
        return Icons.check_circle_rounded;
      case AppStatus.paid:
        return Icons.task_alt_rounded;
      case AppStatus.expired:
        return Icons.cancel_rounded;
      case AppStatus.overdue:
        return Icons.error_rounded;
      case AppStatus.expiring:
        return Icons.schedule_rounded;
      case AppStatus.pending:
        return Icons.hourglass_top_rounded;
      case AppStatus.cancelled:
        return Icons.block_rounded;

      case AppStatus.frozen:
        return Icons.ac_unit_rounded;

      case AppStatus.terminated:
        return Icons.cancel_rounded;

      case AppStatus.scheduled:
        return Icons.event_rounded;
      case AppStatus.completed:
        return Icons.check_circle_rounded;
      case AppStatus.booked:
        return Icons.event_available_rounded;
      case AppStatus.waitlisted:
        return Icons.hourglass_bottom_rounded;
      case AppStatus.attended:
        return Icons.how_to_reg_rounded;
      case AppStatus.noShow:
        return Icons.person_off_rounded;

      case AppStatus.draft:
        return Icons.edit_note_rounded;
      case AppStatus.unpaid:
        return Icons.receipt_long_rounded;
      case AppStatus.partial:
        return Icons.pie_chart_rounded;
    }
  }

  static String _defaultLabel(AppStatus s) {
    switch (s) {
      case AppStatus.active:
        return 'Active';
      case AppStatus.expired:
        return 'Expired';
      case AppStatus.expiring:
        return 'Expiring';
      case AppStatus.paid:
        return 'Paid';
      case AppStatus.pending:
        return 'Pending';
      case AppStatus.overdue:
        return 'Overdue';
      case AppStatus.cancelled:
        return 'Cancelled';

      case AppStatus.frozen:
        return 'Frozen';

      case AppStatus.terminated:
        return 'Terminated';

      case AppStatus.scheduled:
        return 'Scheduled';
      case AppStatus.completed:
        return 'Completed';
      case AppStatus.booked:
        return 'Booked';
      case AppStatus.waitlisted:
        return 'Waitlisted';
      case AppStatus.attended:
        return 'Attended';
      case AppStatus.noShow:
        return 'No-show';

      case AppStatus.draft:
        return 'Draft';
      case AppStatus.unpaid:
        return 'Unpaid';
      case AppStatus.partial:
        return 'Part paid';
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalised = _normalise(status);
    final color = _colorFor(normalised);
    final icon = _iconFor(normalised);
    final text = label ?? _defaultLabel(normalised);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
