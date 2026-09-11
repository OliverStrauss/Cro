// A single point-in-time sighting of a stranger's public, in-flight bird, from
// GET /birds/public - the one bird query that isn't scoped to the caller or their friends.
// Deliberately much thinner than FriendBird: no nestFromId/nestToId/timestamps, since the
// server never exposes the flight's real endpoints here - latitude/longitude is the only
// location data, and it's a point strictly between the two real endpoints, never either one.
class PublicBird {
  final String id;
  final String senderUserId;
  final String senderUsername;
  final String? senderProfilePictureUrl;
  final String type;
  final String? content;
  final String? audioUrl;
  final String? imageUrl;
  final double latitude;
  final double longitude;

  PublicBird({
    required this.id,
    required this.senderUserId,
    required this.senderUsername,
    this.senderProfilePictureUrl,
    required this.type,
    this.content,
    this.audioUrl,
    this.imageUrl,
    required this.latitude,
    required this.longitude,
  });

  factory PublicBird.fromJson(Map<String, dynamic> json) => PublicBird(
        id: json['id'] as String,
        senderUserId: json['senderUserId'] as String,
        senderUsername: json['senderUsername'] as String,
        senderProfilePictureUrl: json['senderProfilePictureUrl'] as String?,
        type: json['type'] as String,
        content: json['content'] as String?,
        audioUrl: json['audioUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}
