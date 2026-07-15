import 'dart:typed_data';

import 'package:vector_tile_renderer/vector_tile_renderer.dart';

/// Converts a single Mapbox Vector Tile (MVT) into a raster PNG on the device.
///
/// This is the "convert if needed" step of the offline pipeline: free vector
/// map data is rasterized on the phone at download time so it can be stored and
/// rendered by the existing raster (`flutter_map`) offline layer without any
/// network access afterwards.
///
/// The vector tiles must use the OpenMapTiles source schema, which is what the
/// bundled [ProvidedThemes.lightTheme] targets (its layers read from the
/// `openmaptiles` source). Data produced by planetiler's default profile,
/// OpenMapTiles, or MapTiler downloads satisfies this.
class VectorTileRasterizer {
  VectorTileRasterizer({Theme? theme, this.scale = 1})
    : assert(scale >= 1 && scale <= 4, 'scale must be between 1 and 4'),
      theme = theme ?? ProvidedThemes.lightTheme() {
    _factory = TileFactory(this.theme, const Logger.noop());
  }

  /// The theme used to style rendered tiles.
  final Theme theme;

  /// Output scale. `1` renders a 256px tile; higher values (up to `4`) produce
  /// sharper tiles at proportionally larger byte sizes.
  final int scale;

  /// The source id that the bundled theme expects tiles to be keyed under.
  static const _sourceId = 'openmaptiles';

  late final TileFactory _factory;
  final VectorTileReader _reader = VectorTileReader();

  /// Renders [mvtBytes] (a decoded, uncompressed MVT tile) at tile zoom [z] to
  /// PNG bytes. Throws when [mvtBytes] is not a decodable vector tile.
  Future<Uint8List> rasterize(List<int> mvtBytes, int z) async {
    final bytes = mvtBytes is Uint8List
        ? mvtBytes
        : Uint8List.fromList(mvtBytes);
    final vectorTile = _reader.read(bytes);
    final tile = _factory.create(vectorTile);
    final renderer = ImageRenderer(theme: theme, scale: scale.toDouble());
    final image = await renderer.render(
      TileSource(tileset: Tileset({_sourceId: tile})),
      zoom: z.toDouble(),
      zoomScaleFactor: 1,
    );
    try {
      return await image.toPng();
    } finally {
      image.dispose();
    }
  }
}
