import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../../services/api_response.dart';
import '../../services/invoice_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../lifecycle/lifecycle_shared.dart';

/// One invoice: its lines, totals and the actions available for its state.
///
/// A draft is editable. An issued invoice is not — the UI hides every editing
/// affordance rather than showing buttons the server will reject (FR-04 §2.1).
class InvoiceDetailScreen extends StatefulWidget {
  final int invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _service = InvoiceService();
  Invoice? _invoice;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inv = await _service.getInvoice(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _invoice = inv;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<Invoice> Function() action) async {
    setState(() => _busy = true);
    try {
      final inv = await action();
      if (!mounted) return;
      setState(() {
        _invoice = inv;
        _busy = false;
        _changed = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _addLine() async {
    final line = await showDialog<_NewLine>(
      context: context,
      builder: (_) => const _AddLineDialog(),
    );
    if (line == null) return;
    _run(
      () => _service.addItem(
        widget.invoiceId,
        description: line.description,
        unitPriceInPaise: line.unitPriceInPaise,
        quantity: line.quantity,
      ),
    );
  }

  Future<void> _applyDiscount() async {
    final result = await showDialog<_DiscountChoice>(
      context: context,
      builder: (_) => const _ApplyDiscountDialog(),
    );
    if (result == null) return;
    _run(
      () => _service.applyDiscount(
        widget.invoiceId,
        code: result.code,
        adHocInPaise: result.adHocInPaise,
        reason: result.reason,
      ),
    );
  }

  Future<void> _issue() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => LifecycleDialogShell(
        title: 'Issue this invoice?',
        subtitle: 'It gets a permanent number and cannot be edited afterwards',
        icon: Icons.receipt_long,
        accent: AppColors.primary,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          AppButton(
            text: 'Issue',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
        child: const LifecycleNotice(
          tone: LifecycleTone.warning,
          text:
              'Once issued, lines and prices are frozen. To correct a mistake later '
              'you cancel this invoice and issue a new one — both stay on record.',
        ),
      ),
    );
    if (confirmed == true) _run(() => _service.issue(widget.invoiceId));
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => LifecycleDialogShell(
        title: 'Cancel this invoice?',
        subtitle: _invoice?.invoiceNumber ?? '',
        icon: Icons.block,
        accent: AppColors.danger,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
          ),
          AppButton(
            text: 'Cancel invoice',
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LifecycleNotice(
              tone: LifecycleTone.warning,
              text:
                  'The invoice number is kept and never reused — a cancelled document '
                  'stays visible on the record. A reason is required.',
            ),
            AppSpacing.gapLg,
            const LifecycleFieldLabel('Reason'),
            AppSpacing.gapXs,
            TextField(
              controller: controller,
              autofillHints: const [],
              decoration: const InputDecoration(
                hintText: 'e.g. raised in error, wrong member',
              ),
            ),
          ],
        ),
      ),
    );
    if (reason != null) {
      _run(() => _service.cancel(widget.invoiceId, reason: reason));
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(inv?.invoiceNumber ?? 'Draft invoice'),
          actions: [
            if (inv != null && inv.isIssued)
              IconButton(
                tooltip: 'Cancel invoice',
                icon: const Icon(Icons.block),
                onPressed: _busy ? null : _cancel,
              ),
          ],
        ),
        body: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorBanner(message: _error!, onRetry: _load)
            : inv == null
            ? const SizedBox.shrink()
            : _body(inv),
        bottomNavigationBar: (inv != null && inv.isDraft)
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppButton(
                    text: 'Issue invoice',
                    loading: _busy,
                    onPressed: _busy || inv.items.isEmpty ? null : _issue,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _body(Invoice inv) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _headerCard(inv),
          AppSpacing.gapMd,

          if (inv.isCancelled && inv.cancelledReason != null) ...[
            LifecycleNotice(
              tone: LifecycleTone.blocked,
              text: 'Cancelled — ${inv.cancelledReason}',
            ),
            AppSpacing.gapMd,
          ],

          // A draft snapshots the gym's tax basis when it was created, so a
          // draft opened after the setting changed would otherwise be quietly
          // computing on the old basis. State it rather than surprise anyone.
          if (inv.isDraft) ...[
            LifecycleNotice(
              tone: LifecycleTone.info,
              text: inv.pricesIncludeTax
                  ? 'Prices include tax — the amounts you enter are what the member pays, '
                        'and GST is calculated out of them.'
                  : 'Tax is added on top — GST is added to the amounts you enter, so the '
                        'member pays more than the figure typed in.',
            ),
            AppSpacing.gapMd,
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Line items',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              if (inv.isDraft)
                TextButton.icon(
                  onPressed: _busy ? null : _addLine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
                ),
            ],
          ),
          AppSpacing.gapXs,

          if (inv.items.isEmpty)
            const LifecycleNotice(
              tone: LifecycleTone.info,
              text:
                  'No lines yet. An invoice needs at least one line before it can be issued.',
            ),
          for (final item in inv.items) ...[
            _lineCard(inv, item),
            AppSpacing.gapXs,
          ],

          AppSpacing.gapMd,
          _totalsCard(inv),

          if (inv.isDraft) ...[
            AppSpacing.gapMd,
            OutlinedButton.icon(
              onPressed: _busy ? null : _applyDiscount,
              icon: const Icon(Icons.local_offer_outlined, size: 18),
              label: Text(
                inv.discountInPaise > 0 ? 'Change discount' : 'Apply discount',
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _headerCard(Invoice inv) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  inv.memberName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              StatusChip(status: inv.displayState),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            [
              inv.memberPhone,
              if (inv.invoiceDate != null)
                'Issued ${inv.invoiceDate!.substring(0, 10)}',
              if (inv.dueDate != null) 'Due ${inv.dueDate!.substring(0, 10)}',
            ].join(' · '),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (inv.gstin != null) ...[
            AppSpacing.gapXs,
            Text(
              'GSTIN ${inv.gstin}${inv.placeOfSupply != null ? ' · ${inv.placeOfSupply}' : ''}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lineCard(Invoice inv, InvoiceItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} × ${formatRupees(item.unitPriceInRupees)} · GST ${item.taxRatePct.toStringAsFixed(0)}%'
                  '${item.sacCode != null ? ' · SAC ${item.sacCode}' : ''}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatRupees(item.lineTotalInRupees),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          if (inv.isDraft)
            IconButton(
              tooltip: 'Remove line',
              icon: const Icon(Icons.close, size: 16),
              onPressed: _busy
                  ? null
                  : () => _run(() => _service.removeItem(inv.id, item.id)),
            ),
        ],
      ),
    );
  }

  Widget _totalsCard(Invoice inv) {
    return LifecycleOutcome(
      emphasisColor: AppColors.primary,
      rows: [
        ('Subtotal', formatRupees(inv.subtotalInPaise / 100)),
        if (inv.discountInPaise > 0)
          (
            'Discount${inv.discountLabel != null ? ' — ${inv.discountLabel}' : ''}',
            '− ${formatRupees(inv.discountInPaise / 100)}',
          ),
        ('CGST', formatRupees(inv.cgstInPaise / 100)),
        ('SGST', formatRupees(inv.sgstInPaise / 100)),
        if (!inv.isDraft) ('Paid', formatRupees(inv.paidInPaise / 100)),
        if (!inv.isDraft && inv.dueInPaise > 0)
          ('Balance due', formatRupees(inv.dueInPaise / 100)),
        ('Total', formatRupees(inv.totalInRupees)),
      ],
    );
  }
}

// ─── Add line dialog ─────────────────────────────────────────────────────────

class _NewLine {
  final String description;
  final int unitPriceInPaise;
  final int quantity;
  _NewLine(this.description, this.unitPriceInPaise, this.quantity);
}

class _AddLineDialog extends StatefulWidget {
  const _AddLineDialog();

  @override
  State<_AddLineDialog> createState() => _AddLineDialogState();
}

class _AddLineDialogState extends State<_AddLineDialog> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _submit() {
    final desc = _descriptionController.text.trim();
    final rupees = double.tryParse(_amountController.text.trim()) ?? -1;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;

    if (desc.isEmpty) {
      setState(() => _error = 'Description is required');
      return;
    }
    if (rupees < 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (qty <= 0) {
      setState(() => _error = 'Quantity must be at least 1');
      return;
    }
    Navigator.pop(context, _NewLine(desc, (rupees * 100).round(), qty));
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: 'Add a line',
      subtitle: 'Tax is applied per line at the gym rate',
      icon: Icons.add_box_outlined,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(text: 'Add', onPressed: _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Description'),
          AppSpacing.gapXs,
          TextField(
            controller: _descriptionController,
            autofillHints: const [],
            decoration: const InputDecoration(
              hintText: 'e.g. Annual Membership — Gold',
            ),
          ),
          AppSpacing.gapLg,
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Unit price (₹)'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LifecycleFieldLabel('Qty'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _qtyController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Apply discount dialog ───────────────────────────────────────────────────

class _DiscountChoice {
  final String? code;
  final int? adHocInPaise;
  final String reason;
  _DiscountChoice({this.code, this.adHocInPaise, this.reason = ''});
}

enum _DiscountMode { coded, adHoc, none }

class _ApplyDiscountDialog extends StatefulWidget {
  const _ApplyDiscountDialog();

  @override
  State<_ApplyDiscountDialog> createState() => _ApplyDiscountDialogState();
}

class _ApplyDiscountDialogState extends State<_ApplyDiscountDialog> {
  final _service = InvoiceService();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  _DiscountMode _mode = _DiscountMode.coded;
  List<Discount> _discounts = [];
  String? _selectedCode;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _service.getDiscounts(activeOnly: true);
      if (!mounted) return;
      setState(() {
        _discounts = list;
        _selectedCode = list.isNotEmpty ? list.first.code : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _submit() {
    switch (_mode) {
      case _DiscountMode.coded:
        if (_selectedCode == null) {
          setState(() => _error = 'Select a discount');
          return;
        }
        Navigator.pop(context, _DiscountChoice(code: _selectedCode));
      case _DiscountMode.adHoc:
        final rupees = double.tryParse(_amountController.text.trim()) ?? 0;
        final reason = _reasonController.text.trim();
        if (rupees <= 0) {
          setState(() => _error = 'Enter an amount greater than 0');
          return;
        }
        if (reason.isEmpty) {
          setState(
            () => _error = 'A reason is required for an off-the-books discount',
          );
          return;
        }
        Navigator.pop(
          context,
          _DiscountChoice(adHocInPaise: (rupees * 100).round(), reason: reason),
        );
      case _DiscountMode.none:
        Navigator.pop(context, _DiscountChoice());
    }
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: 'Apply a discount',
      subtitle: 'Recorded on the invoice, with its reason',
      icon: Icons.local_offer_outlined,
      accent: AppColors.success,
      loading: _loading,
      error: _error,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(text: 'Apply', onPressed: _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_DiscountMode>(
            segments: const [
              ButtonSegment(value: _DiscountMode.coded, label: Text('Code')),
              ButtonSegment(value: _DiscountMode.adHoc, label: Text('One-off')),
              ButtonSegment(value: _DiscountMode.none, label: Text('None')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _error = null;
            }),
          ),
          AppSpacing.gapLg,

          if (_mode == _DiscountMode.coded) ...[
            if (_discounts.isEmpty)
              const LifecycleNotice(
                tone: LifecycleTone.info,
                text:
                    'No active discount codes yet. Create one from the Discounts tab, '
                    'or use a one-off amount.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedCode,
                isExpanded: true,
                items: _discounts
                    .map(
                      (d) => DropdownMenuItem(
                        value: d.code,
                        child: Text(
                          '${d.code} — ${d.name} (${d.valueLabel})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCode = v),
              ),
          ] else if (_mode == _DiscountMode.adHoc) ...[
            const LifecycleFieldLabel('Amount (₹)'),
            AppSpacing.gapXs,
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofillHints: const [],
            ),
            AppSpacing.gapLg,
            const LifecycleFieldLabel('Reason'),
            AppSpacing.gapXs,
            TextField(
              controller: _reasonController,
              autofillHints: const [],
              decoration: const InputDecoration(
                hintText: 'e.g. matched competitor quote',
              ),
            ),
            AppSpacing.gapSm,
            const LifecycleNotice(
              tone: LifecycleTone.info,
              text:
                  'One-off discounts always need a reason, so the price can be explained later.',
            ),
          ] else
            const LifecycleNotice(
              tone: LifecycleTone.info,
              text: 'Removes any discount currently on this invoice.',
            ),
        ],
      ),
    );
  }
}
