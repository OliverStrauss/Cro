import 'package:flutter/material.dart';

import '../../models/hub.dart';
import '../../models/hub_picture_suggestion.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';

/// Admin-only "Suggested hubs" queue, embedded directly in the Hubs screen (not the side
/// panel) per the design spec. Adapted from the phone app's HubSuggestionsScreen, plus
/// resolving each suggester's username (Hub only stores createdByUserId) for the
/// "Suggested by X" line the design calls for.
class HubSuggestionsPanel extends StatefulWidget {
  final AuthState authState;
  final HubService hubService;
  final ProfileService profileService;
  final VoidCallback onChanged;

  const HubSuggestionsPanel({
    super.key,
    required this.authState,
    required this.hubService,
    required this.profileService,
    required this.onChanged,
  });

  @override
  State<HubSuggestionsPanel> createState() => _HubSuggestionsPanelState();
}

class _HubSuggestionsPanelState extends State<HubSuggestionsPanel> {
  List<Hub> _suggestions = [];
  List<HubPictureSuggestion> _pictureSuggestions = [];
  final Map<String, String> _usernameById = {};
  final Map<String, String> _hubNameById = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _confirmRejectId;
  String? _confirmRejectPictureId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        widget.hubService.listSuggestions(widget.authState.token!),
        widget.hubService.listPictureSuggestions(widget.authState.token!),
        widget.hubService.listHubs(widget.authState.token!),
      ]);
      final suggestions = results[0] as List<Hub>;
      final pictureSuggestions = results[1] as List<HubPictureSuggestion>;
      _hubNameById
        ..clear()
        ..addEntries((results[2] as List<Hub>).map((h) => MapEntry(h.id, h.name)));

      // N+1 username resolution, cached per suggester - same accepted tradeoff category as
      // GET /friends' own N+1 avatar lookups, fine at expected suggestion-queue sizes.
      for (final hub in suggestions) {
        if (_usernameById.containsKey(hub.createdByUserId)) continue;
        try {
          final profile = await widget.profileService.getUser(hub.createdByUserId);
          _usernameById[hub.createdByUserId] = profile.username;
        } catch (_) {
          _usernameById[hub.createdByUserId] = 'someone';
        }
      }
      for (final suggestion in pictureSuggestions) {
        if (_usernameById.containsKey(suggestion.suggestedByUserId)) continue;
        try {
          final profile = await widget.profileService.getUser(suggestion.suggestedByUserId);
          _usernameById[suggestion.suggestedByUserId] = profile.username;
        } catch (_) {
          _usernameById[suggestion.suggestedByUserId] = 'someone';
        }
      }

      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _pictureSuggestions = pictureSuggestions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _approve(Hub suggestion) async {
    try {
      await widget.hubService.approveSuggestion(widget.authState.token!, suggestion.id);
      await _load();
      widget.onChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _handleReject(Hub suggestion) async {
    if (_confirmRejectId != suggestion.id) {
      setState(() => _confirmRejectId = suggestion.id);
      return;
    }
    setState(() => _confirmRejectId = null);
    try {
      await widget.hubService.rejectSuggestion(widget.authState.token!, suggestion.id);
      await _load();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _approvePicture(HubPictureSuggestion suggestion) async {
    try {
      await widget.hubService.approvePictureSuggestion(widget.authState.token!, suggestion.id);
      await _load();
      widget.onChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _handleRejectPicture(HubPictureSuggestion suggestion) async {
    if (_confirmRejectPictureId != suggestion.id) {
      setState(() => _confirmRejectPictureId = suggestion.id);
      return;
    }
    setState(() => _confirmRejectPictureId = null);
    try {
      await widget.hubService.rejectPictureSuggestion(widget.authState.token!, suggestion.id);
      await _load();
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
    if (_isLoading) {
      return const Center(key: Key('hubSuggestionsLoading'), child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        key: const Key('hubSuggestionsError'),
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
    if (_suggestions.isEmpty && _pictureSuggestions.isEmpty) {
      return const Padding(
        key: Key('noHubSuggestionsMessage'),
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No pending suggestions', style: TextStyle(fontSize: 12.5, color: CroColors.fog)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final suggestion in _suggestions) ...[
          _row(suggestion),
          const SizedBox(height: 10),
        ],
        if (_pictureSuggestions.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Photo suggestions',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: CroColors.fog),
            ),
          ),
          const SizedBox(height: 6),
          for (final suggestion in _pictureSuggestions) ...[
            _pictureRow(suggestion),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _row(Hub suggestion) {
    final isConfirming = _confirmRejectId == suggestion.id;
    final username = _usernameById[suggestion.createdByUserId] ?? 'someone';
    return Container(
      key: Key('hubSuggestion_${suggestion.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0F2B2F33), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: CroColors.deliveryAmber.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
            child: Text(
              suggestion.name.isEmpty ? '?' : suggestion.name[0].toUpperCase(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CroColors.amberInk),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Suggested by $username · ${suggestion.category ?? 'Landmark'}',
                  style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('approveSuggestionButton_${suggestion.id}'),
            style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: CroColors.success),
            onPressed: () => _approve(suggestion),
            child: const Text('Approve'),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: Key('rejectSuggestionButton_${suggestion.id}'),
            onTap: () => _handleReject(suggestion),
            child: Text(
              isConfirming ? 'Confirm?' : 'Reject',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isConfirming ? Theme.of(context).colorScheme.error : CroColors.fog,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pictureRow(HubPictureSuggestion suggestion) {
    final isConfirming = _confirmRejectPictureId == suggestion.id;
    final username = _usernameById[suggestion.suggestedByUserId] ?? 'someone';
    final hubName = _hubNameById[suggestion.hubId] ?? 'a Hub';
    return Container(
      key: Key('hubPictureSuggestion_${suggestion.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0F2B2F33), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              suggestion.blobUrl,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 38,
                height: 38,
                color: CroColors.fog.withValues(alpha: 0.2),
                child: const Icon(Icons.image_not_supported_outlined, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hubName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Suggested by $username', style: const TextStyle(fontSize: 11.5, color: CroColors.fog)),
              ],
            ),
          ),
          TextButton(
            key: Key('approvePictureSuggestionButton_${suggestion.id}'),
            style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: CroColors.success),
            onPressed: () => _approvePicture(suggestion),
            child: const Text('Approve'),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: Key('rejectPictureSuggestionButton_${suggestion.id}'),
            onTap: () => _handleRejectPicture(suggestion),
            child: Text(
              isConfirming ? 'Confirm?' : 'Reject',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isConfirming ? Theme.of(context).colorScheme.error : CroColors.fog,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
