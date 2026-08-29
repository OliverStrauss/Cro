import '../../models/bird.dart';
import '../../models/friend_request.dart';

/// Which top-level screen the icon rail has selected.
enum WebNavItem { map, nests, hubs, friends, you }

/// What the right-hand context panel is currently showing. The panel itself is only mounted
/// when one of these is selected - there is no "nothing selected" member here; the journey
/// log moved out to a top-bar popup (see JourneyLogPanel/TopBar) and no longer occupies this
/// panel's default state.
enum PanelMode { nest, hub, bird }

/// The "Your birds" dock's All/Away/Home filter chips.
enum DockFilter { all, away, home }

/// Pure, stateless derived-value helpers shared across the shell - deliberately not a
/// state store itself (no fields, nothing mutable). Kept separate from
/// WebShellScreen/YourBirdsDock so the same badge-count logic the icon rail's Nests/Friends
/// badges need can't silently drift from whatever the dock/nests screen count separately.
class WebShellController {
  const WebShellController._();

  /// "n waiting" - unread birds currently resident at one of the caller's own nests,
  /// including ones delivered by someone else (GET /birds alone can't see those - see
  /// WebShellScreen._loadNestResidents). Drives both the Nests rail badge and each nest
  /// card's own badge.
  static int nestsBadgeCount(Map<String, List<Bird>> nestResidentsByNestId) =>
      nestResidentsByNestId.values.expand((birds) => birds).where((b) => !b.isRead).length;

  /// Incoming friend-request count - drives the Friends rail badge.
  static int friendsBadgeCount(List<FriendRequest> incoming) => incoming.length;
}
