import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import 'map_render_theme.dart';

/// Converts a single Mapbox Vector Tile (MVT) into a raster PNG on the device.
///
/// This is the "convert if needed" step of the offline pipeline: free vector
/// map data is rasterized on the phone at download time so it can be stored and
/// rendered by the existing raster (`flutter_map`) offline layer without any
/// network access afterwards.
///
/// The vector tiles must use the OpenMapTiles source schema, which is what the
/// bundled [buildTrailRenderTheme] targets (its layers read from the
/// `openmaptiles` source). Data produced by planetiler's default profile,
/// OpenMapTiles, or MapTiler downloads satisfies this.
class VectorTileRasterizer {
  VectorTileRasterizer({Theme? theme, this.scale = 1})
    : assert(scale >= 1 && scale <= 4, 'scale must be between 1 and 4'),
      theme = theme ?? buildTrailRenderTheme() {
    _factory = TileFactory(this.theme, const Logger.noop());
  }

  /// The theme used to style rendered tiles.
  final Theme theme;

  /// Output scale. `1` renders a 256px tile; higher values (up to `4`) produce
  /// sharper tiles at proportionally larger byte sizes.
  final int scale;

  /// The source id that the bundled theme expects tiles to be keyed under.
  static const _sourceId = 'openmaptiles';

  /// Web Mercator tile edge length in logical pixels.
  static const _tileSize = 256;

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

  /// Rasterizes [mvtBytes] — a tile at [sourceZ]/[sourceX]/[sourceY] — into the
  /// PNG for a deeper child tile [targetZ]/[targetX]/[targetY] (with
  /// [targetZ] > [sourceZ]). The parent's vector geometry is scaled up and only
  /// the child's sub-square is drawn, so lines and labels stay crisp beyond the
  /// source's maximum zoom instead of being pixel-stretched by the map view.
  Future<Uint8List> rasterizeOverzoom(
    List<int> mvtBytes, {
    required int sourceZ,
    required int sourceX,
    required int sourceY,
    required int targetZ,
    required int targetX,
    required int targetY,
  }) async {
    assert(targetZ > sourceZ, 'overzoom requires a deeper target zoom');
    final dz = targetZ - sourceZ;
    final factor = (1 << dz).toDouble();
    final subX = targetX - (sourceX << dz);
    final subY = targetY - (sourceY << dz);
    final sub = _tileSize / factor;

    final bytes = mvtBytes is Uint8List
        ? mvtBytes
        : Uint8List.fromList(mvtBytes);
    final tile = _factory.create(_reader.read(bytes));
    final tileSource = TileSource(tileset: Tileset({_sourceId: tile}));

    final recorder = ui.PictureRecorder();
    final size = (scale * _tileSize).toDouble();
    final rect = ui.Rect.fromLTWH(0, 0, size, size);
    final canvas = ui.Canvas(recorder, rect);
    canvas.clipRect(rect);
    // Retina/output scale, then the overzoom scale into the child's sub-square.
    canvas.scale(scale.toDouble() * factor);
    canvas.translate(-subX * sub, -subY * sub);
    Renderer(theme: theme).render(
      canvas,
      tileSource,
      zoomScaleFactor: factor,
      zoom: targetZ.toDouble(),
      rotation: 0,
    );
    final image = await recorder.endRecording().toImage(
      size.floor(),
      size.floor(),
    );
    try {
      return await image.toPng();
    } finally {
      image.dispose();
    }
  }
}
