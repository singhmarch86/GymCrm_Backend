/// A gym staff member. Maps backend users.StaffRow.
class Staff {
  final int id;
  final String name;
  final String phone;
  final String email;
  final String role; // owner | staff
  final String status; // active | inactive

  /// Open leads currently assigned — the workload figure shown in the list.
  final int leadCount;

  final String createdAt;

  Staff({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.status,
    required this.leadCount,
    required this.createdAt,
  });

  factory Staff.fromJson(Map<String, dynamic> j) => Staff(
    id: j['id'] ?? 0,
    name: j['name'] ?? '',
    phone: j['phone'] ?? '',
    email: j['email'] ?? '',
    role: j['role'] ?? 'staff',
    status: j['status'] ?? 'active',
    leadCount: j['lead_count'] ?? 0,
    createdAt: j['created_at'] ?? '',
  );

  bool get isOwner => role == 'owner';
  bool get isActive => status == 'active';

  String get roleLabel => isOwner ? 'Owner' : 'Staff';

  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';
}
