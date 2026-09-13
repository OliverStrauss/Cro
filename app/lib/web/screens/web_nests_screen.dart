import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/waypoint.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../widgets/waypoint_name_dialog.dart';
import '../widgets/coordinate_readout.dart';

/// The Nests screen: own nests in a 2-up grid (rename, two-step delete, "n waiting" badge),
/// friends' nests in a 3-up compact grid. "+ Add a nest" hands off to the Map screen's
/// add-nest mode (see WebShellScreen._startAddNest/_placeNest).
class WebNestsScreen extends StatefulWidget {
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final Map<String, List<Bird>> nestResidentsByNestId;
  final String? selectedNestId;
  final ValueChanged<Waypoint> onSelectNest;
  final VoidCallback onStartAddNest;
  final AuthState authState;
  final WaypointService waypointService;
  final VoidCallback onDataChanged;

  const WebNestsScreen({
    super.key,
    required this.ownNests,
    required this.friendWaypoints,
    required this.nestResidentsByNestId,
    required this.selectedNestId,
    required this.onSelectNest,
    required this.onStartAddNest,
    required this.authState,
    required this.waypointService,
    required this.onDataChanged,
  });

  @override
  State<WebNestsScreen> createState() => _WebNestsScreenState();
}

class _WebNestsScreenState extends State<WebNestsScreen> {
  String? _confirmDeleteId;

  Future<void> _rename(Waypoint nest) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => WaypointNameDialog(initialName: nest.name),
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;

    try {
      await widget.waypointService.updateWaypoint(
        widget.authState.token!,
        nest.id,
        name: newName.trim(),
        latitude: nest.latitude,
        longitude: nest.longitude,
      );
      widget.onDataChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _handleDelete(Waypoint nest) async {
    if (_confirmDeleteId != nest.id) {
      setState(() => _confirmDeleteId = nest.id);
      return;
    }
    setState(() => _confirmDeleteId = null);
    try {
      await widget.waypointService.deleteWaypoint(widget.authState.token!, nest.id);
      widget.onDataChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Theme.of(context).colorScheme.error : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('webNestsScreen'),
      // Top padding keeps content clear of the floating actions cluster (no top bar - see
      // 05_web_ui_updates.md item 1).
      padding: const EdgeInsets.fromLTRB(26, 74, 26, 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Always visible, left-aligned (05_web_ui_updates.md item 6) - no count line. A
          // user still gets exactly one personal nest (see WaypointService.CreateAsync);
          // once they already have one this becomes "Move nest" instead - _placeNest (see
          // WebShellScreen) relocates the existing one rather than erroring, once they tap
          // the map.
          OutlinedButton(
            key: const Key('webAddNestButton'),
            onPressed: widget.onStartAddNest,
            style: OutlinedButton.styleFrom(
              foregroundColor: CroColors.deepWaypoint,
              side: BorderSide(color: CroColors.waypointBlue.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Text(widget.ownNests.isEmpty ? '+ Add a nest' : 'Move nest'),
          ),
          const SizedBox(height: 16),
          if (widget.ownNests.isEmpty)
            Padding(
              key: const Key('noOwnNestsMessage'),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No nests yet - add one to get started', style: CroTextStyles.data(size: 13.5)),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 2.6,
              children: [for (final nest in widget.ownNests) _ownNestCard(nest)],
            ),
          const SizedBox(height: 26),
          Text("Friends' nests", style: CroTextStyles.label(size: 12.5)),
          const SizedBox(height: 14),
          if (widget.friendWaypoints.isEmpty)
            Text('No friend nests visible yet', style: CroTextStyles.data(size: 12.5))
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.4,
              children: [for (final nest in widget.friendWaypoints) _friendNestCard(nest)],
            ),
        ],
      ),
    );
  }

  Widget _ownNestCard(Waypoint nest) {
    final isConfirming = _confirmDeleteId == nest.id;
    final residents = widget.nestResidentsByNestId[nest.id] ?? const [];
    final waitingCount = residents.where((b) => !b.isRead).length;
    final birdLine = residents.isEmpty ? 'No birds resting here' : '${residents.length} of your birds here';

    final selected = nest.id == widget.selectedNestId;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: CroBorders.radius,
      child: InkWell(
        key: Key('webNestCard_${nest.id}'),
        borderRadius: CroBorders.radius,
        onTap: () => widget.onSelectNest(nest),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: CroBorders.radius,
            border: Border.all(color: selected ? CroColors.waypointBlue : CroColors.hairline, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: CroColors.waypointBlue,
                    child: Text(
                      nest.name.isEmpty ? '?' : nest.name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: CroColors.surface),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nest.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        CoordinateReadout(latitude: nest.latitude, longitude: nest.longitude),
                      ],
                    ),
                  ),
                  if (waitingCount > 0)
                    Container(
                      key: Key('webNestWaitingBadge_${nest.id}'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: CroColors.alertAway, borderRadius: CroBorders.radiusSmall),
                      child: Text(
                        '$waitingCount waiting',
                        style: CroTextStyles.label(size: 9.5, color: CroColors.surface),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(birdLine, style: CroTextStyles.data(size: 12.5)),
                  const Spacer(),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key('webRenameNestButton_${nest.id}'),
                      borderRadius: CroBorders.radiusSmall,
                      onTap: () => _rename(nest),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text('Rename', style: CroTextStyles.label(size: 11, color: CroColors.deepWaypoint)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key('webDeleteNestButton_${nest.id}'),
                      borderRadius: CroBorders.radiusSmall,
                      onTap: () => _handleDelete(nest),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text(
                          isConfirming ? 'Confirm?' : 'Delete',
                          style: CroTextStyles.label(size: 11, color: isConfirming ? Theme.of(context).colorScheme.error : CroColors.fog),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _friendNestCard(Waypoint nest) {
    final color = hexToColor(nest.color ?? '#6B7280');
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: CroBorders.radius,
      child: InkWell(
        key: Key('webFriendNestCard_${nest.id}'),
        borderRadius: CroBorders.radius,
        onTap: () => widget.onSelectNest(nest),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(borderRadius: CroBorders.radius, border: Border.all(color: CroColors.hairline)),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: color,
                child: Text(
                  nest.name.isEmpty ? '?' : nest.name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CroColors.surface),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nest.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text(nest.username ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: CroColors.fog)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
