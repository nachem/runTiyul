import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/services/terrain_contour_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = TerrainContourService(interval: 10, indexEvery: 5);

  test('decodes Terrarium encoding to metres', () {
    // 32768 m offset means (128,0,0) == 0 m at the sea-level reference.
    expect(TerrainContourService.terrariumElevation(128, 0, 0), 0);
    // One step of green is 1 m.
    expect(TerrainContourService.terrariumElevation(128, 1, 0), 1);
    // One step of red is 256 m.
    expect(TerrainContourService.terrariumElevation(129, 0, 0), 256);
  });

  test('decodes an RGBA buffer into an elevation grid', () {
    // 2x1 tile: pixel 0 -> 0 m, pixel 1 -> 10 m.
    final rgba = Uint8List.fromList([
      128, 0, 0, 255, // 0 m
      128, 10, 0, 255, // 10 m
    ]);
    final tile = service.decodeTerrariumRgba(rgba, 2, 1);
    expect(tile.at(0, 0), 0);
    expect(tile.at(1, 0), 10);
    expect(tile.range, (0.0, 10.0));
  });

  test('flat terrain produces no contour lines', () {
    final tile = ElevationTile(4, 4, Float64List(16)); // all zero
    expect(service.contourSegments(tile), isEmpty);
  });

  test('a ramp crossing a contour level yields segments at that level', () {
    // 3x3 grid ramping 0..40 m across x, so the 10/20/30 m contours cross it.
    final elevations = Float64List(9);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        elevations[y * 3 + x] = x * 20.0; // 0, 20, 40 across columns
      }
    }
    final tile = ElevationTile(3, 3, elevations);
    final segments = service.contourSegments(tile);
    expect(segments, isNotEmpty);

    final levels = segments.map((s) => s.level).toSet();
    expect(levels, contains(10.0));
    expect(levels, contains(20.0));
    expect(levels, contains(30.0));
    // 20 m is a multiple of interval*indexEvery? interval 10 * indexEvery 5 =
    // 50, so 20 m is a minor line, not an index line.
    expect(
      segments.where((s) => s.level == 20.0).every((s) => !s.isIndex),
      isTrue,
    );
  });

  test('index lines fall on every fifth interval', () {
    final elevations = Float64List(9);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        elevations[y * 3 + x] = x * 60.0; // spans 0..120 m
      }
    }
    final tile = ElevationTile(3, 3, elevations);
    final segments = service.contourSegments(tile);
    // 50 m and 100 m are index lines (multiples of 50 m).
    expect(
      segments.where((s) => s.level == 50.0).every((s) => s.isIndex),
      isTrue,
    );
    expect(
      segments.where((s) => s.level == 100.0).every((s) => s.isIndex),
      isTrue,
    );
  });

  test('renders a contour tile to a valid PNG', () async {
    final elevations = Float64List(8 * 8);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        elevations[y * 8 + x] = x * 15.0;
      }
    }
    final tile = ElevationTile(8, 8, elevations);
    final png = await service.renderTile(tile);
    expect(png, isNotEmpty);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });

  test('renders a valid PNG with contour labels disabled', () async {
    const plain = TerrainContourService(
      interval: 10,
      indexEvery: 5,
      labelContours: false,
    );
    final elevations = Float64List(8 * 8);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        elevations[y * 8 + x] = x * 15.0;
      }
    }
    final tile = ElevationTile(8, 8, elevations);
    final png = await plain.renderTile(tile);
    expect(png, isNotEmpty);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });
}
