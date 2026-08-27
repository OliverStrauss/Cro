// One row per distinct emoji already used on a public bird - count and whether the caller
// is among the reactors. Reactions are only ever shown/fetched for a bird with isPublic ==
// true; the server rejects reacting to a private one.
class BirdReactionSummary {
  final String emoji;
  final int count;
  final bool reactedByMe;

  BirdReactionSummary({required this.emoji, required this.count, required this.reactedByMe});

  factory BirdReactionSummary.fromJson(Map<String, dynamic> json) => BirdReactionSummary(
        emoji: json['emoji'] as String,
        count: json['count'] as int,
        reactedByMe: json['reactedByMe'] as bool,
      );
}

// Fixed allowlist, must match BirdReactionEmoji.Allowed on the server.
const availableReactionEmojis = ['👍', '❤️', '😂', '😮', '🎉'];
