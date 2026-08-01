/// Classes & booking models. See docs/FR-02-classes-booking.md in the backend
/// repo for the business rules — these types carry no logic, only parsing.
library;

/// A class offering — "Yoga", "Zumba". Long-lived, edited rarely.
class ClassType {
  final int id;
  final String name;
  final String? description;
  final int durationMinutes;
  final int defaultCapacity;
  final bool isActive;

  const ClassType({
    required this.id,
    required this.name,
    this.description,
    required this.durationMinutes,
    required this.defaultCapacity,
    required this.isActive,
  });

  factory ClassType.fromJson(Map<String, dynamic> j) => ClassType(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        durationMinutes: (j['duration_minutes'] ?? 0) as int,
        defaultCapacity: (j['default_capacity'] ?? 0) as int,
        isActive: (j['is_active'] ?? true) as bool,
      );
}

/// A recurring schedule — day/time/trainer/capacity. Editing this never
/// retroactively changes sessions already generated.
class ClassSchedule {
  final int id;
  final int classTypeId;
  final String classTypeName;
  final int dayOfWeek; // 0 = Sunday .. 6 = Saturday
  final String startTime; // "HH:MM:SS"
  final int durationMinutes;
  final int capacity;
  final int? trainerUserId;
  final String? trainerName;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;
  final bool isActive;

  const ClassSchedule({
    required this.id,
    required this.classTypeId,
    required this.classTypeName,
    required this.dayOfWeek,
    required this.startTime,
    required this.durationMinutes,
    required this.capacity,
    this.trainerUserId,
    this.trainerName,
    required this.effectiveFrom,
    this.effectiveUntil,
    required this.isActive,
  });

  static const dayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];

  String get dayName => dayNames[dayOfWeek % 7];

  factory ClassSchedule.fromJson(Map<String, dynamic> j) => ClassSchedule(
        id: j['id'] as int,
        classTypeId: j['class_type_id'] as int,
        classTypeName: (j['class_type_name'] ?? '') as String,
        dayOfWeek: (j['day_of_week'] ?? 0) as int,
        startTime: (j['start_time'] ?? '') as String,
        durationMinutes: (j['duration_minutes'] ?? 0) as int,
        capacity: (j['capacity'] ?? 0) as int,
        trainerUserId: j['trainer_user_id'] as int?,
        trainerName: j['trainer_name'] as String?,
        effectiveFrom: DateTime.parse(j['effective_from'] as String),
        effectiveUntil: j['effective_until'] == null
            ? null
            : DateTime.parse(j['effective_until'] as String),
        isActive: (j['is_active'] ?? true) as bool,
      );
}

/// One bookable occurrence, with live booking counts so the sessions list
/// never needs a second query per card.
class ClassSession {
  final int id;
  final int? scheduleId;
  final int classTypeId;
  final String classTypeName;
  final DateTime sessionDate;
  final String startTime;
  final int durationMinutes;
  final int capacity;
  final int? trainerUserId;
  final String? trainerName;
  final String status; // scheduled | cancelled | completed
  final int bookedCount;
  final int waitlistCount;

  const ClassSession({
    required this.id,
    this.scheduleId,
    required this.classTypeId,
    required this.classTypeName,
    required this.sessionDate,
    required this.startTime,
    required this.durationMinutes,
    required this.capacity,
    this.trainerUserId,
    this.trainerName,
    required this.status,
    required this.bookedCount,
    required this.waitlistCount,
  });

  bool get isFull => bookedCount >= capacity;
  int get spotsLeft => (capacity - bookedCount).clamp(0, capacity);

  factory ClassSession.fromJson(Map<String, dynamic> j) => ClassSession(
        id: j['id'] as int,
        scheduleId: j['schedule_id'] as int?,
        classTypeId: j['class_type_id'] as int,
        classTypeName: (j['class_type_name'] ?? '') as String,
        sessionDate: DateTime.parse(j['session_date'] as String),
        startTime: (j['start_time'] ?? '') as String,
        durationMinutes: (j['duration_minutes'] ?? 0) as int,
        capacity: (j['capacity'] ?? 0) as int,
        trainerUserId: j['trainer_user_id'] as int?,
        trainerName: j['trainer_name'] as String?,
        status: (j['status'] ?? 'scheduled') as String,
        bookedCount: (j['booked_count'] ?? 0) as int,
        waitlistCount: (j['waitlist_count'] ?? 0) as int,
      );
}

/// One member's claim on one session.
class Booking {
  final int id;
  final int sessionId;
  final int memberId;
  final String memberName;
  final String status; // booked | waitlisted | cancelled | attended | no_show
  final int? waitlistPosition;
  final DateTime bookedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  const Booking({
    required this.id,
    required this.sessionId,
    required this.memberId,
    required this.memberName,
    required this.status,
    this.waitlistPosition,
    required this.bookedAt,
    this.cancelledAt,
    this.cancelReason,
  });

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'] as int,
        sessionId: j['session_id'] as int,
        memberId: j['member_id'] as int,
        memberName: (j['member_name'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        waitlistPosition: j['waitlist_position'] as int?,
        bookedAt: DateTime.parse(j['booked_at'] as String),
        cancelledAt: j['cancelled_at'] == null
            ? null
            : DateTime.parse(j['cancelled_at'] as String),
        cancelReason: j['cancel_reason'] as String?,
      );
}

/// Result of a booking operation — the affected booking, the session's fresh
/// counts, and (on a cancel that freed a slot) whoever got promoted.
class BookingResult {
  final Booking booking;
  final ClassSession session;
  final Booking? promoted;

  const BookingResult({
    required this.booking,
    required this.session,
    this.promoted,
  });

  factory BookingResult.fromJson(Map<String, dynamic> j) => BookingResult(
        booking: Booking.fromJson(j['booking'] as Map<String, dynamic>),
        session: ClassSession.fromJson(j['session'] as Map<String, dynamic>),
        promoted: j['promoted'] == null
            ? null
            : Booking.fromJson(j['promoted'] as Map<String, dynamic>),
      );
}
