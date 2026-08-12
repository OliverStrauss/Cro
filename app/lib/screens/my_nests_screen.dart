import 'package:flutter/material.dart';
// latlong2 also declares its own Path<T> class (for geo paths), which collides with
// dart:ui's Path (needed here for the dashed-border CustomPainter below) - only LatLng is
// actually used from this import.
import 'package:latlong2/latlong.dart' hide Path;

import '../models/waypoint.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../widgets/avatar_with_fallback.dart';
import '../widgets/waypoint_name_dialog.dart';
import 'map_screen.dart';

class MyNestsScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  // Forwarded to the MapScreen pushed by the "add" flow (see _addNest below) - kept
  // injectable for tests, same as every other service on this screen.
  final FriendsService friendsService;
  final ProfileService profileService;

  MyNestsScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    FriendsService? friendsService,
    ProfileService? profileService,
  }) : waypointService = waypointService ?? WaypointService(),
       friendsService = friendsService ?? FriendsService(),
       profileService = profileService ?? ProfileService();

  @override
  State<MyNestsScreen> createState() => _MyNestsScreenState();
}

class _MyNestsScreenState extends State<MyNestsScreen> {
  List<Waypoint> _nests = [];
  bool _isLoading = true;
  String? _errorMessage;
  // The nest currently in its "Confirm?" state, awaiting a second tap on the same row's
  // delete action - a lighter two-tap inline pattern instead of a separate confirmation
  // dialog. Null when nothing is pending confirmation.
  String? _confirmDeleteId;

  @override
  void initState() {
    super.initState();
    _loadNests();
  }

  Future<void> _loadNests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final nests = await widget.waypointService.listWaypoints(
        widget.authState.token!,
      );
      setState(() {
        _nests = nests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _renameNest(Waypoint nest) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => WaypointNameDialog(initialName: nest.name),
    );
    if (newName == null || newName.trim().isEmpty) {
      return;
    }

    try {
      await widget.waypointService.updateWaypoint(
        widget.authState.token!,
        nest.id,
        name: newName.trim(),
        latitude: nest.latitude,
        longitude: nest.longitude,
      );
      await _loadNests();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _handleDeleteTap(Waypoint nest) async {
    if (_confirmDeleteId != nest.id) {
      setState(() => _confirmDeleteId = nest.id);
      return;
    }

    setState(() => _confirmDeleteId = null);
    try {
      await widget.waypointService.deleteWaypoint(
        widget.authState.token!,
        nest.id,
      );
      await _loadNests();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  bool get _hasPrivateNest => _nests.any((n) => !n.isPublic);
  bool get _hasPublicNest => _nests.any((n) => n.isPublic);

  // Resolves which kind the next "Add a nest" tap should create, without ever touching
  // the server's 409 cap error for the common path: if a slot is already filled the other
  // one is the only valid choice, so there's nothing to ask; only when both are empty does
  // the user need to pick. Returns null if the user backs out of the picker.
  Future<bool?> _resolveNestKindToAdd() async {
    if (_hasPrivateNest && !_hasPublicNest) {
      return true;
    }
    if (_hasPublicNest && !_hasPrivateNest) {
      return false;
    }
    return showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add which kind of nest?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Private nest'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Public nest'),
          ),
        ],
      ),
    );
  }

  Future<void> _addNest() async {
    final isPublic = await _resolveNestKindToAdd();
    if (isPublic == null || !mounted) {
      return;
    }

    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapScreen(
          authState: widget.authState,
          waypointService: widget.waypointService,
          pickLocationMode: true,
        ),
      ),
    );
    if (point == null || !mounted) {
      return;
    }

    final name = await showDialog<String>(
      context: context,
      builder: (context) => WaypointNameDialog(
        kindLabel: isPublic ? 'Public nest' : 'Private nest',
      ),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }

    try {
      await widget.waypointService.createWaypoint(
        widget.authState.token!,
        name: name.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
        isPublic: isPublic,
      );
      await _loadNests();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Nests')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        key: Key('myNestsLoadingIndicator'),
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('myNestsErrorState'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadNests, child: const Text('Retry')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_nests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              key: Key('noNestsMessage'),
              child: Text(
                'No nests yet - tap + to add one',
                style: TextStyle(fontSize: 13.5, color: CroColors.fog),
              ),
            ),
          ),
        for (final nest in _nests) ...[
          _buildNestRow(nest),
          const SizedBox(height: 12),
        ],
        if (_hasPrivateNest && _hasPublicNest)
          const Padding(
            key: Key('bothNestSlotsFullMessage'),
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'Both nest slots are full',
                style: TextStyle(fontSize: 13.5, color: CroColors.fog),
              ),
            ),
          )
        else
          _buildAddNestRow(),
      ],
    );
  }

  // Pushes the map centered on this nest - the row's own tap area, separate from the
  // rename/delete controls nested inside it, which each capture their own tap via the
  // gesture arena before it would reach this GestureDetector.
  void _openNestOnMap(Waypoint nest) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapScreen(
          authState: widget.authState,
          waypointService: widget.waypointService,
          friendsService: widget.friendsService,
          profileService: widget.profileService,
          focusPoint: LatLng(nest.latitude, nest.longitude),
        ),
      ),
    );
  }

  Widget _buildNestRow(Waypoint nest) {
    final isConfirmingDelete = _confirmDeleteId == nest.id;
    return GestureDetector(
      key: Key('nestTile_${nest.id}'),
      onTap: () => _openNestOnMap(nest),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: CroColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F2B2F33),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            AvatarWithFallback(
              imageUrl: nest.profilePictureUrl,
              initialsSource: nest.name,
              radius: 22,
              hasBorder: true,
              borderColor: CroColors.waypointBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          nest.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: CroColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        nest.isPublic ? 'Public' : 'Private',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: CroColors.fog,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '(${nest.latitude.toStringAsFixed(4)}, ${nest.longitude.toStringAsFixed(4)})',
                    style: const TextStyle(fontSize: 12, color: CroColors.fog),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('renameNestButton_${nest.id}'),
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _renameNest(nest),
            ),
            GestureDetector(
              key: Key('deleteNestButton_${nest.id}'),
              onTap: () => _handleDeleteTap(nest),
              child: Text(
                isConfirmingDelete ? 'Confirm?' : 'Delete',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isConfirmingDelete
                      ? Theme.of(context).colorScheme.error
                      : CroColors.fog,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddNestRow() {
    return GestureDetector(
      key: const Key('addNestButton'),
      onTap: _addNest,
      child: CustomPaint(
        painter: _DashedRoundedBorderPainter(
          color: CroColors.waypointBlue.withValues(alpha: 0.5),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '+',
                style: TextStyle(
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: CroColors.deepWaypoint,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _hasPrivateNest
                    ? 'Add your public nest'
                    : (_hasPublicNest ? 'Add your private nest' : 'Add a nest'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
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

// Flutter has no built-in dashed-border decoration, and this is the only place in the app
// that needs one - not worth pulling in a dependency for a single dashed rounded rect.
class _DashedRoundedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedRoundedBorderPainter({required this.color});

  static const _radius = 16.0;
  static const _dashWidth = 6.0;
  static const _dashSpace = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(_radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance = next + _dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
