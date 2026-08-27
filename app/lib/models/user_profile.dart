class UserProfile {
  final String id;
  final String username;
  final String email;
  final String? profilePictureUrl;
  final bool isAdmin;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    this.profilePictureUrl,
    this.isAdmin = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        email: json['email'] as String,
        profilePictureUrl: json['profilePictureUrl'] as String?,
        isAdmin: json['isAdmin'] as bool? ?? false,
      );
}
