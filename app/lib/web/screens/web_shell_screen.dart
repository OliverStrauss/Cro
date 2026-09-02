import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/bird.dart';
import '../../models/friend_bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../services/bird_reaction_service.dart';
import '../../services/bird_service.dart';
import '../../services/friends_service.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../widgets/compose_bird_dialog.dart';
import '../../widgets/hub_name_dialog.dart';
import '../../widgets/send_bird_dialog.dart';
import '../../widgets/waypoint_name_dialog.dart';
import '../models/event.dart';
import '../services/event_service.dart';
import '../state/web_shell_controller.dart';
import '../state/web_shell_data.dart';
import '../widgets/compose_bird_modal.dart';
import '../widgets/context_panel.dart';
import '../widgets/floating_actions_cluster.dart';
import '../widgets/icon_rail.dart';
import '../widgets/your_birds_dock.dart';
import 'web_friends_screen.dart';
import 'web_hubs_screen.dart';
import 'web_map_screen.dart';
import 'web_nests_screen.dart';
import 'web_you_screen.dart';

// Same cap as the phone app's birds_screen.dart - enforced server-side too, but mirrored
// here so the web compose entry points (dock's "Add bird" card, floating compose action)
// can short-circuit with a toast instead of a round-trip error.
const _maxBirdsPerUser = 5;

/// Top-level widget for the app's single UI (rail + content + floating actions cluster +
/// dock + right panel), used unconditionally on every platform, selected in main.dart.
/// There is no top bar: the floating actions cluster (journey log / bell) and the dock both
/// overlay the content column instead (see 05_web_ui_updates.md item 1). Every network-backed
/// piece of state (nests, birds, hubs, friends, notifications) lives in WebShellData, a
/// ChangeNotifier this widget just listens to and rebuilds on - this class only owns pure UI
/// state (nav selection, panel selection, dock filter/expanded, add-nest/add-hub flags) with
/// plain setState, plus the dialogs/snackbars that need a BuildContext.
class WebShellScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService? waypointService;
  final FriendsService? friendsService;
  final BirdService? birdService;
  final HubService? hubService;
  final ProfileService? profileService;
  final EventService? eventService;
  final BirdReactionService? reactionService;

  const WebShellScreen({
    super.key,
    required this.authState,
    this.waypointService,
    this.friendsService,
    this.birdService,
    this.hubService,
    this.profileService,
    this.eventService,
    this.reactionService,
  });

  @override
  State<WebShellScreen> createState() => WebShellScreenState();
}

class WebShellScreenState extends State<WebShellScreen> {
  late final WebShellData _data = WebShellData(
    authState: widget.authState,
    waypointService: widget.waypointService,
    friendsService: widget.friendsService,
    birdService: widget.birdService,
    hubService: widget.hubService,
    profileService: widget.profileService,
    eventService: widget.eventService,
    reactionService: widget.reactionService,
  );

  WebNavItem _selectedNav = WebNavItem.map;
  PanelMode? _panelMode;
  Waypoint? _selectedNest;
  bool _selectedNestIsOwn = false;
  Hub? _selectedHub;
  Bird? _selectedBird;
  FriendBird? _selectedFriendBird;

  DockFilter _dockFilter = DockFilter.all;
  bool _dockExpanded = false;
  // Hidden/shown is independent of expanded/less-detail (05_web_ui_updates.md item 7) - a
  // per-session choice, not persisted, same as every other piece of shell UI state here.
  bool _dockHidden = false;
  bool _addingNest = false;
  bool _addingHub = false;

  final _dockKey = GlobalKey();
  double _dockHeight = 132;

  @override
  void initState() {
    super.initState();
    _data.addListener(_onDataChanged);
    _data.onNewNotification = _showNotificationToast;
    _data.load();
    _data.startPolling();
  }

  @override
  void dispose() {
    _data.removeListener(_onDataChanged);
    _data.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  void _selectNav(WebNavItem item) => setState(() => _selectedNav = item);

  void _selectNest(Waypoint nest) {
    setState(() {
      // The panel only ever renders on the Map tab now (it floats over the map itself) -
      // a selection made from elsewhere (the Nests screen, the dock) jumps there so the
      // panel it opens is actually visible.
      _selectedNav = WebNavItem.map;
      _panelMode = PanelMode.nest;
      _selectedNest = nest;
      _selectedNestIsOwn = _data.ownNests.any((n) => n.id == nest.id);
      _selectedHub = null;
      _selectedBird = null;
      _selectedFriendBird = null;
    });
  }

  void _selectHub(Hub hub) {
    setState(() {
      _selectedNav = WebNavItem.map;
      _panelMode = PanelMode.hub;
      _selectedHub = hub;
      _selectedNest = null;
      _selectedBird = null;
      _selectedFriendBird = null;
    });
    if ((_data.hubUnreadCounts[hub.id] ?? 0) > 0) _data.markHubRead(hub.id);
  }

  void _selectBird(Bird bird) {
    setState(() {
      _selectedNav = WebNavItem.map;
      _panelMode = PanelMode.bird;
      _selectedBird = bird;
      _selectedNest = null;
      _selectedHub = null;
      _selectedFriendBird = null;
    });
  }

  void _selectFriendBird(FriendBird bird) {
    setState(() {
      _selectedNav = WebNavItem.map;
      _panelMode = PanelMode.friendBird;
      _selectedFriendBird = bird;
      _selectedNest = null;
      _selectedHub = null;
      _selectedBird = null;
    });
    // Only a public bird's marker is tappable at all (see WebMapScreen), so this is never
    // called for a private one - no guard needed here.
    if (!bird.hasViewed) _markFriendBirdViewed(bird);
  }

  Future<void> _markFriendBirdViewed(FriendBird bird) async {
    await _data.markFriendBirdViewed(bird);
    if (!mounted) return;
    final updated = _data.friendsBirds.where((b) => b.id == bird.id).firstOrNull;
    if (updated != null && _selectedFriendBird?.id == bird.id) {
      setState(() => _selectedFriendBird = updated);
    }
  }

  void _closePanel() {
    setState(() {
      _panelMode = null;
      _selectedNest = null;
      _selectedHub = null;
      _selectedBird = null;
      _selectedFriendBird = null;
    });
  }

  // notifications minus FriendRequestReceived - that kind exists purely to drive the toast
  // above and the timeline; the dropdown itself shows the same pending request via
  // incomingRequests (see build()'s FloatingActionsCluster) with richer UI already.
  List<AppEvent> get _dropdownNotifications =>
      _data.notifications.where((n) => n.kind != EventKind.friendRequestReceived).toList();

  void _showNotificationToast(AppEvent notification) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(notification.displayText),
        action: SnackBarAction(label: 'View', onPressed: () => _openNotification(notification)),
      ),
    );
  }

  Future<void> _openNotification(AppEvent notification) async {
    await _data.markNotificationRead(notification.id);
    if (!mounted) return;

    if (notification.targetType == EventTargetType.nest && notification.targetId != null) {
      final nest = _data.ownNests.where((n) => n.id == notification.targetId).firstOrNull;
      if (nest != null) _selectNest(nest);
    } else if (notification.targetType == EventTargetType.bird && notification.targetId != null) {
      final bird = _data.birds.where((b) => b.id == notification.targetId).firstOrNull;
      if (bird != null) _selectBird(bird);
    } else {
      _selectNav(WebNavItem.friends);
    }
  }

  void _startAddNest() {
    setState(() {
      _addingNest = true;
      _addingHub = false;
      _selectedNav = WebNavItem.map;
    });
  }

  void _cancelAddNest() => setState(() => _addingNest = false);

  void _startAddHub() {
    setState(() {
      _addingHub = true;
      _addingNest = false;
      _selectedNav = WebNavItem.map;
    });
  }

  void _cancelAddHub() => setState(() => _addingHub = false);

  Future<void> _placeHub(LatLng point) async {
    setState(() => _addingHub = false);
    final result = await showDialog<HubNameDialogResult>(
      context: context,
      builder: (context) => const HubNameDialog(),
    );
    if (result == null || result.name.trim().isEmpty || !mounted) return;

    try {
      final wasSuggestion = await _data.placeHub(
        latitude: point.latitude,
        longitude: point.longitude,
        name: result.name.trim(),
        category: result.category,
      );
      if (wasSuggestion && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent to admins for review')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _placeNest(LatLng point) async {
    setState(() => _addingNest = false);

    if (_data.ownNests.isNotEmpty) {
      try {
        await _data.moveNest(point);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
      return;
    }

    final name = await showDialog<String>(
      context: context,
      builder: (context) => const WaypointNameDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    try {
      await _data.createNest(point, name.trim());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  void _onComposePressed() {
    if (_data.birds.length >= _maxBirdsPerUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You have the max $_maxBirdsPerUser birds. Delete one from your private nest first.')),
      );
      return;
    }
    final origins = _data.ownNests.map((w) => SendBirdDestination(nestId: w.id, label: w.name)).toList();
    if (origins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Create a nest first - a new bird needs somewhere to depart from.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    final destinations = [
      ..._data.ownNests.map((w) => SendBirdDestination(nestId: w.id, label: w.name)),
      ..._data.friendWaypoints.map((w) => SendBirdDestination(nestId: w.id, label: '${w.name} (${w.username})')),
      ..._data.hubs.map((h) => SendBirdDestination(nestId: h.id, label: '${h.name} (Hub)')),
    ];

    ComposeBirdModal.show(
      context,
      origins: origins,
      destinations: destinations,
      onSubmit: _submitCompose,
    );
  }

  Future<void> _submitCompose(ComposeBirdResult result) async {
    try {
      await _data.submitCompose(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${result.name} is on its way')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final measured = _dockKey.currentContext?.size?.height;
      if (measured != null && measured != _dockHeight && mounted) {
        setState(() => _dockHeight = measured);
      }
    });

    if (_data.isLoading) {
      return const Scaffold(body: Center(key: Key('webShellLoading'), child: CircularProgressIndicator()));
    }
    if (_data.errorMessage != null) {
      return Scaffold(
        body: Center(
          key: const Key('webShellError'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_data.errorMessage!),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _data.load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          IconRail(
            selected: _selectedNav,
            onSelect: _selectNav,
            nestsBadge: WebShellController.nestsBadgeCount(_data.nestResidentsByNestId),
            friendsBadge: WebShellController.friendsBadgeCount(_data.incomingRequests),
            profilePictureUrl: _data.profilePictureUrl,
            initialsSource: _data.username,
            onAvatarTap: () => _selectNav(WebNavItem.you),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildActiveScreen()),
                Positioned(
                  top: 18,
                  right: 22,
                  child: FloatingActionsCluster(
                    // FriendRequestReceived events drive the toast (see onNewNotification
                    // above) but are excluded here - incomingRequests already renders that
                    // exact pending request as its own dropdown row, so showing both would
                    // duplicate it.
                    unreadCount: _dropdownNotifications.where((n) => !n.isRead).length,
                    notifications: _dropdownNotifications,
                    onMarkAllRead: _data.markAllNotificationsRead,
                    onOpenNotification: _openNotification,
                    friends: _data.friends,
                    incomingRequests: _data.incomingRequests,
                    onOpenFriendRequest: (_) => _selectNav(WebNavItem.friends),
                    events: _data.events,
                    eventsLoading: false,
                    eventsError: null,
                    onRetryEvents: _data.load,
                  ),
                ),
                // Floats directly over the map instead of sitting in its own Row column, so
                // the map stays visible around/behind it rather than a grey Scaffold body
                // showing through below a content-hugged panel - and only on the Map tab
                // itself, since a nest/hub/bird selection is only ever made from the map.
                if (_selectedNav == WebNavItem.map && _panelMode != null)
                  Positioned(
                    top: 90,
                    right: 22,
                    child: ConstrainedBox(
                      // Loose (not tight) max, so the panel still hugs shorter content -
                      // Positioned itself would force an exact fill if both top and bottom
                      // were pinned instead.
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 90 - _dockHeight - 20),
                      child: ContextPanel(
                        mode: _panelMode!,
                        selectedNest: _selectedNest,
                        selectedNestIsOwn: _selectedNestIsOwn,
                        selectedHub: _selectedHub,
                        selectedBird: _selectedBird,
                        selectedFriendBird: _selectedFriendBird,
                        ownBirds: _data.birds,
                        ownNests: _data.ownNests,
                        friendWaypoints: _data.friendWaypoints,
                        hubs: _data.hubs,
                        onClose: _closePanel,
                        authState: widget.authState,
                        waypointService: _data.waypointService,
                        friendsService: _data.friendsService,
                        birdService: _data.birdService,
                        hubService: _data.hubService,
                        profileService: _data.profileService,
                        reactionService: _data.reactionService,
                        onDataChanged: _data.load,
                        onFollowOnMap: () => _selectNav(WebNavItem.map),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: YourBirdsDock(
                    key: _dockKey,
                    birds: _data.birds,
                    ownNests: _data.ownNests,
                    friendWaypoints: _data.friendWaypoints,
                    hubs: _data.hubs,
                    filter: _dockFilter,
                    onFilterChanged: (f) => setState(() => _dockFilter = f),
                    expanded: _dockExpanded,
                    onToggleExpanded: () => setState(() => _dockExpanded = !_dockExpanded),
                    hidden: _dockHidden,
                    onHide: () => setState(() => _dockHidden = true),
                    onShow: () => setState(() => _dockHidden = false),
                    onBirdTap: _selectBird,
                    onComposePressed: _onComposePressed,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveScreen() {
    switch (_selectedNav) {
      case WebNavItem.map:
        return WebMapScreen(
          ownNests: _data.ownNests,
          friendWaypoints: _data.friendWaypoints,
          birds: _data.birds,
          friendsBirds: _data.friendsBirds,
          hubs: _data.hubs,
          friends: _data.friends,
          hubUnreadCounts: _data.hubUnreadCounts,
          nestResidentsByNestId: _data.nestResidentsByNestId,
          selectedNestId: _selectedNest?.id,
          selectedHubId: _selectedHub?.id,
          selectedBirdId: _selectedBird?.id ?? _selectedFriendBird?.id,
          bottomInset: _dockHeight,
          onSelectNest: _selectNest,
          onSelectHub: _selectHub,
          onSelectBird: _selectBird,
          onSelectFriendBird: _selectFriendBird,
          addingNest: _addingNest,
          onPlaceNest: _placeNest,
          onCancelAddNest: _cancelAddNest,
          isAdmin: _data.isAdmin,
          addingHub: _addingHub,
          onPlaceHub: _placeHub,
          onCancelAddHub: _cancelAddHub,
        );
      case WebNavItem.nests:
        return WebNestsScreen(
          ownNests: _data.ownNests,
          friendWaypoints: _data.friendWaypoints,
          nestResidentsByNestId: _data.nestResidentsByNestId,
          selectedNestId: _selectedNest?.id,
          onSelectNest: _selectNest,
          onStartAddNest: _startAddNest,
          authState: widget.authState,
          waypointService: _data.waypointService,
          onDataChanged: _data.load,
        );
      case WebNavItem.hubs:
        return WebHubsScreen(
          hubs: _data.hubs,
          isAdmin: _data.isAdmin,
          selectedHubId: _selectedHub?.id,
          onSelectHub: _selectHub,
          authState: widget.authState,
          hubService: _data.hubService,
          profileService: _data.profileService,
          onDataChanged: _data.load,
          onStartAddHub: _startAddHub,
        );
      case WebNavItem.friends:
        return WebFriendsScreen(
          authState: widget.authState,
          friendsService: _data.friendsService,
          friendWaypoints: _data.friendWaypoints,
          isAdmin: _data.isAdmin,
          onDataChanged: _data.load,
        );
      case WebNavItem.you:
        return WebYouScreen(
          authState: widget.authState,
          profileService: _data.profileService,
          username: _data.username,
          profilePictureUrl: _data.profilePictureUrl,
          isAdmin: _data.isAdmin,
          birdCount: _data.birds.length,
          nestCount: _data.ownNests.length,
          friendCount: _data.friends.length,
          events: _data.events,
          onDataChanged: _data.load,
          onNavigateFriends: () => _selectNav(WebNavItem.friends),
          onNavigateHubs: () => _selectNav(WebNavItem.hubs),
        );
    }
  }
}
