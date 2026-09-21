import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/hub_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Friend.isBot defaults to false and parses true', () {
    final base = {'id': 'u1', 'username': 'mia'};
    expect(Friend.fromJson(base).isBot, isFalse);
    expect(Friend.fromJson({...base, 'isBot': true}).isBot, isTrue);
  });

  test('HubMessage.senderIsBot defaults to false and parses true', () {
    final base = {
      'id': 'm1',
      'senderId': 'u1',
      'senderUsername': 'pixel',
      'birdName': 'b',
      'type': 'Robin',
      'createdAt': '2026-09-21T00:00:00Z',
    };
    expect(HubMessage.fromJson(base).senderIsBot, isFalse);
    expect(HubMessage.fromJson({...base, 'senderIsBot': true}).senderIsBot, isTrue);
  });
}
