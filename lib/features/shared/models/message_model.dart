// ─────────────────────────────────────────────────────────────────────────────
// GroupMessage  &  MessageSender  –  shared message data models
// ─────────────────────────────────────────────────────────────────────────────

class MessageSender {
  final String id;
  final String fullName;
  final String? role;

  const MessageSender({required this.id, required this.fullName, this.role});

  factory MessageSender.fromJson(Map<String, dynamic> j) => MessageSender(
    id: j['_id']?.toString() ?? '',
    fullName: j['full_name']?.toString() ?? 'Unknown',
    role: j['role']?.toString(),
  );

  String get initial => fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
}

class GroupMessage {
  final String id;
  final String groupId;
  final String? recipientId; // null → broadcast to whole group
  final MessageSender? sender;
  final String senderModel; // 'User' | 'Pilgrim'
  final String type; // 'text' | 'voice' | 'tts' | 'meetpoint'
  final String? content;
  final String? mediaUrl; // filename only (voice/image)
  final String? originalText; // TTS source text
  final bool isUrgent;
  final int duration; // seconds (voice)
  final Map<String, dynamic>?
  meetpointData; // { area_id, name, latitude, longitude }
  final DateTime createdAt;

  const GroupMessage({
    required this.id,
    required this.groupId,
    this.recipientId,
    this.sender,
    required this.senderModel,
    required this.type,
    this.content,
    this.mediaUrl,
    this.originalText,
    required this.isUrgent,
    required this.duration,
    this.meetpointData,
    required this.createdAt,
  });

  bool get isFromModerator => senderModel == 'User';
  bool get isBroadcast => recipientId == null;

  factory GroupMessage.fromJson(Map<String, dynamic> j) {
    final senderData = j['sender_id'];
    MessageSender? sender;
    if (senderData is Map<String, dynamic>) {
      sender = MessageSender.fromJson(senderData);
    }

    return GroupMessage(
      id: j['_id']?.toString() ?? '',
      groupId: j['group_id']?.toString() ?? '',
      recipientId: j['recipient_id']?.toString(),
      sender: sender,
      senderModel: j['sender_model']?.toString() ?? 'User',
      type: j['type']?.toString() ?? 'text',
      content: j['content']?.toString(),
      mediaUrl: j['media_url']?.toString(),
      originalText: j['original_text']?.toString(),
      isUrgent: j['is_urgent'] as bool? ?? false,
      duration: (j['duration'] as num?)?.toInt() ?? 0,
      meetpointData: j['meetpoint_data'] is Map<String, dynamic>
          ? j['meetpoint_data'] as Map<String, dynamic>
          : null,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
