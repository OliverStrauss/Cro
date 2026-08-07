import 'package:flutter/material.dart';

import '../state/auth_state.dart';

class ProfileScreen extends StatelessWidget {
  final AuthState authState;

  const ProfileScreen({super.key, required this.authState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        key: const Key('profileScreenPlaceholder'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Profile coming soon'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              key: const Key('logoutButton'),
              onPressed: authState.logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}
