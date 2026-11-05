import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../analysis/series_analysis.dart';
import '../../data/sensor_hub.dart';
import '../../domain/sensor_kind.dart';
import '../../domain/units.dart';

class ChartStyle {
  const ChartStyle({required this.grid, required this.label});

  final Color grid;
  final Color label;

  factory ChartStyle.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChartStyle(grid: scheme.outlineVariant, label: scheme.onSurfaceVariant);
  }
}

/// Live chart. It repaints only on the hub frame and never rebuilds a widget.
class LiveChart extends StatelessWidget {
  const LiveChart({
    super.key,
    required this.hub,
    required this.kind,
    required this.channels,
    required this.colors,
    required this.windowMs,
    required this.units,
    this.height = 110,
  });

  final SensorHub hub;
  final SensorKind kind;
  final List<int> channels;
  final List<Color> colors;
  final int windowMs;
  final UnitPrefs units;
  final double height;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _LivePainter(
              hub: hub,
              kind: kind,
              channels: channels,
              colors: colors,
              windowMs: windowMs,
              units: units,
              style: ChartStyle.of(context),
            ),
          ),
        ),
      );
}

const double _labelGutter = 46;

class _LivePainter extends CustomPainter {
  _LivePainter({
    required this.hub,
    required this.kind,
    required this.channels,
    required this.colors,
    required this.windowMs,
    required this.units,
    required this.style,
  }) : super(repaint: hub.frame);

  final SensorHub hub;
  final SensorKind kind;
  final List<int> channels;
  final List<Color> colors;
  final int windowMs;
  final UnitPrefs units;
  final ChartStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(_labelGutter, 4, size.width - _labelGutter, size.height - 8);
    final buffer = hub.buffer(kind);
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final from = now - windowMs;
    if (buffer == null || buffer.length == 0 || plot.width <= 0) {
      drawGrid(canvas, plot, style, 0, 1, (v) => '');
      return;
    }

    var first = buffer.length;
    for (var i = buffer.length - 1; i >= 0; i--) {
      if (buffer.timeAt(i) < from) break;
      first = i;
    }

    final columns = plot.width.ceil();
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    final mins = List.generate(channels.length, (_) => List<double>.filled(columns, double.nan));
    final maxs = List.generate(channels.length, (_) => List<double>.filled(columns, double.nan));
    final scale = columns / windowMs;

    for (var i = first; i < buffer.length; i++) {
      final column = ((buffer.timeAt(i) - from) * scale).floor();
      if (column < 0 || column >= columns) continue;
      for (var c = 0; c < channels.length; c++) {
        final raw = buffer.valueAt(channels[c], i);
        if (raw.isNaN) continue;
        final v = units.convert(kind, channels[c], raw);
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
        if (mins[c][column].isNaN || v < mins[c][column]) mins[c][column] = v;
        if (maxs[c][column].isNaN || v > maxs[c][column]) maxs[c][column] = v;
      }
    }

    if (minY == double.infinity) {
      drawGrid(canvas, plot, style, 0, 1, (v) => '');
      return;
    }
    final range = niceRange(minY, maxY);
    final decimals = units.decimals(kind, channels.first);
    drawGrid(canvas, plot, style, range.$1, range.$2, (v) => compactNumber(v, decimals));
    for (var c = 0; c < channels.length; c++) {
      drawEnvelope(canvas, plot, mins[c], maxs[c], range.$1, range.$2, colors[c % colors.length]);
    }
  }

  @override
  bool shouldRepaint(covariant _LivePainter old) =>
      old.windowMs != windowMs ||
      old.kind != kind ||
      old.units != units ||
      old.style.grid != style.grid;
}

/// Static chart for recorded sessions. Each series may have its own scale, so that
/// sensors with different units can be compared by shape.
class SeriesChartData {
  const SeriesChartData(this.label, this.bins, this.color, {this.convert});

  final String label;
  final MinMaxBins bins;
  final Color color;
  final double Function(double)? convert;
}

class SessionChart extends StatelessWidget {
  const SessionChart({
    super.key,
    required this.series,
    required this.decimals,
    this.independentScales = false,
    this.height = 220,
  });

  final List<SeriesChartData> series;
  final int decimals;
  final bool independentScales;
  final double height;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SessionPainter(series, decimals, independentScales, ChartStyle.of(context)),
          ),
        ),
      );
}

class _SessionPainter extends CustomPainter {
  _SessionPainter(this.series, this.decimals, this.independent, this.style);

  final List<SeriesChartData> series;
  final int decimals;
  final bool independent;
  final ChartStyle style;

  List<double> _mapped(SeriesChartData s, List<double> values) {
    final convert = s.convert;
    return convert == null ? values : [for (final v in values) v.isNaN ? v : convert(v)];
  }

  (double, double) _extent(List<double> mins, List<double> maxs) {
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (var i = 0; i < mins.length; i++) {
      if (!mins[i].isNaN && mins[i] < low) low = mins[i];
      if (!maxs[i].isNaN && maxs[i] > high) high = maxs[i];
    }
    return (low, high);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gutter = independent ? 8.0 : _labelGutter;
    final plot = Rect.fromLTWH(gutter, 4, size.width - gutter, size.height - 8);
    final prepared = [
      for (final s in series) (s, _mapped(s, s.bins.mins), _mapped(s, s.bins.maxs)),
    ];
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (final (_, mins, maxs) in prepared) {
      final (l, h) = _extent(mins, maxs);
      low = math.min(low, l);
      high = math.max(high, h);
    }
    if (low == double.infinity) {
      drawGrid(canvas, plot, style, 0, 1, (v) => '');
      return;
    }
    final shared = niceRange(low, high);
    drawGrid(canvas, plot, style, shared.$1, shared.$2,
        (v) => independent ? '' : compactNumber(v, decimals));
    for (final (s, mins, maxs) in prepared) {
      var range = shared;
      if (independent) {
        final (l, h) = _extent(mins, maxs);
        if (l == double.infinity) continue;
        range = niceRange(l, h);
      }
      drawEnvelope(canvas, plot, mins, maxs, range.$1, range.$2, s.color);
    }
  }

  @override
  bool shouldRepaint(covariant _SessionPainter old) =>
      old.series != series || old.independent != independent || old.decimals != decimals;
}

/// Range with a small margin; a flat signal stays centered and visible.
(double, double) niceRange(double low, double high) {
  if (high - low < 1e-9) {
    final pad = low.abs() * 0.05 + 1e-3;
    return (low - pad, high + pad);
  }
  final pad = (high - low) * 0.08;
  return (low - pad, high + pad);
}

String compactNumber(double v, int decimals) {
  final abs = v.abs();
  if (abs >= 100000) return '${(v / 1000).toStringAsFixed(0)}k';
  if (abs >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(math.min(decimals, abs >= 100 ? 0 : decimals));
}

void drawGrid(Canvas canvas, Rect plot, ChartStyle style, double low, double high,
    String Function(double) label) {
  final paint = Paint()
    ..color = style.grid
    ..strokeWidth = 1;
  const steps = 2;
  for (var i = 0; i <= steps; i++) {
    final y = plot.top + plot.height * i / steps;
    canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
    final text = label(high - (high - low) * i / steps);
    if (text.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: style.label, fontSize: 10)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: plot.left - 6);
    final dy = (y - painter.height / 2).clamp(0.0, plot.bottom + 4 - painter.height);
    painter.paint(canvas, Offset(plot.left - painter.width - 6, dy));
  }
}

/// Draws one vertical segment per column between min and max, joined to the next:
/// the result is a line that never hides spikes, whatever the sample count.
void drawEnvelope(Canvas canvas, Rect plot, List<double> mins, List<double> maxs, double low,
    double high, Color color) {
  final columns = mins.length;
  final path = Path();
  var started = false;
  var firstX = 0.0;
  var lastX = 0.0;
  final dx = plot.width / columns;
  final dy = plot.height / (high - low);
  double yOf(double v) => plot.bottom - (v - low) * dy;
  for (var i = 0; i < columns; i++) {
    if (mins[i].isNaN) continue;
    final x = plot.left + i * dx;
    if (!started) {
      path.moveTo(x, yOf(maxs[i]));
      firstX = x;
      started = true;
    } else {
      path.lineTo(x, yOf(maxs[i]));
    }
    lastX = x;
    if (maxs[i] != mins[i]) path.lineTo(x, yOf(mins[i]));
  }
  if (!started) return;

  // Soft area under the line, then a wide halo and the sharp line on top.
  final area = Path.from(path)
    ..lineTo(lastX, plot.bottom)
    ..lineTo(firstX, plot.bottom)
    ..close();
  canvas.drawPath(
    area,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)],
      ).createShader(plot),
  );
  canvas.drawPath(
    path,
    Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round,
  );
}
