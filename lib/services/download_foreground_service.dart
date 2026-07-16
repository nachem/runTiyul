import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps offline-map downloads alive while the app is in the background.
///
/// The download loop itself runs on the Flutter main isolate. On Android this
/// starts a small foreground service (with an ongoing notification) so the OS
/// does not suspend or kill the process while tiles are still downloading, and
/// so network access keeps working with the screen off. It is a deliberate
/// no-op on other platforms, which cannot run this kind of long, custom
/// background work; those rely on [AppStore.resumeInterruptedDownloads] instead.
///
/// Every call is best-effort: a platform failure never propagates, so a
/// download always continues in the foreground even if the keep-alive service
/// cannot start.
class DownloadForegroundService {
  DownloadForegroundService();

  static const MethodChannel _channel = MethodChannel(
    'trail_runner/download_service',
  );

  /// Starts the keep-alive foreground service.
  Future<void> start() => _invoke('start');

  /// Stops the keep-alive foreground service.
  Future<void> stop() => _invoke('stop');

  Future<void> _invoke(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on Object {
      // Best-effort: never let a platform failure interrupt downloading.
    }
  }
}
