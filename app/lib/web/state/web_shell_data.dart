import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../models/bird.dart';
import '../../models/friend.dart';
import '../../models/friend_bird.dart';
import '../../models/friend_request.dart';
import '../../models/hub.dart';
import '../../models/user_profile.dart';
import '../../models/waypoint.dart';
import '../../services/bird_reaction_service.dart';
import '../../services/bird_service.dart';
import '../../services/friends_service.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../utils/jwt_utils.dart';
import '../../widgets/compose_bird_dialog.dart';
import '../models/event.dart';
import '../services/event_service.dart';

/// Owns every network-backed piece of the web shell's state (nests, birds, hubs, friends,
/// notifications, the caller's own profile) plus the mutations that touch them - everything
/// WebShellScreen used to hold and mutate via setState directly. A ChangeNotifier, same
/// pattern AuthState already uses elsewhere in this codebase (no state-mgmt package exists
/// here), so WebShellScreen just listens and rebuilds instead of owning this data itself.
/// UI-only concerns (nav/panel selection, dock layout, add-nest/add-hub flags, dialogs,
/// snackbars) stay on WebShellScreen - this class never touches BuildContext.
class WebShellData extends ChangeNotifier {
  WebShellData({
    required this.authState,
    WaypointService? waypointService,
    FriendsService? friendsService,
    BirdService? birdService,
    HubService? hubService,
    ProfileService? profileService,
    EventService? eventService,
    BirdReactionService? reactionService,
  }) : waypointService = waypointService ?? WaypointService(),
       friendsService = friendsService ?? FriendsService(),
       birdService = birdService ?? BirdService(),
       hubService = hubService ?? HubService(),
       profileService = profileService ?? ProfileService(),
       eventService = eventService ?? EventService(),
       reactionService = reactionService ?? BirdReactionService();

  final AuthState authState;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final BirdService birdService;
  final HubService hubService;
  final ProfileService profileService;
  final EventService eventService;
  final BirdReactionService reactionService;

  List<Waypoint> ownNests = [];
  List<Waypoint> friendWaypoints = [];
  List<Bird> birds = [];
  List<FriendBird> friendsBirds = [];
  List<Hub> hubs = [];
  // Keyed by hubId - drives the "!" badge on a Hub's map marker (see WebMapScreen). Mirrors
  // the phone app's MapScreen._hubUnreadCounts.
  Map<String, int> hubUnreadCounts = {};
  List<FriendRequest> incomingRequests = [];
  List<Friend> friends = [];
  List<AppEvent> events = [];
  List<AppEvent> notifications = [];
  String username = '';
  String? profilePictureUrl;
  bool isAdmin = false;
  // Every own nest's current residents (idle birds, including ones delivered by someone
  // else) - GET /birds alone can't see deliveries from other senders, so this is a separate
  // per-nest fetch, same reasoning as the phone app's NestDetailsSheet. Small N (a user has
  // at most 1 nest), fetched alongside everything else in load().
  Map<String, List<Bird>> nestResidentsByNestId = {};

  bool isLoading = true;
  String? errorMessage;

  Timer? _liveUpdateTimer;
  bool _disposed = false;

  void startPolling() {
    // Unlike the phone app's MapScreen (which needs explicit start/stop hooks because
    // IndexedStack keeps every tab alive across switches), the web shell only ever mounts
    // one content screen at a time and the dock/journey log are always visible regardless
    // of which nav item is selected - so polling can just run for the shell's whole
    // lifetime instead of being tied to a specific tab's visibility.
    _liveUpdateTimer = Timer.periodic(const Duration(seconds: 3), (_) => refreshBirds());
  }

  @override
  void dispose() {
    _disposed = true;
    _liveUpdateTimer?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshBirds() async {
    try {
      final token = authState.token!;
      final results = await Future.wait([
        birdService.listBirds(token),
        friendsService.getFriendsBirds(token),
        hubService.getUnreadCounts(token),
      ]);
      if (_disposed) return;
      birds = results[0] as List<Bird>;
      friendsBirds = results[1] as List<FriendBird>;
      hubUnreadCounts = results[2] as Map<String, int>;
      _notify();
    } catch (_) {
      // Swallow - same "a blip on a silent background poll shouldn't blank an
      // already-rendered screen" reasoning as the phone MapScreen.
    }
  }

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    _notify();

    try {
      final token = authState.token!;
      final userId = jwtSubject(token);
      final results = await Future.wait([
        waypointService.listWaypoints(token),
        friendsService.getFriendsWaypoints(token),
        birdService.listBirds(token),
        friendsService.getFriendsBirds(token),
        hubService.listHubs(token),
        hubService.getUnreadCounts(token),
        friendsService.getIncomingRequests(token),
        eventService.listEvents(token),
        eventService.listNotifications(token),
        friendsService.getFriends(token),
        if (userId != null) profileService.getUser(userId),
      ]);
      ownNests = results[0] as List<Waypoint>;
      friendWaypoints = results[1] as List<Waypoint>;
      birds = results[2] as List<Bird>;
      friendsBirds = results[3] as List<FriendBird>;
      hubs = results[4] as List<Hub>;
      hubUnreadCounts = results[5] as Map<String, int>;
      incomingRequests = results[6] as List<FriendRequest>;
      events = results[7] as List<AppEvent>;
      notifications = results[8] as List<AppEvent>;
      friends = results[9] as List<Friend>;
      if (results.length > 10) {
        final profile = results[10] as UserProfile;
        username = profile.username;
        profilePictureUrl = profile.profilePictureUrl;
        isAdmin = profile.isAdmin;
      }
      _notify();
      await _loadNestResidents(token);
      if (_disposed) return;
      isLoading = false;
      _notify();
    } catch (e) {
      errorMessage = e.toString();
      isLoading = false;
      _notify();
    }
  }

  Future<void> _loadNestResidents(String token) async {
    final residentLists = await Future.wait(ownNests.map((n) => birdService.getNestResidents(token, n.id)));
    if (_disposed) return;
    nestResidentsByNestId = {
      for (var i = 0; i < ownNests.length; i++) ownNests[i].id: residentLists[i],
    };
    _notify();
  }

  Future<void> markHubRead(String hubId) async {
    // Optimistic - clear the marker badge immediately rather than waiting on the round trip,
    // same "not worth surfacing an error state over" reasoning as markFriendBirdViewed; the
    // next poll reconciles it either way.
    hubUnreadCounts = {...hubUnreadCounts, hubId: 0};
    _notify();
    try {
      await hubService.markHubRead(authState.token!, hubId);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> markFriendBirdViewed(FriendBird bird) async {
    try {
      await birdService.markBirdViewed(authState.token!, bird.id);
      if (_disposed) return;
      friendsBirds = [for (final b in friendsBirds) b.id == bird.id ? _asViewed(b) : b];
      _notify();
    } catch (_) {
      // Best-effort, same "not worth surfacing an error state over" reasoning as
      // markAllNotificationsRead - the next full reload reconciles it anyway.
    }
  }

  FriendBird _asViewed(FriendBird b) => FriendBird(
    id: b.id,
    userId: b.userId,
    username: b.username,
    color: b.color,
    name: b.name,
    type: b.type,
    nestFromId: b.nestFromId,
    nestToId: b.nestToId,
    departedAt: b.departedAt,
    estimatedArrivalAt: b.estimatedArrivalAt,
    isPublic: b.isPublic,
    content: b.content,
    audioUrl: b.audioUrl,
    imageUrl: b.imageUrl,
    hasViewed: true,
  );

  Future<void> markAllNotificationsRead() async {
    try {
      await eventService.markAllNotificationsRead(authState.token!);
      notifications = [for (final n in notifications) _markRead(n)];
      _notify();
    } catch (_) {
      // Best-effort from the UI's perspective too - a failed mark-read isn't worth
      // surfacing an error state over; the next full reload will reconcile it anyway.
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await eventService.markNotificationRead(authState.token!, notificationId);
    } catch (_) {
      // Non-fatal - still mark it read locally even if the server call failed.
    }
    if (_disposed) return;
    notifications = [for (final n in notifications) n.id == notificationId ? _markRead(n) : n];
    _notify();
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

  /// Creates or suggests a Hub depending on admin status, then reloads. Returns whether it
  /// was submitted as a suggestion (non-admin) rather than created outright, so the caller
  /// can show the "sent to admins" toast without this class touching BuildContext.
  Future<bool> placeHub({
    required double latitude,
    required double longitude,
    required String name,
    required String category,
  }) async {
    final wasSuggestion = !isAdmin;
    if (isAdmin) {
      await hubService.createHub(authState.token!, name: name, latitude: latitude, longitude: longitude, category: category);
    } else {
      await hubService.suggestHub(authState.token!, name: name, latitude: latitude, longitude: longitude, category: category);
    }
    await load();
    return wasSuggestion;
  }

  // A user gets exactly one personal nest, always private now (Hubs are the only public
  // landmark type), enforced server-side by WaypointService.CreateAsync. Once one already
  // exists, placing a new point moves it instead of erroring - see WebShellScreen's
  // add-nest flow, which becomes "Move nest" once ownNests is non-empty but arms the same
  // flow either way.
  Future<void> moveNest(LatLng point) async {
    final existing = ownNests.first;
    await waypointService.updateWaypoint(
      authState.token!,
      existing.id,
      name: existing.name,
      latitude: point.latitude,
      longitude: point.longitude,
    );
    await load();
  }

  Future<void> createNest(LatLng point, String name) async {
    await waypointService.createWaypoint(
      authState.token!,
      name: name,
      latitude: point.latitude,
      longitude: point.longitude,
      isPublic: false,
    );
    await load();
  }

  Future<void> submitCompose(ComposeBirdResult result) async {
    await birdService.composeAndSendBird(
      authState.token!,
      type: result.type,
      name: result.name,
      originNestId: result.originNestId,
      destinationId: result.destinationId,
      content: result.content,
      isPublic: result.isPublic,
      mediaBytes: result.mediaBytes,
      mediaContentType: result.mediaContentType,
      mediaFilename: result.mediaFilename,
    );
    await load();
  }
}
