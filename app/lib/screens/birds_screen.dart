import 'package:flutter/material.dart';

import '../models/bird.dart';
import '../models/hub.dart';
import '../models/waypoint.dart';
import '../services/bird_service.dart';
import '../services/friends_service.dart';
import '../services/hub_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../widgets/avatar_with_fallback.dart';
import '../widgets/compose_bird_dialog.dart';
import '../widgets/send_bird_dialog.dart';

const _maxBirdsPerUser = 5;

class BirdsScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final BirdService birdService;
  final FriendsService friendsService;
  final HubService hubService;

  BirdsScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    BirdService? birdService,
    FriendsService? friendsService,
    HubService? hubService,
  })  : waypointService = waypointService ?? WaypointService(),
        birdService = birdService ?? BirdService(),
        friendsService = friendsService ?? FriendsService(),
        hubService = hubService ?? HubService();

  @override
  State<BirdsScreen> createState() => BirdsScreenState();
}

class BirdsScreenState extends State<BirdsScreen> {
  List<Bird> _birds = [];
  List<Waypoint> _ownNests = [];
  Map<String, String> _nestNameById = {};
  bool _isLoading = true;
  String? _errorMessage;
  // The bird currently in its "Confirm?" state, awaiting a second tap on the same row's
  // delete action - same two-tap pattern as MyNestsScreen. Null when nothing is pending.
  String? _confirmDeleteId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // IndexedStack keeps this screen alive rather than disposing it, so switching tabs
  // doesn't naturally re-fetch - exposed so HomeScreen can force a refresh whenever the
  // user switches to this tab.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final results = await Future.wait([
        widget.birdService.listBirds(token),
        widget.waypointService.listWaypoints(token),
        widget.friendsService.getFriendsWaypoints(token),
        widget.hubService.listHubs(token),
      ]);
      final birds = results[0] as List<Bird>;
      final ownNests = results[1] as List<Waypoint>;
      final friendNests = results[2] as List<Waypoint>;
      final hubs = results[3] as List<Hub>;

      // A bird's current/destination nest can belong to a friend or be a Hub (it traveled
      // there), so name lookup needs all three merged together.
      final nestNameById = <String, String>{
        for (final nest in [...ownNests, ...friendNests]) nest.id: nest.name,
        for (final hub in hubs) hub.id: hub.name,
      };

      setState(() {
        _birds = birds;
        _ownNests = ownNests;
        _nestNameById = nestNameById;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _locationText(Bird bird) {
    if (bird.isTraveling) {
      return 'Heading to ${_nestNameById[bird.nestToId] ?? 'a nest'}';
    }
    if (bird.currentNestId != null) {
      return _nestNameById[bird.currentNestId] ?? 'Unknown nest';
    }
    return 'Unassigned';
  }

  // Only traveling birds have a meaningful ETA. No `intl` dependency in this project, so this
  // is a plain relative countdown rather than a formatted timestamp.
  String? _etaText(Bird bird) {
    if (!bird.isTraveling || bird.estimatedArrivalAt == null) {
      return null;
    }
    final remaining = bird.estimatedArrivalAt!.difference(DateTime.now());
    if (remaining.isNegative) {
      return 'Arriving any moment';
    }
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return hours > 0 ? 'Arrives in ${hours}h ${minutes}m' : 'Arrives in ${minutes}m';
  }

  Future<void> _openSendFlow(Bird bird) async {
    final token = widget.authState.token!;
    try {
      final results = await Future.wait([
        widget.waypointService.listWaypoints(token),
        widget.friendsService.getFriendsWaypoints(token),
      ]);
      final ownNests = results[0].where((w) => w.id != bird.currentNestId);
      final friendNests = results[1];

      final destinations = [
        ...ownNests.map((w) => SendBirdDestination(nestId: w.id, label: w.name)),
        ...friendNests.map((w) => SendBirdDestination(nestId: w.id, label: '${w.name} (${w.username})')),
      ];

      if (!mounted) return;
      final result = await showDialog<SendBirdResult>(
        context: context,
        builder: (_) => SendBirdDialog(destinations: destinations),
      );
      if (result == null) return;

      await widget.birdService.sendBird(token, bird.id, nestId: result.nestId, content: result.content);
      _showToast('${bird.name} is on its way!');
      await _load();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _openComposeFlow() async {
    final token = widget.authState.token!;
    try {
      final friendNests = await widget.friendsService.getFriendsWaypoints(token);
      final hubs = await widget.hubService.listHubs(token);

      final origins = _ownNests.map((w) => SendBirdDestination(nestId: w.id, label: w.name)).toList();
      final destinations = [
        ..._ownNests.map((w) => SendBirdDestination(nestId: w.id, label: w.name)),
        ...friendNests.map((w) => SendBirdDestination(nestId: w.id, label: '${w.name} (${w.username})')),
        ...hubs.map((h) => SendBirdDestination(nestId: h.id, label: '${h.name} (Hub)')),
      ];

      if (origins.isEmpty) {
        _showToast('Create a nest first - a new bird needs somewhere to depart from.', isError: true);
        return;
      }

      if (!mounted) return;
      final result = await showDialog<ComposeBirdResult>(
        context: context,
        builder: (_) => ComposeBirdDialog(origins: origins, destinations: destinations),
      );
      if (result == null) return;

      await widget.birdService.composeAndSendBird(
        token,
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
      _showToast('${result.name} is on its way!');
      await _load();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _renameBird(Bird bird) async {
    final controller = TextEditingController(text: bird.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename this bird'),
        content: TextField(
          key: const Key('birdNameField'),
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            key: const Key('saveBirdNameButton'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;

    try {
      await widget.birdService.renameBird(widget.authState.token!, bird.id, newName.trim());
      await _load();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _pickAndUploadPicture(Bird bird) async {
    try {
      final image = await widget.birdService.pickImage();
      if (image == null) return;
      final bytes = await image.readAsBytes();
      await widget.birdService.uploadBirdPicture(
        widget.authState.token!,
        bird.id,
        bytes,
        filename: image.name,
        contentType: image.mimeType ?? 'image/jpeg',
      );
      await _load();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _handleDeleteTap(Bird bird) async {
    if (_confirmDeleteId != bird.id) {
      setState(() => _confirmDeleteId = bird.id);
      return;
    }

    setState(() => _confirmDeleteId = null);
    try {
      await widget.birdService.deleteBird(widget.authState.token!, bird.id);
      await _load();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final atCapacity = _birds.length >= _maxBirdsPerUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Birds')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        key: const Key('spawnBirdButton'),
        tooltip: atCapacity ? 'You have the max $_maxBirdsPerUser birds' : 'Spawn a bird',
        onPressed: atCapacity
            ? () => _showToast('You have the max $_maxBirdsPerUser birds. Delete one from your private nest first.')
            : _openComposeFlow,
        backgroundColor: atCapacity ? CroColors.fog : null,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(key: Key('birdsLoadingIndicator'), child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('birdsErrorState'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_birds.isEmpty) {
      return const Center(key: Key('noBirdsMessage'), child: Text('No birds yet - tap + to spawn one'));
    }

    return ListView(
      children: _birds.map((bird) {
        final canSend = !bird.isTraveling;
        final eta = _etaText(bird);
        final isConfirmingDelete = _confirmDeleteId == bird.id;
        return Card(
          key: Key('birdCard_${bird.id}'),
          child: ListTile(
            // Tapping the avatar picks/uploads a picture for this bird specifically -
            // separate from tapping the row body, which opens the send flow.
            leading: GestureDetector(
              key: Key('birdAvatar_${bird.id}'),
              onTap: () => _pickAndUploadPicture(bird),
              child: AvatarWithFallback(
                imageUrl: bird.profilePictureUrl,
                initialsSource: bird.name,
                radius: 20,
                hasBorder: true,
                borderColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(bird.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bird.type),
                Text(_locationText(bird), key: Key('birdLocation_${bird.id}')),
                if (eta != null) Text(eta, key: Key('birdEta_${bird.id}')),
              ],
            ),
            isThreeLine: true,
            onTap: canSend ? () => _openSendFlow(bird) : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('renameBirdButton_${bird.id}'),
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _renameBird(bird),
                ),
                GestureDetector(
                  key: Key('deleteBirdButton_${bird.id}'),
                  onTap: () => _handleDeleteTap(bird),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
