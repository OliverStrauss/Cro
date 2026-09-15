import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/widgets/send_bird_dialog.dart';

// Stands in for the platform-backed AudioRecorder in tests - startStream/stop are no-ops and
// onAmplitudeChanged is driven manually via emit(), since the real plugin talks to platform
// channels/mic hardware that aren't available under flutter test.
class _FakeAudioRecorder extends AudioRecorder {
  final _amplitudeCtrl = StreamController<Amplitude>.broadcast();
  bool startStreamThrows = false;
  AudioEncoder? lastStreamEncoder;
  List<int> streamedBytes = const [1, 2, 3, 4];

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    lastStreamEncoder = config.encoder;
    if (startStreamThrows) {
      throw Exception('mic unavailable');
    }
    return Stream.value(Uint8List.fromList(streamedBytes));
  }

  @override
  Future<String?> stop() async => null;

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      _amplitudeCtrl.stream;

  @override
  Future<void> dispose() async => _amplitudeCtrl.close();

  void emit(double dBFS) =>
      _amplitudeCtrl.add(Amplitude(current: dBFS, max: dBFS));
}

void main() {
  // Origin at (0, 0); same-longitude destinations reduce the haversine formula to a plain
  // meridian distance, so "nearer" here is simply "smaller latitude offset".
  final nearNest = SendBirdDestination(nestId: 'n1', name: 'Near Nest', latitude: 0.09, longitude: 0, isHub: false);
  final farNest = SendBirdDestination(
    nestId: 'n2',
    name: 'Far Nest',
    ownerUsername: 'bob',
    latitude: 0.9,
    longitude: 0,
    isHub: false,
  );
  final nearHub = SendBirdDestination(
    nestId: 'h1',
    name: 'Near Hub',
    latitude: 0.045,
    longitude: 0,
    isHub: true,
    category: 'Park',
  );
  final farHub = SendBirdDestination(
    nestId: 'h2',
    name: 'Far Hub',
    latitude: 0.45,
    longitude: 0,
    isHub: true,
    category: 'Bar',
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<SendBirdResult>(
              context: context,
              builder: (_) => SendBirdDialog(
                destinations: [nearNest, farNest, nearHub, farHub],
                originLatitude: 0,
                originLongitude: 0,
                speedKmh: 60,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  testWidgets('Nest tab (default) offers only nests, sorted nearest-first; Hub tab augments with hubs', (tester) async {
    await openDialog(tester);

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(find.text('Near Nest'), findsOneWidget);
    expect(find.text('Far Nest (bob)'), findsOneWidget);
    expect(find.text('Near Hub (Park)'), findsNothing);
    // Nearer destination renders above the farther one.
    expect(
      tester.getTopLeft(find.text('Near Nest')).dy,
      lessThan(tester.getTopLeft(find.text('Far Nest (bob)')).dy),
    );

    await tester.tap(find.text('Hub'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(find.text('Near Hub (Park)'), findsOneWidget);
    expect(find.text('Far Hub (Bar)'), findsOneWidget);
    expect(find.text('Near Nest'), findsNothing);
  });

  testWidgets('Hub tab shows a filter chip for every HubCategory, same fixed list as recommending a hub, and selecting one filters the dropdown', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Hub'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sendBirdCategoryChip_Park')), findsOneWidget);
    expect(find.byKey(const Key('sendBirdCategoryChip_Bar')), findsOneWidget);
    // Shown even though no destination in this dialog has that category - the chip list is
    // the fixed HubCategory.all, not derived from which hubs happen to be present.
    expect(find.byKey(const Key('sendBirdCategoryChip_Business')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sendBirdCategoryChip_Park')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(find.text('Near Hub (Park)'), findsOneWidget);
    expect(find.text('Far Hub (Bar)'), findsNothing);
  });

  testWidgets('every entry shows a distance-and-travel-time trailing label', (tester) async {
    await openDialog(tester);
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();

    final trailingLabels = tester.widgetList<Text>(find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').contains(' mi · '),
    ));
    expect(trailingLabels.length, 2); // Near Nest + Far Nest visible on the Nest tab
  });

  testWidgets('selecting a destination and confirming pops a SendBirdResult with trimmed content', (tester) async {
    SendBirdResult? result;
    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<SendBirdResult>(
                context: context,
                builder: (_) => SendBirdDialog(
                  destinations: [nearNest, farNest],
                  originLatitude: 0,
                  originLongitude: 0,
                  speedKmh: 60,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // Send is disabled with nothing picked yet.
    expect(tester.widget<FilledButton>(find.byKey(const Key('confirmSendBirdButton'))).onPressed, isNull);

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Far Nest (bob)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sendBirdMessageField')), '  hello  ');
    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(result?.nestId, 'n2');
    expect(result?.content, 'hello');
  });

  testWidgets('public/private switch defaults off, honors initialIsPublic, and its value reaches the result', (tester) async {
    SendBirdResult? result;
    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<SendBirdResult>(
                context: context,
                builder: (_) => SendBirdDialog(
                  destinations: [nearNest],
                  originLatitude: 0,
                  originLongitude: 0,
                  speedKmh: 60,
                  initialIsPublic: true,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byKey(const Key('sendBirdPublicSwitch'))).value, isTrue);

    await tester.tap(find.byKey(const Key('sendBirdPublicSwitch')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Near Nest').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(result?.isPublic, isFalse);
  });

  testWidgets('recording a Parrot clip shows a live waveform driven by mic amplitude, which clears on stop', (tester) async {
    final fakeRecorder = _FakeAudioRecorder();
    addTearDown(fakeRecorder.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<SendBirdResult>(
              context: context,
              builder: (_) => SendBirdDialog(
                destinations: [nearNest],
                originLatitude: 0,
                originLongitude: 0,
                speedKmh: 60,
                birdType: BirdType.parrot,
                recorder: fakeRecorder,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sendBirdWaveform')), findsNothing);

    await tester.tap(find.byKey(const Key('sendBirdRecordButton')));
    await tester.pump();
    expect(find.text('Recording...'), findsOneWidget);
    expect(find.byKey(const Key('sendBirdWaveform')), findsOneWidget);

    fakeRecorder.emit(-10);
    await tester.pump();
    final loudHeight = tester
        .widget<AnimatedContainer>(find.byKey(const Key('sendBirdWaveformBar_0')))
        .constraints!
        .maxHeight;

    fakeRecorder.emit(-55);
    await tester.pump();
    final quietHeight = tester
        .widget<AnimatedContainer>(find.byKey(const Key('sendBirdWaveformBar_0')))
        .constraints!
        .maxHeight;

    expect(loudHeight, greaterThan(quietHeight));

    await tester.tap(find.byKey(const Key('sendBirdRecordButton')));
    await tester.pump();
    expect(find.byKey(const Key('sendBirdWaveform')), findsNothing);
    expect(find.text('Clip recorded'), findsOneWidget);
  });

  testWidgets('a recorded Parrot clip is sent as pcm16bits-streamed audio wrapped in a playable WAV file', (tester) async {
    // record_web's startStream only actually supports AudioEncoder.pcm16bits on web - any
    // other encoder throws before a byte is captured (see send_bird_dialog.dart), which
    // silently produced empty, inaudible clips. This locks in the encoder that must be
    // requested and that the raw PCM bytes get wrapped in a real WAV file before upload.
    final fakeRecorder = _FakeAudioRecorder();
    addTearDown(fakeRecorder.dispose);
    SendBirdResult? result;

    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<SendBirdResult>(
                context: context,
                builder: (_) => SendBirdDialog(
                  destinations: [nearNest],
                  originLatitude: 0,
                  originLongitude: 0,
                  speedKmh: 60,
                  birdType: BirdType.parrot,
                  recorder: fakeRecorder,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sendBirdRecordButton')));
    await tester.pump();
    expect(fakeRecorder.lastStreamEncoder, AudioEncoder.pcm16bits);

    await tester.tap(find.byKey(const Key('sendBirdRecordButton')));
    await tester.pump();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Near Nest').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(result?.mediaContentType, 'audio/wav');
    expect(result?.mediaFilename, 'clip.wav');
    final bytes = result!.mediaBytes!;
    // 44-byte PCM WAV header ('RIFF' ... 'WAVE' ... 'data') followed by the raw PCM chunk.
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(bytes.length, 44 + fakeRecorder.streamedBytes.length);
    expect(bytes.sublist(44), fakeRecorder.streamedBytes);
  });

  testWidgets('a failure starting the recorder surfaces an error instead of leaving the button inert', (tester) async {
    final fakeRecorder = _FakeAudioRecorder()..startStreamThrows = true;
    addTearDown(fakeRecorder.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<SendBirdResult>(
              context: context,
              builder: (_) => SendBirdDialog(
                destinations: [nearNest],
                originLatitude: 0,
                originLongitude: 0,
                speedKmh: 60,
                birdType: BirdType.parrot,
                recorder: fakeRecorder,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sendBirdRecordButton')));
    await tester.pumpAndSettle();

    // No exception escapes the tap, the button stays in its not-recording state, and the
    // failure is surfaced to the user instead of silently doing nothing.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('sendBirdWaveform')), findsNothing);
    expect(find.text('Tap to record (optional)'), findsOneWidget);
    expect(find.textContaining('Could not start recording'), findsOneWidget);
  });
}
