import 'package:flutter/material.dart';

import '../../theme.dart';
import '../models/event.dart';
import 'journey_log_panel.dart';

/// The floating top-right action cluster (journey log / notification bell) that replaced
/// the old 70px top bar - see 05_web_ui_updates.md item 1. It's positioned by its caller
/// (WebShellScreen) as an overlay inside the content column's own Stack, so it never overlaps
/// the right-hand context panel the way a full-width header would have. Every screen's
/// title/subtitle and the "Live" polling indicator went away with the bar itself - polling
/// still runs, it's just no longer advertised in the UI. A "Send a bird" button briefly lived
/// here too (matching the design doc), but every screen already has its own compose entry
/// point (the dock's "+" card, the context panel, a nest's resident-bird tiles) so it was
/// just a duplicate - same call the pre-redesign top bar made, restored after seeing it live.
class FloatingActionsCluster extends StatefulWidget {
  final int unreadCount;
  final List<AppEvent> notifications;
  final VoidCallback onMarkAllRead;
  final ValueChanged<AppEvent> onOpenNotification;
  final List<AppEvent> events;
  final bool eventsLoading;
  final String? eventsError;
  final VoidCallback onRetryEvents;

  const FloatingActionsCluster({
    super.key,
    required this.unreadCount,
    required this.notifications,
    required this.onMarkAllRead,
    required this.onOpenNotification,
    required this.events,
    required this.eventsLoading,
    required this.eventsError,
    required this.onRetryEvents,
  });

  @override
  State<FloatingActionsCluster> createState() => _FloatingActionsClusterState();
}

class _FloatingActionsClusterState extends State<FloatingActionsCluster> {
  // Shared between each trigger button and its own popup's TapRegion so pressing a trigger
  // while its popup is already open is handled purely by that button's onTap toggle, rather
  // than also registering as an "outside" tap on its own popup and racing with the toggle.
  static const _notifGroup = 'webTopBarNotifications';
  static const _journeyGroup = 'webTopBarJourneyLog';

  final _bellLink = LayerLink();
  final _journeyLink = LayerLink();
  OverlayEntry? _dropdownEntry;
  OverlayEntry? _journeyEntry;

  @override
  void didUpdateWidget(covariant FloatingActionsCluster oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep an already-open dropdown's contents (unread counts, mark-all-read having just
    // run, freshly loaded events) in sync with new data instead of only refreshing on the
    // next open/close. Deferred a frame - calling OverlayEntry.markNeedsBuild synchronously
    // from inside didUpdateWidget (itself part of this build pass) trips "setState called
    // during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dropdownEntry?.markNeedsBuild();
      _journeyEntry?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _dropdownEntry?.remove();
    _dropdownEntry = null;
    _journeyEntry?.remove();
    _journeyEntry = null;
    super.dispose();
  }

  void _toggleDropdown() {
    if (_dropdownEntry != null) {
      _closeDropdown();
      return;
    }
    _closeJourneyLog();
    // A dropdown built from a StatefulWidget nested a few levels deep only ever paints
    // within its parent's own stacking position - a later-painted sibling elsewhere on the
    // page (the map, the dock) would paint over any part of it that visually overflows
    // outside those bounds. Inserting into the app's root Overlay via a LayerLink is the
    // standard fix: the dropdown becomes a top-level layer that always paints above the
    // rest of the page, positioned relative to the bell via CompositedTransformFollower
    // regardless of where the bell itself sits in the tree.
    _dropdownEntry = OverlayEntry(
      // Align, not just CompositedTransformFollower directly: an OverlayEntry's builder
      // result sits as a non-Positioned child of the Overlay's own internal Stack, which
      // uses StackFit.expand - without this Align, the follower (and everything under it,
      // including the dropdown itself) would be forced to fill the entire screen instead of
      // sizing to its own content, since a bare CompositedTransformFollower just passes
      // whatever constraints it's given straight down to its child. Align reports its own
      // size as the full available space but hands its child loose constraints and only
      // hit-tests within the child's actual (small) footprint - it doesn't reintroduce a
      // full-screen tap barrier.
      builder: (context) => Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: _bellLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 10),
          // TapRegion (not a full-screen GestureDetector barrier) so an outside tap closes
          // this without competing in the same gesture arena as whatever was tapped - a
          // barrier's own tap recognizer and the journey log button's would fight over the
          // same pointer, and only one could ever win, breaking a single click's ability to
          // switch straight from one popup to the other.
          child: TapRegion(
            groupId: _notifGroup,
            onTapOutside: (_) => _closeDropdown(),
            child: _NotificationsDropdown(
              notifications: widget.notifications,
              onMarkAllRead: widget.onMarkAllRead,
              onOpenNotification: (n) {
                _closeDropdown();
                widget.onOpenNotification(n);
              },
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_dropdownEntry!);
    setState(() {});
  }

  void _closeDropdown() {
    _dropdownEntry?.remove();
    _dropdownEntry = null;
    if (mounted) setState(() {});
  }

  void _toggleJourneyLog() {
    if (_journeyEntry != null) {
      _closeJourneyLog();
      return;
    }
    _closeDropdown();
    _journeyEntry = OverlayEntry(
      // See the matching comment on the notifications dropdown's OverlayEntry above - Align
      // is required here for the same reason (an OverlayEntry's root sizes to fill the whole
      // screen unless wrapped this way).
      builder: (context) => Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: _journeyLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 10),
          child: TapRegion(
            groupId: _journeyGroup,
            onTapOutside: (_) => _closeJourneyLog(),
            child: _PopupSurface(
              key: const Key('webJourneyLogDropdown'),
              width: 380,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
              child: JourneyLogPanel(
                events: widget.events,
                isLoading: widget.eventsLoading,
                errorMessage: widget.eventsError,
                onRetry: widget.onRetryEvents,
                onClose: _closeJourneyLog,
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_journeyEntry!);
    setState(() {});
  }

  void _closeJourneyLog() {
    _journeyEntry?.remove();
    _journeyEntry = null;
    if (mounted) setState(() {});
  }

  // The journey log button's glyph: a vertical timeline (three dots, two connector bars).
  Widget _timelineDot(bool active) => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(color: active ? CroColors.deepWaypoint : CroColors.fog, shape: BoxShape.circle),
  );

  Widget _timelineBar(bool active) =>
      Container(width: 2, height: 4, color: (active ? CroColors.deepWaypoint : CroColors.fog).withValues(alpha: 0.45));

  // Both popup trigger tiles (journey log, bell) share this 40px card treatment - a soft
  // shadow instead of Material's own generic elevation shadow, matching this web shell's
  // established convention (see your_birds_dock.dart's dock shadow).
  Widget _triggerTile({required Key key, required Color bg, required VoidCallback onTap, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: CroColors.ink.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = _dropdownEntry != null;
    final journeyOpen = _journeyEntry != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TapRegion(
          groupId: _journeyGroup,
          child: CompositedTransformTarget(
            link: _journeyLink,
            child: _triggerTile(
              key: const Key('webJourneyLogButton'),
              bg: journeyOpen ? CroColors.waypointBlue.withValues(alpha: 0.16) : Colors.white,
              onTap: _toggleJourneyLog,
              child: Tooltip(
                message: 'Journey log',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _timelineDot(journeyOpen),
                    const SizedBox(height: 2),
                    _timelineBar(journeyOpen),
                    const SizedBox(height: 2),
                    _timelineDot(journeyOpen),
                    const SizedBox(height: 2),
                    _timelineBar(journeyOpen),
                    const SizedBox(height: 2),
                    _timelineDot(journeyOpen),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        TapRegion(
          groupId: _notifGroup,
          child: CompositedTransformTarget(
            link: _bellLink,
            child: _triggerTile(
              key: const Key('webNotificationBell'),
              bg: open ? CroColors.waypointBlue.withValues(alpha: 0.16) : Colors.white,
              onTap: _toggleDropdown,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.notifications_outlined,
                    size: 19,
                    color: open ? CroColors.deepWaypoint : CroColors.fog,
                  ),
                  if (widget.unreadCount > 0)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        key: const Key('webNotificationBadge'),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CroColors.alertAway,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared "white rounded card with the design's soft shadow" wrapper for both popups -
/// `Material(elevation:)` renders Flutter's own generic elevation shadow, not the design's
/// soft, wide one; a literal BoxShadow matches this web shell's established convention (see
/// your_birds_dock.dart's dock shadow) instead.
class _PopupSurface extends StatelessWidget {
  final double width;
  final BoxConstraints? constraints;
  final Widget child;

  const _PopupSurface({super.key, required this.width, this.constraints, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: constraints,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CroColors.ink.withValues(alpha: 0.06)),
        boxShadow: [BoxShadow(color: CroColors.ink.withValues(alpha: 0.32), blurRadius: 44, offset: const Offset(0, 20))],
      ),
      child: child,
    );
  }
}

// Only 3 event kinds are ever surfaced as notifications (see api/Services/EventService.cs) -
// a bird landing at your nest, a bird you sent landing elsewhere, and a friend request being
// accepted. Real AppEvent data has no separate "who"/"tint" field the way the design mock's
// fabricated demo data did, so this derives a tinted glyph per kind instead - the same
// approach journey_log_panel.dart already uses for its timeline dots.
(IconData, Color) _notificationGlyph(String kind) => switch (kind) {
  EventKind.birdArrivedAtYourNest => (Icons.flutter_dash, CroColors.waypointBlue),
  EventKind.birdArrived => (Icons.flutter_dash, CroColors.deepWaypoint),
  EventKind.friendRequestAccepted => (Icons.person, CroColors.deliveryAmber),
  _ => (Icons.notifications, CroColors.fog),
};

class _NotificationsDropdown extends StatelessWidget {
  final List<AppEvent> notifications;
  final VoidCallback onMarkAllRead;
  final ValueChanged<AppEvent> onOpenNotification;

  const _NotificationsDropdown({
    required this.notifications,
    required this.onMarkAllRead,
    required this.onOpenNotification,
  });

  // No `intl` dependency in this project - a plain relative-time string, same convention
  // journey_log_panel.dart already uses.
  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    final days = diff.inDays;
    return '$days day${days == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    // Empty means empty (05_web_ui_updates.md item 5): when there's nothing to show, the
    // dropdown is just its header - no "Nothing yet" placeholder, no divider, and no
    // "Mark all read" (there's nothing to mark).
    final hasNotifications = notifications.isNotEmpty;
    return _PopupSurface(
      key: const Key('webNotificationsDropdown'),
      width: 372,
      constraints: const BoxConstraints(maxHeight: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Notifications',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                ),
                if (hasNotifications)
                  GestureDetector(
                    key: const Key('webMarkAllReadButton'),
                    onTap: onMarkAllRead,
                    child: const Text(
                      'Mark all read',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint),
                    ),
                  ),
              ],
            ),
          ),
          if (hasNotifications) ...[
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: notifications.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = notifications[i];
                  final (glyph, tint) = _notificationGlyph(n.kind);
                  return Material(
                    color: n.isRead ? Colors.white : const Color(0xFFF7FBFD),
                    child: InkWell(
                      key: Key('webNotification_${n.id}'),
                      onTap: () => onOpenNotification(n),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: Icon(glyph, size: 17, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(n.displayText, style: const TextStyle(fontSize: 13, height: 1.45)),
                                  const SizedBox(height: 3),
                                  Text(
                                    _relativeTime(n.createdAt),
                                    style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
                                  ),
                                ],
                              ),
                            ),
                            if (!n.isRead) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 5),
                                decoration: const BoxDecoration(color: CroColors.waypointBlue, shape: BoxShape.circle),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
