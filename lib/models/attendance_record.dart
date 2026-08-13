/// AttendanceRecord maps the backend's AttendanceResponse
/// (internal/attendance/dto.go).
class AttendanceRecord {
  final int id;
  final int gymId;
  final int memberId;
  final String memberName;
  final String checkedInAt; // full UTC timestamp
  final String checkedInDate; // date-only
  final String createdAt;

  AttendanceRecord({
    required this.id,
    required this.gymId,
    required this.memberId,
    required this.memberName,
    required this.checkedInAt,
    required this.checkedInDate,
    required this.createdAt,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
    id: j['id'] ?? 0,
    gymId: j['gym_id'] ?? 0,
    memberId: j['member_id'] ?? 0,
    memberName: j['member_name'] ?? '',
    checkedInAt: j['checked_in_at'] ?? '',
    checkedInDate: j['checked_in_date'] ?? '',
    createdAt: j['created_at'] ?? '',
  );

  /// Display-friendly time, e.g. "09:30 AM"
  String get timeLabel {
    try {
      final dt = DateTime.parse(checkedInAt).toLocal();
      final h = dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$hour:$m $period';
    } catch (_) {
      return '';
    }
  }

  /// Display-friendly date, e.g. "01 Jul 2026"
  String get dateLabel {
    try {
      final dt = DateTime.parse(checkedInDate);
      const months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return checkedInDate;
    }
  }

  /// Returns true if this record is for today.
  bool get isToday {
    try {
      final d = DateTime.parse(checkedInDate);
      final now = DateTime.now();
      return d.year == now.year && d.month == now.month && d.day == now.day;
    } catch (_) {
      return false;
    }
  }
}
