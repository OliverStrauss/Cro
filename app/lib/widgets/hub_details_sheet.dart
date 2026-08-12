import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/avatar_with_fallback.dart';

// Bottom sheet shown when tapping a Hub marker on the map - read-only for everyone
// (including admins, in this pass): a Hub has no rename/delete/picture-upload actions,
// unlike NestDetailsSheet's own-nest branch, so this doesn't inherit that widget's
// ownership-action machinery.
class HubDetailsSheet extends StatelessWidget {
  final String name;
  final String? category;
  final String? profilePictureUrl;
  final double latitude;
  final double longitude;

  const HubDetailsSheet({
    super.key,
    required this.name,
    this.category,
    this.profilePictureUrl,
    required this.latitude,
    required this.longitude,
  });

  static Future<void> show(
    BuildContext context, {
    required String name,
    String? category,
    String? profilePictureUrl,
    required double latitude,
    required double longitude,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => HubDetailsSheet(
        name: name,
        category: category,
        profilePictureUrl: profilePictureUrl,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('hubDetailsSheet'),
      decoration: const BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2E2B2F33),
            blurRadius: 30,
            offset: Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0x262B2F33),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AvatarWithFallback(
                  imageUrl: profilePictureUrl,
                  initialsSource: name,
                  radius: 26,
                  hasBorder: true,
                  borderColor: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: CroColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        category ?? 'Hub',
                        key: const Key('hubDetailsCategory'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: CroColors.fog,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Location', style: TextStyle(fontSize: 13, color: CroColors.fog)),
                const Spacer(),
                Text(
                  '(${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})',
                  key: const Key('hubDetailsLocation'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CroColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CroColors.deepWaypoint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
