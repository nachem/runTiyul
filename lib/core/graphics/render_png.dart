import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Owns native drawing resources through encoding and all failure paths.
/// OFF-005: repeated offline conversion must not retain native pictures/images.
Future<Uint8List> renderPng({
  required int width,
  required int height,
  required FutureOr<void> Function(ui.Canvas canvas) draw,
}) async {
  final recorder = ui.PictureRecorder();
  ui.Picture? picture;
  ui.Image? image;
  try {
    final canvas = ui.Canvas(recorder);
    await draw(canvas);
    picture = recorder.endRecording();
    image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not encode the map tile.');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
  }
}
