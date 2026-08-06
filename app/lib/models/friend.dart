class Friend {
  final String userId;
  final String username;
  final String? color;

  Friend({required this.userId, required this.username, this.color});

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        userId: json['id'] as String,
        username: json['username'] as String,
        color: json['color'] as String?,
      );
}
