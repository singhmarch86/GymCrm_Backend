/// WorkoutPlan — a structured exercise program assigned to a member.
/// Full implementation in the Workout Plans sprint.
class WorkoutPlan {
  final int id;
  final int gymId;
  final String name;
  final String? description;
  final int? durationWeeks;
  final String goal; // weight_loss | muscle_gain | endurance | flexibility
  final String createdAt;

  WorkoutPlan({
    required this.id,
    required this.gymId,
    required this.name,
    this.description,
    this.durationWeeks,
    required this.goal,
    required this.createdAt,
  });

  factory WorkoutPlan.fromJson(Map<String, dynamic> j) => WorkoutPlan(
        id: j['id'] ?? 0,
        gymId: j['gym_id'] ?? 0,
        name: j['name'] ?? '',
        description: j['description'],
        durationWeeks: j['duration_weeks'],
        goal: j['goal'] ?? '',
        createdAt: j['created_at'] ?? '',
      );
}
