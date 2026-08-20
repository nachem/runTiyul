import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'navigation_monitor.dart';

typedef AlertHaptic = Future<void> Function(NavAlert alert);
typedef AlertTonePlayer = Future<bool> Function(NavAlert alert);
typedef AlertVoicePlayer = Future<bool> Function(String message);
typedef AlertWait = Future<void> Function(Duration duration);

class NavigationFeedbackResult {
  const NavigationFeedbackResult({
    this.tonePlayed = false,
    this.voiceSpoken = false,
    this.usedToneFallback = false,
  });

  final bool tonePlayed;
  final bool voiceSpoken;
  final bool usedToneFallback;

  bool get audioPlayed => tonePlayed || voiceSpoken;
}

/// Delivers the optional audio and haptic feedback required by NAV-004.
class NavigationAlertFeedback {
  static const _navigationAudioChannel = MethodChannel(
    'trail_runner/navigation_audio',
  );

  factory NavigationAlertFeedback({
    required AlertHaptic haptic,
    required AlertTonePlayer playTone,
    required AlertVoicePlayer speak,
    Future<void> Function()? stop,
    Future<void> Function()? dispose,
    AlertWait? wait,
  }) => NavigationAlertFeedback._(
    haptic: haptic,
    playTone: playTone,
    speak: speak,
    stop: stop ?? _noOp,
    dispose: dispose ?? _noOp,
    wait: wait ?? Future<void>.delayed,
  );

  NavigationAlertFeedback._({
    required this._haptic,
    required this._playTone,
    required this._speak,
    required this._stop,
    required this._dispose,
    required this._wait,
  });

  factory NavigationAlertFeedback.device() {
    final player = AudioPlayer();
    final textToSpeech = FlutterTts();
    final audioContext = AudioContextConfig(
      focus: AudioContextConfigFocus.duckOthers,
    ).build();
    Future<String?>? speechSetup;
    return NavigationAlertFeedback(
      haptic: (alert) => switch (alert) {
        NavAlert.offRoute ||
        NavAlert.offRouteReminder => HapticFeedback.heavyImpact(),
        NavAlert.junction => HapticFeedback.mediumImpact(),
        NavAlert.progress => HapticFeedback.lightImpact(),
        NavAlert.none => _noOp(),
      },
      playTone: (alert) async {
        final asset = switch (alert) {
          NavAlert.offRoute || NavAlert.offRouteReminder => _offRouteToneAsset,
          NavAlert.junction || NavAlert.progress => _junctionToneAsset,
          NavAlert.none => null,
        };
        if (asset == null) return false;
        await player.stop();
        await player.play(
          AssetSource(asset),
          mode: PlayerMode.lowLatency,
          ctx: audioContext,
        );
        return true;
      },
      speak: (message) async {
        try {
          final locale = await (speechSetup ??= _configureSpeech(textToSpeech));
          if (locale == null) {
            speechSetup = null;
            return false;
          }
          await textToSpeech.stop();
          return await textToSpeech.speak(message, focus: Platform.isAndroid) ==
              1;
        } on Object {
          speechSetup = null;
          rethrow;
        }
      },
      stop: () async {
        await Future.wait([player.stop(), textToSpeech.stop()]);
        if (Platform.isIOS) {
          await _navigationAudioChannel.invokeMethod<void>('release');
        }
      },
      dispose: () async {
        await textToSpeech.stop();
        await player.dispose();
      },
    );
  }

  factory NavigationAlertFeedback.silent() => NavigationAlertFeedback(
    haptic: (_) => _noOp(),
    playTone: (_) async => false,
    speak: (_) async => false,
  );

  final AlertHaptic _haptic;
  final AlertTonePlayer _playTone;
  final AlertVoicePlayer _speak;
  final Future<void> Function() _stop;
  final Future<void> Function() _dispose;
  final AlertWait _wait;
  int _generation = 0;

  static const _offRouteToneAsset = 'audio/navigation/off_route_warning.ogg';
  static const _junctionToneAsset = 'audio/navigation/junction_ahead.ogg';

  Future<NavigationFeedbackResult> notify(
    NavStatus status, {
    required NavFeedbackMode mode,
  }) async {
    final alert = status.triggered;
    if (alert == NavAlert.none) return const NavigationFeedbackResult();

    final generation = ++_generation;
    final haptic = _bestEffortAction(() => _haptic(alert));
    await _bestEffortAction(_stop);

    var tonePlayed = false;
    var voiceSpoken = false;
    if (mode.usesTone) {
      tonePlayed = await _playTonePattern(status, generation);
    }

    if (mode.usesVoice && generation == _generation) {
      if (tonePlayed) {
        await _wait(const Duration(milliseconds: 80));
      }
      if (generation == _generation) {
        final message = guidanceFor(status);
        voiceSpoken = message != null
            ? await _bestEffortBool(() => _speak(message))
            : false;
      }
    }

    var usedToneFallback = false;
    if (mode == NavFeedbackMode.voice &&
        !voiceSpoken &&
        generation == _generation) {
      tonePlayed = await _playTonePattern(status, generation);
      usedToneFallback = tonePlayed;
    } else if (mode == NavFeedbackMode.toneAndVoice &&
        !voiceSpoken &&
        tonePlayed) {
      usedToneFallback = true;
    }

    await haptic;
    if (generation == _generation && (mode.usesTone || mode.usesVoice)) {
      await _bestEffortAction(_stop);
    }
    return NavigationFeedbackResult(
      tonePlayed: tonePlayed,
      voiceSpoken: voiceSpoken,
      usedToneFallback: usedToneFallback,
    );
  }

  Future<void> dispose() async {
    _generation++;
    await _bestEffortAction(_stop);
    await _bestEffortAction(_dispose);
  }

  static String? guidanceFor(NavStatus status) {
    return switch (status.triggered) {
      NavAlert.offRoute ||
      NavAlert.offRouteReminder => _offRouteGuidance(status),
      NavAlert.junction => _junctionGuidance(status),
      NavAlert.progress => _progressGuidance(status),
      NavAlert.none => null,
    };
  }

  Future<bool> _playTonePattern(NavStatus status, int generation) async {
    final count = switch (status.triggered) {
      NavAlert.offRouteReminder
          when status.offRouteTrend == OffRouteTrend.approaching =>
        2,
      NavAlert.offRouteReminder
          when status.offRouteTrend == OffRouteTrend.movingAway =>
        3,
      NavAlert.progress => 2,
      _ => 1,
    };
    final gap = switch (status.triggered) {
      NavAlert.progress => const Duration(milliseconds: 600),
      _ when status.offRouteTrend == OffRouteTrend.approaching =>
        const Duration(milliseconds: 900),
      _ => const Duration(milliseconds: 220),
    };
    var played = false;
    for (var index = 0; index < count && generation == _generation; index++) {
      final cuePlayed = await _bestEffortBool(
        () => _playTone(status.triggered),
      );
      played = cuePlayed || played;
      if (cuePlayed && generation == _generation) {
        await _wait(_toneDuration(status.triggered));
      }
      if (index < count - 1 && generation == _generation) {
        await _wait(gap);
      }
    }
    return played;
  }

  static String _offRouteGuidance(NavStatus status) {
    final distance = status.distanceToRouteMeters;
    final recoveryCompass = status.forwardRecoveryBearingDegrees == null
        ? null
        : _compassDirection(status.forwardRecoveryBearingDegrees!);
    final lead = distance == null
        ? 'Off route'
        : '${_spokenDistance(distance)} meters off route';
    if (!status.hasForwardRecovery) {
      return '$lead. Keep to a recognized trail or path. '
          'Finding a forward connection ahead.';
    }
    final recoveryDistance = status.forwardRecoveryDistanceMeters;
    final direction = recoveryCompass ?? 'forward';
    return [
      '$lead.',
      'Follow the marked path $direction.',
      if (recoveryDistance != null)
        'Rejoin the planned route in ${_spokenDistance(recoveryDistance)} meters.',
    ].join(' ');
  }

  static String _progressGuidance(NavStatus status) {
    final completed = status.routeCompletedMeters;
    final remaining = status.routeRemainingMeters;
    if (completed == null || remaining == null) return 'On route.';
    return '${_spokenRouteDistance(completed)} completed, '
        '${_spokenRouteDistance(remaining)} remaining.';
  }

  static String _spokenRouteDistance(double meters) {
    if (meters < 1000) return '${_spokenDistance(meters)} meters';
    final kilometers = (meters / 1000).toStringAsFixed(1);
    return '$kilometers kilometers';
  }

  static String _compassDirection(double bearing) {
    const directions = [
      'north',
      'north-east',
      'east',
      'south-east',
      'south',
      'south-west',
      'west',
      'north-west',
    ];
    return directions[((bearing + 22.5) ~/ 45) % directions.length];
  }

  static String _junctionGuidance(NavStatus status) {
    final distance = status.junctionDistanceMeters;
    final instruction = maneuverInstruction(
      status.junctionTurnDegrees,
      fallback: status.junctionTurn,
    );
    final lead = status.maneuverPhase == ManeuverPhase.apex
        ? '${_capitalize(instruction)} now'
        : distance == null
        ? 'Junction ahead, $instruction'
        : 'In ${_spokenDistance(distance)} meters, $instruction';
    final following = status.followingTurnDegrees == null
        ? ''
        : ', then immediately ${maneuverInstruction(status.followingTurnDegrees)}';
    return '$lead$following.';
  }

  static String maneuverInstruction(
    double? turnDegrees, {
    TurnDirection? fallback,
  }) {
    if (turnDegrees == null || !turnDegrees.isFinite) {
      return switch (fallback) {
        TurnDirection.left => 'keep left',
        TurnDirection.right => 'keep right',
        TurnDirection.straight => 'continue straight',
        null => 'check the map',
      };
    }
    final magnitude = turnDegrees.abs();
    final rounded = magnitude.round();
    if (magnitude <= 15) return 'continue straight';
    if (magnitude >= 150) return 'make a $rounded degree U-turn';
    final side = turnDegrees < 0 ? 'left' : 'right';
    if (magnitude <= 55) return 'bear $side $rounded degrees';
    if (magnitude <= 110) return 'turn $side $rounded degrees';
    return 'make a sharp $side turn, $rounded degrees';
  }

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  static int _spokenDistance(double meters) {
    final rounded = (meters / 5).round() * 5;
    return rounded < 5 ? 5 : rounded;
  }

  static Duration _toneDuration(NavAlert alert) => switch (alert) {
    NavAlert.offRoute ||
    NavAlert.offRouteReminder => const Duration(milliseconds: 556),
    NavAlert.junction || NavAlert.progress => const Duration(milliseconds: 501),
    NavAlert.none => Duration.zero,
  };

  static Future<String?> _configureSpeech(FlutterTts textToSpeech) async {
    await textToSpeech.awaitSpeakCompletion(true);
    await textToSpeech.setSpeechRate(0.48);
    await textToSpeech.setVolume(1);
    await textToSpeech.setPitch(1);
    if (Platform.isAndroid) {
      await textToSpeech.setAudioAttributesForNavigation();
      final voice = selectOfflineEnglishVoice(await textToSpeech.getVoices);
      if (voice == null) return null;
      final locale = voice['locale']!;
      if (await textToSpeech.isLanguageInstalled(locale) != true) return null;
      if (await textToSpeech.setLanguage(locale) != 1) return null;
      if (await textToSpeech.setVoice(voice) != 1) return null;
      return locale;
    } else if (Platform.isIOS) {
      await textToSpeech.setSharedInstance(true);
      await textToSpeech.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        const [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions
              .interruptSpokenAudioAndMixWithOthers,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }

    final languages = await textToSpeech.getLanguages;
    if (languages is! Iterable) return null;
    final available = languages
        .map((language) => language.toString())
        .where((language) => language.toLowerCase().startsWith('en'))
        .toList(growable: false);
    final ordered = [
      for (final preferred in const ['en-US', 'en-GB', 'en-AU'])
        ...available.where(
          (language) => language.toLowerCase() == preferred.toLowerCase(),
        ),
      ...available.where(
        (language) => !const [
          'en-US',
          'en-GB',
          'en-AU',
        ].any((preferred) => language.toLowerCase() == preferred.toLowerCase()),
      ),
    ];
    for (final locale in ordered) {
      final usable = await textToSpeech.isLanguageAvailable(locale);
      if (usable == true) {
        await textToSpeech.setLanguage(locale);
        return locale;
      }
    }
    return null;
  }

  static Map<String, String>? selectOfflineEnglishVoice(Object? rawVoices) {
    if (rawVoices is! Iterable) return null;
    final candidates = <Map<String, String>>[];
    for (final rawVoice in rawVoices) {
      if (rawVoice is! Map) continue;
      final name = rawVoice['name']?.toString() ?? '';
      final locale = rawVoice['locale']?.toString() ?? '';
      final networkRequired = rawVoice['network_required']
          ?.toString()
          .toLowerCase();
      final features = rawVoice['features']?.toString().toLowerCase() ?? '';
      if (name.isEmpty ||
          !locale.toLowerCase().startsWith('en') ||
          (networkRequired != '0' && networkRequired != 'false') ||
          features.contains('notinstalled') ||
          features.contains('not_installed')) {
        continue;
      }
      candidates.add({
        'name': name,
        'locale': locale,
        'quality': rawVoice['quality']?.toString() ?? 'unknown',
      });
    }
    candidates.sort((left, right) {
      final localeComparison = _localeRank(
        left['locale']!,
      ).compareTo(_localeRank(right['locale']!));
      if (localeComparison != 0) return localeComparison;
      return _qualityRank(
        left['quality']!,
      ).compareTo(_qualityRank(right['quality']!));
    });
    if (candidates.isEmpty) return null;
    return {
      'name': candidates.first['name']!,
      'locale': candidates.first['locale']!,
    };
  }

  static int _localeRank(String locale) => switch (locale.toLowerCase()) {
    'en-us' => 0,
    'en-gb' => 1,
    'en-au' => 2,
    _ => 3,
  };

  static int _qualityRank(String quality) => switch (quality.toLowerCase()) {
    'very high' => 0,
    'high' => 1,
    'normal' => 2,
    'low' => 3,
    'very low' => 4,
    _ => 5,
  };

  static Future<void> _bestEffortAction(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Navigation feedback must never interrupt activity recording.
    }
  }

  static Future<bool> _bestEffortBool(Future<bool> Function() action) async {
    try {
      return await action();
    } on Object {
      return false;
    }
  }

  static Future<void> _noOp() async {}
}
