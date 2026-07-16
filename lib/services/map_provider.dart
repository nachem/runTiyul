import 'package:flutter/foundation.dart';

class MapProviderConfig {
  const MapProviderConfig({
    required this.id,
    required this.urlTemplate,
    required this.attribution,
    required this.offlineDownloadsAllowed,
    required this.isDevelopmentOsmOverride,
    this.label = 'Map',
    this.vectorSourceUrl = '',
  });

  final String id;

  /// Short human-readable name shown in the base-layer picker (for example
  /// "Streets" or "Satellite").
  final String label;
  final String urlTemplate;
  final String attribution;
  final bool offlineDownloadsAllowed;
  final bool isDevelopmentOsmOverride;

  /// Whether this APK includes the on-device developer unlock for public raster
  /// downloads. This repository intentionally defaults the capability on; a
  /// future production release can set `ALLOW_PUBLIC_RASTER_DEV_UNLOCK=false`.
  /// Release builds still start locked until the user completes the warning
  /// gesture and confirmation on that device.
  static const bool publicRasterDevUnlockCompiled = bool.fromEnvironment(
    'ALLOW_PUBLIC_RASTER_DEV_UNLOCK',
    defaultValue: true,
  );

  /// URL (or local file path) of a vector MBTiles archive (OpenMapTiles schema)
  /// to build offline areas from. Empty means the per-tile raster downloader is
  /// used instead. When set, the selected area's vector tiles are downloaded and
  /// rasterized to PNG on the device.
  final String vectorSourceUrl;

  /// True when a vector source is configured, so offline areas are produced by
  /// on-device vector-to-raster conversion rather than per-tile downloads.
  bool get usesVectorSource => vectorSourceUrl.isNotEmpty;

  /// True when the configured tile URL is the public OpenStreetMap standard
  /// tile service, so an OpenStreetMap credit is accurate.
  bool get isOpenStreetMapStandard =>
      urlTemplate.contains('tile.openstreetmap.org');

  /// Public raster services allowed only by the explicit development workflow.
  /// This intentionally excludes Satellite and arbitrary custom providers.
  bool get isPublicDevelopmentRaster =>
      isOpenStreetMapStandard || id == 'cyclosm';

  MapProviderConfig withDevelopmentDownloadEnabled() => MapProviderConfig(
    id: id,
    label: label,
    urlTemplate: urlTemplate,
    attribution: attribution,
    offlineDownloadsAllowed: true,
    isDevelopmentOsmOverride: true,
    vectorSourceUrl: vectorSourceUrl,
  );

  static MapProviderConfig fromEnvironment() {
    const url = String.fromEnvironment(
      'TRAIL_TILE_URL',
      defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
    const id = String.fromEnvironment(
      'TRAIL_TILE_PROVIDER_ID',
      defaultValue: 'openstreetmap-standard',
    );
    const configuredAttribution = String.fromEnvironment(
      'TRAIL_TILE_ATTRIBUTION',
    );
    const approved = bool.fromEnvironment('TRAIL_TILE_OFFLINE_ALLOWED');
    const configuredDevelopmentOverride = bool.fromEnvironment(
      'ENABLE_DEV_OSM_DOWNLOADS',
      defaultValue: true,
    );
    final developmentOverride = kDebugMode && configuredDevelopmentOverride;
    const vectorSourceUrl = String.fromEnvironment(
      'TRAIL_VECTOR_MBTILES',
      defaultValue: 'https://tiles.openfreemap.org/planet',
    );
    // Only credit OpenStreetMap when the tiles actually come from the OSM
    // standard service. A custom provider that does not supply its own
    // attribution must not falsely claim OpenStreetMap.
    final isOsm = url.contains('tile.openstreetmap.org');
    final usesOpenFreeMap = vectorSourceUrl.contains('openfreemap.org');
    final developmentRasterAllowed = isOsm && developmentOverride;
    final attribution = configuredAttribution.isNotEmpty
        ? configuredAttribution
        : usesOpenFreeMap
        ? 'OpenStreetMap contributors, OpenMapTiles, OpenFreeMap'
        : (isOsm ? 'OpenStreetMap contributors' : 'Configured tile provider');
    return MapProviderConfig(
      id: id,
      urlTemplate: url,
      attribution: attribution,
      label: 'Streets',
      offlineDownloadsAllowed: approved || developmentRasterAllowed,
      isDevelopmentOsmOverride: developmentRasterAllowed && !approved,
      vectorSourceUrl: vectorSourceUrl,
    );
  }

  Uri tileUri(int zoom, int x, int y) {
    return Uri.parse(
      urlTemplate
          .replaceAll('{z}', '$zoom')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y'),
    );
  }

  /// Esri "World Imagery" satellite/orthophoto tiles. Interactive display is
  /// permitted with the credit in [attribution]; the service does not allow
  /// bulk/offline caching, so [offlineDownloadsAllowed] is false and this layer
  /// is never targeted by the offline downloader.
  static const MapProviderConfig esriWorldImagery = MapProviderConfig(
    id: 'esri-world-imagery',
    label: 'Satellite',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution:
        'Imagery: Esri, Maxar, Earthstar Geographics, and the GIS User '
        'Community',
    offlineDownloadsAllowed: false,
    isDevelopmentOsmOverride: false,
  );

  /// Additional online-only base layers the user can switch to for viewing.
  /// These are display-only imagery/basemap sources whose terms permit
  /// interactive display with attribution but not bulk offline download.
  static const List<MapProviderConfig> onlineImageryLayers = [esriWorldImagery];

  /// Free Terrarium-encoded elevation ("terrain-RGB") tiles from the AWS Open
  /// Data "Terrain Tiles" set. Every pixel encodes height, so the app derives
  /// contour lines and hillshade from them entirely on the device. The data is
  /// openly licensed (SRTM, Copernicus, GMTED, and other public sources) and
  /// permits offline use, so [offlineDownloadsAllowed] is true. These tiles are
  /// elevation data, never a display base layer.
  static const MapProviderConfig terrariumTerrain = MapProviderConfig(
    id: 'aws-terrarium',
    label: 'Contours',
    urlTemplate:
        'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/'
        '{z}/{x}/{y}.png',
    attribution:
        'Elevation: Terrain Tiles (AWS Open Data) from SRTM, Copernicus, '
        'GMTED, and other sources',
    offlineDownloadsAllowed: true,
    isDevelopmentOsmOverride: false,
  );

  /// The elevation source used only while baking contours and hillshade into a
  /// converted vector offline area. Defaults to [terrariumTerrain]; overridable
  /// with `TRAIL_TERRAIN_URL` for a self-hosted Terrarium source.
  static MapProviderConfig terrainSource() {
    const url = String.fromEnvironment('TRAIL_TERRAIN_URL');
    if (url.isEmpty) return terrariumTerrain;
    return MapProviderConfig(
      id: terrariumTerrain.id,
      label: terrariumTerrain.label,
      urlTemplate: url,
      attribution: terrariumTerrain.attribution,
      offlineDownloadsAllowed: true,
      isDevelopmentOsmOverride: false,
    );
  }

  /// CyclOSM raster tiles with cycle cartography, contour lines, and hillshade
  /// already baked in, so online viewing never fetches separate elevation data.
  ///
  /// CyclOSM's public service is for interactive use, not a production bulk
  /// download backend. Small raster downloads are therefore enabled only by the
  /// development override, which defaults on in debug builds and is always off
  /// in profile/release builds.
  static MapProviderConfig cyclOsm() {
    const configuredDevelopmentOverride = bool.fromEnvironment(
      'ENABLE_DEV_OSM_DOWNLOADS',
      defaultValue: true,
    );
    final developmentOverride = kDebugMode && configuredDevelopmentOverride;
    return MapProviderConfig(
      id: 'cyclosm',
      label: 'CyclOSM',
      urlTemplate:
          'https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
      attribution: 'CyclOSM, OpenStreetMap contributors',
      offlineDownloadsAllowed: developmentOverride,
      isDevelopmentOsmOverride: developmentOverride,
    );
  }
}
