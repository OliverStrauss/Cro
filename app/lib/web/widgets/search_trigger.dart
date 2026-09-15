import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/hub.dart';
import '../../models/place_search_result.dart';
import '../../models/search_results.dart';
import '../../models/waypoint.dart';
import '../../services/search_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';

/// The search trigger next to the notification bell (see FloatingActionsCluster, its sibling
/// in the same floating top-right row) - finds real-world places (via GET /search's
/// server-side geocoding), Hubs, and Nests, and hands whichever result is picked back to
/// WebShellScreen to pan/zoom the map there (see WebMapScreen.searchLocation for places,
/// the existing onSelectHub/onSelectNest paths for the other two). Uses the same
/// Overlay+LayerLink dropdown mechanism as FloatingActionsCluster's notifications dropdown,
/// for the same reason documented there: a dropdown nested inside this row would otherwise
/// be painted over by the map/dock.
class SearchTrigger extends StatefulWidget {
  final SearchService? searchService;
  final AuthState authState;
  final ValueChanged<PlaceSearchResult> onSelectPlace;
  final ValueChanged<Hub> onSelectHub;
  final ValueChanged<Waypoint> onSelectNest;

  const SearchTrigger({
    super.key,
    this.searchService,
    required this.authState,
    required this.onSelectPlace,
    required this.onSelectHub,
    required this.onSelectNest,
  });

  @override
  State<SearchTrigger> createState() => _SearchTriggerState();
}

class _SearchTriggerState extends State<SearchTrigger> {
  static const _group = 'webTopBarSearch';

  late final SearchService _searchService =
      widget.searchService ?? SearchService();
  final _link = LayerLink();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  OverlayEntry? _entry;
  SearchResults? _results;
  // Bumped on every keystroke so a slower, older request completing after a newer one
  // can't overwrite the dropdown with stale results - see _search.
  int _requestId = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _entry?.remove();
    _debounce?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    _open();
  }

  void _open() {
    _entry = OverlayEntry(
      builder: (context) => Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 10),
          child: TapRegion(
            groupId: _group,
            onTapOutside: (_) => _close(),
            child: _SearchPopup(
              controller: _controller,
              focusNode: _focusNode,
              results: _results,
              onChanged: _onQueryChanged,
              onSelectPlace: (p) {
                _close();
                widget.onSelectPlace(p);
              },
              onSelectHub: (h) {
                _close();
                widget.onSelectHub(h);
              },
              onSelectNest: (n) {
                _close();
                widget.onSelectNest(n);
              },
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    setState(() {});
    _focusNode.requestFocus();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    _controller.clear();
    _results = null;
    _debounce?.cancel();
    // Invalidates any still-in-flight request from before closing, same reason _search
    // checks _requestId before applying a response.
    _requestId++;
    if (mounted) setState(() {});
  }

  void _onQueryChanged(String query) {
    final trimmed = query.trim();
    _debounce?.cancel();
    if (trimmed.isEmpty) {
      _requestId++;
      setState(() => _results = null);
      _entry?.markNeedsBuild();
      return;
    }
    // Matches web_profile_screen.dart's friend search: keeps real traffic under
    // NominatimGeocodingService's ~1req/sec Nominatim cap (see TECH_DEBT.md).
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _search(trimmed),
    );
  }

  Future<void> _search(String query) async {
    final token = widget.authState.token;
    if (token == null) return;
    final requestId = ++_requestId;
    try {
      final results = await _searchService.search(token, query);
      // Discard a response to a keystroke that's no longer the latest one - otherwise a
      // slower earlier request completing after a faster later one would flash stale
      // results back onto the dropdown.
      if (!mounted || requestId != _requestId) return;
      setState(() => _results = results);
      _entry?.markNeedsBuild();
    } catch (_) {
      // A blip on live-as-you-type search isn't worth surfacing - same call
      // web_profile_screen.dart's friend search already makes.
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _entry != null;
    return TapRegion(
      groupId: _group,
      child: CompositedTransformTarget(
        link: _link,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: CroBorders.radius,
            border: Border.all(color: CroColors.hairline),
          ),
          child: Material(
            color: open
                ? CroColors.waypointBlue.withValues(alpha: 0.16)
                : Theme.of(context).colorScheme.surface,
            borderRadius: CroBorders.radius,
            child: InkWell(
              key: const Key('webSearchTrigger'),
              borderRadius: CroBorders.radius,
              onTap: _toggle,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Tooltip(
                  message: 'Search',
                  child: Icon(
                    Icons.search,
                    size: 19,
                    color: open ? CroColors.deepWaypoint : CroColors.fog,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchPopup extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final SearchResults? results;
  final ValueChanged<String> onChanged;
  final ValueChanged<PlaceSearchResult> onSelectPlace;
  final ValueChanged<Hub> onSelectHub;
  final ValueChanged<Waypoint> onSelectNest;

  const _SearchPopup({
    required this.controller,
    required this.focusNode,
    required this.results,
    required this.onChanged,
    required this.onSelectPlace,
    required this.onSelectHub,
    required this.onSelectNest,
  });

  @override
  Widget build(BuildContext context) {
    final hasResults = results != null && !results!.isEmpty;
    return Container(
      width: 340,
      constraints: const BoxConstraints(maxHeight: 420),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: CroBorders.radius,
        border: Border.all(color: CroColors.hairline),
        boxShadow: [
          BoxShadow(
            color: CroColors.ink.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      // The OverlayEntry this sits in has no Scaffold/Material ancestor of its own (Overlay
      // content isn't a descendant of the page's Scaffold) - TextField needs one for its
      // cursor/selection handles, same reason each row below brings its own Material for
      // InkWell.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                key: const Key('webSearchField'),
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                decoration: const InputDecoration(
                  hintText: 'Search places, hubs, nests',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
              ),
            ),
            if (hasResults) ...[
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  key: const Key('webSearchResults'),
                  shrinkWrap: true,
                  children: [
                    if (results!.places.isNotEmpty)
                      const _SearchSection(label: 'Places'),
                    for (var i = 0; i < results!.places.length; i++)
                      _SearchResultRow(
                        key: Key('webSearchResultPlace_$i'),
                        icon: Icons.place_outlined,
                        title: results!.places[i].displayName,
                        onTap: () => onSelectPlace(results!.places[i]),
                      ),
                    if (results!.hubs.isNotEmpty)
                      const _SearchSection(label: 'Hubs'),
                    for (final hub in results!.hubs)
                      _SearchResultRow(
                        key: Key('webSearchResultHub_${hub.id}'),
                        icon: Icons.flag_outlined,
                        title: hub.name,
                        onTap: () => onSelectHub(hub),
                      ),
                    if (results!.nests.isNotEmpty)
                      const _SearchSection(label: 'Nests'),
                    for (final nest in results!.nests)
                      _SearchResultRow(
                        key: Key('webSearchResultNest_${nest.id}'),
                        icon: Icons.home_outlined,
                        title: nest.name,
                        onTap: () => onSelectNest(nest),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchSection extends StatelessWidget {
  final String label;
  const _SearchSection({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        label,
        style: CroTextStyles.label(size: 11, color: CroColors.fog),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _SearchResultRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: CroColors.fog),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
