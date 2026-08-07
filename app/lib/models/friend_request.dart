class FriendRequest {
  final String userId;
  final String username;
  final String? profilePictureUrl;

  FriendRequest({required this.userId, required this.username, this.profilePictureUrl});

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        userId: json['id'] as String,
        username: json['username'] as String,
        profilePictureUrl: json['profilePictureUrl'] as String?,
      );
}
