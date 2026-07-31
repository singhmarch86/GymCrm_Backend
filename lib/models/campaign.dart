/// Campaign — a marketing message sent to a segment of members.
/// Full implementation in the Marketing Automation sprint.
class Campaign {
  final int id;
  final int gymId;
  final String name;
  final String channel;   // whatsapp | sms | email
  final String type;      // renewal_reminder | birthday | offer | inactive | referral
  final String status;    // draft | scheduled | sent | failed
  final String? message;
  final int? recipientCount;
  final String? scheduledAt;
  final String createdAt;

  Campaign({
    required this.id,
    required this.gymId,
    required this.name,
    required this.channel,
    required this.type,
    required this.status,
    this.message,
    this.recipientCount,
    this.scheduledAt,
    required this.createdAt,
  });

  factory Campaign.fromJson(Map<String, dynamic> j) => Campaign(
        id: j['id'] ?? 0,
        gymId: j['gym_id'] ?? 0,
        name: j['name'] ?? '',
        channel: j['channel'] ?? 'whatsapp',
        type: j['type'] ?? 'offer',
        status: j['status'] ?? 'draft',
        message: j['message'],
        recipientCount: j['recipient_count'],
        scheduledAt: j['scheduled_at'],
        createdAt: j['created_at'] ?? '',
      );
}
