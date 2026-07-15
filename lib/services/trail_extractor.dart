import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:vector_tile/vector_tile.dart';

import 'trail_network.dart';

/// Extracts trail geometry from an OpenMapTiles vector tile.
///
/// The `transportation` layer contains line features with a `class` attribute;
/// classes `path` and `track` are the walkable/runnable trails. Coordinates are
/// projected to latitude/longitude by the `vector_tile` package using the
/// tile's z/x/y, so the caller receives real-world trail lines.
class TrailExtractor {
  const TrailExtractor({this.trailClasses = const {'path', 'track'}});

  /// The OpenMapTiles `transportation` classes treated as trails.
  final Set<String> trailClasses;

  /// Extracts trails from raw MVT [bytes] for tile [z]/[x]/[y].
  List<TrailPolyline> extractFromBytes(List<int> bytes, int z, int x, int y) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    return extractFromTile(VectorTile.fromBytes(bytes: data), z, x, y);
  }

  /// Extracts trails from an already-decoded [tile] for tile [z]/[x]/[y].
  List<TrailPolyline> extractFromTile(VectorTile tile, int z, int x, int y) {
    final trails = <TrailPolyline>[];
    for (final layer in tile.layers.where(
      (layer) => layer.name == 'transportation',
    )) {
      for (final feature in layer.features) {
        if (feature.type != VectorTileGeomType.LINESTRING) continue;
        final properties = feature.decodeProperties();
        final kind = properties['class']?.stringValue;
        if (kind == null || !trailClasses.contains(kind)) continue;
        final name = properties['name']?.stringValue;

        final geoJson = feature.toGeoJson(x: x, y: y, z: z);
        if (geoJson is GeoJsonLineString) {
          _add(trails, geoJson.geometry?.coordinates, kind, name);
        } else if (geoJson is GeoJsonMultiLineString) {
          for (final line in geoJson.geometry?.coordinates ?? const []) {
            _add(trails, line, kind, name);
          }
        }
      }
    }
    return trails;
  }

  void _add(
    List<TrailPolyline> trails,
    List<List<double>>? coordinates,
    String kind,
    String? name,
  ) {
    if (coordinates == null || coordinates.length < 2) return;
    // GeoJSON coordinates are [longitude, latitude].
    final points = coordinates
        .map((c) => LatLng(c[1], c[0]))
        .toList(growable: false);
    trails.add(TrailPolyline(points: points, kind: kind, name: name));
  }
}
