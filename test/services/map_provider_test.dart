import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/services/map_provider.dart';

void main() {
  group('OFF-009 provider download policy', () {
    test('OFF-003: time estimates include pacing without a trailing break', () {
      const policy = RasterDownloadPolicy.development;
      expect(policy.minimumDuration(0), Duration.zero);
      expect(policy.minimumDuration(1), Duration.zero);
      expect(policy.minimumDuration(20), const Duration(milliseconds: 9500));
      expect(policy.minimumDuration(21), const Duration(milliseconds: 19500));
      expect(policy.minimumDuration(41), const Duration(seconds: 39));
    });

    test('development sources use one worker, spacing, and batch breaks', () {
      final provider = MapProviderConfig.cyclOsm();
      expect(provider.downloadPolicy.maxConcurrentRequests, 1);
      expect(
        provider.downloadPolicy.minimumRequestInterval,
        const Duration(milliseconds: 500),
      );
      expect(provider.downloadPolicy.requestsPerBatch, 20);
      expect(provider.downloadPolicy.batchPause, const Duration(seconds: 10));
      expect(
        MapProviderConfig.openTopoMap
            .withDevelopmentDownloadEnabled()
            .downloadPolicy,
        same(RasterDownloadPolicy.development),
      );
    });

    test('explicit provider limits survive developer promotion', () {
      const policy = RasterDownloadPolicy(
        maxConcurrentRequests: 1,
        minimumRequestInterval: Duration(seconds: 2),
        requestsPerBatch: 5,
        batchPause: Duration(seconds: 30),
      );
      const provider = MapProviderConfig(
        id: 'authorized-test',
        urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
        attribution: 'Test',
        offlineDownloadsAllowed: false,
        isDevelopmentOsmOverride: false,
        downloadPolicy: policy,
      );
      expect(
        provider.withDevelopmentDownloadEnabled().downloadPolicy,
        same(policy),
      );
      expect(provider.offlineDownloadsAllowed, isFalse);
    });
  });

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
    test('compiles the release developer unlock capability by default', () {
      expect(MapProviderConfig.publicRasterDevUnlockCompiled, isTrue);
    });

    test('does not compile special authorized raster downloads by default', () {
      expect(MapProviderConfig.authorizedViewRasterDevUnlockCompiled, isFalse);
    });

    test('defaults to the OpenFreeMap vector source and allows downloads', () {
      final provider = MapProviderConfig.fromEnvironment();

      expect(provider.vectorSourceUrl, contains('openfreemap.org'));
      expect(provider.usesVectorSource, isTrue);
      expect(provider.offlineDownloadsAllowed, isTrue);
      expect(provider.attribution, contains('OpenFreeMap'));
    });
  });

  group('MapProviderConfig.cyclOsm', () {
    test('keeps the keyless CyclOSM development-download endpoint', () {
      final provider = MapProviderConfig.cyclOsm();

      expect(provider.id, 'cyclosm');
      expect(provider.label, 'CyclOSM');
      expect(provider.urlTemplate, contains('tile-cyclosm.openstreetmap.fr'));
      expect(provider.attribution, contains('CyclOSM'));
      expect(provider.attribution, contains('OpenStreetMap contributors'));
      expect(provider.onlineFallbackUrlTemplate, isNull);
    });

    test('debug builds expose only a development raster download', () {
      final provider = MapProviderConfig.cyclOsm();

      expect(provider.offlineDownloadsAllowed, isTrue);
      expect(provider.isDevelopmentOsmOverride, isTrue);
    });

    test('development download config does not promote the fallback', () {
      final provider = MapProviderConfig.cyclOsm();
      final downloadable = provider.withDevelopmentDownloadEnabled();

      expect(downloadable.urlTemplate, provider.urlTemplate);
      expect(
        downloadable.onlineFallbackUrlTemplate,
        provider.onlineFallbackUrlTemplate,
      );
      expect(downloadable.offlineDownloadsAllowed, isTrue);
    });
  });

  group('MapProviderConfig.openTopoMap', () {
    test('is a direct, view-only topographic layer', () {
      const provider = MapProviderConfig.openTopoMap;

      expect(provider.id, 'opentopomap');
      expect(provider.label, 'Topographic');
      expect(provider.maxNativeZoom, 17);
      expect(provider.withDevelopmentDownloadEnabled().maxNativeZoom, 17);
      expect(provider.urlTemplate, contains('opentopomap.org'));
      expect(provider.attribution, contains('OpenStreetMap contributors'));
      expect(provider.attribution, contains('SRTM'));
      expect(provider.onlineFallbackUrlTemplate, isNull);
      expect(provider.offlineDownloadsAllowed, isFalse);
      expect(provider.authorizedDebugDownloadsOnly, isTrue);
    });
  });
}
