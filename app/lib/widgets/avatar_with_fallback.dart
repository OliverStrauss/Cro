import 'package:flutter/material.dart';

// Extracted from the identical pattern previously copy-pasted in ProfileScreen and
// FriendListTile: a CircleAvatar that shows imageUrl when present, falling back to a
// single initial both when no URL is given and when the network image fails to load.
class AvatarWithFallback extends StatefulWidget {
  final String? imageUrl;
  final String initialsSource;
  final double radius;
  final Key? avatarKey;
  final bool hasBorder;
  final Color? borderColor;

  const AvatarWithFallback({
    super.key,
    required this.imageUrl,
    required this.initialsSource,
    this.radius = 24,
    this.avatarKey,
    this.hasBorder = false,
    this.borderColor,
  });

  @override
  State<AvatarWithFallback> createState() => _AvatarWithFallbackState();
}

class _AvatarWithFallbackState extends State<AvatarWithFallback> {
  bool _pictureFailedToLoad = false;

  String get _initials {
    final trimmed = widget.initialsSource.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @override
  void didUpdateWidget(covariant AvatarWithFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different URL (e.g. after a refresh or a re-upload) deserves a fresh attempt
    // rather than staying stuck showing the previous failure's fallback.
    if (oldWidget.imageUrl != widget.imageUrl) {
      _pictureFailedToLoad = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    final showImage = url != null && !_pictureFailedToLoad;
    final avatar = CircleAvatar(
      key: widget.avatarKey,
      radius: widget.radius,
      backgroundImage: showImage ? NetworkImage(url) : null,
      // CircleAvatar asserts backgroundImage != null || onBackgroundImageError == null,
      // so this must be gated on the exact same condition as backgroundImage above -
      // once _pictureFailedToLoad flips, both need to go null together.
      onBackgroundImageError: showImage
          ? (exception, stackTrace) {
              if (mounted) setState(() => _pictureFailedToLoad = true);
            }
          : null,
      child: showImage ? null : Text(_initials, style: TextStyle(fontSize: widget.radius * 0.6)),
    );

    if (!widget.hasBorder) {
      return avatar;
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.borderColor ?? Theme.of(context).colorScheme.primary,
          width: 3,
        ),
      ),
      child: avatar,
    );
  }
}
