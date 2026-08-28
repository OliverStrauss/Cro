// A row in the "Blocked users" list, from GET /friends/blocked - same shape as
// UserSearchResult/FriendRequest but deliberately its own type, same reasoning as those:
// conflating them would misrepresent the relationship.
class BlockedUser {
  final String userId;
  final String username;
  final String? profilePictureUrl;

  BlockedUser({required this.userId, required this.username, this.profilePictureUrl});

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        userId: json['id'] as String,
        username: json['username'] as String,
        profilePictureUrl: json['profilePictureUrl'] as String?,
      );
}
