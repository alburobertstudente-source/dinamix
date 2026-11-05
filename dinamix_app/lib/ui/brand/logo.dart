import 'dart:math' as math;

import 'package:flutter/material.dart';

/// DYNAMIX identity: the mark is a rounded tile with an "X" made of two sensor
/// axes; one axis carries an acceleration spike. The wordmark is drawn as
/// custom monoline geometric letters, so it does not depend on any font.
class BrandColors {
  static const Color cyan = Color(0xFF12D8FF);
  static const Color blue = Color(0xFF0A6FE0);
  static const Color deep = Color(0xFF062A55);
  static const Color accent = Color(0xFF7CF5FF);
  static const List<Color> tile = [Color(0xFF16E0FF), Color(0xFF0A7BE8), Color(0xFF0748B0)];
}

class DynamixMark extends StatelessWidget {
  const DynamixMark({super.key, this.size = 40, this.progress = 1, this.monochrome});

  final double size;

  /// 0–1: draws the strokes progressively (splash animation).
  final double progress;

  /// Single colour version (e.g. on a coloured background).
  final Color? monochrome;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Logo DYNAMIX',
        image: true,
        child: CustomPaint(
          size: Size.square(size),
          painter: MarkPainter(progress: progress, monochrome: monochrome),
        ),
      );
}

class MarkPainter extends CustomPainter {
  MarkPainter({this.progress = 1, this.monochrome, this.withTile = true});

  final double progress;
  final Color? monochrome;
  final bool withTile;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & Size.square(s);
    if (withTile) {
      final tile = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28));
      final paint = Paint();
      if (monochrome != null) {
        paint.color = monochrome!;
      } else {
        paint.shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: BrandColors.tile,
        ).createShader(rect);
      }
      canvas.drawRRect(tile, paint);
      // Soft top highlight.
      canvas.drawRRect(
        tile,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
    final ink = monochrome != null && withTile ? Colors.white : (monochrome ?? Colors.white);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.105
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset p(double x, double y) => Offset(x * s, y * s);

    // Axis 1: plain diagonal.
    final a = Path()
      ..moveTo(p(0.28, 0.72).dx, p(0.28, 0.72).dy)
      ..lineTo(p(0.72, 0.28).dx, p(0.72, 0.28).dy);
    // Axis 2: diagonal carrying an acceleration spike across the centre.
    final b = Path()
      ..moveTo(p(0.28, 0.28).dx, p(0.28, 0.28).dy)
      ..lineTo(p(0.43, 0.43).dx, p(0.43, 0.43).dy)
      ..lineTo(p(0.47, 0.31).dx, p(0.47, 0.31).dy)
      ..lineTo(p(0.56, 0.62).dx, p(0.56, 0.62).dy)
      ..lineTo(p(0.60, 0.55).dx, p(0.60, 0.55).dy)
      ..lineTo(p(0.72, 0.72).dx, p(0.72, 0.72).dy);
    _drawPartial(canvas, a, stroke, (progress * 2).clamp(0, 1).toDouble());
    _drawPartial(
      canvas,
      b,
      stroke..strokeWidth = s * 0.085,
      ((progress - 0.25) * 1.6).clamp(0, 1).toDouble(),
    );
    if (progress >= 0.95) {
      canvas.drawCircle(p(0.72, 0.72), s * 0.065, Paint()..color = monochrome == null ? BrandColors.accent : ink);
    }
  }

  static void _drawPartial(Canvas canvas, Path path, Paint paint, double t) {
    if (t <= 0) return;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
    }
  }

  @override
  bool shouldRepaint(covariant MarkPainter old) =>
      old.progress != progress || old.monochrome != monochrome;
}

/// The word DYNAMIX as custom geometric letters (monoline, round caps).
class DynamixWordmark extends StatelessWidget {
  const DynamixWordmark({super.key, this.height = 22, this.color, this.accent, this.progress = 1});

  final double height;
  final Color? color;
  final Color? accent;
  final double progress;

  // 4 letters of 0.62 h, M of 0.82 h, I of 0, X of 0.62 h, 6 gaps of 0.2 h, stroke.
  static const double _ratio = 4 * 0.62 + 0.82 + 0.62 + 6 * 0.2 + 0.16;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'DYNAMIX',
      child: CustomPaint(
        size: Size(height * _ratio, height),
        painter: _WordmarkPainter(ink, accent ?? BrandColors.cyan, progress),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter(this.ink, this.accent, this.progress);

  final Color ink;
  final Color accent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = h * 0.62;
    const gap = 0.2;
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inset = paint.strokeWidth / 2;
    var x = inset;
    double top() => inset;
    double bottom() => h - inset;

    final glyphs = <Path Function(double x0)>[
      // D
      (x0) {
        final r = (bottom() - top()) / 2;
        return Path()
          ..moveTo(x0, top())
          ..lineTo(x0 + w - r, top())
          ..arcToPoint(Offset(x0 + w - r, bottom()), radius: Radius.circular(r))
          ..lineTo(x0, bottom())
          ..close();
      },
      // Y
      (x0) => Path()
        ..moveTo(x0, top())
        ..lineTo(x0 + w / 2, h * 0.52)
        ..lineTo(x0 + w, top())
        ..moveTo(x0 + w / 2, h * 0.52)
        ..lineTo(x0 + w / 2, bottom()),
      // N
      (x0) => Path()
        ..moveTo(x0, bottom())
        ..lineTo(x0, top())
        ..lineTo(x0 + w, bottom())
        ..lineTo(x0 + w, top()),
      // A (open, with a short bar)
      (x0) => Path()
        ..moveTo(x0, bottom())
        ..lineTo(x0 + w / 2, top())
        ..lineTo(x0 + w, bottom())
        ..moveTo(x0 + w * 0.26, h * 0.66)
        ..lineTo(x0 + w * 0.74, h * 0.66),
      // M
      (x0) => Path()
        ..moveTo(x0, bottom())
        ..lineTo(x0, top())
        ..lineTo(x0 + w * 0.66, h * 0.64)
        ..lineTo(x0 + w * 1.32, top())
        ..lineTo(x0 + w * 1.32, bottom()),
      // I
      (x0) => Path()
        ..moveTo(x0, top())
        ..lineTo(x0, bottom()),
    ];
    final widths = [w, w, w, w, w * 1.32, 0.0];
    var drawn = 0;
    final count = glyphs.length + 1;
    for (var i = 0; i < glyphs.length; i++) {
      final local = (progress * count - drawn).clamp(0, 1).toDouble();
      MarkPainter._drawPartial(canvas, glyphs[i](x), paint, local);
      x += widths[i] + h * gap + (i == 4 ? 0 : 0);
      drawn++;
    }
    // X: the two sensor axes, the second one in the accent colour with the spike.
    final local = (progress * count - drawn).clamp(0, 1).toDouble();
    final a = Path()
      ..moveTo(x, bottom())
      ..lineTo(x + w, top());
    final b = Path()
      ..moveTo(x, top())
      ..lineTo(x + w * 0.42, h * 0.42)
      ..lineTo(x + w * 0.5, h * 0.2)
      ..lineTo(x + w * 0.62, h * 0.72)
      ..lineTo(x + w * 0.7, h * 0.6)
      ..lineTo(x + w, bottom());
    MarkPainter._drawPartial(canvas, a, paint, local);
    MarkPainter._drawPartial(canvas, b, Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round, local);
  }

  @override
  bool shouldRepaint(covariant _WordmarkPainter old) =>
      old.ink != ink || old.accent != accent || old.progress != progress;
}

/// Mark + wordmark lockup used in app bars and the splash.
class DynamixLockup extends StatelessWidget {
  const DynamixLockup({super.key, this.height = 32, this.progress = 1});

  final double height;
  final double progress;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DynamixMark(size: height, progress: progress),
          SizedBox(width: height * 0.34),
          DynamixWordmark(height: height * 0.5, progress: math.max(0, progress * 1.2 - 0.2)),
        ],
      );
}
