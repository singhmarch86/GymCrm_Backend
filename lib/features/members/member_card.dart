import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_chip.dart';

class MemberCard extends StatelessWidget {
  final Member member;
  final VoidCallback? onTap;

  const MemberCard({super.key, required this.member, this.onTap});

  /// Canonical application-wide status color mapping — must stay identical
  /// to StatusChip's internal mapping (lib/widgets/status_chip.dart).
  Color getStatusColor() {
    switch (member.status.toLowerCase()) {
      case 'active':
        return AppColors.success;

      case 'expired':
        return AppColors.danger;

      default:
        return AppColors.warning;
    }
  }

  String formatDate(String? date) {
    if (date == null || date.isEmpty) {
      return "--";
    }

    try {
      final parsed = DateTime.parse(date);

      return "${parsed.day.toString().padLeft(2, '0')}/"
          "${parsed.month.toString().padLeft(2, '0')}/"
          "${parsed.year}";
    } catch (_) {
      return date;
    }
  }

  String expiryText() {
    if (member.expiryDate == null || member.expiryDate!.isEmpty) {
      return "--";
    }

    try {
      final expiry = DateTime.parse(member.expiryDate!);
      final now = DateTime.now();

      final diff = expiry.difference(now).inDays;

      if (diff > 1) {
        return "Expires in $diff days";
      }

      if (diff == 1) {
        return "Expires Tomorrow";
      }

      if (diff == 0) {
        return "Expires Today";
      }

      return "Expired ${diff.abs()} days ago";
    } catch (_) {
      return member.expiryDate!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  member.firstName.isNotEmpty
                      ? member.firstName[0].toUpperCase()
                      : "?",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: AppColors.primary,
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${member.firstName} ${member.lastName}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      member.phone,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),

              StatusChip(status: member.status),
            ],
          ),

          const SizedBox(height: 18),

          Divider(color: Colors.grey.shade200),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                size: 18,
                color: Colors.deepPurple,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  member.membershipPlanName != null
                      ? member.membershipPlanName!
                      : member.membershipPlanId != null
                      ? "Plan ID : ${member.membershipPlanId}"
                      : "No Plan Assigned",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: Colors.blue,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text("Started : ${formatDate(member.startDate)}"),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: getStatusColor()),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  expiryText(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: getStatusColor(),
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
