/// Trainer — a gym staff member on the PT roster. Distinct from a `User`
/// account: a trainer here is a standalone record (name, phone, comp) that
/// may or may not also have a login. See FR-03 §0.
class Trainer {
  final int id;
  final String firstName;
  final String lastName;
  final String fullName;
  final String phone;
  final String? email;
  final String? specialization;
  final String status; // active | inactive
  final int? salaryInPaise;
  final double? commissionPct;
  final String createdAt;

  Trainer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.phone,
    this.email,
    this.specialization,
    required this.status,
    this.salaryInPaise,
    this.commissionPct,
    required this.createdAt,
  });

  factory Trainer.fromJson(Map<String, dynamic> j) => Trainer(
        id: j['id'] ?? 0,
        firstName: j['first_name'] ?? '',
        lastName: j['last_name'] ?? '',
        fullName: j['full_name'] ?? '${j['first_name'] ?? ''} ${j['last_name'] ?? ''}',
        phone: j['phone'] ?? '',
        email: j['email'],
        specialization: j['specialization'],
        status: j['status'] ?? 'active',
        salaryInPaise: j['salary_in_paise'],
        commissionPct: (j['commission_pct'] as num?)?.toDouble(),
        createdAt: j['created_at'] ?? '',
      );
}
