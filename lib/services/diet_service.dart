import '../models/diet_plan.dart';

/// DietService — stub.
/// Implement endpoints in the Diet Plans sprint.
class DietService {
  Future<List<DietPlan>> getPlans() async =>
      throw UnimplementedError('Diet Plans not yet implemented');

  Future<DietPlan> createPlan(Map<String, dynamic> data) async =>
      throw UnimplementedError();

  Future<void> assignToMember(int planId, int memberId) async =>
      throw UnimplementedError();
}
