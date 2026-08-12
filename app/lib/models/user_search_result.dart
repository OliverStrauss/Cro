// A row in the "Add Friends" live-suggestions dropdown, from GET /users/search - deliberately
// not a Friend or FriendRequest (neither is true of a bare search hit yet), even though the
// shape is identical, since conflating them would misrepresent the relationship.
class UserSearchResult {
  final String userId;
  final String username;
  final String? profilePictureUrl;

  UserSearchResult({
    required this.userId,
    required this.username,
    this.profilePictureUrl,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      UserSearchResult(
        userId: json['id'] as String,
        username: json['username'] as String,
        profilePictureUrl: json['profilePictureUrl'] as String?,
      );
}
