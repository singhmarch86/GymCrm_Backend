/// Branch — a physical gym location under the same owner account.
/// Full implementation in the Branch Management sprint.
/// Note: current multi-tenant model uses gym_id as the tenant key.
/// Branch support will require a branches table and branch_id on members/payments.
class Branch {
  final int id;
  final int gymId;
  final String name;
  final String? address;
  final String? city;
  final String? phone;
  final String status; // active | inactive
  final String createdAt;

  Branch({
    required this.id,
    required this.gymId,
    required this.name,
    this.address,
    this.city,
    this.phone,
    required this.status,
    required this.createdAt,
  });

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
        id: j['id'] ?? 0,
        gymId: j['gym_id'] ?? 0,
        name: j['name'] ?? '',
        address: j['address'],
        city: j['city'],
        phone: j['phone'],
        status: j['status'] ?? 'active',
        createdAt: j['created_at'] ?? '',
      );
}
