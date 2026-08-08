import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../../models/member.dart';
import '../../services/api_response.dart';
import '../../services/invoice_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../lifecycle/lifecycle_shared.dart';
import 'billing_settings_screen.dart';
import 'invoice_detail_screen.dart';

/// Invoices and the discount rules behind them.
/// See docs/FR-04-invoicing-discounts.md in the backend repo.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  bool _changed = false;
  void _markChanged() => _changed = true;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Invoices'),
            actions: [
              IconButton(
                tooltip: 'Billing settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BillingSettingsScreen()),
                ),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Invoices'),
                Tab(text: 'Discounts'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _InvoicesTab(onChanged: _markChanged),
              _DiscountsTab(onChanged: _markChanged),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Invoices tab ────────────────────────────────────────────────────────────

class _InvoicesTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _InvoicesTab({required this.onChanged});

  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab> {
  final _service = InvoiceService();
  List<InvoiceSummary> _invoices = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

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
      final list = await _service.getInvoices(status: _filter.isEmpty ? null : _filter);
      if (!mounted) return;
      setState(() {
        _invoices = list;
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

  Future<void> _create() async {
    final memberId = await showDialog<int>(
      context: context,
      builder: (_) => const _PickMemberDialog(),
    );
    if (memberId == null) return;
    try {
      final draft = await _service.createDraft(memberId: memberId);
      if (!mounted) return;
      widget.onChanged();
      await _open(draft.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _open(int id) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id)),
    );
    if (changed == true) widget.onChanged();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New invoice'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                for (final f in const [('', 'All'), ('draft', 'Drafts'), ('issued', 'Issued'), ('cancelled', 'Cancelled')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      onSelected: (_) {
                        setState(() => _filter = f.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorBanner(message: _error!, onRetry: _load)
                    : _invoices.isEmpty
                        ? const EmptyStateView(
                            icon: Icons.receipt_long_rounded,
                            title: 'No invoices yet',
                            body: 'Create an invoice for a member — it stays a draft until you issue it.',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                              itemCount: _invoices.length,
                              separatorBuilder: (_, __) => AppSpacing.gapSm,
                              itemBuilder: (_, i) => _InvoiceCard(
                                invoice: _invoices[i],
                                onTap: () => _open(_invoices[i].id),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final InvoiceSummary invoice;
  final VoidCallback onTap;
  const _InvoiceCard({required this.invoice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          invoice.invoiceNumber ?? 'Draft',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: invoice.invoiceNumber == null
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${invoice.memberName}'
                    '${invoice.invoiceDate != null ? ' · ${invoice.invoiceDate!.substring(0, 10)}' : ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (invoice.dueInPaise > 0 && invoice.status == 'issued') ...[
                    const SizedBox(height: 2),
                    Text('Balance ${formatRupees(invoice.dueInPaise / 100)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger)),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatRupees(invoice.totalInRupees),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                StatusChip(status: invoice.displayState),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Discounts tab ───────────────────────────────────────────────────────────

class _DiscountsTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _DiscountsTab({required this.onChanged});

  @override
  State<_DiscountsTab> createState() => _DiscountsTabState();
}

class _DiscountsTabState extends State<_DiscountsTab> {
  final _service = InvoiceService();
  List<Discount> _discounts = [];
  bool _loading = true;
  String? _error;

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
      final list = await _service.getDiscounts();
      if (!mounted) return;
      setState(() {
        _discounts = list;
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

  Future<void> _create() async {
    final created = await showDialog<Discount>(
      context: context,
      builder: (_) => const _CreateDiscountDialog(),
    );
    if (created != null) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _toggle(Discount d) async {
    try {
      await _service.updateDiscount(d.id, isActive: !d.isActive);
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New discount'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorBanner(message: _error!, onRetry: _load)
              : _discounts.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.local_offer_outlined,
                      title: 'No discount codes',
                      body: 'Create reusable codes so a discounted price always has a reason attached.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: _discounts.length,
                        separatorBuilder: (_, __) => AppSpacing.gapSm,
                        itemBuilder: (_, i) => _DiscountCard(
                          discount: _discounts[i],
                          onToggle: () => _toggle(_discounts[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _DiscountCard extends StatelessWidget {
  final Discount discount;
  final VoidCallback onToggle;
  const _DiscountCard({required this.discount, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final usage = discount.maxUses != null
        ? '${discount.timesUsed}/${discount.maxUses} used'
        : '${discount.timesUsed} used';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(discount.code,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(width: 8),
                    Text(discount.valueLabel,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.success)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    discount.name,
                    usage,
                    if (discount.validUntil != null) 'until ${discount.validUntil!.substring(0, 10)}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: discount.isActive, onChanged: (_) => onToggle()),
        ],
      ),
    );
  }
}

class _CreateDiscountDialog extends StatefulWidget {
  const _CreateDiscountDialog();

  @override
  State<_CreateDiscountDialog> createState() => _CreateDiscountDialogState();
}

class _CreateDiscountDialogState extends State<_CreateDiscountDialog> {
  final _service = InvoiceService();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();
  final _maxUsesController = TextEditingController();

  String _type = 'percent';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _valueController.dispose();
    _maxUsesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final raw = double.tryParse(_valueController.text.trim()) ?? -1;

    if (code.isEmpty) {
      setState(() => _error = 'Code is required');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (raw <= 0) {
      setState(() => _error = 'Enter a value greater than 0');
      return;
    }
    if (_type == 'percent' && raw > 100) {
      setState(() => _error = 'A percentage cannot exceed 100');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Flat discounts are stored in paise; percentages as-is.
      final value = _type == 'flat' ? (raw * 100).roundToDouble() : raw;
      final d = await _service.createDiscount(
        code: code,
        name: name,
        discountType: _type,
        value: value,
        maxUses: int.tryParse(_maxUsesController.text.trim()),
      );
      if (!mounted) return;
      Navigator.pop(context, d);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: 'New discount',
      subtitle: 'A reusable code staff can apply to an invoice',
      icon: Icons.local_offer_outlined,
      accent: AppColors.success,
      error: _error,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(text: 'Create', loading: _saving, onPressed: _saving ? null : _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LifecycleFieldLabel('Code'),
          AppSpacing.gapXs,
          TextField(
            controller: _codeController,
            autofillHints: const [],
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'e.g. NEWYEAR25'),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Name'),
          AppSpacing.gapXs,
          TextField(
            controller: _nameController,
            autofillHints: const [],
            decoration: const InputDecoration(hintText: 'e.g. New Year 25% off'),
          ),
          AppSpacing.gapLg,

          const LifecycleFieldLabel('Type'),
          AppSpacing.gapXs,
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'percent', label: Text('Percent')),
              ButtonSegment(value: 'flat', label: Text('Flat ₹')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          AppSpacing.gapLg,

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LifecycleFieldLabel(_type == 'percent' ? 'Percentage' : 'Amount (₹)'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _valueController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                    const LifecycleFieldLabel('Max uses'),
                    AppSpacing.gapXs,
                    TextField(
                      controller: _maxUsesController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [],
                      decoration: const InputDecoration(hintText: 'unlimited'),
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

// ─── Member picker ───────────────────────────────────────────────────────────

class _PickMemberDialog extends StatefulWidget {
  const _PickMemberDialog();

  @override
  State<_PickMemberDialog> createState() => _PickMemberDialogState();
}

class _PickMemberDialogState extends State<_PickMemberDialog> {
  final _memberService = MemberService();
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Member> _results = [];
  bool _searching = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final all = await _memberService.searchMembers(q);
      if (!mounted) return;
      setState(() {
        _results = all.take(6).toList();
        _searching = false;
        _searched = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LifecycleDialogShell(
      title: 'Invoice which member?',
      subtitle: 'Search by name or phone',
      icon: Icons.person_search,
      accent: AppColors.primary,
      error: _error,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            autofillHints: const [],
            decoration: InputDecoration(
              hintText: 'Search…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
          AppSpacing.gapSm,
          if (!_searching && _searched && _results.isEmpty)
            const LifecycleNotice(
              tone: LifecycleTone.info,
              text: 'No matching member found. Add them from the Members screen first.',
            ),
          for (final m in _results) ...[
            InkWell(
              onTap: () => Navigator.pop(context, m.id),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text('${m.firstName} ${m.lastName}', style: const TextStyle(fontSize: 13.5)),
              ),
            ),
            AppSpacing.gapXs,
          ],
        ],
      ),
    );
  }
}
