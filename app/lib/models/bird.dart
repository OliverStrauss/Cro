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
  final DateTime? updatedAt;
  final bool isRead;
  // Message payload media - AudioUrl for Parrot, ImageUrl for Pigeon/Raven. Distinct from
  // profilePictureUrl, the bird's own persistent avatar.
  final String? audioUrl;
  final String? imageUrl;
  final String? profilePictureUrl;
  final bool isPublic;

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
    this.updatedAt,
    this.isRead = true,
    this.audioUrl,
    this.imageUrl,
    this.profilePictureUrl,
    this.isPublic = false,
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
        updatedAt: json['updatedAt'] == null ? null : DateTime.parse(json['updatedAt'] as String),
        isRead: json['isRead'] as bool,
        audioUrl: json['audioUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
        profilePictureUrl: json['profilePictureUrl'] as String?,
        isPublic: json['isPublic'] as bool? ?? false,
      );
}

// The four types a user can compose a bird as - kept alongside the Bird model since both
// the compose dialog and the birds list need this same roster/labeling.
class BirdType {
  static const cro = 'Cro';
  static const parrot = 'Parrot';
  static const raven = 'Raven';
  static const pigeon = 'Pigeon';

  static const all = [cro, parrot, raven, pigeon];

  static String description(String type) => switch (type) {
        cro => 'Text, fastest',
        parrot => 'Audio clip',
        raven => 'Text + image',
        pigeon => 'Image, slower',
        _ => type,
      };
}
