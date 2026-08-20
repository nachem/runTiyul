import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';

class RouteGeometryCleaner {
  const RouteGeometryCleaner({
    this.returnToleranceMeters = 8,
    this.maxExcursionMeters = 18,
    this.maxSpikeLengthMeters = 45,
    this.distance = const GeoDistance(),
  });

  final double returnToleranceMeters;
  final double maxExcursionMeters;
  final double maxSpikeLengthMeters;
  final GeoDistance distance;

  List<LatLng> clean(List<LatLng> route) {
    if (route.length < 3) return route;
    final cleaned = <LatLng>[];
    var start = 0;
    while (start < route.length) {
      final point = route[start];
      if (cleaned.isEmpty ||
          distance.metersBetween(cleaned.last, point) > 0.5) {
        cleaned.add(point);
      }

      final spikeEnd = _spikeEnd(route, start);
      start = spikeEnd == null ? start + 1 : spikeEnd + 1;
    }
    return cleaned.length >= 2 ? cleaned : route;
  }

  int? _spikeEnd(List<LatLng> route, int start) {
    if (start + 2 >= route.length) return null;
    var pathMeters = 0.0;
    var furthestMeters = 0.0;
    int? furthestReturn;
    for (var index = start + 1; index < route.length; index++) {
      pathMeters += distance.metersBetween(route[index - 1], route[index]);
      if (pathMeters > maxSpikeLengthMeters) break;
      final fromStart = distance.metersBetween(route[start], route[index]);
      if (fromStart > furthestMeters) furthestMeters = fromStart;
      if (furthestMeters > maxExcursionMeters) break;
      if (index >= start + 2 && fromStart <= returnToleranceMeters) {
        furthestReturn = index;
      }
    }
    return furthestReturn;
  }
}
