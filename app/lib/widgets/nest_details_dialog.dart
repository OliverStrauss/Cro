import 'package:flutter/material.dart';

import '../screens/my_nests_screen.dart';
import '../state/auth_state.dart';
import 'avatar_with_fallback.dart';

// Shared popup shown when tapping either one of the user's own nest markers or a friend's
// nest marker on the map: bordered profile picture, "Your nest" (for the user's own marker)
// or "{username}'s nest" (for a friend's) title, the name the owner gave that nest, and
// lat/long formatted to 4 decimal places. Own nests get edit/delete actions that hand off
// to the My Nests screen, which owns all nest CRUD logic.
class NestDetailsDialog extends StatelessWidget {
  final String username;
  final bool isOwn;
  final String? profilePictureUrl;
  final String waypointId;
  final String waypointName;
  final double latitude;
  final double longitude;
  final AuthState authState;

  const NestDetailsDialog({
    super.key,
    required this.username,
    required this.isOwn,
    required this.profilePictureUrl,
    required this.waypointId,
    required this.waypointName,
    required this.latitude,
    required this.longitude,
    required this.authState,
  });

  static Future<void> show(
    BuildContext context, {
    required String username,
    required bool isOwn,
    required String? profilePictureUrl,
    required String waypointId,
    required String waypointName,
    required double latitude,
    required double longitude,
    required AuthState authState,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => NestDetailsDialog(
        username: username,
        isOwn: isOwn,
        profilePictureUrl: profilePictureUrl,
        waypointId: waypointId,
        waypointName: waypointName,
        latitude: latitude,
        longitude: longitude,
        authState: authState,
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
        if (isOwn)
          TextButton(
            key: const Key('editNestFromDialogButton'),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MyNestsScreen(authState: authState)),
              );
            },
            child: const Text('Edit'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
