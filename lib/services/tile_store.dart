import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/geo/tile_math.dart';
import '../models/offline_area.dart';
import 'map_provider.dart';

enum MapTileMode { auto, online, offline }

/// The tile-storage namespace for a base-map source. Tiles are keyed by both the
/// provider and the download format so overlapping areas of different formats
/// (for example on-device converted vector vs. OSM raster) never collide on
/// disk, while areas that share a format still deduplicate identical tiles.
String offlineTileNamespace(String providerId, OfflineSourceFormat format) {
  final suffix = format == OfflineSourceFormat.convertedVector ? 'vec' : 'ras';
  return '$providerId-$suffix';
}

class TileStore {
  TileStore._(this.root);

  final Directory root;

  static Future<TileStore> create() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'offline_tiles'));
    await root.create(recursive: true);
    return TileStore._(root);
  }

  static Future<TileStore> at(Directory root) async {
    await root.create(recursive: true);
    return TileStore._(root);
  }

  /// The directory that holds every tile for [providerId], with the provider id
  /// sanitized so it is always a safe single path segment.
  Directory dirFor(String providerId) {
    final safeProvider = providerId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return Directory(p.join(root.path, safeProvider));
  }

  File fileFor(String providerId, int zoom, int x, int y) =>
      File(p.join(dirFor(providerId).path, '$zoom', '$x', '$y.png'));

  String relativePath(File file) => p.relative(file.path, from: root.path);
}

class OfflineFirstTileProvider extends TileProvider {
  OfflineFirstTileProvider({
    required this.store,
    required this.config,
    this.mode = MapTileMode.auto,
  }) : super(headers: {'User-Agent': 'TrailRunner/1.0'});

  final TileStore store;
  final MapProviderConfig config;
  final MapTileMode mode;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final file = store.fileFor(
      config.id,
      coordinates.z,
      coordinates.x,
      coordinates.y,
    );
    if (mode != MapTileMode.online && file.existsSync()) return FileImage(file);
    if (mode == MapTileMode.offline) {
      return MemoryImage(TileProvider.transparentImage);
    }
    return NetworkImage(
      config.tileUri(coordinates.z, coordinates.x, coordinates.y).toString(),
      headers: headers,
    );
  }
}

class TileStoreListenable extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// Renders saved offline tiles from several areas, honoring the user's ordering
/// so the top-most area is drawn over the ones beneath it where they overlap.
///
/// [areas] is top-first: for each requested tile the provider returns the tile
/// from the first (highest) area whose bounds and zoom cover it and that has a
/// stored tile, using that area's per-format namespace. When no area covers the
/// tile, a transparent tile is returned so a lower map layer (or nothing) shows
/// through — this provider never touches the network.
class OrderedOfflineTileProvider extends TileProvider {
  OrderedOfflineTileProvider({required this.store, required this.areas})
    : super(headers: {'User-Agent': 'TrailRunner/1.0'});

  final TileStore store;

  /// Base-map areas in top-first order.
  final List<OfflineArea> areas;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    for (final area in areas) {
      if (coordinates.z < area.minZoom || coordinates.z > area.maxZoom) {
        continue;
      }
      if (area.bounds.crossesAntimeridian) continue;
      if (!tileIntersectsBounds(
        area.bounds,
        coordinates.z,
        coordinates.x,
        coordinates.y,
      )) {
        continue;
      }
      final file = store.fileFor(
        offlineTileNamespace(area.providerId, area.sourceFormat),
        coordinates.z,
        coordinates.x,
        coordinates.y,
      );
      if (file.existsSync()) return FileImage(file);
    }
    return MemoryImage(TileProvider.transparentImage);
  }
}
