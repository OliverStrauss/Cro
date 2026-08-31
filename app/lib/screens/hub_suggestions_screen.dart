import 'package:flutter/material.dart';

import '../models/hub.dart';
import '../models/hub_picture_suggestion.dart';
import '../services/hub_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';

// Admin-only moderation feed for user-suggested Hub locations and photos - reachable from
// the map screen's "Hub Suggestions" button (_isAdmin-gated there; the server enforces the
// same admin check independently). Mirrors MyNestsScreen's row-list shape. Location and
// photo suggestions are two independent queues (see HubService/HubPictureSuggestion) shown
// as separate sections in one list.
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
  List<HubPictureSuggestion> _pictureSuggestions = [];
  final Map<String, String> _hubNameById = {};
  bool _isLoading = true;
  String? _errorMessage;
  // The suggestion currently in its "Confirm?" state, awaiting a second tap on the same
  // row's Reject action - same inline two-tap pattern as MyNestsScreen's delete, chosen
  // over a modal since rejecting a suggestion is lower-stakes than granting admin.
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
      _hubNameById
        ..clear()
        ..addEntries((results[2] as List<Hub>).map((h) => MapEntry(h.id, h.name)));
      setState(() {
        _suggestions = results[0] as List<Hub>;
        _pictureSuggestions = results[1] as List<HubPictureSuggestion>;
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

  Future<void> _approvePicture(HubPictureSuggestion suggestion) async {
    try {
      await widget.hubService.approvePictureSuggestion(
        widget.authState.token!,
        suggestion.id,
      );
      await _load();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _handleRejectPictureTap(HubPictureSuggestion suggestion) async {
    if (_confirmRejectPictureId != suggestion.id) {
      setState(() => _confirmRejectPictureId = suggestion.id);
      return;
    }

    setState(() => _confirmRejectPictureId = null);
    try {
      await widget.hubService.rejectPictureSuggestion(
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

    if (_suggestions.isEmpty && _pictureSuggestions.isEmpty) {
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
        if (_pictureSuggestions.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Photo suggestions',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: CroColors.fog),
            ),
          ),
          const SizedBox(height: 8),
          for (final suggestion in _pictureSuggestions) ...[
            _buildPictureSuggestionRow(suggestion),
            const SizedBox(height: 12),
          ],
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

  Widget _buildPictureSuggestionRow(HubPictureSuggestion suggestion) {
    final isConfirmingReject = _confirmRejectPictureId == suggestion.id;
    return Container(
      key: Key('hubPictureSuggestion_${suggestion.id}'),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              suggestion.blobUrl,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 40,
                height: 40,
                color: CroColors.fog.withValues(alpha: 0.2),
                child: const Icon(Icons.image_not_supported_outlined, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              'For ${_hubNameById[suggestion.hubId] ?? 'a Hub'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: CroColors.fog),
            ),
          ),
          TextButton(
            key: Key('approvePictureSuggestionButton_${suggestion.id}'),
            onPressed: () => _approvePicture(suggestion),
            child: const Text('Approve'),
          ),
          GestureDetector(
            key: Key('rejectPictureSuggestionButton_${suggestion.id}'),
            onTap: () => _handleRejectPictureTap(suggestion),
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
