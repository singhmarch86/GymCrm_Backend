import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/collection_queue.dart';
import '../models/date_span.dart';
import '../models/expected_payments.dart';
import '../models/invoice_batch.dart';
import '../models/leakage.dart';
import '../models/renewal_queue.dart';
import '../models/stock_queue.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Work queues (FR-19) — what is still owed, as opposed to what happened.
///
/// Read-only. Every queue is resolved by acting through the module that owns
/// the thing: restocking goes through PosService.adjustStock, so the stock
/// ledger stays the single writer of stock levels (FR-07 §1). A queue that
/// wrote its own corrections would be a second source of truth.
class QueueService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<StockQueue> getStock() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/queues/stock'),
        headers: headers,
      ),
    );
    return StockQueue.fromJson(unwrapJson(response)['data']);
  }

  /// [from]/[to] filter by DUE DATE and are optional. Omitting them returns
  /// everything outstanding, which is the safe default: narrowing a debt list
  /// by date hides the oldest and worst of it.
  Future<CollectionQueue> getCollections({DateTime? from, DateTime? to}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/queues/collections').replace(
      queryParameters: (from == null || to == null)
          ? null
          : {'from': _ymd(from), 'to': _ymd(to)},
    );
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return CollectionQueue.fromJson(unwrapJson(response)['data']);
  }

  /// [windowDays] omitted uses the server default of 30. Widening it is how
  /// the long-lapsed tail stays reachable now that the expiry alerts are gone
  /// (FR-20 §3).
  Future<RenewalQueue> getRenewals({int? windowDays}) async {
    final headers = await _headers();
    final uri = Uri.parse('$kBaseUrl/api/v1/queues/renewals').replace(
      queryParameters: windowDays == null ? null : {'window': '$windowDays'},
    );
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return RenewalQueue.fromJson(unwrapJson(response)['data']);
  }

  /// What the gym has reason to expect over [span] (FR-19 §5).
  ///
  /// The one queue that takes a date range. Everything else in here is a list
  /// of what is owed now, and "now" does not move when a date control does;
  /// this asks about a window by definition.
  Future<ExpectedPayments> getExpected({DateSpan? span}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/queues/expected',
    ).replace(queryParameters: _spanParams(span));
    final response = await guardRequest(() => http.get(uri, headers: headers));
    return ExpectedPayments.fromJson(unwrapJson(response)['data']);
  }

  /// Value handed over and never billed (FR-21).
  ///
  /// Read-only, and deliberately so. Every finding here needs a human to
  /// decide what it was — goodwill, an unrecorded cash payment, or a real
  /// loss — and nothing on this screen charges anybody.
  Future<LeakageReport> getLeakage() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/queues/leakage'),
        headers: headers,
      ),
    );
    return LeakageReport.fromJson(unwrapJson(response)['data']);
  }

  /// Draft invoices for raised dues (FR-19 §6).
  ///
  /// Raised dues only. An expiring membership is a plan price nobody has
  /// agreed to pay, and it carries no payment id, so there is nothing to send
  /// — which is the point: the mistake is not expressible. To invoice a
  /// renewal, raise the due first and invoice that.
  ///
  /// Everything comes back as a draft. Issuing burns a permanent number and
  /// is a decision made one invoice at a time.
  Future<InvoiceBatch> invoiceDues({
    required List<int> paymentIds,
    String notes = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/queues/expected/invoice'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'payment_ids': paymentIds, 'notes': notes}),
      ),
    );
    return InvoiceBatch.fromJson(unwrapJson(response)['data']);
  }

  /// A single day still goes as `date`, matching StaffWorkService — the two
  /// sit under one date control and must ask the same question of the server.
  static Map<String, String> _spanParams(DateSpan? span) {
    if (span == null) return const {};
    if (span.isSingleDay) return {'date': span.fromParam};
    return {'from': span.fromParam, 'to': span.toParam};
  }

  /// Records that a member owes money.
  ///
  /// Deliberately not PaymentService.collectPayment, which only ever writes a
  /// *paid* row. This is the only way to enter a due that has not been paid.
  Future<int> raiseDue({
    required int memberId,
    required int amountInPaise,
    required DateTime dueDate,
    int? planId,
    String notes = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/payments/due'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'member_id': memberId,
          'amount_in_paise': amountInPaise,
          'due_date': _ymd(dueDate),
          if (planId != null) 'plan_id': planId,
          'notes': notes,
        }),
      ),
    );
    return unwrapJson(response)['data']?['id'] as int? ?? 0;
  }

  /// Records that a member did not come back.
  ///
  /// Owner only, and the server enforces it. Takes them out of the queue
  /// without money arriving, which is why it needs a reason — "churned, no
  /// reason given" is a row nobody can interpret six months later.
  Future<void> confirmLapse(int memberId, {required String reason}) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/confirm-lapse'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      ),
    );
    unwrapJson(response);
  }

  /// Records an attempt, reached or not.
  ///
  /// A call that rang out still counts — somebody tried, and the next person
  /// should not repeat it. Whether they got through is a separate field so the
  /// two never get conflated.
  Future<void> recordContact(
    int paymentId, {
    required String channel,
    required bool reached,
    String note = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/payments/$paymentId/contact'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'channel': channel,
          'reached': reached,
          'note': note,
        }),
      ),
    );
    unwrapJson(response);
  }

  Future<void> recordPromise(
    int paymentId, {
    required DateTime date,
    String note = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/payments/$paymentId/promise'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'date': _ymd(date), 'note': note}),
      ),
    );
    unwrapJson(response);
  }

  /// Settles a due that already exists.
  ///
  /// Deliberately not PaymentService.collectPayment, which creates a *new*
  /// payment: collecting through that would leave the original pending and
  /// record the same money twice, so the queue could never reach zero by
  /// actually being paid.
  Future<void> settle(
    int paymentId, {
    required String paymentMode,
    String reference = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/payments/$paymentId/settle'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'payment_mode': paymentMode,
          'reference_number': reference,
        }),
      ),
    );
    unwrapJson(response);
  }

  /// Owner only, and the server enforces it. The reason is required because
  /// the money stops being receivable, and an unexplained write-off is
  /// indistinguishable from money going missing.
  Future<void> writeOff(int paymentId, {required String reason}) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/payments/$paymentId/write-off'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      ),
    );
    unwrapJson(response);
  }

  /// Local date, never UTC — toIso8601String() would hand the server yesterday
  /// for anything before 05:30 IST.
  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
