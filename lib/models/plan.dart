class Plan {
  final int id;

  final String name;

  final String? description;

  final int durationDays;

  final double priceInRupees;

  final bool isActive;

  Plan({
    required this.id,
    required this.name,
    this.description,
    required this.durationDays,
    required this.priceInRupees,
    required this.isActive,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      durationDays: json['duration_days'] ?? 0,
      priceInRupees: (json['price_in_rupees'] ?? 0).toDouble(),
      isActive: json['is_active'] ?? true,
    );
  }
}
