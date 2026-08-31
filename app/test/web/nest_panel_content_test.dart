import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/web/widgets/nest_panel_content.dart';

class _FakeWaypointService implements WaypointService {
  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeFriendsService implements FriendsService {
  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeBirdService implements BirdService {
  List<Bird> residentsToReturn = [];

  @override
  Future<List<Bird>> getNestResidents(String token, String nestId) async => residentsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeProfileService implements ProfileService {
  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  // A syntactically valid (unsigned) JWT with a fixed subject - NestPanelContent decodes
  // this client-side to split "delivered to you" from "birds here" on an own-nest render.
  final authState = AuthState()..login('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.sig');

  Widget build(Waypoint nest, {required bool isOwn, _FakeBirdService? birdService}) {
    return MaterialApp(
      home: Scaffold(
        body: NestPanelContent(
          nest: nest,
          isOwn: isOwn,
          authState: authState,
          onClose: () {},
          waypointService: _FakeWaypointService(),
          friendsService: _FakeFriendsService(),
          birdService: birdService ?? _FakeBirdService(),
          profileService: _FakeProfileService(),
          onChanged: () {},
        ),
      ),
    );
  }

  testWidgets('a friend nest with nothing to show renders just the minimal header, no instructional note',
      (tester) async {
    final nest = Waypoint(
      id: 'f1',
      userId: 'u2',
      name: "Mia's Cabin",
      latitude: 1,
      longitude: 2,
      username: 'mia',
      color: '#E53935',
    );
    await tester.pumpWidget(build(nest, isOwn: false));
    await tester.pump();

    expect(find.text("mia's nest"), findsOneWidget);
    expect(find.text("Mia's Cabin"), findsOneWidget);
    expect(find.textContaining('will find it waiting'), findsNothing);
    expect(find.textContaining('never what is inside it'), findsNothing);
    expect(find.byKey(const Key('webRenameNestButton')), findsNothing);
  });

  testWidgets('an own nest still shows the normal "Birds here" body', (tester) async {
    final nest = Waypoint(id: 'n1', userId: 'u1', name: 'Backyard', latitude: 1, longitude: 2);
    await tester.pumpWidget(build(nest, isOwn: true));
    await tester.pumpAndSettle();

    expect(find.text('Your nest'), findsOneWidget);
    expect(find.text('Birds here'), findsOneWidget);
    expect(find.byKey(const Key('nestPanelEmpty')), findsOneWidget);
    expect(find.byKey(const Key('webRenameNestButton')), findsOneWidget);
  });
}
