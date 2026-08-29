import '../../models/bird.dart';
import '../../models/friend_request.dart';
import '../../models/waypoint.dart';

/// Which top-level screen the icon rail has selected.
enum WebNavItem { map, nests, hubs, friends, you }

/// What the right-hand context panel is currently showing.
enum PanelMode { journeyLog, nest, hub, bird }

/// The "Your birds" dock's All/Away/Home filter chips.
enum DockFilter { all, away, home }

/// Pure, stateless derived-value helpers shared across the shell - deliberately not a
/// state store itself (no fields, nothing mutable). Kept separate from
/// WebShellScreen/YourBirdsDock so the same badge-count logic the icon rail's Nests/Friends
/// badges need can't silently drift from whatever the dock/nests screen count separately.
class WebShellController {
  const WebShellController._();

  /// "n waiting" - idle, unread birds currently resident at one of the caller's own nests.
  /// Drives both the Nests rail badge and (eventually) each nest card's own badge.
  static int nestsBadgeCount(List<Waypoint> ownNests, List<Bird> birds) {
    final ownNestIds = ownNests.map((n) => n.id).toSet();
    return birds
        .where((b) => !b.isTraveling && !b.isRead && ownNestIds.contains(b.currentNestId))
        .length;
  }

  /// Incoming friend-request count - drives the Friends rail badge.
  static int friendsBadgeCount(List<FriendRequest> incoming) => incoming.length;
}
