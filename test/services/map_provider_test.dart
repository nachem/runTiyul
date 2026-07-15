import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/services/map_provider.dart';

void main() {
  group('MapProviderConfig.isOpenStreetMapStandard', () {
    test('is true for the public OpenStreetMap standard tile service', () {
      const provider = MapProviderConfig(
        id: 'openstreetmap-standard',
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        attribution: 'OpenStreetMap contributors',
        offlineDownloadsAllowed: false,
        isDevelopmentOsmOverride: false,
      );

      expect(provider.isOpenStreetMapStandard, isTrue);
    });

    test('is false for a custom provider so OSM is not credited falsely', () {
      const provider = MapProviderConfig(
        id: 'my-provider',
        urlTemplate: 'https://maps.example.com/{z}/{x}/{y}.png',
        attribution: 'Example maps',
        offlineDownloadsAllowed: true,
        isDevelopmentOsmOverride: false,
      );

      expect(provider.isOpenStreetMapStandard, isFalse);
    });
  });

  group('MapProviderConfig.fromEnvironment', () {
    test('defaults to the OpenFreeMap vector source and allows downloads', () {
      final provider = MapProviderConfig.fromEnvironment();

      expect(provider.vectorSourceUrl, contains('openfreemap.org'));
      expect(provider.usesVectorSource, isTrue);
      expect(provider.offlineDownloadsAllowed, isTrue);
      expect(provider.attribution, contains('OpenFreeMap'));
    });
  });
}
