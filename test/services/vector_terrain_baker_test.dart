import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/vector_terrain_baker.dart';

Future<Uint8List> _png(
  int width,
  int height,
  void Function(Uint8List pixels) fill,
) async {
  final pixels = Uint8List(width * height * 4);
  fill(pixels);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _basePng() => _png(256, 256, (pixels) {
  for (var offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = 238;
    pixels[offset + 1] = 242;
    pixels[offset + 2] = 236;
    pixels[offset + 3] = 255;
  }
});

Future<Uint8List> _terrariumPng() => _png(32, 32, (pixels) {
  for (var y = 0; y < 32; y++) {
    for (var x = 0; x < 32; x++) {
      final offset = (y * 32 + x) * 4;
      pixels[offset] = 128;
      pixels[offset + 1] = (x * 4).clamp(0, 255);
      pixels[offset + 2] = 0;
      pixels[offset + 3] = 255;
    }
  }
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('does not request terrain below the topographic zoom floor', () async {
    final base = await _basePng();
    var requests = 0;
    final baker = TerrariumVectorTerrainBaker(
      config: MapProviderConfig.terrariumTerrain,
      client: MockClient((request) async {
        requests++;
        return http.Response('', 500);
      }),
    );

    final output = await baker.bake(base, const TileCoordinate(9, 1, 1));

    expect(output, base);
    expect(requests, 0);
  });

  test('bakes terrain into a converted vector PNG', () async {
    final base = await _basePng();
    final terrain = await _terrariumPng();
    final baker = TerrariumVectorTerrainBaker(
      config: MapProviderConfig.terrariumTerrain,
      client: MockClient((request) async => http.Response.bytes(terrain, 200)),
    );

    final output = await baker.bake(base, const TileCoordinate(12, 2200, 1400));

    expect(output.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    expect(output, isNot(equals(base)));
  });

  test('deep tiles share one rendered z13 terrain parent in memory', () async {
    final base = await _basePng();
    final terrain = await _terrariumPng();
    final paths = <String>[];
    final baker = TerrariumVectorTerrainBaker(
      config: MapProviderConfig.terrariumTerrain,
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response.bytes(terrain, 200);
      }),
    );

    await baker.bake(base, const TileCoordinate(16, 400, 400));
    await baker.bake(base, const TileCoordinate(16, 401, 400));

    expect(paths, hasLength(1));
    expect(paths.single, contains('/13/50/50.png'));
  });

  test('missing terrain leaves the vector tile unchanged', () async {
    final base = await _basePng();
    final baker = TerrariumVectorTerrainBaker(
      config: MapProviderConfig.terrariumTerrain,
      client: MockClient((request) async => http.Response('', 404)),
    );

    final output = await baker.bake(base, const TileCoordinate(12, 1, 1));

    expect(output, base);
  });
}
