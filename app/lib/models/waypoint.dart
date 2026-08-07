class Waypoint {
  final String id;
  final String userId;
  final String name;
  final double latitude;
  final double longitude;
  // Only present when this Waypoint represents a friend's nest (from
  // GET /friends/waypoints) rather than the signed-in user's own (from GET /waypoints).
  final String? username;
  final String? color;
  final String? profilePictureUrl;

  Waypoint({
    required this.id,
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.username,
    this.color,
    this.profilePictureUrl,
  });

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
        id: json['id'] as String,
        userId: json['userId'] as String,
        name: json['name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        username: json['username'] as String?,
        color: json['color'] as String?,
        profilePictureUrl: json['profilePictureUrl'] as String?,
      );
}
