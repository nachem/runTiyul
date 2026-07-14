import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:gpx/gpx.dart';

import '../core/ids.dart';
import '../models/run_activity.dart';
import '../models/trail_route.dart';

class GpxImportCancelled implements Exception {
  const GpxImportCancelled();
}

class GpxService {
  const GpxService();

  Future<TrailRoute> pickAndImport() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'GPX route', extensions: ['gpx']),
      ],
    );
    if (file == null) throw const GpxImportCancelled();
    final bytes = await file.readAsBytes();
    return parse(utf8.decode(bytes, allowMalformed: false), file.name);
  }

  TrailRoute parse(String xml, String fallbackName) {
    final document = GpxReader().fromString(xml);
    final points = <RoutePoint>[];
    String? name;

    for (final track in document.trks) {
      name ??= track.name;
      for (final segment in track.trksegs) {
        points.addAll(segment.trkpts.map(_pointFromWpt));
      }
    }
    if (points.isEmpty) {
      for (final route in document.rtes) {
        name ??= route.name;
        points.addAll(route.rtepts.map(_pointFromWpt));
      }
    }
    if (points.length < 2) {
      throw const FormatException(
        'The GPX file must contain at least two valid route or track points.',
      );
    }

    final now = DateTime.now().toUtc();
    return TrailRoute(
      id: RouteId.generate().value,
      name: _cleanName(name, fallbackName),
      source: RouteSource.gpx,
      createdAt: now,
      updatedAt: now,
      points: points,
    );
  }

  Future<bool> exportActivity(RunActivity activity) async {
    final name =
        'trail-run-${activity.startedAt.toLocal().toIso8601String().replaceAll(':', '-')}.gpx';
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'GPX activity', extensions: ['gpx']),
      ],
    );
    if (location == null) return false;

    final xml = activityAsXml(activity);
    await XFile.fromData(
      utf8.encode(xml),
      mimeType: 'application/gpx+xml',
      name: name,
    ).saveTo(location.path);
    return true;
  }

  String activityAsXml(RunActivity activity) {
    final gpx = Gpx()
      ..creator = 'RunTiyul'
      ..trks = [
        Trk(
          name: 'Trail run',
          trksegs: [
            Trkseg(
              trkpts: activity.samples
                  .map(
                    (sample) => Wpt(
                      lat: sample.latitude,
                      lon: sample.longitude,
                      ele: sample.altitude,
                      time: sample.recordedAt.toUtc(),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ];
    return GpxWriter().asString(
      gpx,
      pretty: true,
      compatibility: GpxCompatibilityMode.gpx11,
    );
  }

  RoutePoint _pointFromWpt(Wpt point) {
    final latitude = point.lat;
    final longitude = point.lon;
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('The GPX file contains invalid coordinates.');
    }
    return RoutePoint(
      latitude: latitude,
      longitude: longitude,
      elevation: point.ele,
      recordedAt: point.time?.toUtc(),
    );
  }

  String _cleanName(String? candidate, String fallbackName) {
    final value = candidate?.trim();
    if (value != null && value.isNotEmpty) return value;
    final withoutExtension = fallbackName.replaceFirst(
      RegExp(r'\.gpx$', caseSensitive: false),
      '',
    );
    return withoutExtension.trim().isEmpty
        ? 'Imported route'
        : withoutExtension;
  }
}
