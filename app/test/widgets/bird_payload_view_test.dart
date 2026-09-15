import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/theme.dart';
import 'package:cro_app/widgets/bird_payload_view.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(theme: croTheme, home: Scaffold(body: child)),
      );

  group('hasPayload', () {
    test('false when content, audio, and image are all absent', () {
      expect(BirdPayloadView.hasPayload(), isFalse);
    });

    test('false for empty-string content', () {
      expect(BirdPayloadView.hasPayload(content: ''), isFalse);
    });

    test('true when any single field is present', () {
      expect(BirdPayloadView.hasPayload(content: 'hi'), isTrue);
      expect(BirdPayloadView.hasPayload(audioUrl: 'https://x/clip.wav'), isTrue);
      expect(BirdPayloadView.hasPayload(imageUrl: 'https://x/photo.jpg'), isTrue);
    });
  });

  testWidgets('text-only payload shows the content and no waveform', (tester) async {
    await pump(tester, const BirdPayloadView(content: 'hello there'));

    expect(find.byKey(const Key('birdPayloadContent')), findsOneWidget);
    expect(find.text('hello there'), findsOneWidget);
    expect(find.byKey(const Key('birdPayloadWaveform')), findsNothing);
  });

  testWidgets('a Parrot (audio) payload shows the shared waveform row - play button, 24 bars, duration placeholder', (tester) async {
    await pump(tester, const BirdPayloadView(audioUrl: 'https://example.com/clip.wav'));

    expect(find.byKey(const Key('birdPayloadWaveform')), findsOneWidget);
    expect(find.byKey(const Key('birdPayloadAudioButton')), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // Duration hasn't loaded (no real player backend under test) - shows the placeholder.
    expect(find.text('--:--'), findsOneWidget);
  });

  testWidgets('no payload at all shows the empty-state message', (tester) async {
    await pump(tester, const BirdPayloadView());

    expect(find.text('This bird carried no message.'), findsOneWidget);
    expect(find.byKey(const Key('birdPayloadWaveform')), findsNothing);
  });
}
