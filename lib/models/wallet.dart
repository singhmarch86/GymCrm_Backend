// Member wallet. See docs/FR-08-member-wallet.md in the backend repo.
//
// The balance is the running result of an insert-only ledger, so the app only
// ever displays what the server computed — it never adds up transactions
// locally, which would drift the moment anything else touched the wallet.

class WalletTransaction {
  final int id;
  final int amountInPaise;
  final int balanceAfter;
  final String transactionType; // topup | spend | refund | adjustment | expiry
  final String? reason;
  final String createdAt;

  WalletTransaction({
    required this.id,
    required this.amountInPaise,
    required this.balanceAfter,
    required this.transactionType,
    this.reason,
    required this.createdAt,
  });

  bool get isCredit => amountInPaise > 0;

  String get label => switch (transactionType) {
        'topup' => 'Top-up',
        'spend' => 'Spent',
        'refund' => 'Refund',
        'adjustment' => 'Correction',
        'expiry' => 'Expired',
        _ => transactionType,
      };

  factory WalletTransaction.fromJson(Map<String, dynamic> j) => WalletTransaction(
        id: j['id'] ?? 0,
        amountInPaise: j['amount_in_paise'] ?? 0,
        balanceAfter: j['balance_after'] ?? 0,
        transactionType: j['transaction_type'] ?? 'adjustment',
        reason: j['reason'],
        createdAt: j['created_at'] ?? '',
      );
}

class Wallet {
  final int memberId;
  final int balanceInPaise;
  final double balanceInRupees;
  final List<WalletTransaction> transactions;

  Wallet({
    required this.memberId,
    required this.balanceInPaise,
    required this.balanceInRupees,
    required this.transactions,
  });

  bool get hasCredit => balanceInPaise > 0;

  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        memberId: j['member_id'] ?? 0,
        balanceInPaise: j['balance_in_paise'] ?? 0,
        balanceInRupees: (j['balance_in_rupees'] as num?)?.toDouble() ?? 0,
        transactions: ((j['transactions'] as List?) ?? [])
            .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
