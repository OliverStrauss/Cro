import 'package:flutter/material.dart';

import 'avatar_with_fallback.dart';

// Shared popup shown when tapping either the user's own waypoint marker or a
// friend's waypoint marker on the map: profile picture, "{username}'s nest" title,
// and lat/long formatted to 4 decimal places.
class NestDetailsDialog extends StatelessWidget {
  final String username;
  final String? profilePictureUrl;
  final double latitude;
  final double longitude;

  const NestDetailsDialog({
    super.key,
    required this.username,
    required this.profilePictureUrl,
    required this.latitude,
    required this.longitude,
  });

  static Future<void> show(
    BuildContext context, {
    required String username,
    required String? profilePictureUrl,
    required double latitude,
    required double longitude,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => NestDetailsDialog(
        username: username,
        profilePictureUrl: profilePictureUrl,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('nestDetailsDialog'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWithFallback(
            avatarKey: const Key('nestDetailsAvatar'),
            imageUrl: profilePictureUrl,
            initialsSource: username,
            radius: 32,
          ),
          const SizedBox(height: 12),
          Text("$username's nest", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '(${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})',
            key: const Key('nestDetailsCoordinates'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
