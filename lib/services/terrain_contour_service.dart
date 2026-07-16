import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A decoded grid of elevations (metres) sampled from one Terrarium
/// ("terrain-RGB") tile. Row-major, [width] * [height] samples.
class ElevationTile {
  ElevationTile(this.width, this.height, this.elevations)
    : assert(elevations.length == width * height);

  final int width;
  final int height;
  final Float64List elevations;

  double at(int x, int y) => elevations[y * width + x];

  /// Lowest and highest sampled elevation, for choosing contour levels.
  (double min, double max) get range {
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (final value in elevations) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    return (min, max);
  }
}

/// One straight contour segment in tile-pixel coordinates (0..width,
/// 0..height). [level] is its elevation and [isIndex] marks the heavier index
/// contours drawn every Nth interval.
class ContourSegment {
  const ContourSegment(
    this.x1,
    this.y1,
    this.x2,
    this.y2,
    this.level,
    this.isIndex,
  );

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double level;
  final bool isIndex;
}

/// Turns free Terrarium elevation tiles into contour lines and hillshade
/// entirely on the device.
///
/// The pipeline is: decode a Terrarium PNG (or raw RGBA) to an [ElevationTile],
/// trace contour lines with marching squares, optionally shade the relief, and
/// rasterize both to a transparent PNG that is baked into converted vector
/// offline tiles. This service has no network or storage behavior of its own.
class TerrainContourService {
  const TerrainContourService({
    this.interval = 10,
    this.indexEvery = 5,
    this.scale = 1,
    this.metresPerPixel = 30,
    this.labelContours = true,
  }) : assert(interval > 0),
       assert(indexEvery >= 1),
       assert(scale >= 1 && scale <= 4);

  /// Vertical spacing between contour lines, in metres.
  final double interval;

  /// Every [indexEvery]-th contour is drawn as a heavier "index" line.
  final int indexEvery;

  /// Output scale (1 renders a 256px tile).
  final int scale;

  /// Approximate ground resolution used only to scale hillshade slope so the
  /// relief looks natural; it does not affect contour positions.
  final double metresPerPixel;

  /// Whether elevation numbers are drawn along the heavier index contours, as on
  /// a topographic map. Disabled by tests that only assert contour geometry.
  final bool labelContours;

  /// Decodes a Terrarium pixel to metres: `elevation = (R*256 + G + B/256) -
  /// 32768`.
  static double terrariumElevation(int r, int g, int b) =>
      (r * 256 + g + b / 256) - 32768;

  /// Builds an [ElevationTile] from raw RGBA bytes (length `width*height*4`).
  ElevationTile decodeTerrariumRgba(Uint8List rgba, int width, int height) {
    if (rgba.length < width * height * 4) {
      throw ArgumentError('RGBA buffer is too small for ${width}x$height.');
    }
    final elevations = Float64List(width * height);
    for (var i = 0; i < elevations.length; i++) {
      final o = i * 4;
      elevations[i] = terrariumElevation(rgba[o], rgba[o + 1], rgba[o + 2]);
    }
    return ElevationTile(width, height, elevations);
  }

  /// Traces contour lines across [tile] using marching squares. Pure and
  /// deterministic so it can be unit-tested without any rendering.
  List<ContourSegment> contourSegments(ElevationTile tile) {
    final segments = <ContourSegment>[];
    final (min, max) = tile.range;
    if (!min.isFinite || !max.isFinite || max - min < 1e-9) return segments;

    for (var y = 0; y < tile.height - 1; y++) {
      for (var x = 0; x < tile.width - 1; x++) {
        final tl = tile.at(x, y);
        final tr = tile.at(x + 1, y);
        final br = tile.at(x + 1, y + 1);
        final bl = tile.at(x, y + 1);
        final cellMin = math.min(math.min(tl, tr), math.min(bl, br));
        final cellMax = math.max(math.max(tl, tr), math.max(bl, br));

        var level = (cellMin / interval).ceil() * interval;
        for (; level <= cellMax; level += interval) {
          _emitCell(
            segments,
            x.toDouble(),
            y.toDouble(),
            tl,
            tr,
            br,
            bl,
            level.toDouble(),
          );
        }
      }
    }
    return segments;
  }

  void _emitCell(
    List<ContourSegment> out,
    double x,
    double y,
    double tl,
    double tr,
    double br,
    double bl,
    double level,
  ) {
    var caseIndex = 0;
    if (tl >= level) caseIndex |= 8;
    if (tr >= level) caseIndex |= 4;
    if (br >= level) caseIndex |= 2;
    if (bl >= level) caseIndex |= 1;
    if (caseIndex == 0 || caseIndex == 15) return;

    // Edge crossing points (top, right, bottom, left).
    ui.Offset? top() => _lerpEdge(x, y, x + 1, y, tl, tr, level);
    ui.Offset? right() => _lerpEdge(x + 1, y, x + 1, y + 1, tr, br, level);
    ui.Offset? bottom() => _lerpEdge(x, y + 1, x + 1, y + 1, bl, br, level);
    ui.Offset? left() => _lerpEdge(x, y, x, y + 1, tl, bl, level);

    final isIndex = _isIndexLevel(level);
    void add(ui.Offset? a, ui.Offset? b) {
      if (a == null || b == null) return;
      out.add(ContourSegment(a.dx, a.dy, b.dx, b.dy, level, isIndex));
    }

    switch (caseIndex) {
      case 1:
      case 14:
        add(left(), bottom());
      case 2:
      case 13:
        add(bottom(), right());
      case 3:
      case 12:
        add(left(), right());
      case 4:
      case 11:
        add(top(), right());
      case 6:
      case 9:
        add(top(), bottom());
      case 7:
      case 8:
        add(top(), left());
      case 5:
        add(top(), left());
        add(bottom(), right());
      case 10:
        add(top(), right());
        add(bottom(), left());
    }
  }

  ui.Offset? _lerpEdge(
    double ax,
    double ay,
    double bx,
    double by,
    double va,
    double vb,
    double level,
  ) {
    final d = vb - va;
    if (d.abs() < 1e-9) return null;
    final t = ((level - va) / d).clamp(0.0, 1.0);
    return ui.Offset(ax + (bx - ax) * t, ay + (by - ay) * t);
  }

  bool _isIndexLevel(double level) {
    final step = (level / interval).round();
    return step % indexEvery == 0;
  }

  /// Renders [tile] to a transparent PNG containing contour lines and, when
  /// [hillshade] is set, a soft shaded relief beneath them.
  Future<Uint8List> renderTile(
    ElevationTile tile, {
    bool hillshade = true,
  }) async {
    final size = 256 * scale;
    final recorder = ui.PictureRecorder();
    final rect = ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    final canvas = ui.Canvas(recorder, rect);

    if (hillshade) {
      final shade = await _hillshadeImage(tile);
      try {
        canvas.drawImageRect(
          shade,
          ui.Rect.fromLTWH(
            0,
            0,
            shade.width.toDouble(),
            shade.height.toDouble(),
          ),
          rect,
          ui.Paint()..filterQuality = ui.FilterQuality.low,
        );
      } finally {
        shade.dispose();
      }
    }

    // Map grid coordinates (0..width-1) onto the tile canvas.
    final sx = size / (tile.width - 1);
    final sy = size / (tile.height - 1);
    final minorPaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..color = const ui.Color(0x99a06a3c)
      ..strokeWidth = 1.0 * scale
      ..isAntiAlias = true;
    final indexPaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..color = const ui.Color(0xcc7a4a24)
      ..strokeWidth = 1.8 * scale
      ..isAntiAlias = true;

    final segments = contourSegments(tile);
    for (final s in segments) {
      canvas.drawLine(
        ui.Offset(s.x1 * sx, s.y1 * sy),
        ui.Offset(s.x2 * sx, s.y2 * sy),
        s.isIndex ? indexPaint : minorPaint,
      );
    }
    if (labelContours) _drawContourLabels(canvas, segments, sx, sy, size);

    final image = await recorder.endRecording().toImage(size, size);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Draws elevation numbers along the heavier index contours, spaced apart and
  /// turned to follow the local contour direction, the way a topographic map
  /// labels its lines. The label count is capped so a low-zoom tile spanning a
  /// huge elevation range cannot explode in cost.
  void _drawContourLabels(
    ui.Canvas canvas,
    List<ContourSegment> segments,
    double sx,
    double sy,
    int size,
  ) {
    const maxLabels = 14;
    const margin = 18.0;
    final minSpacing = 68.0 * scale;
    final placed = <ui.Offset>[];
    for (final segment in segments) {
      if (placed.length >= maxLabels) break;
      if (!segment.isIndex) continue;
      final cx = (segment.x1 + segment.x2) / 2 * sx;
      final cy = (segment.y1 + segment.y2) / 2 * sy;
      if (cx < margin ||
          cy < margin ||
          cx > size - margin ||
          cy > size - margin) {
        continue;
      }
      final anchor = ui.Offset(cx, cy);
      if (placed.any((p) => (p - anchor).distance < minSpacing)) continue;
      placed.add(anchor);
      var angle = math.atan2(
        (segment.y2 - segment.y1) * sy,
        (segment.x2 - segment.x1) * sx,
      );
      // Keep the number upright regardless of the line's direction.
      if (angle > math.pi / 2) angle -= math.pi;
      if (angle < -math.pi / 2) angle += math.pi;
      _drawLabel(canvas, segment.level.round().toString(), cx, cy, angle);
    }
  }

  /// Draws [text] centered at ([x], [y]), rotated by [angle], with a light halo
  /// so it stays legible over both the hillshade and the contour lines.
  void _drawLabel(
    ui.Canvas canvas,
    String text,
    double x,
    double y,
    double angle,
  ) {
    final fontSize = 9.5 * scale;
    ui.Paragraph build(ui.Paint paint) {
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: ui.TextAlign.center,
                fontSize: fontSize,
                fontWeight: ui.FontWeight.w700,
              ),
            )
            ..pushStyle(ui.TextStyle(foreground: paint))
            ..addText(text);
      return builder.build()
        ..layout(ui.ParagraphConstraints(width: fontSize * text.length + 12));
    }

    final halo = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.0 * scale
      ..color = const ui.Color(0xE6FFFFFF);
    final fill = ui.Paint()..color = const ui.Color(0xFF6B4423);
    final haloParagraph = build(halo);
    final fillParagraph = build(fill);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    final offset = ui.Offset(
      -haloParagraph.width / 2,
      -haloParagraph.height / 2,
    );
    canvas.drawParagraph(haloParagraph, offset);
    canvas.drawParagraph(fillParagraph, offset);
    canvas.restore();
  }

  /// Decodes a Terrarium PNG and renders its contours (and optional hillshade)
  /// to a transparent PNG overlay tile.
  Future<Uint8List> renderTerrariumPng(
    Uint8List pngBytes, {
    bool hillshade = true,
  }) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final tile = decodeTerrariumRgba(
          data!.buffer.asUint8List(),
          image.width,
          image.height,
        );
        return renderTile(tile, hillshade: hillshade);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<ui.Image> _hillshadeImage(ElevationTile tile) {
    final w = tile.width;
    final h = tile.height;
    final pixels = Uint8List(w * h * 4);
    // Light from the north-west, 45° above the horizon (the cartographic
    // convention). Shadows are drawn as translucent black; lit slopes are clear.
    const azimuth = 315.0 * math.pi / 180.0;
    const zenith = (90.0 - 45.0) * math.pi / 180.0;
    final cosZenith = math.cos(zenith);
    final sinZenith = math.sin(zenith);

    double sample(int x, int y) =>
        tile.at(x.clamp(0, w - 1), y.clamp(0, h - 1));

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dzdx =
            (sample(x + 1, y) - sample(x - 1, y)) / (2 * metresPerPixel);
        final dzdy =
            (sample(x, y + 1) - sample(x, y - 1)) / (2 * metresPerPixel);
        final slope = math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy));
        final aspect = math.atan2(dzdy, -dzdx);
        var illumination =
            cosZenith * math.cos(slope) +
            sinZenith * math.sin(slope) * math.cos(azimuth - aspect);
        illumination = illumination.clamp(0.0, 1.0);
        // Darken shadowed areas; keep lit areas transparent so the base map
        // shows through.
        final shadow = ((1.0 - illumination) * 90).round().clamp(0, 255);
        final o = (y * w + x) * 4;
        pixels[o] = 0;
        pixels[o + 1] = 0;
        pixels[o + 2] = 0;
        pixels[o + 3] = shadow;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
