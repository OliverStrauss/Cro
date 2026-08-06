import 'package:flutter/material.dart';

import '../state/auth_state.dart';

class MapScreen extends StatelessWidget {
  final AuthState authState;

  const MapScreen({super.key, required this.authState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: const Center(
        key: Key('mapScreenPlaceholder'),
        child: Text('Map coming soon'),
      ),
    );
  }
}
