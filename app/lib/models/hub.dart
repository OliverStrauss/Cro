// App-curated public landmark, placed by an admin through the map's "Add Hub" flow -
// unlike Waypoint, a Hub has no single user-owner (createdByUserId just records who
// placed it, not an ownership check).
class Hub {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String status;
  final String createdByUserId;
  final String? category;
  final String? profilePictureUrl;

  Hub({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.createdByUserId,
    this.category,
    this.profilePictureUrl,
  });

  factory Hub.fromJson(Map<String, dynamic> json) => Hub(
        id: json['id'] as String,
        name: json['name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        status: json['status'] as String,
        createdByUserId: json['createdByUserId'] as String,
        category: json['category'] as String?,
        profilePictureUrl: json['profilePictureUrl'] as String?,
      );
}
