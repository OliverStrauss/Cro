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
class WebHubsScreen extends StatefulWidget {
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
  State<WebHubsScreen> createState() => _WebHubsScreenState();
}

class _WebHubsScreenState extends State<WebHubsScreen> {
  final _searchController = TextEditingController();
  // Null means "every category" - same toggle-to-clear convention as SendBirdDialog's own
  // category chips (see lib/widgets/send_bird_dialog.dart's _toggleCategory), reused here
  // rather than inventing a second one for the same interaction.
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Hub> get _filteredHubs {
    final query = _searchController.text.trim().toLowerCase();
    return widget.hubs.where((h) {
      final matchesQuery =
          query.isEmpty || h.name.toLowerCase().contains(query);
      final matchesCategory =
          _selectedCategory == null || h.category == _selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList();
  }

  void _toggleCategory(String category) {
    setState(
      () => _selectedCategory = _selectedCategory == category ? null : category,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredHubs;
    return SingleChildScrollView(
      key: const Key('webHubsScreen'),
      // Top padding keeps content clear of the floating actions cluster (no top bar - see
      // 05_web_ui_updates.md item 1).
      padding: const EdgeInsets.fromLTRB(26, 74, 26, 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search + category filter sit top-left, mirroring the Add/Suggest a Hub button's
          // fixed top-right spot - the two anchor opposite corners of the same row rather
          // than stacking, so neither reads as an afterthought bolted under the other.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        key: const Key('webHubSearchField'),
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search hubs by name',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      // Same "unconditional Row over a virtualizing ListView" choice as
                      // SendBirdDialog's category chips - HubCategory.all is a short fixed
                      // set, so nothing here needs lazy building.
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final category in HubCategory.all)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  key: Key('webHubCategoryChip_$category'),
                                  label: Text(category),
                                  selected: _selectedCategory == category,
                                  onSelected: (_) => _toggleCategory(category),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              OutlinedButton(
                key: const Key('webAddHubButton'),
                onPressed: widget.onStartAddHub,
                style: OutlinedButton.styleFrom(
                  foregroundColor: CroColors.amberInk,
                  side: BorderSide(
                    color: CroColors.deliveryAmber.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Text(widget.isAdmin ? '+ Add a Hub' : '+ Suggest a Hub'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Padding(
              key: const Key('noHubsMessage'),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                widget.hubs.isEmpty
                    ? 'No hubs nearby yet'
                    : 'No hubs match your search',
                style: CroTextStyles.data(size: 13.5),
              ),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 3.2,
              children: [
                for (final hub in filtered)
                  _HubCard(
                    hub: hub,
                    selected: hub.id == widget.selectedHubId,
                    onTap: () => widget.onSelectHub(hub),
                  ),
              ],
            ),
          if (widget.isAdmin) ...[
            const SizedBox(height: 26),
            Row(
              children: [
                Text('Suggested hubs', style: CroTextStyles.label(size: 13)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: CroColors.deliveryAmber),
                    borderRadius: CroBorders.radiusSmall,
                  ),
                  child: Text('Admin', style: CroTextStyles.stamp()),
                ),
              ],
            ),
            const SizedBox(height: 14),
            HubSuggestionsPanel(
              authState: widget.authState,
              hubService: widget.hubService,
              profileService: widget.profileService,
              onChanged: widget.onDataChanged,
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

  const _HubCard({
    required this.hub,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: CroBorders.radius,
      child: InkWell(
        key: Key('webHubCard_${hub.id}'),
        borderRadius: CroBorders.radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: CroBorders.radius,
            border: Border.all(
              color: selected ? CroColors.deliveryAmber : CroColors.hairline,
              width: selected ? 1.5 : 1,
            ),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'VIEW BOARD →',
                style: CroTextStyles.label(
                  size: 10,
                  color: CroColors.deepWaypoint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
