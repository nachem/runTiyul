import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/core/graphics/render_png.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG rendering disposes pictures on success and draw failure', () async {
    final pictures = <ui.Picture>[];
    final disposed = <ui.Picture>[];
    final previousCreate = ui.Picture.onCreate;
    final previousDispose = ui.Picture.onDispose;
    ui.Picture.onCreate = pictures.add;
    ui.Picture.onDispose = disposed.add;
    addTearDown(() {
      ui.Picture.onCreate = previousCreate;
      ui.Picture.onDispose = previousDispose;
    });
    for (var i = 0; i < 10; i++) {
      final png = await renderPng(
        width: 16,
        height: 16,
        draw: (canvas) {
          canvas.drawColor(const ui.Color(0xff008800), ui.BlendMode.src);
        },
      );
      expect(png.take(4), [137, 80, 78, 71]);
    }
    await expectLater(
      renderPng(
        width: 16,
        height: 16,
        draw: (_) {
          throw StateError('Drawing failed');
        },
      ),
      throwsStateError,
    );
    expect(pictures, hasLength(11));
    expect(disposed, unorderedEquals(pictures));
  });
}
