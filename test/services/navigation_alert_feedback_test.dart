import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/services/navigation_alert_feedback.dart';
import 'package:trail_runner/services/navigation_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const offRoute = NavStatus(
    offRoute: true,
    distanceToRouteMeters: 42,
    triggered: NavAlert.offRoute,
  );
  const junction = NavStatus(
    offRoute: false,
    junctionDistanceMeters: 27,
    junctionTurn: TurnDirection.left,
    triggered: NavAlert.junction,
  );

  test(
    'tone and voice mode sequences distinct cue before spoken guidance',
    () async {
      var hapticCount = 0;
      final events = <String>[];
      final feedback = NavigationAlertFeedback(
        haptic: () async => hapticCount++,
        playTone: (alert) async {
          events.add('tone:${alert.name}');
          return true;
        },
        speak: (message) async {
          events.add('voice:$message');
          return true;
        },
        wait: (_) async {},
      );

      final result = await feedback.notify(
        junction,
        mode: NavFeedbackMode.toneAndVoice,
      );

      expect(hapticCount, 1);
      expect(events, ['tone:junction', 'voice:In 25 meters, keep left.']);
      expect(result.tonePlayed, isTrue);
      expect(result.voiceSpoken, isTrue);
      expect(result.usedToneFallback, isFalse);
    },
  );

  test('feedback modes select tones, voice, or haptics only', () async {
    var hapticCount = 0;
    var toneCount = 0;
    var voiceCount = 0;
    final feedback = NavigationAlertFeedback(
      haptic: () async => hapticCount++,
      playTone: (_) async {
        toneCount++;
        return true;
      },
      speak: (_) async {
        voiceCount++;
        return true;
      },
    );

    await feedback.notify(offRoute, mode: NavFeedbackMode.tones);
    await feedback.notify(offRoute, mode: NavFeedbackMode.voice);
    await feedback.notify(offRoute, mode: NavFeedbackMode.hapticsOnly);

    expect(hapticCount, 3);
    expect(toneCount, 1);
    expect(voiceCount, 1);
  });

  test(
    'voice mode falls back to a bundled tone when speech is unavailable',
    () async {
      var toneCount = 0;
      final feedback = NavigationAlertFeedback(
        haptic: () async {},
        playTone: (_) async {
          toneCount++;
          return true;
        },
        speak: (_) async => false,
      );

      final result = await feedback.notify(
        offRoute,
        mode: NavFeedbackMode.voice,
      );

      expect(toneCount, 1);
      expect(result.voiceSpoken, isFalse);
      expect(result.usedToneFallback, isTrue);
      expect(result.audioPlayed, isTrue);
    },
  );

  test('guidance is concise and includes junction direction', () {
    expect(
      NavigationAlertFeedback.guidanceFor(offRoute),
      'Off route. Check the map.',
    );
    expect(
      NavigationAlertFeedback.guidanceFor(junction),
      'In 25 meters, keep left.',
    );
  });

  test(
    'Android voice selection requires an installed offline English voice',
    () {
      final selected = NavigationAlertFeedback.selectOfflineEnglishVoice([
        {
          'name': 'network-us',
          'locale': 'en-US',
          'network_required': '1',
          'quality': 'very high',
        },
        {
          'name': 'offline-gb',
          'locale': 'en-GB',
          'network_required': '0',
          'quality': 'very high',
        },
        {
          'name': 'offline-us',
          'locale': 'en-US',
          'network_required': '0',
          'quality': 'high',
        },
        {
          'name': 'offline-he',
          'locale': 'he-IL',
          'network_required': '0',
          'quality': 'very high',
        },
      ]);

      expect(selected, {'name': 'offline-us', 'locale': 'en-US'});
      expect(
        NavigationAlertFeedback.selectOfflineEnglishVoice([
          {'name': 'network-us', 'locale': 'en-US', 'network_required': '1'},
        ]),
        isNull,
      );
    },
  );

  test('bundled CC0 cues are valid Ogg files', () async {
    for (final asset in const [
      'assets/audio/navigation/off_route_warning.ogg',
      'assets/audio/navigation/junction_ahead.ogg',
    ]) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(10000));
      expect(
        data.buffer.asUint8List(data.offsetInBytes, 4),
        orderedEquals('OggS'.codeUnits),
      );
    }
  });

  test('feedback failures do not escape into activity recording', () async {
    final feedback = NavigationAlertFeedback(
      haptic: () => Future<void>.error(StateError('haptic unavailable')),
      playTone: (_) => Future<bool>.error(StateError('audio unavailable')),
      speak: (_) => Future<bool>.error(StateError('voice unavailable')),
      stop: () => Future<void>.error(StateError('stop unavailable')),
      wait: (_) async {},
    );

    await expectLater(
      feedback.notify(offRoute, mode: NavFeedbackMode.toneAndVoice),
      completes,
    );
  });
}
