import 'package:flutter/material.dart';

import '../../models/hub.dart';
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
  final Map<String, String> _usernameById = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _confirmRejectId;

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
      final suggestions = await widget.hubService.listSuggestions(widget.authState.token!);
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

      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
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
    if (_suggestions.isEmpty) {
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
}
