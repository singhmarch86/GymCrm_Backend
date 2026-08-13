// Invoicing models. See docs/FR-04-invoicing-discounts.md in the backend repo.
//
// An invoice is a document, not money: `payments` remain the record of what
// actually arrived. `paymentState` here is computed server-side from the
// payments linked to the invoice — the app never derives it locally.

class InvoiceItem {
  final int id;
  final String description;
  final String itemType; // plan | pt_package | product | custom
  final int? referenceId;
  final int quantity;
  final int unitPriceInPaise;
  final double unitPriceInRupees;
  final int discountInPaise;
  final double taxRatePct;
  final String? sacCode;
  final int taxInPaise;
  final int lineTotalInPaise;
  final double lineTotalInRupees;

  InvoiceItem({
    required this.id,
    required this.description,
    required this.itemType,
    this.referenceId,
    required this.quantity,
    required this.unitPriceInPaise,
    required this.unitPriceInRupees,
    required this.discountInPaise,
    required this.taxRatePct,
    this.sacCode,
    required this.taxInPaise,
    required this.lineTotalInPaise,
    required this.lineTotalInRupees,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
    id: j['id'] ?? 0,
    description: j['description'] ?? '',
    itemType: j['item_type'] ?? 'custom',
    referenceId: j['reference_id'],
    quantity: j['quantity'] ?? 1,
    unitPriceInPaise: j['unit_price_in_paise'] ?? 0,
    unitPriceInRupees: (j['unit_price_in_rupees'] as num?)?.toDouble() ?? 0,
    discountInPaise: j['discount_in_paise'] ?? 0,
    taxRatePct: (j['tax_rate_pct'] as num?)?.toDouble() ?? 0,
    sacCode: j['sac_code'],
    taxInPaise: j['tax_in_paise'] ?? 0,
    lineTotalInPaise: j['line_total_in_paise'] ?? 0,
    lineTotalInRupees: (j['line_total_in_rupees'] as num?)?.toDouble() ?? 0,
  );
}

class Invoice {
  final int id;
  final int memberId;
  final String memberName;
  final String memberPhone;
  final String? invoiceNumber;
  final String? financialYear;
  final String status; // draft | issued | cancelled

  final String paymentState; // unpaid | partial | paid
  final int paidInPaise;
  final int dueInPaise;

  final String? invoiceDate;
  final String? dueDate;
  final String? placeOfSupply;
  final String? gstin;
  final bool pricesIncludeTax;

  final String? discountCode;
  final String? discountLabel;
  final String? discountReason;
  final int discountInPaise;

  final int subtotalInPaise;
  final int taxInPaise;
  final int totalInPaise;
  final double totalInRupees;
  final int cgstInPaise;
  final int sgstInPaise;

  final String? notes;
  final String? cancelledReason;
  final String createdAt;
  final List<InvoiceItem> items;

  Invoice({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.memberPhone,
    this.invoiceNumber,
    this.financialYear,
    required this.status,
    required this.paymentState,
    required this.paidInPaise,
    required this.dueInPaise,
    this.invoiceDate,
    this.dueDate,
    this.placeOfSupply,
    this.gstin,
    required this.pricesIncludeTax,
    this.discountCode,
    this.discountLabel,
    this.discountReason,
    required this.discountInPaise,
    required this.subtotalInPaise,
    required this.taxInPaise,
    required this.totalInPaise,
    required this.totalInRupees,
    required this.cgstInPaise,
    required this.sgstInPaise,
    this.notes,
    this.cancelledReason,
    required this.createdAt,
    required this.items,
  });

  bool get isDraft => status == 'draft';
  bool get isIssued => status == 'issued';
  bool get isCancelled => status == 'cancelled';

  /// What staff should see as the headline state: a cancelled document is
  /// cancelled, not "unpaid".
  String get displayState =>
      isCancelled ? 'cancelled' : (isDraft ? 'draft' : paymentState);

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
    id: j['id'] ?? 0,
    memberId: j['member_id'] ?? 0,
    memberName: j['member_name'] ?? '',
    memberPhone: j['member_phone'] ?? '',
    invoiceNumber: j['invoice_number'],
    financialYear: j['financial_year'],
    status: j['status'] ?? 'draft',
    paymentState: j['payment_state'] ?? 'unpaid',
    paidInPaise: j['paid_in_paise'] ?? 0,
    dueInPaise: j['due_in_paise'] ?? 0,
    invoiceDate: j['invoice_date'],
    dueDate: j['due_date'],
    placeOfSupply: j['place_of_supply'],
    gstin: j['gstin'],
    pricesIncludeTax: j['prices_include_tax'] ?? false,
    discountCode: j['discount_code'],
    discountLabel: j['discount_label'],
    discountReason: j['discount_reason'],
    discountInPaise: j['discount_in_paise'] ?? 0,
    subtotalInPaise: j['subtotal_in_paise'] ?? 0,
    taxInPaise: j['tax_in_paise'] ?? 0,
    totalInPaise: j['total_in_paise'] ?? 0,
    totalInRupees: (j['total_in_rupees'] as num?)?.toDouble() ?? 0,
    cgstInPaise: j['cgst_in_paise'] ?? 0,
    sgstInPaise: j['sgst_in_paise'] ?? 0,
    notes: j['notes'],
    cancelledReason: j['cancelled_reason'],
    createdAt: j['created_at'] ?? '',
    items: ((j['items'] as List?) ?? [])
        .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// List-view shape — no line items.
class InvoiceSummary {
  final int id;
  final int memberId;
  final String memberName;
  final String? invoiceNumber;
  final String status;
  final String paymentState;
  final String? invoiceDate;
  final String? dueDate;
  final int totalInPaise;
  final double totalInRupees;
  final int paidInPaise;
  final int dueInPaise;
  final String createdAt;

  InvoiceSummary({
    required this.id,
    required this.memberId,
    required this.memberName,
    this.invoiceNumber,
    required this.status,
    required this.paymentState,
    this.invoiceDate,
    this.dueDate,
    required this.totalInPaise,
    required this.totalInRupees,
    required this.paidInPaise,
    required this.dueInPaise,
    required this.createdAt,
  });

  String get displayState => status == 'cancelled'
      ? 'cancelled'
      : (status == 'draft' ? 'draft' : paymentState);

  factory InvoiceSummary.fromJson(Map<String, dynamic> j) => InvoiceSummary(
    id: j['id'] ?? 0,
    memberId: j['member_id'] ?? 0,
    memberName: j['member_name'] ?? '',
    invoiceNumber: j['invoice_number'],
    status: j['status'] ?? 'draft',
    paymentState: j['payment_state'] ?? 'unpaid',
    invoiceDate: j['invoice_date'],
    dueDate: j['due_date'],
    totalInPaise: j['total_in_paise'] ?? 0,
    totalInRupees: (j['total_in_rupees'] as num?)?.toDouble() ?? 0,
    paidInPaise: j['paid_in_paise'] ?? 0,
    dueInPaise: j['due_in_paise'] ?? 0,
    createdAt: j['created_at'] ?? '',
  );
}

class Discount {
  final int id;
  final String code;
  final String name;
  final String discountType; // percent | flat
  final double value;
  final String? validFrom;
  final String? validUntil;
  final int? maxUses;
  final int timesUsed;
  final bool isActive;
  final String createdAt;

  Discount({
    required this.id,
    required this.code,
    required this.name,
    required this.discountType,
    required this.value,
    this.validFrom,
    this.validUntil,
    this.maxUses,
    required this.timesUsed,
    required this.isActive,
    required this.createdAt,
  });

  bool get isPercent => discountType == 'percent';

  /// "25% off" or "₹500 off" — value is paise for flat discounts.
  String get valueLabel => isPercent
      ? '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}% off'
      : '₹${(value / 100).toStringAsFixed(0)} off';

  factory Discount.fromJson(Map<String, dynamic> j) => Discount(
    id: j['id'] ?? 0,
    code: j['code'] ?? '',
    name: j['name'] ?? '',
    discountType: j['discount_type'] ?? 'percent',
    value: (j['value'] as num?)?.toDouble() ?? 0,
    validFrom: j['valid_from'],
    validUntil: j['valid_until'],
    maxUses: j['max_uses'],
    timesUsed: j['times_used'] ?? 0,
    isActive: j['is_active'] ?? true,
    createdAt: j['created_at'] ?? '',
  );
}

class BillingSettings {
  final String invoicePrefix;
  final String? gstin;
  final double defaultTaxRate;
  final String? defaultSacCode;
  final bool pricesIncludeTax;
  final String? legalName;
  final String? addressLine;
  final String? stateName;

  BillingSettings({
    required this.invoicePrefix,
    this.gstin,
    required this.defaultTaxRate,
    this.defaultSacCode,
    required this.pricesIncludeTax,
    this.legalName,
    this.addressLine,
    this.stateName,
  });

  factory BillingSettings.fromJson(Map<String, dynamic> j) => BillingSettings(
    invoicePrefix: j['invoice_prefix'] ?? 'INV',
    gstin: j['gstin'],
    defaultTaxRate: (j['default_tax_rate'] as num?)?.toDouble() ?? 18,
    defaultSacCode: j['default_sac_code'],
    pricesIncludeTax: j['prices_include_tax'] ?? false,
    legalName: j['legal_name'],
    addressLine: j['address_line'],
    stateName: j['state_name'],
  );
}
