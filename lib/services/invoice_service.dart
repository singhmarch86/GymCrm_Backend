import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/invoice.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Invoices, discounts and per-gym billing settings.
///
/// No money maths here: every total, tax split and payment state comes from
/// the server. The app displays what it is told — which is the only way the
/// document staff see can be guaranteed to match the one that was stored.
/// See docs/FR-04-invoicing-discounts.md in the backend repo.
class InvoiceService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  // ── Invoices ───────────────────────────────────────────────────────────────

  Future<List<InvoiceSummary>> getInvoices({String? status}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/invoices').replace(
      queryParameters: (status != null && status.isNotEmpty)
          ? {'status': status}
          : null,
    );
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => InvoiceSummary.fromJson(e)).toList();
  }

  Future<List<InvoiceSummary>> getMemberInvoices(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/invoices'),
        headers: headers,
      ),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => InvoiceSummary.fromJson(e)).toList();
  }

  Future<Invoice> getInvoice(int id) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/invoices/$id'),
        headers: headers,
      ),
    );
    return Invoice.fromJson(unwrapJson(response)['data']);
  }

  /// Opens a draft. Nothing is numbered until it's issued, so an abandoned
  /// draft costs nothing and can be deleted outright.
  Future<Invoice> createDraft({
    required int memberId,
    DateTime? dueDate,
    String notes = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/invoices'),
        headers: headers,
        body: jsonEncode({
          'member_id': memberId,
          if (dueDate != null) 'due_date': _ymd(dueDate),
          'notes': notes,
        }),
      ),
    );
    return Invoice.fromJson(unwrapJson(response)['data']);
  }

  Future<Invoice> addItem(
    int invoiceId, {
    required String description,
    required int unitPriceInPaise,
    int quantity = 1,
    int discountInPaise = 0,
    double? taxRatePct,
    String itemType = 'custom',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/invoices/$invoiceId/items'),
        headers: headers,
        body: jsonEncode({
          'description': description,
          'unit_price_in_paise': unitPriceInPaise,
          'quantity': quantity,
          'discount_in_paise': discountInPaise,
          if (taxRatePct != null) 'tax_rate_pct': taxRatePct,
          'item_type': itemType,
        }),
      ),
    );
    return Invoice.fromJson(unwrapJson(response)['data']);
  }

  /// Adds a line from the plan catalogue. The price is taken server-side from
  /// the plan, never sent by the app — so a stale cached price can't end up on
  /// a document.
  Future<Invoice> addPlanItem(
    int invoiceId, {
    required int planId,
    int quantity = 1,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/invoices/$invoiceId/plan-items'),
        headers: headers,
        body: jsonEncode({'plan_id': planId, 'quantity': quantity}),
      ),
    );
    return Invoice.fromJson(unwrapJson(response)['data']);
  }

  Future<Invoice> removeItem(int invoiceId, int itemId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.delete(
        Uri.parse('$kBaseUrl/api/v1/invoices/$invoiceId/items/$itemId'),
        headers: headers,
      ),
    );
    return Invoice.fromJson(unwrapJson(response)['data']);
  }

  /// Applies a coded discount, an ad-hoc amount (reason required), or clears
  /// the discount when both are omitted.
  Future<Invoice> applyDiscount(
    int invoiceId, {
    String? code,
    int? adHocInPaise,
    String reason = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/invoices/$invoiceId/discount'),
        headers: headers,
        body: jsonEncode({
          if (code != null && code.isNotEmpty) 'code': code,
          if (adHocInPaise != null && adHocInPaise > 0)
            'ad_hoc_in_paise': adHocInPaise,
          'reason': reason,
        }),
      ),
    );
    return Invoice.fromJson(unwrapJson(response)['data']);
  }

  /// Issues the draft: assigns its permanent number and freezes it.
  Future<Invoice> issue(int invoiceId, {DateTime? invoiceDate}) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/invoices/$invoiceId/issue'),
        headers: headers,
        body: jsonEncode({
          if (invoiceDate != null) 'invoice_date': _ymd(invoiceDate),
        }),
      ),
    );
    return Invoice.fromJson(unwrapJson(response)['data']);
  }

  /// Voids an issued invoice. The number is kept — an auditor should see a
  /// cancelled document, not a missing one.
  Future<Invoice> cancel(int invoiceId, {required String reason}) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/invoices/$invoiceId/cancel'),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ),
    );
    return Invoice.fromJson(unwrapJson(response)['data']);
  }

  Future<void> deleteDraft(int invoiceId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.delete(
        Uri.parse('$kBaseUrl/api/v1/invoices/$invoiceId'),
        headers: headers,
      ),
    );
    unwrapJson(response);
  }

  // ── Discounts ──────────────────────────────────────────────────────────────

  Future<List<Discount>> getDiscounts({bool activeOnly = false}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/discounts',
    ).replace(queryParameters: activeOnly ? {'active_only': 'true'} : null);
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Discount.fromJson(e)).toList();
  }

  Future<Discount> createDiscount({
    required String code,
    required String name,
    required String discountType,
    required double value,
    DateTime? validFrom,
    DateTime? validUntil,
    int? maxUses,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/discounts'),
        headers: headers,
        body: jsonEncode({
          'code': code,
          'name': name,
          'discount_type': discountType,
          'value': value,
          if (validFrom != null) 'valid_from': _ymd(validFrom),
          if (validUntil != null) 'valid_until': _ymd(validUntil),
          if (maxUses != null) 'max_uses': maxUses,
        }),
      ),
    );
    return Discount.fromJson(unwrapJson(response)['data']);
  }

  Future<Discount> updateDiscount(
    int id, {
    String? name,
    double? value,
    bool? isActive,
    int? maxUses,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.put(
        Uri.parse('$kBaseUrl/api/v1/discounts/$id'),
        headers: headers,
        body: jsonEncode({
          if (name != null) 'name': name,
          if (value != null) 'value': value,
          if (isActive != null) 'is_active': isActive,
          if (maxUses != null) 'max_uses': maxUses,
        }),
      ),
    );
    return Discount.fromJson(unwrapJson(response)['data']);
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<BillingSettings> getSettings() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/billing-settings'),
        headers: headers,
      ),
    );
    return BillingSettings.fromJson(unwrapJson(response)['data']);
  }

  Future<BillingSettings> updateSettings({
    String? invoicePrefix,
    String? gstin,
    double? defaultTaxRate,
    bool? pricesIncludeTax,
    String? legalName,
    String? addressLine,
    String? stateName,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.put(
        Uri.parse('$kBaseUrl/api/v1/billing-settings'),
        headers: headers,
        body: jsonEncode({
          if (invoicePrefix != null) 'invoice_prefix': invoicePrefix,
          if (gstin != null) 'gstin': gstin,
          if (defaultTaxRate != null) 'default_tax_rate': defaultTaxRate,
          if (pricesIncludeTax != null) 'prices_include_tax': pricesIncludeTax,
          if (legalName != null) 'legal_name': legalName,
          if (addressLine != null) 'address_line': addressLine,
          if (stateName != null) 'state_name': stateName,
        }),
      ),
    );
    return BillingSettings.fromJson(unwrapJson(response)['data']);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
