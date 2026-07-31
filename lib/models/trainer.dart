/// Trainer — a gym staff member who trains members.
/// Full implementation in the Trainer Management sprint.
class Trainer {
  final int id;
  final int gymId;
  final String firstName;
  final String lastName;
  final String phone;
  final String? email;
  final String? specialization;
  final String status; // active | inactive
  final int? salaryInPaise;
  final double? commissionPct;
  final String createdAt;

  Trainer({
    required this.id,
    required this.gymId,
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.email,
    this.specialization,
    required this.status,
    this.salaryInPaise,
    this.commissionPct,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName';

  factory Trainer.fromJson(Map<String, dynamic> j) => Trainer(
        id: j['id'] ?? 0,
        gymId: j['gym_id'] ?? 0,
        firstName: j['first_name'] ?? '',
        lastName: j['last_name'] ?? '',
        phone: j['phone'] ?? '',
        email: j['email'],
        specialization: j['specialization'],
        status: j['status'] ?? 'active',
        salaryInPaise: j['salary_in_paise'],
        commissionPct: (j['commission_pct'] as num?)?.toDouble(),
        createdAt: j['created_at'] ?? '',
      );
}
