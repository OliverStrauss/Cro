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
  static const _birdsTabIndex = 2;

  int _selectedIndex = 0;
  final _mapKey = GlobalKey<MapScreenState>();
  final _birdsKey = GlobalKey<BirdsScreenState>();

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ProfileScreen(authState: widget.authState),
      MapScreen(key: _mapKey, authState: widget.authState),
      BirdsScreen(key: _birdsKey, authState: widget.authState),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: tabs),
      // The subtle 1px top border (in place of Material's default elevation shadow) isn't
      // expressible via NavigationBarThemeData alone, so it's a plain Container wrapper here.
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x142B2F33)))),
        child: NavigationBar(
          key: const Key('homeNavBar'),
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) {
            final wasOnMap = _selectedIndex == _mapTabIndex;
            setState(() => _selectedIndex = i);
            // IndexedStack never rebuilds MapScreen on its own - force a refresh whenever
            // the user actually switches to it, so stale colors/waypoints don't linger.
            if (i == _mapTabIndex) {
              _mapKey.currentState?.refresh();
              _mapKey.currentState?.startLiveUpdates();
            } else if (wasOnMap) {
              // Symmetric "switched away from map" hook - IndexedStack keeps MapScreen
              // alive in the background rather than disposing it, so without this the
              // live-update timer would keep polling every 3s even while another tab
              // is showing.
              _mapKey.currentState?.stopLiveUpdates();
            }
            // Same "IndexedStack never rebuilds a backgrounded tab" issue as the map: without
            // this, birds assigned to a nest the user just created (or that arrived while
            // another tab was open) wouldn't show up as tappable until some other state change
            // happened to trigger a rebuild.
            if (i == _birdsTabIndex) {
              _birdsKey.currentState?.refresh();
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
      ),
    );
  }
}
