import 'package:flutter/material.dart';

import '../../models/renewal_due.dart';
import '../../models/renewal_queue.dart';
import '../../services/api_response.dart';
import '../../services/queue_service.dart';
import '../../theme/app_colors.dart';
import 'renew_dialog.dart';

/// What can be done about one expiring membership (FR-19 §4).
///
/// Two actions: take the renewal, or record that they are not coming back.
/// Confirming a lapse is owner-only and needs a reason, for the same reason a
/// write-off does — it removes somebody from the queue without money arriving.
///
/// Nothing here sends anything.
Future<bool?> showRenewalActionSheet(
  BuildContext context, {
  required RenewalItem item,
  required bool isOwner,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RenewalActionSheet(item: item, isOwner: isOwner),
  );
}

class _RenewalActionSheet extends StatefulWidget {
  final RenewalItem item;
  final bool isOwner;

  const _RenewalActionSheet({required this.item, required this.isOwner});

  @override
  State<_RenewalActionSheet> createState() => _RenewalActionSheetState();
}

class _RenewalActionSheetState extends State<_RenewalActionSheet> {
  final _service = QueueService();
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.member,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(_summary(),
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.danger)),
                  ),
                ),

              const SizedBox(height: 8),

              _action(
                icon: Icons.autorenew_rounded,
                colour: AppColors.success,
                title: 'Renew the membership',
                subtitle: item.owesMoney
                    // Said here rather than discovered at the till.
                    ? 'They still owe ${_rupees(item.owedInPaise)} separately'
                    : 'Opens the usual renewal form',
                onTap: _busy ? null : _renew,
              ),

              if (widget.isOwner) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Divider(color: Colors.grey.shade300, height: 1),
                ),
                _action(
                  icon: Icons.person_off_rounded,
                  colour: AppColors.danger,
                  title: 'They are not coming back',
                  subtitle:
                      'Takes them off this list and records why. Needs a reason.',
                  onTap: _busy ? null : _confirmLapse,
                ),
              ],

              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  String _summary() {
    final item = widget.item;
    final d = item.daysUntilExpiry;
    final when = d < 0
        ? 'Lapsed ${-d} days ago'
        : d == 0
            ? 'Expires today'
            : 'Expires in $d days';
    return [
      when,
      if (item.planName != null) item.planName!,
      if (item.phone.isNotEmpty) item.phone,
    ].join(' · ');
  }

  Widget _action({
    required IconData icon,
    required Color colour,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) =>
      ListTile(
        enabled: onTap != null,
        onTap: onTap,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 19, color: colour),
        ),
        title: Text(title,
            style:
                const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
      );

  /// Reuses the existing renewal dialog, so there is one path that records a
  /// renewal and one place its rules live.
  Future<void> _renew() async {
    final item = widget.item;
    final renewed = await showRenewDialog(
      context,
      renewal: RenewalDue(
        // RenewalDue.id is the member id — renew_dialog passes it straight
        // through as memberId.
        id: item.memberId,
        memberName: item.member,
        phone: item.phone,
        planId: item.planId,
        planName: item.planName,
        expiryDate: item.expiryDate?.toIso8601String().split('T').first,
        daysRemaining: item.daysUntilExpiry,
        status: item.hasLapsed ? 'expired' : 'active',
      ),
    );
    if (renewed == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _confirmLapse() async {
    final reason = await _askReason();
    if (reason == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as not returning?'),
        content: Text(
          '${widget.item.member} comes off the renewals list and is recorded '
          'as churned, with your reason on their timeline.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.confirmLapse(widget.item.memberId, reason: reason);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<String?> _askReason() async {
    final controller = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Why are they not returning?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. moved away, joined another gym',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  setDialogState(() => error = 'A reason is required');
                  return;
                }
                Navigator.pop(ctx, text);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
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
