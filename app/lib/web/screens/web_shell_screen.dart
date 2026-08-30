import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/bird.dart';
import '../../models/friend_bird.dart';
import '../../models/friend_request.dart';
import '../../models/hub.dart';
import '../../models/user_profile.dart';
import '../../models/waypoint.dart';
import '../../services/bird_service.dart';
import '../../services/friends_service.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/jwt_utils.dart';
import '../../widgets/waypoint_name_dialog.dart';
import '../models/event.dart';
import '../services/event_service.dart';
import '../state/web_shell_controller.dart';
import '../widgets/context_panel.dart';
import '../widgets/icon_rail.dart';
import '../widgets/top_bar.dart';
import '../widgets/your_birds_dock.dart';
import 'web_hubs_screen.dart';
import 'web_map_screen.dart';
import 'web_nests_screen.dart';

/// Top-level widget for the web shell (rail + top bar + content + dock + right panel) - the
/// kIsWeb-gated sibling to the phone HomeScreen, selected in main.dart. Owns every piece of
/// shell state (nav selection, panel selection, dock filter/expanded, map filter) the same
/// way HomeScreen owns tab selection: one StatefulWidget, plain setState, no state-mgmt
/// package (none exists anywhere else in this codebase).
class WebShellScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService? waypointService;
  final FriendsService? friendsService;
  final BirdService? birdService;
  final HubService? hubService;
  final ProfileService? profileService;
  final EventService? eventService;

  const WebShellScreen({
    super.key,
    required this.authState,
    this.waypointService,
    this.friendsService,
    this.birdService,
    this.hubService,
    this.profileService,
    this.eventService,
  });

  @override
  State<WebShellScreen> createState() => WebShellScreenState();
}

class WebShellScreenState extends State<WebShellScreen> {
  late final WaypointService _waypointService = widget.waypointService ?? WaypointService();
  late final FriendsService _friendsService = widget.friendsService ?? FriendsService();
  late final BirdService _birdService = widget.birdService ?? BirdService();
  late final HubService _hubService = widget.hubService ?? HubService();
  late final ProfileService _profileService = widget.profileService ?? ProfileService();
  late final EventService _eventService = widget.eventService ?? EventService();

  WebNavItem _selectedNav = WebNavItem.map;
  PanelMode _panelMode = PanelMode.journeyLog;
  Waypoint? _selectedNest;
  bool _selectedNestIsOwn = false;
  Hub? _selectedHub;
  Bird? _selectedBird;

  DockFilter _dockFilter = DockFilter.all;
  bool _dockExpanded = false;
  MapFilter _mapFilter = MapFilter.all;
  bool _addingNest = false;

  final _dockKey = GlobalKey();
  double _dockHeight = 132;

  List<Waypoint> _ownNests = [];
  List<Waypoint> _friendWaypoints = [];
  List<Bird> _birds = [];
  List<FriendBird> _friendsBirds = [];
  List<Hub> _hubs = [];
  List<FriendRequest> _incomingRequests = [];
  List<AppEvent> _events = [];
  List<AppEvent> _notifications = [];
  String _username = '';
  String? _profilePictureUrl;
  bool _isAdmin = false;
  // Every own nest's current residents (idle birds, including ones delivered by someone
  // else) - GET /birds alone can't see deliveries from other senders, so this is a separate
  // per-nest fetch, same reasoning as the phone app's NestDetailsSheet. Small N (a user has
  // at most 2 nests), fetched alongside everything else in _loadData.
  Map<String, List<Bird>> _nestResidentsByNestId = {};

  bool _isLoading = true;
  String? _errorMessage;
  Timer? _liveUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Unlike the phone app's MapScreen (which needs explicit start/stop hooks because
    // IndexedStack keeps every tab alive across switches), the web shell only ever mounts
    // one content screen at a time and the dock/journey log are always visible regardless
    // of which nav item is selected - so polling can just run for the shell's whole
    // lifetime instead of being tied to a specific tab's visibility.
    _liveUpdateTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshBirds());
  }

  @override
  void dispose() {
    _liveUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshBirds() async {
    try {
      final token = widget.authState.token!;
      final results = await Future.wait([
        _birdService.listBirds(token),
        _friendsService.getFriendsBirds(token),
      ]);
      if (!mounted) return;
      setState(() {
        _birds = results[0] as List<Bird>;
        _friendsBirds = results[1] as List<FriendBird>;
      });
    } catch (_) {
      // Swallow - same "a blip on a silent background poll shouldn't blank an
      // already-rendered screen" reasoning as the phone MapScreen.
    }
  }

  Future<void> refresh() => _loadData();

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final userId = jwtSubject(token);
      final results = await Future.wait([
        _waypointService.listWaypoints(token),
        _friendsService.getFriendsWaypoints(token),
        _birdService.listBirds(token),
        _friendsService.getFriendsBirds(token),
        _hubService.listHubs(token),
        _friendsService.getIncomingRequests(token),
        _eventService.listEvents(token),
        _eventService.listNotifications(token),
        if (userId != null) _profileService.getUser(userId),
      ]);
      setState(() {
        _ownNests = results[0] as List<Waypoint>;
        _friendWaypoints = results[1] as List<Waypoint>;
        _birds = results[2] as List<Bird>;
        _friendsBirds = results[3] as List<FriendBird>;
        _hubs = results[4] as List<Hub>;
        _incomingRequests = results[5] as List<FriendRequest>;
        _events = results[6] as List<AppEvent>;
        _notifications = results[7] as List<AppEvent>;
        if (results.length > 8) {
          final profile = results[8] as UserProfile;
          _username = profile.username;
          _profilePictureUrl = profile.profilePictureUrl;
          _isAdmin = profile.isAdmin;
        }
      });
      await _loadNestResidents(token);
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNestResidents(String token) async {
    final residentLists = await Future.wait(_ownNests.map((n) => _birdService.getNestResidents(token, n.id)));
    if (!mounted) return;
    setState(() {
      _nestResidentsByNestId = {
        for (var i = 0; i < _ownNests.length; i++) _ownNests[i].id: residentLists[i],
      };
    });
  }

  void _selectNav(WebNavItem item) => setState(() => _selectedNav = item);

  void _selectNest(Waypoint nest) {
    setState(() {
      _panelMode = PanelMode.nest;
      _selectedNest = nest;
      _selectedNestIsOwn = _ownNests.any((n) => n.id == nest.id);
      _selectedHub = null;
      _selectedBird = null;
    });
  }

  void _selectHub(Hub hub) {
    setState(() {
      _panelMode = PanelMode.hub;
      _selectedHub = hub;
      _selectedNest = null;
      _selectedBird = null;
    });
  }

  void _selectBird(Bird bird) {
    setState(() {
      _panelMode = PanelMode.bird;
      _selectedBird = bird;
      _selectedNest = null;
      _selectedHub = null;
    });
  }

  void _closePanel() {
    setState(() {
      _panelMode = PanelMode.journeyLog;
      _selectedNest = null;
      _selectedHub = null;
      _selectedBird = null;
    });
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      await _eventService.markAllNotificationsRead(widget.authState.token!);
      setState(() {
        _notifications = [for (final n in _notifications) _markRead(n)];
      });
    } catch (_) {
      // Best-effort from the UI's perspective too - a failed mark-read isn't worth
      // surfacing an error state over; the next full reload will reconcile it anyway.
    }
  }

  AppEvent _markRead(AppEvent n) => AppEvent(
    id: n.id,
    kind: n.kind,
    displayText: n.displayText,
    quotedNote: n.quotedNote,
    targetType: n.targetType,
    targetId: n.targetId,
    isNotification: n.isNotification,
    isRead: true,
    createdAt: n.createdAt,
  );

  Future<void> _openNotification(AppEvent notification) async {
    try {
      await _eventService.markNotificationRead(widget.authState.token!, notification.id);
    } catch (_) {
      // Non-fatal - still route even if the mark-read call itself failed.
    }
    if (!mounted) return;
    setState(() {
      _notifications = [for (final n in _notifications) n.id == notification.id ? _markRead(n) : n];
    });

    if (notification.targetType == EventTargetType.nest && notification.targetId != null) {
      final nest = _ownNests.where((n) => n.id == notification.targetId).firstOrNull;
      if (nest != null) _selectNest(nest);
    } else if (notification.targetType == EventTargetType.bird && notification.targetId != null) {
      final bird = _birds.where((b) => b.id == notification.targetId).firstOrNull;
      if (bird != null) _selectBird(bird);
    } else {
      _selectNav(WebNavItem.friends);
    }
  }

  void _startAddNest() {
    setState(() {
      _addingNest = true;
      _selectedNav = WebNavItem.map;
    });
  }

  void _cancelAddNest() => setState(() => _addingNest = false);

  Future<void> _placeNest(LatLng point) async {
    setState(() => _addingNest = false);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const WaypointNameDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    try {
      // A user's first nest is their private one; a second is the public one - same
      // one-private-one-public cap the server enforces (see WaypointService.CreateAsync).
      final isPublic = _ownNests.any((n) => !n.isPublic);
      await _waypointService.createWaypoint(
        widget.authState.token!,
        name: name.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
        isPublic: isPublic,
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  void _onComposePressed() {
    // The compose modal lands in a later PR alongside the rest of the notification/reaction
    // wiring - a placeholder toast keeps the button from feeling dead in the meantime.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Compose is coming in the next update')),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final measured = _dockKey.currentContext?.size?.height;
      if (measured != null && measured != _dockHeight && mounted) {
        setState(() => _dockHeight = measured);
      }
    });

    if (_isLoading) {
      return const Scaffold(body: Center(key: Key('webShellLoading'), child: CircularProgressIndicator()));
    }
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          key: const Key('webShellError'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final titles = switch (_selectedNav) {
      WebNavItem.map => ('Map', 'Everything your flock can reach'),
      WebNavItem.nests => ('Nests', 'Your roosts and the ones your friends keep'),
      WebNavItem.hubs => ('Hubs', 'Public landmarks with a shared board'),
      WebNavItem.friends => ('Friends', 'Who you can send to, and who is asking'),
      WebNavItem.you => ('You', 'Your keeper account'),
    };

    return Scaffold(
      body: Row(
        children: [
          IconRail(
            selected: _selectedNav,
            onSelect: _selectNav,
            nestsBadge: WebShellController.nestsBadgeCount(_nestResidentsByNestId),
            friendsBadge: WebShellController.friendsBadgeCount(_incomingRequests),
            profilePictureUrl: _profilePictureUrl,
            initialsSource: _username,
            onAvatarTap: () => _selectNav(WebNavItem.you),
          ),
          Expanded(
            child: Column(
              children: [
                TopBar(
                  title: titles.$1,
                  subtitle: titles.$2,
                  unreadCount: _notifications.where((n) => !n.isRead).length,
                  notifications: _notifications,
                  onComposePressed: _onComposePressed,
                  onMarkAllRead: _markAllNotificationsRead,
                  onOpenNotification: _openNotification,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildActiveScreen()),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: YourBirdsDock(
                          key: _dockKey,
                          birds: _birds,
                          ownNests: _ownNests,
                          friendWaypoints: _friendWaypoints,
                          hubs: _hubs,
                          filter: _dockFilter,
                          onFilterChanged: (f) => setState(() => _dockFilter = f),
                          expanded: _dockExpanded,
                          onToggleExpanded: () => setState(() => _dockExpanded = !_dockExpanded),
                          onBirdTap: _selectBird,
                          onComposePressed: _onComposePressed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ContextPanel(
            mode: _panelMode,
            selectedNest: _selectedNest,
            selectedNestIsOwn: _selectedNestIsOwn,
            selectedHub: _selectedHub,
            selectedBird: _selectedBird,
            onClose: _closePanel,
            events: _events,
            eventsLoading: false,
            eventsError: null,
            onRetryEvents: _loadData,
            authState: widget.authState,
            waypointService: _waypointService,
            friendsService: _friendsService,
            birdService: _birdService,
            hubService: _hubService,
            profileService: _profileService,
            onDataChanged: _loadData,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveScreen() {
    switch (_selectedNav) {
      case WebNavItem.map:
        return WebMapScreen(
          ownNests: _ownNests,
          friendWaypoints: _friendWaypoints,
          birds: _birds,
          friendsBirds: _friendsBirds,
          hubs: _hubs,
          selectedNestId: _selectedNest?.id,
          selectedHubId: _selectedHub?.id,
          bottomInset: _dockHeight,
          filter: _mapFilter,
          onFilterChanged: (f) => setState(() => _mapFilter = f),
          onSelectNest: _selectNest,
          onSelectHub: _selectHub,
          onSelectBird: _selectBird,
          addingNest: _addingNest,
          onPlaceNest: _placeNest,
          onCancelAddNest: _cancelAddNest,
        );
      case WebNavItem.nests:
        return WebNestsScreen(
          ownNests: _ownNests,
          friendWaypoints: _friendWaypoints,
          nestResidentsByNestId: _nestResidentsByNestId,
          selectedNestId: _selectedNest?.id,
          onSelectNest: _selectNest,
          onStartAddNest: _startAddNest,
          authState: widget.authState,
          waypointService: _waypointService,
          onDataChanged: _loadData,
        );
      case WebNavItem.hubs:
        return WebHubsScreen(
          hubs: _hubs,
          isAdmin: _isAdmin,
          selectedHubId: _selectedHub?.id,
          onSelectHub: _selectHub,
          authState: widget.authState,
          hubService: _hubService,
          profileService: _profileService,
          onDataChanged: _loadData,
        );
      case WebNavItem.friends:
      case WebNavItem.you:
        final label = _selectedNav == WebNavItem.friends ? 'Friends' : 'You';
        return SingleChildScrollView(
          key: Key('webPlaceholder_$label'),
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 240),
          child: Text(
            '$label is coming in the next update.',
            style: const TextStyle(fontSize: 14, color: CroColors.fog),
          ),
        );
    }
  }
}
