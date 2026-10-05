import '../models/workout_plan.dart';

/// WorkoutService — stub.
/// Implement endpoints in the Workout Plans sprint.
class WorkoutService {
  Future<List<WorkoutPlan>> getPlans() async =>
      throw UnimplementedError('Workout Plans not yet implemented');

  Future<WorkoutPlan> createPlan(Map<String, dynamic> data) async =>
      throw UnimplementedError();

  Future<void> assignToMember(int planId, int memberId) async =>
      throw UnimplementedError();
}
