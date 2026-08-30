// Mirrors api/Models/Event.cs. One row per thing that has ever happened to the caller -
// a bird departing/arriving, a hub post, a friend request being accepted - written once and
// never pruned server-side. The journey log reads the full list; the notification dropdown
// reads the isNotification subset.
class AppEvent {
  final String id;
  final String kind;
  final String displayText;
  final String? quotedNote;
  final String? targetType;
  final String? targetId;
  final bool isNotification;
  final bool isRead;
  final DateTime createdAt;

  AppEvent({
    required this.id,
    required this.kind,
    required this.displayText,
    this.quotedNote,
    this.targetType,
    this.targetId,
    required this.isNotification,
    required this.isRead,
    required this.createdAt,
  });

  factory AppEvent.fromJson(Map<String, dynamic> json) => AppEvent(
    id: json['id'] as String,
    kind: json['kind'] as String,
    displayText: json['displayText'] as String,
    quotedNote: json['quotedNote'] as String?,
    targetType: json['targetType'] as String?,
    targetId: json['targetId'] as String?,
    isNotification: json['isNotification'] as bool,
    isRead: json['isRead'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

// Matches api/Models/Event.cs's EventKind constants.
class EventKind {
  static const birdDeparted = 'BirdDeparted';
  static const birdArrived = 'BirdArrived';
  static const birdArrivedAtYourNest = 'BirdArrivedAtYourNest';
  static const hubPostCreated = 'HubPostCreated';
  static const birdJoinedFlock = 'BirdJoinedFlock';
  static const friendAdded = 'FriendAdded';
  static const friendRequestAccepted = 'FriendRequestAccepted';
}

// Matches api/Models/Event.cs's EventTargetType constants.
class EventTargetType {
  static const bird = 'Bird';
  static const nest = 'Nest';
  static const hub = 'Hub';
}
