import 'dart:math';

import 'package:flutter/material.dart';

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

  SendBirdResult({required this.nestId, this.content});
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLng / 2) * sin(dLng / 2);
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
// Hub - and an optional message, then pops a SendBirdResult - the caller is responsible for
// actually calling BirdService.sendBird, same "dialog only collects input" split as
// WaypointNameDialog. Distance/ETA are previews computed from [originLatitude]/
// [originLongitude] (wherever this send actually departs from) using the same
// haversine-distance/base-speed formula as the backend's real send (see BirdService.cs and
// GeoDistance.cs) - not fetched from the server, so entries don't need a round trip just to
// list them.
class SendBirdDialog extends StatefulWidget {
  final List<SendBirdDestination> destinations;
  final double originLatitude;
  final double originLongitude;
  final double speedKmh;

  const SendBirdDialog({
    super.key,
    required this.destinations,
    required this.originLatitude,
    required this.originLongitude,
    required this.speedKmh,
  });

  @override
  State<SendBirdDialog> createState() => _SendBirdDialogState();
}

class _SendBirdDialogState extends State<SendBirdDialog> {
  late final List<_DestinationView> _views;
  bool _hubMode = false;
  final Set<String> _selectedCategories = {};
  String? _selectedNestId;
  final _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _views = widget.destinations.map((d) {
      final km = _haversineKm(widget.originLatitude, widget.originLongitude, d.latitude, d.longitude);
      final hours = widget.speedKmh > 0 ? km / widget.speedKmh : 0.0;
      return _DestinationView(d, km, hours);
    }).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  List<_DestinationView> get _modeViews => _views.where((v) => v.destination.isHub == _hubMode).toList();

  Set<String> get _availableCategories =>
      _hubMode ? _modeViews.map((v) => v.destination.category).whereType<String>().toSet() : {};

  List<_DestinationView> get _visibleViews {
    if (!_hubMode || _selectedCategories.isEmpty) return _modeViews;
    return _modeViews.where((v) => _selectedCategories.contains(v.destination.category)).toList();
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
      if (!_selectedCategories.remove(category)) _selectedCategories.add(category);
      _selectedNestId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleViews;
    final categories = _availableCategories;

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
              Text('Send this bird', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                key: const Key('sendBirdModeToggle'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Nest'), icon: Icon(Icons.holiday_village_rounded)),
                  ButtonSegment(value: true, label: Text('Hub'), icon: Icon(Icons.map_rounded)),
                ],
                selected: {_hubMode},
                onSelectionChanged: (selection) => _setHubMode(selection.first),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in HubCategory.all)
                      if (categories.contains(category))
                        FilterChip(
                          key: Key('sendBirdCategoryChip_$category'),
                          label: Text(category),
                          selected: _selectedCategories.contains(category),
                          onSelected: (_) => _toggleCategory(category),
                        ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (visible.isEmpty)
                Text(
                  _hubMode ? 'No hubs match.' : 'No other nests to send to yet.',
                  style: const TextStyle(color: CroColors.fog),
                )
              else
                DropdownMenu<String>(
                  key: ValueKey('sendBirdDropdown_${_hubMode}_${_selectedCategories.join(',')}'),
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  hintText: _hubMode ? 'Search hubs by name' : 'Search nests by name',
                  dropdownMenuEntries: [
                    for (final v in visible)
                      DropdownMenuEntry(
                        value: v.destination.nestId,
                        label: v.destination.label,
                        leadingIcon: Icon(
                          v.destination.isHub ? HubCategory.iconFor(v.destination.category) : Icons.person_pin_circle_rounded,
                          size: 20,
                        ),
                        trailingIcon: Text(
                          '${v.miles.toStringAsFixed(1)} mi · ${_travelTimeLabel(v.hours)}',
                          style: const TextStyle(fontSize: 11, color: CroColors.fog),
                        ),
                      ),
                  ],
                  onSelected: (value) => setState(() => _selectedNestId = value),
                ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('sendBirdMessageField'),
                controller: _contentController,
                decoration: const InputDecoration(labelText: 'Message (optional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('confirmSendBirdButton'),
                    onPressed: _selectedNestId == null
                        ? null
                        : () => Navigator.of(context).pop(SendBirdResult(
                              nestId: _selectedNestId!,
                              content: _contentController.text.trim().isEmpty ? null : _contentController.text.trim(),
                            )),
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
}
