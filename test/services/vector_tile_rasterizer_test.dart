import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/services/vector_tile_rasterizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rasterizes an empty vector tile to a valid PNG', () async {
    final rasterizer = VectorTileRasterizer();
    // An empty MVT buffer decodes to a tile with no layers; the theme still
    // paints its background, so the output is a valid, non-empty PNG.
    final png = await rasterizer.rasterize(<int>[], 14);

    expect(png, isNotEmpty);
    // PNG signature: 89 50 4E 47.
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });
}
