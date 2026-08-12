// A friend's in-flight bird, from GET /friends/birds - only ever traveling birds, and
// only for accepted friends, so unlike Bird there's no idle/currentNestId state to model.
class FriendBird {
  final String id;
  final String userId;
  final String username;
  final String? color;
  final String name;
  final String type;
  final String? nestFromId;
  final String? nestToId;
  final DateTime departedAt;
  final DateTime estimatedArrivalAt;
  final bool isPublic;
  // Only ever populated when isPublic - GET /friends/birds omits these for a still-private
  // bird so a friend's in-flight message can't be read early, same rule reactions follow.
  final String? content;
  final String? audioUrl;
  final String? imageUrl;

  FriendBird({
    required this.id,
    required this.userId,
    required this.username,
    this.color,
    required this.name,
    required this.type,
    this.nestFromId,
    this.nestToId,
    required this.departedAt,
    required this.estimatedArrivalAt,
    this.isPublic = false,
    this.content,
    this.audioUrl,
    this.imageUrl,
  });

  factory FriendBird.fromJson(Map<String, dynamic> json) => FriendBird(
        id: json['id'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        color: json['color'] as String?,
        name: json['name'] as String,
        type: json['type'] as String,
        nestFromId: json['nestFromId'] as String?,
        nestToId: json['nestToId'] as String?,
        departedAt: DateTime.parse(json['departedAt'] as String),
        estimatedArrivalAt: DateTime.parse(json['estimatedArrivalAt'] as String),
        isPublic: json['isPublic'] as bool? ?? false,
        content: json['content'] as String?,
        audioUrl: json['audioUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
      );
}
