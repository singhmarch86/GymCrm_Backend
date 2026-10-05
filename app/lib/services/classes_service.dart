import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/class_models.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// Classes, recurring schedules, sessions, and bookings with waitlist.
/// No business rules here — every limit and count shown to staff comes from
/// the server. See docs/FR-02-classes-booking.md in the backend repo.
class ClassesService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  // ── Class types ────────────────────────────────────────────────────────────

  Future<List<ClassType>> getClassTypes({bool activeOnly = false}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/class-types',
    ).replace(queryParameters: activeOnly ? {'active_only': 'true'} : null);
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => ClassType.fromJson(e)).toList();
  }

  Future<ClassType> createClassType({
    required String name,
    required int durationMinutes,
    required int defaultCapacity,
    String description = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/class-types'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'duration_minutes': durationMinutes,
          'default_capacity': defaultCapacity,
          'description': description,
        }),
      ),
    );
    return ClassType.fromJson(unwrapJson(response)['data']);
  }

  /// Edits a class type. Only the fields passed are changed — omit a
  /// parameter to leave it as-is. Never affects schedules or sessions
  /// already created from this type; they hold their own snapshot.
  Future<ClassType> updateClassType(
    int id, {
    String? name,
    String? description,
    int? durationMinutes,
    int? defaultCapacity,
    bool? isActive,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.put(
        Uri.parse('$kBaseUrl/api/v1/class-types/$id'),
        headers: headers,
        body: jsonEncode({
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (durationMinutes != null) 'duration_minutes': durationMinutes,
          if (defaultCapacity != null) 'default_capacity': defaultCapacity,
          if (isActive != null) 'is_active': isActive,
        }),
      ),
    );
    return ClassType.fromJson(unwrapJson(response)['data']);
  }

  // ── Schedules ──────────────────────────────────────────────────────────────

  Future<List<ClassSchedule>> getSchedules({bool activeOnly = false}) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/class-schedules',
    ).replace(queryParameters: activeOnly ? {'active_only': 'true'} : null);
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => ClassSchedule.fromJson(e)).toList();
  }

  /// Creates a recurrence rule. The backend materializes the first rolling
  /// window of sessions immediately — no separate "generate" call is needed
  /// for a schedule to be bookable right away.
  Future<ClassSchedule> createSchedule({
    required int classTypeId,
    required int dayOfWeek,
    required String startTime, // "HH:MM"
    int durationMinutes = 0, // 0 = use class type default
    int capacity = 0, // 0 = use class type default
    int? trainerUserId,
    DateTime? effectiveFrom,
    DateTime? effectiveUntil,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/class-schedules'),
        headers: headers,
        body: jsonEncode({
          'class_type_id': classTypeId,
          'day_of_week': dayOfWeek,
          'start_time': startTime,
          if (durationMinutes > 0) 'duration_minutes': durationMinutes,
          if (capacity > 0) 'capacity': capacity,
          if (trainerUserId != null) 'trainer_user_id': trainerUserId,
          if (effectiveFrom != null) 'effective_from': _ymd(effectiveFrom),
          if (effectiveUntil != null) 'effective_until': _ymd(effectiveUntil),
        }),
      ),
    );
    return ClassSchedule.fromJson(unwrapJson(response)['data']);
  }

  // ── Sessions ───────────────────────────────────────────────────────────────

  Future<List<ClassSession>> getSessions({
    required DateTime from,
    required DateTime to,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/class-sessions',
    ).replace(queryParameters: {'from': _ymd(from), 'to': _ymd(to)});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => ClassSession.fromJson(e)).toList();
  }

  Future<ClassSession> getSession(int id) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/class-sessions/$id'),
        headers: headers,
      ),
    );
    return ClassSession.fromJson(unwrapJson(response)['data']);
  }

  Future<ClassSession> updateSession(
    int id, {
    int? capacity,
    int? trainerUserId,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.put(
        Uri.parse('$kBaseUrl/api/v1/class-sessions/$id'),
        headers: headers,
        body: jsonEncode({
          if (capacity != null) 'capacity': capacity,
          if (trainerUserId != null) 'trainer_user_id': trainerUserId,
        }),
      ),
    );
    return ClassSession.fromJson(unwrapJson(response)['data']);
  }

  /// Cancels the session and every active booking on it.
  Future<ClassSession> cancelSession(int id) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/class-sessions/$id/cancel'),
        headers: headers,
      ),
    );
    return ClassSession.fromJson(unwrapJson(response)['data']);
  }

  Future<ClassSession> completeSession(int id) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/class-sessions/$id/complete'),
        headers: headers,
      ),
    );
    return ClassSession.fromJson(unwrapJson(response)['data']);
  }

  // ── Bookings ───────────────────────────────────────────────────────────────

  /// Books the member, or places them on the waitlist if the session is full.
  Future<BookingResult> book(int sessionId, int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/class-sessions/$sessionId/bookings'),
        headers: headers,
        body: jsonEncode({'member_id': memberId}),
      ),
    );
    return BookingResult.fromJson(unwrapJson(response)['data']);
  }

  /// Cancels a booking. If it held a session slot, the oldest waitlisted
  /// member is promoted — check `result.promoted` to tell the caller.
  Future<BookingResult> cancelBooking(
    int bookingId, {
    String reason = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/bookings/$bookingId/cancel'),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ),
    );
    return BookingResult.fromJson(unwrapJson(response)['data']);
  }

  /// Marks a booking attended or no-show. Only valid after the session starts.
  Future<BookingResult> markAttendance(
    int bookingId, {
    required bool attended,
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/bookings/$bookingId/attendance'),
        headers: headers,
        body: jsonEncode({'attended': attended}),
      ),
    );
    return BookingResult.fromJson(unwrapJson(response)['data']);
  }

  /// A session's roster — booked first, then waitlisted in order, then past
  /// attendance/cancellations.
  Future<List<Booking>> sessionBookings(int sessionId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/class-sessions/$sessionId/bookings'),
        headers: headers,
      ),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Booking.fromJson(e)).toList();
  }

  /// A member's own booking history, newest first.
  Future<List<Booking>> memberBookings(int memberId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/members/$memberId/bookings'),
        headers: headers,
      ),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => Booking.fromJson(e)).toList();
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
