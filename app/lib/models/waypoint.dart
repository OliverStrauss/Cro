class Waypoint {
  final String name;
  final double latitude;
  final double longitude;

  Waypoint({required this.name, required this.latitude, required this.longitude});

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
        name: json['name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}
