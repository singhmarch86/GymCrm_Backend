/// AiInsight — a generated business insight shown on the dashboard.
/// No AI integration yet — architecture and service placeholders only.
/// Full implementation when AI/ML backend is available.
class AiInsight {
  final int id;
  final String category; // churn | revenue | attendance | plan | renewal
  final String severity; // info | warning | critical
  final String message; // e.g. "12 members inactive for 14 days"
  final String? action; // suggested action label
  final String? actionRoute; // route to navigate to on tap
  final String generatedAt;

  AiInsight({
    required this.id,
    required this.category,
    required this.severity,
    required this.message,
    this.action,
    this.actionRoute,
    required this.generatedAt,
  });

  factory AiInsight.fromJson(Map<String, dynamic> j) => AiInsight(
    id: j['id'] ?? 0,
    category: j['category'] ?? 'info',
    severity: j['severity'] ?? 'info',
    message: j['message'] ?? '',
    action: j['action'],
    actionRoute: j['action_route'],
    generatedAt: j['generated_at'] ?? '',
  );
}

/// Hardcoded sample insights for UI development before AI backend exists.
/// Replace with API call in the AI Insights sprint.
List<AiInsight> sampleInsights() => [
  AiInsight(
    id: 1,
    category: 'churn',
    severity: 'warning',
    message: '12 members inactive for 14 days',
    action: 'View Members',
    actionRoute: '/members',
    generatedAt: DateTime.now().toIso8601String(),
  ),
  AiInsight(
    id: 2,
    category: 'revenue',
    severity: 'info',
    message: 'Gold plan generates 68% of total revenue',
    action: 'View Plans',
    actionRoute: '/plans',
    generatedAt: DateTime.now().toIso8601String(),
  ),
  AiInsight(
    id: 3,
    category: 'renewal',
    severity: 'warning',
    message: '8 memberships expiring in the next 3 days',
    action: 'View Renewals',
    actionRoute: '/renewals',
    generatedAt: DateTime.now().toIso8601String(),
  ),
];
