/// DietPlan — a nutritional plan assigned to a member.
/// Full implementation in the Diet Plans sprint.
class DietPlan {
  final int id;
  final int gymId;
  final String name;
  final String? description;
  final int? caloriesPerDay;
  final int? proteinGrams;
  final int? carbsGrams;
  final int? fatGrams;
  final String goal; // weight_loss | muscle_gain | maintenance
  final String createdAt;

  DietPlan({
    required this.id,
    required this.gymId,
    required this.name,
    this.description,
    this.caloriesPerDay,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
    required this.goal,
    required this.createdAt,
  });

  factory DietPlan.fromJson(Map<String, dynamic> j) => DietPlan(
    id: j['id'] ?? 0,
    gymId: j['gym_id'] ?? 0,
    name: j['name'] ?? '',
    description: j['description'],
    caloriesPerDay: j['calories_per_day'],
    proteinGrams: j['protein_grams'],
    carbsGrams: j['carbs_grams'],
    fatGrams: j['fat_grams'],
    goal: j['goal'] ?? '',
    createdAt: j['created_at'] ?? '',
  );
}
