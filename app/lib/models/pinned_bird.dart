// A durable "saved message" - a bird that landed directly at the receiver's own nest,
// snapshotted at pin time so it survives that bird later being picked up and resent
// elsewhere. See api/Models/PinnedBird.cs. isPublic is fixed at pin time from the bird's own
// visibility when it arrived - the pinner never chooses it.
class PinnedBird {
  final String id;
  final String receiverId;
  final String senderId;
  final String senderUsername;
  final String birdId;
  final String birdName;
  final String? originNestName;
  final String type;
  final String? content;
  final String? audioUrl;
  final String? imageUrl;
  final bool isPublic;
  final DateTime createdAt;

  PinnedBird({
    required this.id,
    required this.receiverId,
    required this.senderId,
    required this.senderUsername,
    required this.birdId,
    required this.birdName,
    this.originNestName,
    required this.type,
    this.content,
    this.audioUrl,
    this.imageUrl,
    required this.isPublic,
    required this.createdAt,
  });

  factory PinnedBird.fromJson(Map<String, dynamic> json) => PinnedBird(
        id: json['id'] as String,
        receiverId: json['receiverId'] as String,
        senderId: json['senderId'] as String,
        senderUsername: json['senderUsername'] as String,
        birdId: json['birdId'] as String,
        birdName: json['birdName'] as String,
        originNestName: json['originNestName'] as String?,
        type: json['type'] as String,
        content: json['content'] as String?,
        audioUrl: json['audioUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
        isPublic: json['isPublic'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
