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
    const developmentOverride = bool.fromEnvironment(
      'ENABLE_DEV_OSM_DOWNLOADS',
    );
    const vectorSourceUrl = String.fromEnvironment(
      'TRAIL_VECTOR_MBTILES',
      defaultValue: 'https://tiles.openfreemap.org/planet',
    );
    // Only credit OpenStreetMap when the tiles actually come from the OSM
    // standard service. A custom provider that does not supply its own
    // attribution must not falsely claim OpenStreetMap.
    final isOsm = url.contains('tile.openstreetmap.org');
    final usesOpenFreeMap = vectorSourceUrl.contains('openfreemap.org');
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
      offlineDownloadsAllowed:
          approved || developmentOverride || vectorSourceUrl.isNotEmpty,
      isDevelopmentOsmOverride: developmentOverride && !approved,
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
}
