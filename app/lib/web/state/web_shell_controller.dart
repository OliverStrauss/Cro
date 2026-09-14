import '../../models/bird.dart';
import '../../models/friend_request.dart';

/// Which top-level screen the icon rail has selected.
enum WebNavItem { map, nests, hubs, pinned, profile }

/// What the right-hand context panel is currently showing. The panel itself is only mounted
/// when one of these is selected - there is no "nothing selected" member here. `friendBird`
/// is a friend's public bird (read-only view, distinct from `bird` which is always the
/// caller's own).
enum PanelMode { nest, hub, bird, friendBird, publicBird }

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

  /// Incoming friend-request count - drives the Profile rail badge (Friends is merged into
  /// Profile, so this now rides on that icon instead of its own).
  static int friendsBadgeCount(List<FriendRequest> incoming) => incoming.length;
}
