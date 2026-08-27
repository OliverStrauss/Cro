// One entry on a Hub's public message board - a durable record of a bird that landed
// there, independent of that bird's own later lifecycle (it may since have been picked up
// and resent elsewhere). See api/Models/HubMessage.cs.
class HubMessage {
  final String id;
  final String senderId;
  final String senderUsername;
  final String? senderProfilePictureUrl;
  final String birdName;
  final String? originNestName;
  final String type;
  final String? content;
  final String? audioUrl;
  final String? imageUrl;
  final DateTime createdAt;

  HubMessage({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    this.senderProfilePictureUrl,
    required this.birdName,
    this.originNestName,
    required this.type,
    this.content,
    this.audioUrl,
    this.imageUrl,
    required this.createdAt,
  });

  factory HubMessage.fromJson(Map<String, dynamic> json) => HubMessage(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        senderUsername: json['senderUsername'] as String,
        senderProfilePictureUrl: json['senderProfilePictureUrl'] as String?,
        birdName: json['birdName'] as String,
        originNestName: json['originNestName'] as String?,
        type: json['type'] as String,
        content: json['content'] as String?,
        audioUrl: json['audioUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
