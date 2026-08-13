import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chain_stock.dart';
import '../../services/chain_stock_service.dart';
import '../../theme/app_colors.dart';

/// Sending stock to another branch (FR-22).
///
/// The only write in the whole feature, and it is always a person confirming
/// a number. Nothing rebalances on its own: the system can see that one
/// branch is short and another is deep, but it cannot see the delivery cost,
/// who is driving, or that the manager already has a van going that way.
///
/// Returns true when something was actually sent.
Future<bool> showSendStockSheet(
  BuildContext context, {
  required ChainItem item,
  required BranchStock from,
  required List<BranchRef> branches,
  BranchStock? suggestedTo,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SendSheet(
      item: item,
      from: from,
      branches: branches,
      suggestedTo: suggestedTo,
    ),
  );
  return sent ?? false;
}

class _SendSheet extends StatefulWidget {
  final ChainItem item;
  final BranchStock from;
  final List<BranchRef> branches;
  final BranchStock? suggestedTo;

  const _SendSheet({
    required this.item,
    required this.from,
    required this.branches,
    this.suggestedTo,
  });

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  final _qty = TextEditingController();
  final _reason = TextEditingController();

  int? _toGymId;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _toGymId = widget.suggestedTo?.gymId;

    // Pre-filled with what would bring the short branch back to its own
    // reorder level, capped by what the sender can spare. A starting point
    // the reader can overwrite, not a decision — the field is editable and
    // the arithmetic behind it is printed underneath.
    final need = widget.suggestedTo == null
        ? 0
        : widget.suggestedTo!.reorderLevel - widget.suggestedTo!.stockQty;
    final suggested = need.clamp(0, widget.from.spare);
    if (suggested > 0) _qty.text = '$suggested';
  }

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Every branch except the one sending. A branch cannot send to itself and
  /// the server refuses it anyway; leaving it in the list would be offering a
  /// choice that always fails.
  List<BranchRef> get _destinations =>
      widget.branches.where((b) => b.gymId != widget.from.gymId).toList();

  Future<void> _send() async {
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (_toGymId == null) {
      setState(() => _error = 'Choose which branch this is going to.');
      return;
    }
    if (qty < 1) {
      setState(() => _error = 'Enter how many units to send.');
      return;
    }
    if (qty > widget.from.stockQty) {
      setState(
        () =>
            _error = '${widget.from.branch} only has ${widget.from.stockQty}.',
      );
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await ChainStockService().send(
        productId: widget.from.productId,
        toGymId: _toGymId!,
        quantity: qty,
        reason: _reason.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    final leftBehind = widget.from.stockQty - qty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Send ${widget.item.name}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'From ${widget.from.branch} · ${widget.from.stockQty} in stock, '
                '${widget.from.spare} to spare above its reorder level',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 18),

              Text(
                'To',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in _destinations)
                    ChoiceChip(
                      label: Text(b.name),
                      selected: _toGymId == b.gymId,
                      onSelected: _sending
                          ? null
                          : (_) => setState(() => _toGymId = b.gymId),
                    ),
                ],
              ),

              const SizedBox(height: 18),

              Text(
                'How many',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: _qty,
                enabled: !_sending,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: 'Units',
                  suffixText: 'of ${widget.from.stockQty}',
                ),
              ),

              // What the sending branch is left holding. The number that
              // decides whether this transfer is a good idea, and the one a
              // person sending stock away is least likely to work out.
              if (qty > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      leftBehind < widget.from.reorderLevel
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: leftBehind < widget.from.reorderLevel
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        leftBehind < 0
                            ? '${widget.from.branch} does not have that many'
                            : leftBehind < widget.from.reorderLevel
                            ? '${widget.from.branch} would drop to $leftBehind, '
                                  'below its own reorder level of '
                                  '${widget.from.reorderLevel}'
                            : '${widget.from.branch} keeps $leftBehind, still '
                                  'above its reorder level of '
                                  '${widget.from.reorderLevel}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: leftBehind < widget.from.reorderLevel
                              ? AppColors.warning
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              TextField(
                controller: _reason,
                enabled: !_sending,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Why (optional)',
                  hintText: 'Model Town nearly out',
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
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
              ],

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send'),
                ),
              ),

              const SizedBox(height: 10),
              Text(
                'This moves stock between branches. It is not a sale, and no '
                'invoice is raised.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
