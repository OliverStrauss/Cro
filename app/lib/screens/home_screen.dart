import 'package:flutter/material.dart';

import '../state/auth_state.dart';
import 'birds_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthState authState;

  const HomeScreen({super.key, required this.authState});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _mapTabIndex = 1;

  int _selectedIndex = 0;
  final _mapKey = GlobalKey<MapScreenState>();

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ProfileScreen(authState: widget.authState),
      MapScreen(key: _mapKey, authState: widget.authState),
      BirdsScreen(authState: widget.authState),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        key: const Key('homeNavBar'),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          setState(() => _selectedIndex = i);
          // IndexedStack never rebuilds MapScreen on its own - force a refresh whenever
          // the user actually switches to it, so stale colors/waypoints don't linger.
          if (i == _mapTabIndex) {
            _mapKey.currentState?.refresh();
          }
        },
        destinations: const [
          NavigationDestination(
            key: Key('navProfile'),
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            key: Key('navMap'),
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            key: Key('navBirds'),
            icon: Icon(Icons.egg_outlined),
            selectedIcon: Icon(Icons.egg),
            label: 'Birds',
          ),
        ],
      ),
    );
  }
}
