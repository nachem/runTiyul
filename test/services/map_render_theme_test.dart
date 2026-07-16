import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/services/map_render_theme.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trail theme extends the base style with emphasis layers', () {
    final base = ProvidedThemes.lightTheme();
    final theme = buildTrailRenderTheme();

    // The trail theme keeps every base layer and appends the overlay layers, so
    // it must have strictly more layers than the base OSM Liberty style.
    expect(theme.layers.length, greaterThan(base.layers.length));
    expect(theme.id, 'trail-runner');

    final ids = theme.layers.map((layer) => layer.id).toSet();
    expect(ids, contains('trail-emphasis-casing'));
    expect(ids, contains('trail-emphasis-line'));
    expect(ids, contains('trail-mountain-peak-label'));
  });

  test('overlay layers all bind to the openmaptiles source', () {
    final overlay = ThemeReader().read(trailOverlayStyle());
    for (final layer in overlay.layers) {
      expect(layer.tileSource, 'openmaptiles', reason: layer.id);
    }
  });

  test('emphasis layers appear on top of the base layers', () {
    final theme = buildTrailRenderTheme();
    final base = ProvidedThemes.lightTheme();
    // Overlay layers must render after (i.e. be indexed after) every base
    // layer, otherwise the emphasis would be hidden beneath roads or fills.
    final firstOverlayIndex = theme.layers.indexWhere(
      (layer) => layer.id == 'trail-emphasis-casing',
    );
    expect(firstOverlayIndex, greaterThanOrEqualTo(base.layers.length));
  });

  group('preferEnglishLabels', () {
    Map<String, dynamic> styleWith(Object? textField) => {
      'version': 8,
      'sources': <String, dynamic>{},
      'layers': [
        {
          'id': 'label',
          'type': 'symbol',
          'source': 'openmaptiles',
          'source-layer': 'place',
          'layout': {
            'text-field': textField,
            'text-font': ['Roboto Regular'],
            'text-size': 12,
          },
          'paint': {'text-color': '#333333'},
        },
      ],
    };

    Object? textFieldOf(Map<String, dynamic> style) =>
        ((style['layers'] as List).first as Map)['layout']['text-field'];

    test(
      'rewrites a local {name} label to the English coalesce expression',
      () {
        final result = preferEnglishLabels(styleWith('{name}'));
        expect(textFieldOf(result), [
          'coalesce',
          ['get', 'name:en'],
          ['get', 'name:latin'],
          ['get', 'name_en'],
          ['get', 'name'],
        ]);
      },
    );

    test('rewrites {name_en}, {name:latin}, and {name:nonlatin} labels', () {
      for (final token in ['{name_en}', '{name:latin}', '{name:nonlatin}']) {
        final field = textFieldOf(preferEnglishLabels(styleWith(token)));
        expect(field, isA<List>(), reason: token);
        expect((field as List).first, 'coalesce', reason: token);
      }
    });

    test('collapses a multi-token name field to a single expression', () {
      final field = textFieldOf(
        preferEnglishLabels(styleWith('{name:latin}\n{name:nonlatin}')),
      );
      expect(field, isA<List>());
      expect((field as List).first, 'coalesce');
    });

    test('leaves a {ref} road shield unchanged', () {
      expect(textFieldOf(preferEnglishLabels(styleWith('{ref}'))), '{ref}');
    });

    test('leaves a mixed {ref} {name} field unchanged to preserve the ref', () {
      expect(
        textFieldOf(preferEnglishLabels(styleWith('{ref} {name}'))),
        '{ref} {name}',
      );
    });

    test('preserves other layout properties while rewriting the label', () {
      final result = preferEnglishLabels(styleWith('{name}'));
      final layout = ((result['layers'] as List).first as Map)['layout'] as Map;
      expect(layout['text-size'], 12);
      expect(layout['text-font'], ['Roboto Regular']);
    });

    test('does not mutate the input style', () {
      final input = styleWith('{name}');
      preferEnglishLabels(input);
      expect(textFieldOf(input), '{name}');
    });

    test('the rewritten label still parses into a symbol layer', () {
      final theme = ThemeReader().read(
        preferEnglishLabels(styleWith('{name}')),
      );
      final layer = theme.layers.singleWhere((l) => l.id == 'label');
      expect(layer.type, ThemeLayerType.symbol);
    });
  });
}
