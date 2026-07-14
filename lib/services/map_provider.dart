class MapProviderConfig {
  const MapProviderConfig({
    required this.id,
    required this.urlTemplate,
    required this.attribution,
    required this.offlineDownloadsAllowed,
    required this.isDevelopmentOsmOverride,
  });

  final String id;
  final String urlTemplate;
  final String attribution;
  final bool offlineDownloadsAllowed;
  final bool isDevelopmentOsmOverride;

  static MapProviderConfig fromEnvironment() {
    const url = String.fromEnvironment(
      'TRAIL_TILE_URL',
      defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
    const id = String.fromEnvironment(
      'TRAIL_TILE_PROVIDER_ID',
      defaultValue: 'openstreetmap-standard',
    );
    const attribution = String.fromEnvironment(
      'TRAIL_TILE_ATTRIBUTION',
      defaultValue: 'OpenStreetMap contributors',
    );
    const approved = bool.fromEnvironment('TRAIL_TILE_OFFLINE_ALLOWED');
    const developmentOverride = bool.fromEnvironment(
      'ENABLE_DEV_OSM_DOWNLOADS',
    );
    return const MapProviderConfig(
      id: id,
      urlTemplate: url,
      attribution: attribution,
      offlineDownloadsAllowed: approved || developmentOverride,
      isDevelopmentOsmOverride: developmentOverride && !approved,
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
}
