import 'package:flutter/material.dart';

import 'avatar_with_fallback.dart';

// Shared popup shown when tapping either the user's own waypoint marker or a
// friend's waypoint marker on the map: bordered profile picture, "Your nest" (for
// the user's own marker) or "{username}'s nest" (for a friend's) title, the name
// the owner gave their delivery spot, and lat/long formatted to 4 decimal places.
class NestDetailsDialog extends StatelessWidget {
  final String username;
  final bool isOwn;
  final String? profilePictureUrl;
  final String waypointName;
  final double latitude;
  final double longitude;

  const NestDetailsDialog({
    super.key,
    required this.username,
    required this.isOwn,
    required this.profilePictureUrl,
    required this.waypointName,
    required this.latitude,
    required this.longitude,
  });

  static Future<void> show(
    BuildContext context, {
    required String username,
    required bool isOwn,
    required String? profilePictureUrl,
    required String waypointName,
    required double latitude,
    required double longitude,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => NestDetailsDialog(
        username: username,
        isOwn: isOwn,
        profilePictureUrl: profilePictureUrl,
        waypointName: waypointName,
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
            hasBorder: true,
          ),
          const SizedBox(height: 12),
          Text(isOwn ? 'Your nest' : "$username's nest", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            waypointName,
            key: const Key('nestDetailsWaypointName'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
