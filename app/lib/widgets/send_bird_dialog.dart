import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../models/bird.dart';
import '../models/hub_category.dart';
import '../theme.dart';

class SendBirdDestination {
  final String nestId;
  final String name;
  // Set only for a friend's nest - null for the caller's own nest and for a Hub.
  final String? ownerUsername;
  final double latitude;
  final double longitude;
  final bool isHub;
  // Set only for a Hub, one of HubCategory.all.
  final String? category;

  SendBirdDestination({
    required this.nestId,
    required this.name,
    this.ownerUsername,
    required this.latitude,
    required this.longitude,
    required this.isHub,
    this.category,
  });

  // Also doubles as the search-match text for the destination dropdown below (its default
  // filter matches substring anywhere in this label), so a name, username, or hub category
  // all work as a search term without a separate filter callback.
  String get label {
    if (isHub) return category == null ? name : '$name ($category)';
    return ownerUsername == null ? name : '$name ($ownerUsername)';
  }
}

class SendBirdResult {
  final String nestId;
  final String? content;
  // Whether this leg (and everything about it - content/media) is visible to friends on the
  // map, same meaning as Bird.isPublic. Picked per-send now rather than fixed at compose time.
  final bool isPublic;
  // This leg's payload media for a Parrot (audio) or Pigeon/Raven (image) - null for a
  // text-only Cro. Mirrors ComposeBirdResult's shape from the retired compose flow.
  final List<int>? mediaBytes;
  final String? mediaContentType;
  final String? mediaFilename;

  SendBirdResult({
    required this.nestId,
    this.content,
    this.isPublic = false,
    this.mediaBytes,
    this.mediaContentType,
    this.mediaFilename,
  });
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _toRadians(double degrees) => degrees * pi / 180.0;

String _travelTimeLabel(double hours) {
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

class _DestinationView {
  final SendBirdDestination destination;
  final double distanceKm;
  final double hours;

  _DestinationView(this.destination, this.distanceKm, this.hours);

  double get miles => distanceKm * 0.621371;
}

// Picks a destination nest or Hub - either the sender's own nest, a friend's, or a public
// Hub - and this leg's payload, then pops a SendBirdResult - the caller is responsible for
// actually calling BirdService.sendBird, same "dialog only collects input" split as
// WaypointNameDialog. Distance/ETA are previews computed from [originLatitude]/
// [originLongitude] (wherever this send actually departs from) using the same
// haversine-distance/base-speed formula as the backend's real send (see BirdService.cs and
// GeoDistance.cs) - not fetched from the server, so entries don't need a round trip just to
// list them. The payload field shown matches [birdType]'s BirdPayloadValidator rules (Cro:
// text, Parrot: recorded audio, Pigeon: image, Raven: text + image) - adapted from the
// retired ComposeBirdDialog, which asked for the same per-type payload up front when a bird
// was first spawned.
class SendBirdDialog extends StatefulWidget {
  final List<SendBirdDestination> destinations;
  final double originLatitude;
  final double originLongitude;
  final double speedKmh;
  final String birdType;
  // Pre-checks the public/private switch to this leg's current value - a bird already public
  // stays public by default on its next send instead of silently reverting to private.
  final bool initialIsPublic;
  final AudioRecorder? recorder;
  final ImagePicker? imagePicker;

  const SendBirdDialog({
    super.key,
    required this.destinations,
    required this.originLatitude,
    required this.originLongitude,
    required this.speedKmh,
    this.birdType = BirdType.cro,
    this.initialIsPublic = false,
    this.recorder,
    this.imagePicker,
  });

  @override
  State<SendBirdDialog> createState() => _SendBirdDialogState();
}

class _SendBirdDialogState extends State<SendBirdDialog> {
  late final List<_DestinationView> _views;
  late final AudioRecorder _recorder = widget.recorder ?? AudioRecorder();
  late final ImagePicker _imagePicker = widget.imagePicker ?? ImagePicker();
  bool _hubMode = false;
  String? _selectedCategory;
  String? _selectedNestId;
  bool _isPublic = false;
  final _contentController = TextEditingController();

  bool _isRecording = false;
  List<int>? _audioBytes;
  StreamSubscription<Uint8List>? _audioSub;
  List<int>? _imageBytes;
  String? _imageFilename;

  bool get _wantsText =>
      widget.birdType == BirdType.cro || widget.birdType == BirdType.raven;
  bool get _wantsAudio => widget.birdType == BirdType.parrot;
  bool get _wantsImage =>
      widget.birdType == BirdType.pigeon || widget.birdType == BirdType.raven;

  @override
  void initState() {
    super.initState();
    _isPublic = widget.initialIsPublic;
    _views = widget.destinations.map((d) {
      final km = _haversineKm(
        widget.originLatitude,
        widget.originLongitude,
        d.latitude,
        d.longitude,
      );
      final hours = widget.speedKmh > 0 ? km / widget.speedKmh : 0.0;
      return _DestinationView(d, km, hours);
    }).toList()..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  }

  @override
  void dispose() {
    _contentController.dispose();
    _audioSub?.cancel();
    if (widget.recorder == null) {
      _recorder.dispose();
    }
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _recorder.stop();
      await _audioSub?.cancel();
      setState(() => _isRecording = false);
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone permission is needed to record a Parrot clip',
            ),
          ),
        );
      }
      return;
    }

    _audioBytes = [];
    final stream = await _recorder.startStream(const RecordConfig());
    _audioSub = stream.listen((chunk) => _audioBytes!.addAll(chunk));
    setState(() => _isRecording = true);
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageFilename = picked.name;
    });
  }

  List<_DestinationView> get _modeViews =>
      _views.where((v) => v.destination.isHub == _hubMode).toList();

  List<_DestinationView> get _visibleViews {
    if (!_hubMode || _selectedCategory == null) return _modeViews;
    return _modeViews
        .where((v) => v.destination.category == _selectedCategory)
        .toList();
  }

  void _setHubMode(bool hubMode) {
    if (hubMode == _hubMode) return;
    setState(() {
      _hubMode = hubMode;
      _selectedNestId = null;
    });
  }

  void _toggleCategory(String category) {
    setState(() {
      _selectedCategory = _selectedCategory == category ? null : category;
      _selectedNestId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleViews;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: CroColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send this bird',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                key: const Key('sendBirdModeToggle'),
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Nest'),
                    icon: Icon(Icons.holiday_village_rounded),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Hub'),
                    icon: Icon(Icons.map_rounded),
                  ),
                ],
                selected: {_hubMode},
                onSelectionChanged: (selection) => _setHubMode(selection.first),
              ),
              if (_hubMode) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final category in HubCategory.all)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            key: Key('sendBirdCategoryChip_$category'),
                            label: Text(category),
                            selected: _selectedCategory == category,
                            onSelected: (_) => _toggleCategory(category),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (visible.isEmpty)
                Text(
                  _hubMode
                      ? 'No hubs match.'
                      : 'No other nests to send to yet.',
                  style: const TextStyle(color: CroColors.fog),
                )
              else
                DropdownMenu<String>(
                  key: ValueKey(
                    'sendBirdDropdown_${_hubMode}_${_selectedCategory ?? ''}',
                  ),
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  hintText: _hubMode
                      ? 'Search hubs by name'
                      : 'Search nests by name',
                  dropdownMenuEntries: [
                    for (final v in visible)
                      DropdownMenuEntry(
                        value: v.destination.nestId,
                        label: v.destination.label,
                        leadingIcon: Icon(
                          v.destination.isHub
                              ? HubCategory.iconFor(v.destination.category)
                              : Icons.person_pin_circle_rounded,
                          size: 20,
                        ),
                        trailingIcon: Text(
                          '${v.miles.toStringAsFixed(1)} mi · ${_travelTimeLabel(v.hours)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: CroColors.fog,
                          ),
                        ),
                      ),
                  ],
                  onSelected: (value) =>
                      setState(() => _selectedNestId = value),
                ),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const Key('sendBirdPublicSwitch'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Make this bird public'),
                subtitle: const Text(
                  "Friends can see it on the map and open what it's carrying",
                  style: TextStyle(fontSize: 11.5, color: CroColors.fog),
                ),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
              ),
              const SizedBox(height: 12),
              ..._buildPayloadFields(context),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('confirmSendBirdButton'),
                    onPressed: _selectedNestId == null
                        ? null
                        : () => Navigator.of(context).pop(
                            SendBirdResult(
                              nestId: _selectedNestId!,
                              content: _contentController.text.trim().isEmpty
                                  ? null
                                  : _contentController.text.trim(),
                              isPublic: _isPublic,
                              mediaBytes: _wantsAudio
                                  ? _audioBytes
                                  : (_wantsImage ? _imageBytes : null),
                              mediaContentType: _wantsAudio
                                  ? 'audio/wav'
                                  : (_wantsImage ? 'image/jpeg' : null),
                              mediaFilename: _wantsAudio
                                  ? 'clip.wav'
                                  : (_wantsImage
                                        ? (_imageFilename ?? 'photo.jpg')
                                        : null),
                            ),
                          ),
                    child: const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPayloadFields(BuildContext context) {
    final fields = <Widget>[];
    if (_wantsText) {
      fields.add(
        TextField(
          key: const Key('sendBirdMessageField'),
          controller: _contentController,
          decoration: const InputDecoration(labelText: 'Message (optional)'),
          maxLines: 3,
        ),
      );
    }
    if (_wantsAudio) {
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 12));
      fields.add(
        Row(
          children: [
            IconButton(
              key: const Key('sendBirdRecordButton'),
              icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic),
              color: _isRecording ? Theme.of(context).colorScheme.error : null,
              onPressed: _toggleRecording,
            ),
            Text(
              _isRecording
                  ? 'Recording...'
                  : (_audioBytes != null
                        ? 'Clip recorded'
                        : 'Tap to record (optional)'),
            ),
          ],
        ),
      );
    }
    if (_wantsImage) {
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 12));
      fields.add(
        Row(
          children: [
            IconButton(
              key: const Key('sendBirdPickImageButton'),
              icon: const Icon(Icons.image),
              onPressed: _pickImage,
            ),
            Text(_imageFilename ?? 'No image chosen (optional)'),
          ],
        ),
      );
    }
    return fields;
  }
}
