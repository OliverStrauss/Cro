import 'package:flutter/material.dart';

import '../state/auth_state.dart';

class ProfileScreen extends StatelessWidget {
  final AuthState authState;

  const ProfileScreen({super.key, required this.authState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            key: const Key('logoutButton'),
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: authState.logout,
          ),
        ],
      ),
      body: const Center(
        key: Key('profileScreenPlaceholder'),
        child: Text('Profile coming soon'),
      ),
    );
  }
}
