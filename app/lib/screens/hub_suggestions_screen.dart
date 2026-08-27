import 'package:flutter/material.dart';

import '../models/hub.dart';
import '../services/hub_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';

// Admin-only moderation feed for user-suggested Hub locations - reachable from the map
// screen's "Hub Suggestions" button (_isAdmin-gated there; the server enforces the same
// admin check independently). Mirrors MyNestsScreen's row-list shape.
class HubSuggestionsScreen extends StatefulWidget {
  final AuthState authState;
  final HubService hubService;

  HubSuggestionsScreen({super.key, required this.authState, HubService? hubService})
      : hubService = hubService ?? HubService();

  @override
  State<HubSuggestionsScreen> createState() => _HubSuggestionsScreenState();
}

class _HubSuggestionsScreenState extends State<HubSuggestionsScreen> {
  List<Hub> _suggestions = [];
  bool _isLoading = true;
  String? _errorMessage;
  // The suggestion currently in its "Confirm?" state, awaiting a second tap on the same
  // row's Reject action - same inline two-tap pattern as MyNestsScreen's delete, chosen
  // over a modal since rejecting a suggestion is lower-stakes than granting admin.
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
      final suggestions = await widget.hubService.listSuggestions(
        widget.authState.token!,
      );
      setState(() {
        _suggestions = suggestions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _approve(Hub suggestion) async {
    try {
      await widget.hubService.approveSuggestion(
        widget.authState.token!,
        suggestion.id,
      );
      await _load();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _handleRejectTap(Hub suggestion) async {
    if (_confirmRejectId != suggestion.id) {
      setState(() => _confirmRejectId = suggestion.id);
      return;
    }

    setState(() => _confirmRejectId = null);
    try {
      await widget.hubService.rejectSuggestion(
        widget.authState.token!,
        suggestion.id,
      );
      await _load();
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
      appBar: AppBar(title: const Text('Hub Suggestions')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        key: Key('hubSuggestionsLoadingIndicator'),
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('hubSuggestionsErrorState'),
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
      return const Center(
        key: Key('noHubSuggestionsMessage'),
        child: Text(
          'No pending suggestions',
          style: TextStyle(fontSize: 13.5, color: CroColors.fog),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final suggestion in _suggestions) ...[
          _buildSuggestionRow(suggestion),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSuggestionRow(Hub suggestion) {
    final isConfirmingReject = _confirmRejectId == suggestion.id;
    return Container(
      key: Key('hubSuggestion_${suggestion.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0F2B2F33), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CroColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '(${suggestion.latitude.toStringAsFixed(4)}, ${suggestion.longitude.toStringAsFixed(4)})',
                  style: const TextStyle(fontSize: 12, color: CroColors.fog),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('approveSuggestionButton_${suggestion.id}'),
            onPressed: () => _approve(suggestion),
            child: const Text('Approve'),
          ),
          GestureDetector(
            key: Key('rejectSuggestionButton_${suggestion.id}'),
            onTap: () => _handleRejectTap(suggestion),
            child: Text(
              isConfirmingReject ? 'Confirm?' : 'Reject',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isConfirmingReject
                    ? Theme.of(context).colorScheme.error
                    : CroColors.fog,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
