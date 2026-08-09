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
      );
}
