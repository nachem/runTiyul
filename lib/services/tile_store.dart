import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'map_provider.dart';

enum MapTileMode { auto, online, offline }

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

  File fileFor(String providerId, int zoom, int x, int y) {
    final safeProvider = providerId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File(p.join(root.path, safeProvider, '$zoom', '$x', '$y.png'));
  }

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
