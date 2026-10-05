/// A walk-in visit — distinct from a Lead (an enquiry, which may never set
/// foot in the gym) and a Member (a paying signup). Converting a visit into
/// a lead is an explicit staff action, never automatic.
class Visitor {
  final int id;
  final String name;
  final String? phone;
  final String purpose; // trial | guest | tour | other
  final DateTime checkedInAt;
  final DateTime? checkedOutAt;
  final int? hostStaffUserId;
  final String? hostStaffName;
  final int? convertedLeadId;
  final String? notes;
  final bool stillInBuilding;

  const Visitor({
    required this.id,
    required this.name,
    this.phone,
    required this.purpose,
    required this.checkedInAt,
    this.checkedOutAt,
    this.hostStaffUserId,
    this.hostStaffName,
    this.convertedLeadId,
    this.notes,
    required this.stillInBuilding,
  });

  factory Visitor.fromJson(Map<String, dynamic> j) => Visitor(
    id: j['id'] as int,
    name: (j['name'] ?? '') as String,
    phone: j['phone'] as String?,
    purpose: (j['purpose'] ?? 'trial') as String,
    checkedInAt: DateTime.parse(j['checked_in_at'] as String),
    checkedOutAt: j['checked_out_at'] == null
        ? null
        : DateTime.parse(j['checked_out_at']),
    hostStaffUserId: j['host_staff_user_id'] as int?,
    hostStaffName: j['host_staff_name'] as String?,
    convertedLeadId: j['converted_lead_id'] as int?,
    notes: j['notes'] as String?,
    stillInBuilding: (j['still_in_building'] ?? false) as bool,
  );
}
