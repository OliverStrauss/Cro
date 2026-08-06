import 'package:flutter/material.dart';

import '../state/auth_state.dart';

class FriendsScreen extends StatelessWidget {
  final AuthState authState;

  const FriendsScreen({super.key, required this.authState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: const Center(
        key: Key('friendsScreenPlaceholder'),
        child: Text('Friends coming soon'),
      ),
    );
  }
}
