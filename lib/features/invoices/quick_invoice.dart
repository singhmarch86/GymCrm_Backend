import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../../services/api_response.dart';
import '../../services/invoice_service.dart';
import 'invoice_detail_screen.dart';

/// Creating an invoice from wherever money actually happens.
///
/// The Invoices screen is not the only place a gym raises a bill — it happens
/// when a PT package is sold, a membership is renewed, a payment is taken. This
/// helper is the single path all of those use, so the flow (and the resulting
/// document) is identical no matter where staff started from.
///
/// It creates a *draft* with the line pre-filled and opens it. Nothing is
/// issued automatically: numbering a tax document stays an explicit decision
/// (FR-04 §2).
class QuickInvoice {
  /// Raises a draft invoice for [memberId] containing a single line, then opens
  /// the invoice detail screen so staff can adjust, discount, and issue it.
  ///
  /// Returns true if anything was created, so callers can refresh.
  static Future<bool> createAndOpen(
    BuildContext context, {
    required int memberId,
    required String description,
    required int amountInPaise,
    String itemType = 'custom',
    int? referenceId,
  }) async {
    final service = InvoiceService();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final draft = await service.createDraft(memberId: memberId);
      await service.addItem(
        draft.id,
        description: description,
        unitPriceInPaise: amountInPaise,
        itemType: itemType,
      );

      await navigator.push(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: draft.id),
        ),
      );
      return true;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
  }

  /// Raises a draft invoice for a plan the member is buying or renewing.
  ///
  /// Uses the plan-item endpoint rather than sending a price: the server reads
  /// the current catalogue price and snapshots it onto the line, so a stale
  /// price cached in the app can never end up on a tax document (FR-04 §3).
  static Future<bool> createForPlan(
    BuildContext context, {
    required int memberId,
    required int planId,
  }) async {
    final service = InvoiceService();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final draft = await service.createDraft(memberId: memberId);
      await service.addPlanItem(draft.id, planId: planId);
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: draft.id),
        ),
      );
      return true;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
  }

  /// A member's invoices, for the "Invoices" section on a member's profile.
  static Future<List<InvoiceSummary>> forMember(int memberId) =>
      InvoiceService().getMemberInvoices(memberId);
}
