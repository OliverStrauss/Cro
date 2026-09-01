import 'package:flutter/material.dart';

import '../../models/hub.dart';
import '../../models/hub_category.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../widgets/avatar_with_fallback.dart';
import '../widgets/hub_suggestions_panel.dart';

/// The Hubs screen: approved hub cards in a grid, plus (admin only) the suggested-hubs
/// moderation queue below them.
class WebHubsScreen extends StatelessWidget {
  final List<Hub> hubs;
  final bool isAdmin;
  final String? selectedHubId;
  final ValueChanged<Hub> onSelectHub;
  final AuthState authState;
  final HubService hubService;
  final ProfileService profileService;
  final VoidCallback onDataChanged;
  final VoidCallback onStartAddHub;

  const WebHubsScreen({
    super.key,
    required this.hubs,
    required this.isAdmin,
    required this.selectedHubId,
    required this.onSelectHub,
    required this.authState,
    required this.hubService,
    required this.profileService,
    required this.onDataChanged,
    required this.onStartAddHub,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('webHubsScreen'),
      // Top padding keeps content clear of the floating actions cluster (no top bar - see
      // 05_web_ui_updates.md item 1).
      padding: const EdgeInsets.fromLTRB(26, 74, 26, 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              OutlinedButton(
                key: const Key('webAddHubButton'),
                onPressed: onStartAddHub,
                style: OutlinedButton.styleFrom(
                  foregroundColor: CroColors.amberInk,
                  side: BorderSide(color: CroColors.deliveryAmber.withValues(alpha: 0.6), width: 1.5),
                ),
                child: Text(isAdmin ? '+ Add a Hub' : '+ Suggest a Hub'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (hubs.isEmpty)
            const Padding(
              key: Key('noHubsMessage'),
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No hubs nearby yet', style: TextStyle(fontSize: 13.5, color: CroColors.fog)),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 3.2,
              children: [for (final hub in hubs) _HubCard(hub: hub, selected: hub.id == selectedHubId, onTap: () => onSelectHub(hub))],
            ),
          if (isAdmin) ...[
            const SizedBox(height: 26),
            Row(
              children: [
                const Text('Suggested hubs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: CroColors.deliveryAmber.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Admin',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: CroColors.amberInk),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            HubSuggestionsPanel(
              authState: authState,
              hubService: hubService,
              profileService: profileService,
              onChanged: onDataChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final Hub hub;
  final bool selected;
  final VoidCallback onTap;

  const _HubCard({required this.hub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('webHubCard_${hub.id}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? CroColors.deliveryAmber.withValues(alpha: 0.6) : CroColors.ink.withValues(alpha: 0.06)),
          boxShadow: const [BoxShadow(color: Color(0x122B2F33), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWithFallback(
              imageUrl: hub.profilePictureUrl,
              initialsSource: hub.name,
              fallbackIcon: HubCategory.iconFor(hub.category),
              radius: 18,
            ),
            const SizedBox(height: 4),
            Text(
              hub.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 1),
            const Text('View board →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint)),
          ],
        ),
      ),
    );
  }
}
