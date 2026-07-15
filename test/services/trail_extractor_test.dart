import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/services/trail_extractor.dart';
import 'package:vector_tile/vector_tile.dart';

VectorTile _syntheticTile({required String klass}) {
  final value = VectorTileValue(stringValue: klass);
  // MoveTo(2048,2048) then LineTo(+0,+512): a short line near the tile center.
  // Command ints: MoveTo=9, LineTo=10; params are zig-zag encoded.
  final feature = VectorTileFeature(
    id: Int64(1),
    tags: [0, 0],
    type: VectorTileGeomType.LINESTRING,
    geometryList: [9, 4096, 4096, 10, 0, 1024],
    extent: 4096,
    keys: ['class'],
    values: [value],
  );
  final layer = VectorTileLayer(
    name: 'transportation',
    extent: 4096,
    version: 2,
    keys: ['class'],
    values: [value],
    features: [feature],
  );
  return VectorTile(layers: [layer]);
}

void main() {
  test('extracts a path trail and projects to correct lat/lng order', () {
    // Tile z=2, x=3, y=0 covers roughly lon [90,180], lat [66.5,85.05].
    final trails = const TrailExtractor().extractFromTile(
      _syntheticTile(klass: 'path'),
      2,
      3,
      0,
    );

    expect(trails, hasLength(1));
    expect(trails.first.kind, 'path');
    expect(trails.first.points, hasLength(2));

    final point = trails.first.points.first;
    // Latitude and longitude must not be swapped.
    expect(point.latitude, inInclusiveRange(66.0, 85.1));
    expect(point.longitude, inInclusiveRange(90.0, 180.0));
  });

  test('ignores non-trail transportation classes', () {
    final trails = const TrailExtractor().extractFromTile(
      _syntheticTile(klass: 'primary'),
      2,
      3,
      0,
    );
    expect(trails, isEmpty);
  });
}
