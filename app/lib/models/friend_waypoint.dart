class FriendWaypoint {
  final String userId;
  final String username;
  final String color;
  final double latitude;
  final double longitude;

  FriendWaypoint({
    required this.userId,
    required this.username,
    required this.color,
    required this.latitude,
    required this.longitude,
  });

  factory FriendWaypoint.fromJson(Map<String, dynamic> json) => FriendWaypoint(
        userId: json['id'] as String,
        username: json['username'] as String,
        color: json['color'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}
