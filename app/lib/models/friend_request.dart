class FriendRequest {
  final String userId;
  final String username;

  FriendRequest({required this.userId, required this.username});

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        userId: json['id'] as String,
        username: json['username'] as String,
      );
}
