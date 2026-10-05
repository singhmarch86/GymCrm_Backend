/// The counter prompt (FR-11).
///
/// One line of context for the front desk at the moment a member is standing
/// there. Most check-ins produce nothing at all — that is the design, not a
/// gap. A panel that always has something on it stops being read.
library;

class CounterPrompt {
  final String kind;
  final String text;

  /// Set only when the prompt was recorded as shown. This is what "mark
  /// handled" refers to, and it is absent on a lookup.
  final int? promptId;

  const CounterPrompt({
    required this.kind,
    required this.text,
    required this.promptId,
  });

  /// Returns null when there is nothing worth saying — the normal outcome.
  static CounterPrompt? fromResult(Map<String, dynamic> data) {
    final p = data['prompt'];
    if (p == null) return null;
    return CounterPrompt(
      kind: p['kind'] as String? ?? '',
      text: p['text'] as String? ?? '',
      promptId: data['prompt_id'] as int?,
    );
  }

  /// A short label so staff can see at a glance what kind of moment this is.
  String get label => switch (kind) {
    'first_visit' => 'First ever visit',
    'welcome_back' => 'Back after a break',
    'alert' => 'Needs attention',
    'pt_low' => 'PT running out',
    'restock' => 'Due a restock',
    'wallet_low' => 'Wallet low',
    _ => 'Note',
  };
}
