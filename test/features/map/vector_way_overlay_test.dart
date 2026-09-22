import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/features/map/vector_way_overlay_controller.dart';
import 'package:trail_runner/services/route_trail_builder.dart';
import 'package:trail_runner/services/trail_network.dart';

class _Builder extends RouteTrailBuilder {
  final calls = <bool>[];
  Completer<TrailNetwork>? pending;
  @override
  Future<TrailNetwork> networkForBounds(
    GeoBounds bounds,
    String sourceUrl, {
    bool allowNetwork = true,
    bool Function()? isCancelled,
  }) async {
    calls.add(allowNetwork);
    return pending?.future ??
        Future.value(
          const TrailNetwork([
            TrailPolyline(
              points: [LatLng(0, 0), LatLng(0, 0.001)],
              kind: 'path',
            ),
          ]),
        );
  }
}

void main() {
  const bounds = GeoBounds(north: 0.01, south: 0, east: 0.01, west: 0);
  test(
    'MAP-013 hides and does no loading at low zoom; offline uses cache only',
    () async {
      final builder = _Builder();
      final overlay = VectorWayOverlayController(
        builder,
        debounce: Duration.zero,
      );
      addTearDown(overlay.dispose);
      overlay.update(
        bounds: bounds,
        zoom: 10,
        source: 'https://example/planet',
        allowNetwork: true,
      );
      overlay.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(builder.calls, isEmpty);
      expect(overlay.visible, isFalse);
      overlay.update(
        bounds: bounds,
        zoom: 16,
        source: 'https://example/planet',
        allowNetwork: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(builder.calls, [false]);
      expect(overlay.network.isEmpty, isFalse);
      overlay.update(
        bounds: bounds,
        zoom: 17,
        source: 'https://example/planet',
        allowNetwork: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(builder.calls, [false]);
    },
  );

  test('hiding during a load cannot restore stale vector lines', () async {
    final builder = _Builder()..pending = Completer<TrailNetwork>();
    final overlay = VectorWayOverlayController(
      builder,
      debounce: Duration.zero,
    );
    addTearDown(overlay.dispose);
    overlay.update(
      bounds: bounds,
      zoom: 16,
      source: 'https://example/planet',
      allowNetwork: true,
    );
    overlay.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    overlay.setEnabled(false);
    builder.pending!.complete(
      const TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.001)], kind: 'path'),
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(overlay.network.isEmpty, isTrue);
    expect(overlay.loading, isFalse);
  });

  test(
    'rapid viewport changes keep one request active and only the latest queued',
    () async {
      final builder = _Builder()..pending = Completer<TrailNetwork>();
      final overlay = VectorWayOverlayController(
        builder,
        debounce: Duration.zero,
      );
      addTearDown(overlay.dispose);
      overlay.update(
        bounds: bounds,
        zoom: 16,
        source: 'https://example/planet',
        allowNetwork: true,
      );
      overlay.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      for (var index = 1; index < 5; index++) {
        overlay.update(
          bounds: GeoBounds(
            north: index.toDouble(),
            south: index - 0.01,
            east: index.toDouble(),
            west: index - 0.01,
          ),
          zoom: 16,
          source: 'https://example/planet',
          allowNetwork: true,
        );
        await Future<void>.delayed(Duration.zero);
      }
      expect(builder.calls, [true]);
      builder.pending!.complete(const TrailNetwork([]));
      await Future<void>.delayed(Duration.zero);
      expect(builder.calls, [true, true]);
    },
  );
}
