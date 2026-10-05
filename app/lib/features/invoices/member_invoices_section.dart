import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../../services/api_response.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/status_chip.dart';
import 'invoice_detail_screen.dart';
import 'quick_invoice.dart';
import '../../utils/money.dart';

/// A member's invoices, shown on their profile.
///
/// This is the general-purpose entry point: PT packages, renewals and payments
/// each raise invoices for their own specific sale, but a gym also bills for
/// one-off things (a joining fee, a locker, a replacement card). Raising an
/// invoice for a member has to be possible without first finding a sale to
/// hang it off.
class MemberInvoicesSection extends StatefulWidget {
  final int memberId;

  /// Bumping this from the parent forces a reload — used after an invoice is
  /// raised elsewhere in the panel.
  final int refreshToken;

  const MemberInvoicesSection({
    super.key,
    required this.memberId,
    this.refreshToken = 0,
  });

  @override
  State<MemberInvoicesSection> createState() => _MemberInvoicesSectionState();
}

class _MemberInvoicesSectionState extends State<MemberInvoicesSection> {
  List<InvoiceSummary> _invoices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MemberInvoicesSection old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await QuickInvoice.forMember(widget.memberId);
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

  Future<void> _raise() async {
    final created = await QuickInvoice.createAndOpen(
      context,
      memberId: widget.memberId,
      description: 'Gym charges',
      amountInPaise: 0, // staff set the amount on the draft
    );
    if (created) _load();
  }

  Future<void> _open(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Invoices',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: _raise,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New invoice'),
            ),
          ],
        ),
        AppSpacing.gapXs,

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_error != null)
          Text(
            _error!,
            style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
          )
        else if (_invoices.isEmpty)
          const Text(
            'No invoices for this member yet.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          )
        else
          for (final inv in _invoices) ...[
            InkWell(
              onTap: () => _open(inv.id),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        inv.invoiceNumber ?? 'Draft',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: inv.invoiceNumber == null
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      moneyR(inv.totalInRupees),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(status: inv.displayState),
                  ],
                ),
              ),
            ),
          ],
      ],
    );
  }
}
