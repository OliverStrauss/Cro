class Friend {
  final String userId;
  final String username;
  final String? color;
  final String? profilePictureUrl;
  final bool isAdmin;

  Friend({
    required this.userId,
    required this.username,
    this.color,
    this.profilePictureUrl,
    this.isAdmin = false,
  });

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        userId: json['id'] as String,
        username: json['username'] as String,
        color: json['color'] as String?,
        profilePictureUrl: json['profilePictureUrl'] as String?,
        isAdmin: json['isAdmin'] as bool? ?? false,
      );
}
