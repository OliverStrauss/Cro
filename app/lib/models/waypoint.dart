class Waypoint {
  final String name;
  final double latitude;
  final double longitude;
  // Only present when this Waypoint represents a friend's delivery spot (from
  // GET /friends/waypoints) rather than the signed-in user's own (from GET /waypoint).
  final String? userId;
  final String? username;
  final String? color;
  final String? profilePictureUrl;

  Waypoint({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.userId,
    this.username,
    this.color,
    this.profilePictureUrl,
  });

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
        name: json['name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        userId: json['id'] as String?,
        username: json['username'] as String?,
        color: json['color'] as String?,
        profilePictureUrl: json['profilePictureUrl'] as String?,
      );
}
