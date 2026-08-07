import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../state/auth_state.dart';
import '../utils/jwt_utils.dart';
import '../widgets/avatar_with_fallback.dart';

class ProfileScreen extends StatefulWidget {
  final AuthState authState;
  final ProfileService profileService;

  ProfileScreen({super.key, required this.authState, ProfileService? profileService})
      : profileService = profileService ?? ProfileService();

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = jwtSubject(widget.authState.token!);
      if (userId == null) {
        throw ProfileException('Could not determine the current user');
      }
      final profile = await widget.profileService.getUser(userId);
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadPicture() async {
    final (List<int> bytes, String filename, String contentType) picked;
    try {
      final xFile = await widget.profileService.pickImage();
      if (xFile == null) {
        return;
      }
      picked = (await xFile.readAsBytes(), xFile.name, xFile.mimeType ?? 'image/jpeg');
    } catch (e) {
      _showToast(e.toString(), isError: true);
      return;
    }

    setState(() => _isUploading = true);
    try {
      await widget.profileService.uploadProfilePicture(
        widget.authState.token!,
        picked.$1,
        filename: picked.$2,
        contentType: picked.$3,
      );
      _showToast('Profile picture updated');
      await _loadProfile();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
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
      appBar: AppBar(title: const Text('Profile')),
      body: Column(
        children: [
          Expanded(child: _buildProfileContent()),
          // Kept outside the loading/error states below - signing out shouldn't depend
          // on the profile picture fetch having succeeded.
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              key: const Key('logoutButton'),
              onPressed: widget.authState.logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    if (_isLoading) {
      return const Center(key: Key('profileLoadingIndicator'), child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('profileErrorState'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadProfile, child: const Text('Retry')),
          ],
        ),
      );
    }

    final profile = _profile!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            key: const Key('profileAvatarButton'),
            onTap: _isUploading ? null : _pickAndUploadPicture,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AvatarWithFallback(
                  imageUrl: profile.profilePictureUrl,
                  initialsSource: profile.username,
                  radius: 48,
                ),
                if (_isUploading) const CircularProgressIndicator(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('Tap to change picture', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          Text(profile.username, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}
