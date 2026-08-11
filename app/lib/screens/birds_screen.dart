import 'package:flutter/material.dart';

import '../models/bird.dart';
import '../models/waypoint.dart';
import '../services/bird_service.dart';
import '../services/friends_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../widgets/send_bird_dialog.dart';

class BirdsScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final BirdService birdService;
  final FriendsService friendsService;

  BirdsScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    BirdService? birdService,
    FriendsService? friendsService,
  })  : waypointService = waypointService ?? WaypointService(),
        birdService = birdService ?? BirdService(),
        friendsService = friendsService ?? FriendsService();

  @override
  State<BirdsScreen> createState() => BirdsScreenState();
}

class BirdsScreenState extends State<BirdsScreen> {
  List<Bird> _birds = [];
  Map<String, String> _nestNameById = {};
  // Pre-formatted possessive ("Your" / "Alice's") so _locationText can drop it straight
  // into "Heading to {author} nest, {name}" - same "Your nest"/"{username}'s nest"
  // phrasing NestDetailsDialog already uses elsewhere, for consistency.
  Map<String, String> _nestAuthorById = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // IndexedStack keeps this screen alive rather than disposing it, so switching tabs
  // doesn't naturally re-fetch - exposed so HomeScreen can force a refresh whenever the
  // user switches to this tab (e.g. after creating their first nest, which assigns any
  // previously-nestless birds server-side).
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
      ]);
      final birds = results[0] as List<Bird>;
      final ownNests = results[1] as List<Waypoint>;
      final friendNests = results[2] as List<Waypoint>;

      // A bird's current/destination nest can belong to a friend (it traveled there), so
      // name lookup needs both the caller's own nests and friends' nests merged together.
      final nestNameById = <String, String>{
        for (final nest in [...ownNests, ...friendNests]) nest.id: nest.name,
      };

      // GET /waypoints (own) never includes a username - a nest you own is always
      // authored by you, so that's hardcoded here rather than fetched. GET
      // /friends/waypoints already embeds the owning friend's username per nest.
      final nestAuthorById = <String, String>{
        for (final nest in ownNests) nest.id: 'Your',
        for (final nest in friendNests) nest.id: "${nest.username}'s",
      };

      setState(() {
        _birds = birds;
        _nestNameById = nestNameById;
        _nestAuthorById = nestAuthorById;
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
      final nestName = _nestNameById[bird.nestToId] ?? 'a nest';
      final author = _nestAuthorById[bird.nestToId];
      // Falls back to the plain nest name if the destination can't be resolved to an
      // owner (e.g. a stale race with a friend removing a nest mid-flight) rather than
      // showing a broken "null nest, {name}".
      return author == null ? 'Heading to $nestName' : 'Heading to $author nest, $nestName';
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Birds')),
        body: _buildBody(),
      );

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
      return const Center(key: Key('noBirdsMessage'), child: Text('No birds yet'));
    }

    return ListView(
      children: _birds.map((bird) {
        final canSend = !bird.isTraveling;
        final eta = _etaText(bird);
        return Card(
          key: Key('birdCard_${bird.id}'),
          child: ListTile(
            // This screen only ever shows the caller's own birds, so the icon uses the same
            // "this is yours" primary color already used for the user's own nest marker on
            // the map.
            leading: Icon(Icons.flutter_dash, color: Theme.of(context).colorScheme.primary),
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
          ),
        );
      }).toList(),
    );
  }
}
