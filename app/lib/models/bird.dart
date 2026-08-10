class Bird {
  final String id;
  final String userId;
  final String name;
  final String? currentNestId;
  final bool isTraveling;
  final String? nestFromId;
  final String? nestToId;
  final double? speed;
  final String? content;
  final String type;
  final DateTime? departedAt;
  final DateTime? estimatedArrivalAt;
  final bool isRead;

  Bird({
    required this.id,
    required this.userId,
    required this.name,
    this.currentNestId,
    required this.isTraveling,
    this.nestFromId,
    this.nestToId,
    this.speed,
    this.content,
    required this.type,
    this.departedAt,
    this.estimatedArrivalAt,
    this.isRead = true,
  });

  factory Bird.fromJson(Map<String, dynamic> json) => Bird(
        id: json['id'] as String,
        userId: json['userId'] as String,
        name: json['name'] as String,
        currentNestId: json['currentNestId'] as String?,
        isTraveling: json['isTraveling'] as bool,
        nestFromId: json['nestFromId'] as String?,
        nestToId: json['nestToId'] as String?,
        speed: (json['speed'] as num?)?.toDouble(),
        content: json['content'] as String?,
        type: json['type'] as String,
        departedAt: json['departedAt'] == null ? null : DateTime.parse(json['departedAt'] as String),
        estimatedArrivalAt: json['estimatedArrivalAt'] == null
            ? null
            : DateTime.parse(json['estimatedArrivalAt'] as String),
        isRead: json['isRead'] as bool,
      );
}
