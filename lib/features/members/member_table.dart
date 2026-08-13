import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_data_table.dart';

/// The members list as a table (FR-17).
///
/// With 809 members a card shows about six per screen and a row shows
/// twenty-five. Everything the desk does with this list is scanning — find a
/// name, check an expiry, see who has stopped coming — and scanning is what a
/// table is for and what a card is not.
///
/// Shown at ≥900px only; below that the cards remain, because a table on a
/// phone is a horizontal-scroll nightmare and the most common complaint about
/// gym software on mobile.
class MemberTable extends StatelessWidget {
  final List<Member> members;
  final void Function(Member) onTap;
  final void Function(Member) onCollectPayment;
  final void Function(Member) onRenew;

  final String sortKey;
  final bool sortAscending;
  final void Function(String) onSort;

  const MemberTable({
    super.key,
    required this.members,
    required this.onTap,
    required this.onCollectPayment,
    required this.onRenew,
    required this.sortKey,
    required this.sortAscending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return AppDataTable<Member>(
      rows: members,
      onRowTap: onTap,
      sortKey: sortKey,
      sortAscending: sortAscending,
      onSort: onSort,
      columns: [
        AppColumn(
          label: 'NAME',
          flex: 4,
          cell: (m) =>
              TableText('${m.firstName} ${m.lastName}'.trim(), bold: true),
        ),
        AppColumn(label: 'PHONE', flex: 3, cell: (m) => TableText(m.phone)),
        AppColumn(
          label: 'PLAN',
          flex: 3,
          cell: (m) => TableText(
            m.membershipPlanName ?? '—',
            color: m.membershipPlanName == null ? Colors.grey.shade400 : null,
          ),
        ),
        // Sortable: "who is expiring" is a question actually asked (FR-17 §4).
        AppColumn(
          label: 'EXPIRY',
          flex: 3,
          sortKey: 'expiry',
          cell: (m) => _ExpiryCell(expiry: m.expiryDate),
        ),
        AppColumn(
          label: 'STATUS',
          flex: 2,
          cell: (m) => _StatusCell(status: m.status),
        ),
        // The column nobody else's member list has. It is what turns a
        // directory into a retention tool: an owner scrolling a table where a
        // third of the rows say "6 weeks ago" has learned something no report
        // told them.
        AppColumn(
          label: 'LAST VISIT',
          flex: 3,
          sortKey: 'last_visit',
          cell: (m) => _LastVisitCell(lastVisit: m.lastVisitAt),
        ),
      ],
      actions: (m) => [
        _action(
          tooltip: 'Collect payment',
          icon: Icons.payments_rounded,
          colour: AppColors.success,
          onTap: () => onCollectPayment(m),
        ),
        _action(
          tooltip: 'Renew',
          icon: Icons.autorenew_rounded,
          colour: AppColors.primary,
          onTap: () => onRenew(m),
        ),
      ],
    );
  }

  // Inline, not behind a menu: hiding the action somebody performs forty times
  // a day behind an extra tap is a tax paid all day long (FR-17 §3).
  Widget _action({
    required String tooltip,
    required IconData icon,
    required Color colour,
    required VoidCallback onTap,
  }) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon, size: 18),
    color: colour,
    visualDensity: VisualDensity.compact,
    onPressed: onTap,
  );
}

/// Expiry with days-left colouring — the only colour on the row.
///
/// A table where four columns are tinted is a table nobody reads. The eye
/// should go to the rows needing action and nowhere else (FR-17 §5).
class _ExpiryCell extends StatelessWidget {
  final String? expiry;

  const _ExpiryCell({this.expiry});

  @override
  Widget build(BuildContext context) {
    final raw = expiry;
    if (raw == null || raw.isEmpty) {
      return TableText('—', color: Colors.grey.shade400);
    }
    final date = DateTime.tryParse(raw);
    if (date == null) return TableText('—', color: Colors.grey.shade400);

    final now = DateTime.now();
    final days = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;

    final (colour, suffix) = switch (days) {
      < 0 => (AppColors.danger, 'expired'),
      0 => (AppColors.danger, 'today'),
      <= 7 => (AppColors.warning, '${days}d left'),
      _ => (null, null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TableText(_short(date), bold: colour != null, color: colour),
        if (suffix != null)
          Text(
            suffix,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
      ],
    );
  }

  static String _short(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}

class _StatusCell extends StatelessWidget {
  final String status;

  const _StatusCell({required this.status});

  @override
  Widget build(BuildContext context) {
    final (colour, label) = switch (status) {
      'active' => (AppColors.success, 'Active'),
      'expired' => (AppColors.danger, 'Expired'),
      'frozen' => (AppColors.info, 'Frozen'),
      _ => (Colors.grey.shade500, status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: colour,
        ),
      ),
    );
  }
}

class _LastVisitCell extends StatelessWidget {
  final String? lastVisit;

  const _LastVisitCell({this.lastVisit});

  @override
  Widget build(BuildContext context) {
    final raw = lastVisit;
    if (raw == null || raw.isEmpty) {
      // "Never" is a real answer, and for somebody who joined yesterday it is
      // the expected one — so it is stated plainly rather than alarmed about.
      return TableText('Never', color: Colors.grey.shade400);
    }
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return TableText('—', color: Colors.grey.shade400);

    final days = DateTime.now().difference(date).inDays;
    final text = switch (days) {
      <= 0 => 'Today',
      1 => 'Yesterday',
      < 7 => '$days days ago',
      < 30 => '${(days / 7).floor()} weeks ago',
      _ => '${(days / 30).floor()} months ago',
    };

    // Only a month of silence earns emphasis. Anything shorter is ordinary
    // life and colouring it would make the column noise.
    return TableText(
      text,
      color: days >= 30 ? AppColors.danger : Colors.grey.shade700,
      bold: days >= 30,
    );
  }
}
