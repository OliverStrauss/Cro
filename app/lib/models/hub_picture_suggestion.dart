// A user-suggested photo for a Hub, pending admin approval - mirrors
// api/Models/HubPictureSuggestion.cs. The suggester's username is resolved separately
// (not carried on this model) the same way hub location suggestions resolve theirs.
class HubPictureSuggestion {
  final String id;
  final String hubId;
  final String suggestedByUserId;
  final String blobUrl;
  final DateTime createdAt;

  HubPictureSuggestion({
    required this.id,
    required this.hubId,
    required this.suggestedByUserId,
    required this.blobUrl,
    required this.createdAt,
  });

  factory HubPictureSuggestion.fromJson(Map<String, dynamic> json) => HubPictureSuggestion(
        id: json['id'] as String,
        hubId: json['hubId'] as String,
        suggestedByUserId: json['suggestedByUserId'] as String,
        blobUrl: json['blobUrl'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
