import 'package:flutter/material.dart';

import '../../models/collection_queue.dart';
import '../../services/api_response.dart';
import '../../services/queue_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/money.dart';

/// What can be done about one outstanding due (FR-19 §3).
///
/// Four actions, in the order a real call goes: record what happened, record a
/// date they agreed, take the money, or give up on it. Write-off is last,
/// visually separated, and owner-only — it is the single irreversible action
/// in the queue.
///
/// Nothing here sends anything. The queue records that you made contact; it
/// does not make it. Messaging remains a separate, unstarted project.
Future<bool?> showCollectionActionSheet(
  BuildContext context, {
  required CollectionItem item,
  required bool isOwner,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CollectionActionSheet(item: item, isOwner: isOwner),
  );
}

class _CollectionActionSheet extends StatefulWidget {
  final CollectionItem item;
  final bool isOwner;

  const _CollectionActionSheet({required this.item, required this.isOwner});

  @override
  State<_CollectionActionSheet> createState() => _CollectionActionSheetState();
}

class _CollectionActionSheetState extends State<_CollectionActionSheet> {
  final _service = QueueService();
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                    Text(
                      item.member,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${money(item.amountInPaise)} outstanding'
                      '${item.phone.isEmpty ? '' : ' · ${item.phone}'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
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
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              _action(
                icon: Icons.phone_in_talk_rounded,
                colour: AppColors.info,
                title: 'Record a call',
                subtitle: 'Whether or not they picked up',
                onTap: _busy ? null : _recordCall,
              ),
              _action(
                icon: Icons.event_available_rounded,
                colour: AppColors.primary,
                title: 'They promised a date',
                subtitle: 'Moves it out of the chase list until then',
                onTap: _busy ? null : _recordPromise,
              ),
              _action(
                icon: Icons.payments_rounded,
                colour: AppColors.success,
                title: 'Collect the money',
                subtitle: 'Settles this due — no second entry is created',
                onTap: _busy ? null : _collect,
              ),

              if (widget.isOwner) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Divider(color: Colors.grey.shade300, height: 1),
                ),
                _action(
                  icon: Icons.money_off_rounded,
                  colour: AppColors.danger,
                  title: 'Write it off',
                  subtitle: 'The gym gives up on this money. Needs a reason.',
                  onTap: _busy ? null : _writeOff,
                ),
              ],

              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required Color colour,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) => ListTile(
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
    title: Text(
      title,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
    ),
  );

  static const _modes = {
    'cash': 'Cash',
    'upi': 'UPI',
    'debit_card': 'Debit card',
    'credit_card': 'Credit card',
    'bank_transfer': 'Bank transfer',
  };

  Future<void> _collect() async {
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('How did they pay ${money(widget.item.amountInPaise)}?'),
        children: [
          for (final e in _modes.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(e.value, style: const TextStyle(fontSize: 14)),
              ),
            ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    await _run(() => _service.settle(widget.item.paymentId, paymentMode: mode));
  }

  Future<void> _recordCall() async {
    final reached = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Did they answer?'),
        content: const Text(
          'A call that rang out is still worth recording — it moves this due '
          'out of "nobody has chased these" so the next person does not '
          'repeat it.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No answer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Spoke to them'),
          ),
        ],
      ),
    );
    if (reached == null || !mounted) return;

    final note = await _askText(
      title: reached ? 'What did they say?' : 'Anything to note?',
      hint: reached ? 'e.g. will pay on Friday' : 'optional',
    );
    if (!mounted) return;

    await _run(
      () => _service.recordContact(
        widget.item.paymentId,
        channel: 'call',
        reached: reached,
        note: note ?? '',
      ),
    );
  }

  Future<void> _recordPromise() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      // A promise in the past is either a typo or one already broken. The
      // server refuses it too.
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
      helpText: 'When did they say they would pay?',
    );
    if (date == null || !mounted) return;

    final note = await _askText(title: 'Anything to note?', hint: 'optional');
    if (!mounted) return;

    await _run(
      () => _service.recordPromise(
        widget.item.paymentId,
        date: date,
        note: note ?? '',
      ),
    );
  }

  Future<void> _writeOff() async {
    final reason = await _askText(
      title: 'Why write this off?',
      hint: 'e.g. member left the city',
      // Not optional. An unexplained write-off is indistinguishable from money
      // going missing, and the server rejects a blank one anyway.
      required: true,
    );
    if (reason == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write off this due?'),
        content: Text(
          '₹${widget.item.amountInPaise ~/ 100} from '
          '${widget.item.member} stops being money the gym is owed. '
          'This cannot be undone from here.',
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
            child: const Text('Write it off'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(() => _service.writeOff(widget.item.paymentId, reason: reason));
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    bool required = false,
  }) async {
    final controller = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(hintText: hint, errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (required && text.isEmpty) {
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
