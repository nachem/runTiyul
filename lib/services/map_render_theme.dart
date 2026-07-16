import 'package:vector_tile_renderer/vector_tile_renderer.dart';
// The base OSM Liberty style data is not re-exported by the package's public
// API, but it is the raw Mapbox-GL style that [preferEnglishLabels] rewrites so
// map labels are drawn in English. Importing the implementation file keeps that
// rewrite in sync with the package's base cartography instead of vendoring a
// multi-thousand-line copy of the style.
// ignore: implementation_imports
import 'package:vector_tile_renderer/src/themes/light_theme.dart'
    show lightThemeData;

/// Builds the render theme used to rasterize offline vector tiles on the
/// device.
///
/// The base is the package's OSM Liberty light theme — already a comprehensive
/// OpenMapTiles style (water, landcover, landuse, roads, buildings, and
/// place/road/POI labels) — rewritten by [preferEnglishLabels] so every place,
/// road, water, and POI label is drawn in English (Latin script) instead of the
/// local language. On top of it this adds emphasis that matters for trail
/// running but that a generic street style renders faintly or omits:
///
/// * Bold, high-contrast paths, tracks, and footways with a light casing, using
///   zoom stops that keep them legible when the z14 vector source is overzoomed
///   past its maximum.
/// * Mountain-peak name labels, which the base OSM Liberty style does not draw.
///
/// Overlay layers are appended after the base layers so they paint on top of
/// the base cartography. Rendering never depends on remote sprites or glyphs, so
/// the result stays fully offline.
Theme buildTrailRenderTheme({Logger? logger}) {
  final base = _englishBaseTheme(logger);
  final overlay = ThemeReader(
    logger: logger,
  ).read(preferEnglishLabels(trailOverlayStyle()));
  return Theme(
    id: 'trail-runner',
    version: base.version,
    layers: [...base.layers, ...overlay.layers],
  );
}

/// Reads the base OSM Liberty style and rewrites its labels to English. If the
/// bundled style ever changes shape so the rewrite throws, the stock
/// (local-language) theme is used so maps still render.
Theme _englishBaseTheme(Logger? logger) {
  final reader = ThemeReader(logger: logger);
  try {
    return reader.read(preferEnglishLabels(lightThemeData()));
  } on Object {
    return ProvidedThemes.lightTheme(logger: logger);
  }
}

/// Rewrites a Mapbox-GL style so map labels prefer English.
///
/// Every symbol layer whose `text-field` is made up solely of an OpenMapTiles
/// name token (for example `{name}` or `{name_en}`) is switched to an
/// expression that prefers the English name and falls back through the Latin
/// transliteration to the local name, so labels are English where the data has
/// it and never blank where it does not:
///
/// ```text
/// coalesce(name:en, name:latin, name_en, name)
/// ```
///
/// `name` is always present for a named feature, so this never removes a label.
/// Fields that also contain other tokens (such as a road `{ref}` shield) are
/// left unchanged so their non-name content is preserved.
Map<String, dynamic> preferEnglishLabels(Map<String, dynamic> style) {
  final layers = style['layers'];
  if (layers is! List) return style;
  return {
    ...style,
    'layers': [for (final layer in layers) _withEnglishLabel(layer)],
  };
}

Object? _withEnglishLabel(Object? layer) {
  if (layer is! Map) return layer;
  final layout = layer['layout'];
  if (layout is! Map) return layer;
  final textField = layout['text-field'];
  if (textField is! String || !_isNameOnlyField(textField)) return layer;
  return {
    ...layer.cast<String, dynamic>(),
    'layout': {
      ...layout.cast<String, dynamic>(),
      'text-field': _englishNameExpression(),
    },
  };
}

/// Matches a `text-field` made up solely of OpenMapTiles name tokens (`{name}`,
/// `{name_en}`, `{name:latin}`, …) and whitespace, so name-only labels can be
/// switched to English without disturbing fields that also carry a road `{ref}`
/// or other non-name content.
final RegExp _nameOnlyFieldPattern = RegExp(
  r'^(?:\s*\{name(?:_[a-z]{2}|:[a-z_]+)?\}\s*)+$',
);

bool _isNameOnlyField(String field) => _nameOnlyFieldPattern.hasMatch(field);

/// A fresh Mapbox-GL expression selecting the first available English-preferring
/// name for a feature. Built new on each call so the returned style never
/// aliases a shared list across layers.
List<Object> _englishNameExpression() => <Object>[
  'coalesce',
  <Object>['get', 'name:en'],
  <Object>['get', 'name:latin'],
  <Object>['get', 'name_en'],
  <Object>['get', 'name'],
];

/// The Mapbox-GL style fragment layered over the base theme. Kept as data (not a
/// bundled asset) so the whole renderer stays synchronous and self-contained.
///
/// `class` values follow the OpenMapTiles `transportation` schema: hiking and
/// foot paths are `path`, forest/field tracks are `track`, and pedestrian
/// streets are `pedestrian`. Peaks come from the `mountain_peak` layer.
Map<String, dynamic> trailOverlayStyle() => {
  'version': 8,
  'name': 'RunTiyul trail emphasis',
  'sources': <String, dynamic>{},
  'layers': <Map<String, dynamic>>[
    // A light casing under the trail so it stays readable over dark landcover
    // (forest, scrub) and imagery.
    {
      'id': 'trail-emphasis-casing',
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'transportation',
      'filter': [
        'all',
        ['==', '\$type', 'LineString'],
        ['in', 'class', 'path', 'track', 'pedestrian'],
      ],
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': 'rgba(255, 255, 255, 0.85)',
        'line-width': {
          'base': 1.2,
          'stops': [
            [12, 2.4],
            [16, 5.0],
            [20, 9.0],
          ],
        },
      },
    },
    // The trail itself: a warm, dashed line that clearly reads as a walking or
    // running route rather than a road.
    {
      'id': 'trail-emphasis-line',
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'transportation',
      'filter': [
        'all',
        ['==', '\$type', 'LineString'],
        ['in', 'class', 'path', 'track', 'pedestrian'],
      ],
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': '#b5341f',
        'line-dasharray': [2, 1.5],
        'line-width': {
          'base': 1.2,
          'stops': [
            [12, 1.1],
            [16, 2.6],
            [20, 5.0],
          ],
        },
      },
    },
    // Mountain-peak labels: the base style omits these, but peaks are primary
    // landmarks for trail runners. The `{name}` token is rewritten to the
    // English-preferring expression by [preferEnglishLabels].
    {
      'id': 'trail-mountain-peak-label',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'mountain_peak',
      'minzoom': 11,
      'layout': {
        'text-field': '{name}',
        'text-font': ['Roboto Regular'],
        'text-size': 12,
        'text-anchor': 'top',
        'text-max-width': 8,
      },
      'paint': {
        'text-color': '#5d4037',
        'text-halo-color': 'rgba(255, 255, 255, 0.9)',
        'text-halo-width': 1.5,
      },
    },
  ],
};
