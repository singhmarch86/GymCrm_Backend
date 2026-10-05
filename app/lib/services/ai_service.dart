import '../models/ai_insight.dart';

/// AiService — stub.
/// Returns sample insights until AI backend is available.
/// Replace implementation in the AI Insights sprint.
class AiService {
  Future<List<AiInsight>> getInsights() async {
    // TODO: replace with real API call when AI backend is ready
    await Future.delayed(const Duration(milliseconds: 300));
    return sampleInsights();
  }
}
