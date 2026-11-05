import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../settings/app_settings.dart';

/// Procedural alpine scene (report §20): sky with slow light changes, layered
/// mountains with snow and parallax, drifting clouds, falling snow, a skier
/// carving S-turns (body lean tan φ = v²/(g·R)) and hikers whose legs follow a
/// gait cycle. Everything is vector: no assets, crisp at any density.
///
/// Costs: mountain paths are built once per size; per frame only transforms,
/// one batched point draw for the snow and a few small figures. The ticker stops
/// with [AnimationLevel.off], when the scene is not visible, or with the system
/// "reduce animations" setting.
class MountainScene extends StatefulWidget {
  const MountainScene({super.key, this.level = AnimationLevel.full, this.paused = false, this.height = 260});

  final AnimationLevel level;

  /// Stops the motion (e.g. during an alert, so that it does not distract).
  final bool paused;
  final double height;

  @override
  State<MountainScene> createState() => _MountainSceneState();
}

class _MountainSceneState extends State<MountainScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _time = ValueNotifier<double>(37);
  Duration? _start;

  bool get _animate =>
      widget.level != AnimationLevel.off && !widget.paused && !MediaQuery.disableAnimationsOf(context);

  void _onTick(Duration elapsed) {
    _start ??= elapsed;
    _time.value = 37 + (elapsed - _start!).inMicroseconds / 1e6;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MountainScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_animate && enabled) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
      _start = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _ScenePainter(_time, dark: dark, level: widget.level),
          ),
        ),
      ),
    );
  }
}

class _Layer {
  _Layer(this.path, this.snow, this.color, this.depth);
  final Path path;
  final Path? snow;
  final Color color;
  final double depth;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.time, {required this.dark, required this.level}) : super(repaint: time);

  final ValueNotifier<double> time;
  final bool dark;
  final AnimationLevel level;

  static Size? _cachedSize;
  static bool? _cachedDark;
  static List<_Layer> _layers = const [];
  static List<Offset> _slope = const [];
  static List<Offset> _trail = const [];

  // ---------------------------------------------------------------- geometry

  /// Ridge by midpoint displacement: fixed seed, so the scene is always the same.
  static List<double> _ridge(int seed, int points, double roughness) {
    final r = math.Random(seed);
    final h = List<double>.filled(points, 0);
    h[0] = r.nextDouble();
    h[points - 1] = r.nextDouble();
    var step = points - 1;
    var amp = 1.0;
    while (step > 1) {
      final half = step ~/ 2;
      for (var i = half; i < points - 1; i += step) {
        h[i] = (h[i - half] + h[i + half]) / 2 + (r.nextDouble() - 0.5) * amp;
      }
      amp *= roughness;
      step = half;
    }
    final lo = h.reduce(math.min), hi = h.reduce(math.max);
    return [for (final v in h) (v - lo) / (hi - lo + 1e-9)];
  }

  void _build(Size size) {
    if (_cachedSize == size && _cachedDark == dark) return;
    _cachedSize = size;
    _cachedDark = dark;
    final w = size.width * 1.3; // margin for parallax
    final h = size.height;
    final specs = [
      // seed, base (fraction of height), relief, colour (dark / light), depth, snow line
      (11, 0.56, 0.42, dark ? const Color(0xFF41588A) : const Color(0xFFB9CFEC), 0.15, 0.58),
      (23, 0.66, 0.36, dark ? const Color(0xFF2B3D66) : const Color(0xFF93B1DA), 0.3, 0.7),
      (37, 0.76, 0.26, dark ? const Color(0xFF1A2847) : const Color(0xFF7194C6), 0.5, 0.8),
      (41, 0.86, 0.14, dark ? const Color(0xFF0E1830) : const Color(0xFF557AAE), 0.75, 0.0),
      (53, 0.95, 0.07, dark ? const Color(0xFF070D18) : const Color(0xFF3F649A), 1.0, 0.0),
    ];
    _layers = [];
    for (final (seed, base, relief, color, depth, snowLine) in specs) {
      final ridge = _ridge(seed, 65, 0.48);
      final pts = <Offset>[
        for (var i = 0; i < ridge.length; i++)
          Offset(-0.15 * size.width + w * i / (ridge.length - 1), h * (base - relief * ridge[i])),
      ];
      final path = Path()..moveTo(pts.first.dx, h);
      for (final p in pts) {
        path.lineTo(p.dx, p.dy);
      }
      path
        ..lineTo(pts.last.dx, h)
        ..close();
      Path? snow;
      if (snowLine > 0) {
        // Snow on the peaks: above a line that follows the relief, with a soft
        // wavy lower edge (no floating patches).
        final limit = h * (base - relief * snowLine);
        final s = Path()..moveTo(pts.first.dx, -h);
        for (var i = 0; i < pts.length; i++) {
          final edge = limit + math.sin(i * 1.7 + seed) * h * 0.012 + math.sin(i * 0.6) * h * 0.01;
          s.lineTo(pts[i].dx, edge);
        }
        s
          ..lineTo(pts.last.dx, -h)
          ..close();
        snow = Path.combine(PathOperation.intersect, s, path);
      }
      _layers.add(_Layer(path, snow, color, depth));
    }
    // Ski slope: S-turns down the face of the middle mountain.
    _slope = [
      for (var i = 0; i <= 120; i++)
        () {
          final u = i / 120;
          final x = size.width * (0.22 + 0.42 * u) + math.sin(u * math.pi * 6) * size.width * 0.05;
          final y = h * (0.40 + 0.30 * u);
          return Offset(x, y);
        }(),
    ];
    // Hiking trail on the foreground ridge.
    final near = _ridge(53, 129, 0.55);
    _trail = [
      for (var i = 0; i < near.length; i++)
        Offset(-0.15 * size.width + w * i / (near.length - 1), h * (0.93 - 0.07 * near[i]) + 2),
    ];
  }

  // ------------------------------------------------------------------ paint

  @override
  void paint(Canvas canvas, Size size) {
    _build(size);
    final t = time.value;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);

    // Sky: slow cycle of the light (about 4 minutes), within a calm range.
    final phase = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 240);
    final top = dark
        ? Color.lerp(const Color(0xFF030814), const Color(0xFF0A1C3D), phase)!
        : Color.lerp(const Color(0xFF6FB6F2), const Color(0xFF9FD4FF), phase)!;
    final horizon = dark
        ? Color.lerp(const Color(0xFF1B2F5C), const Color(0xFF3A3466), phase)!
        : Color.lerp(const Color(0xFFFFE2C2), const Color(0xFFDDF0FF), phase)!;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height * 0.75), [top, horizon]));

    // Sun or moon glow.
    final sun = Offset(size.width * (0.72 + 0.04 * math.sin(t / 50)), size.height * (0.2 + 0.04 * phase));
    canvas.drawCircle(
        sun,
        size.height * 0.35,
        Paint()
          ..shader = ui.Gradient.radial(sun, size.height * 0.35, [
            (dark ? const Color(0xFF9FC7FF) : const Color(0xFFFFF4D6)).withValues(alpha: dark ? 0.28 : 0.7),
            Colors.transparent,
          ]));
    canvas.drawCircle(sun, size.height * 0.045,
        Paint()..color = dark ? const Color(0xFFE8F1FF) : const Color(0xFFFFFBEF));

    _clouds(canvas, size, t, far: true);
    for (var i = 0; i < _layers.length; i++) {
      final l = _layers[i];
      final dx = math.sin(t * 0.03) * size.width * 0.035 * l.depth;
      canvas.save();
      canvas.translate(dx, 0);
      final bounds = l.path.getBounds();
      canvas.drawPath(
          l.path,
          Paint()
            ..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, [
              Color.lerp(l.color, Colors.white, dark ? 0.10 : 0.18)!,
              Color.lerp(l.color, Colors.black, dark ? 0.35 : 0.12)!,
            ]));
      if (l.snow != null) {
        canvas.drawPath(
            l.snow!,
            Paint()
              ..color = dark
                  ? Color.lerp(const Color(0xFFBFD2EE), const Color(0xFFDCE8FA), phase)!.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.95));
      }
      if (i == 2 && level != AnimationLevel.off) _skier(canvas, size, t);
      if (i == 4 && level == AnimationLevel.full) _hikers(canvas, size, t);
      canvas.restore();
      if (i == 1) _clouds(canvas, size, t, far: false);
    }
    _snowfall(canvas, size, t);
    canvas.restore();
  }

  void _clouds(Canvas canvas, Size size, double t, {required bool far}) {
    final paint = Paint()..color = (dark ? const Color(0xFFB8C8E8) : Colors.white).withValues(alpha: far ? 0.10 : 0.16);
    final count = far ? 3 : 2;
    for (var i = 0; i < count; i++) {
      final speed = far ? 4.0 : 9.0;
      final span = size.width * 1.6;
      final x = ((i * 0.41 + 0.13) * span + t * speed) % span - size.width * 0.3;
      final y = size.height * (far ? 0.12 + 0.08 * i : 0.3 + 0.07 * i);
      final s = size.height * (far ? 0.06 : 0.05);
      for (final (ox, oy, r) in const [(0.0, 0.0, 1.0), (1.1, 0.25, 0.8), (-1.0, 0.3, 0.75), (2.0, 0.4, 0.55)]) {
        canvas.drawCircle(Offset(x + ox * s, y + oy * s), r * s, paint);
      }
    }
  }

  void _snowfall(Canvas canvas, Size size, double t) {
    final n = switch (level) { AnimationLevel.full => 90, AnimationLevel.light => 35, AnimationLevel.off => 0 };
    if (n == 0) return;
    final small = <Offset>[];
    final big = <Offset>[];
    for (var i = 0; i < n; i++) {
      final seed = (i * 9301 + 49297) % 233280 / 233280.0;
      final seed2 = (i * 4271 + 1013) % 7919 / 7919.0;
      final near = i % 3 == 0;
      // Terminal velocity: larger, nearer flakes fall faster.
      final v = near ? 26.0 : 14.0;
      final y = (seed * size.height + t * v) % (size.height + 10) - 5;
      final x = (seed2 * size.width + math.sin(t * 0.8 + i) * (near ? 9 : 5)) % size.width;
      (near ? big : small).add(Offset(x, y));
    }
    final color = (dark ? Colors.white : Colors.white).withValues(alpha: dark ? 0.75 : 0.9);
    canvas.drawPoints(ui.PointMode.points, small, Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round);
    canvas.drawPoints(ui.PointMode.points, big, Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round);
  }

  // ----------------------------------------------------------------- people

  static Offset _along(List<Offset> pts, double u) {
    final f = u.clamp(0.0, 1.0) * (pts.length - 1);
    final i = f.floor().clamp(0, pts.length - 2);
    return Offset.lerp(pts[i], pts[i + 1], f - i)!;
  }

  void _skier(Canvas canvas, Size size, double t) {
    const period = 14.0;
    final u = (t % period) / period;
    final p = _along(_slope, u);
    final p2 = _along(_slope, math.min(1, u + 0.004));
    final p0 = _along(_slope, math.max(0, u - 0.004));
    final tangent = (p2 - p0);
    final heading = math.atan2(tangent.dy, tangent.dx);
    // Signed curvature of the path → lean into the turn: tan φ = v²/(g R).
    final d1 = p2 - p;
    final d0 = p - p0;
    final cross = d0.dx * d1.dy - d0.dy * d1.dx;
    final turn = (cross / (d0.distance * d1.distance + 1e-9)).clamp(-0.2, 0.2);
    // Lean into the turn, limited to ±20°: the skier stays clearly on the skis.
    final lean = math.atan(turn * 4).clamp(-0.35, 0.35);
    // Legs flex while changing edges (low curvature), extend in the turn.
    final flex = 1 - (turn.abs() / 0.2).clamp(0.0, 1.0);
    final s = size.height * 0.055;
    final ink = Paint()
      ..color = dark ? const Color(0xFFEFF5FF) : const Color(0xFF0B1E3A)
      ..strokeWidth = s * 0.16
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final jacket = Paint()..color = const Color(0xFFFF5A5F);

    canvas.save();
    canvas.translate(p.dx, p.dy);
    // Snow spray in the turns.
    if (turn.abs() > 0.06 && level == AnimationLevel.full) {
      final spray = Paint()..color = Colors.white.withValues(alpha: 0.7);
      for (var k = 0; k < 5; k++) {
        final a = heading + math.pi + (k - 2) * 0.25;
        final r = s * (0.5 + 0.18 * k + 0.2 * math.sin(t * 20 + k));
        canvas.drawCircle(Offset(math.cos(a) * r, math.sin(a) * r + s * 0.1), s * 0.07, spray);
      }
    }
    canvas.rotate((heading * 0.25).clamp(-0.3, 0.3));
    // Skis along the path.
    canvas.drawLine(Offset(-s * 0.7, 0), Offset(s * 0.8, 0), ink..strokeWidth = s * 0.1);
    canvas.rotate(lean);
    final knee = Offset(s * 0.15, -s * (0.35 + 0.08 * (1 - flex)));
    final hip = Offset(-s * 0.05, -s * (0.65 + 0.12 * (1 - flex)));
    final shoulder = Offset(s * 0.1, -s * 1.15);
    canvas.drawLine(Offset.zero, knee, ink..strokeWidth = s * 0.18);
    canvas.drawLine(knee, hip, ink);
    canvas.drawLine(hip, shoulder, jacket..strokeWidth = s * 0.32..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    canvas.drawCircle(shoulder + Offset(s * 0.06, -s * 0.22), s * 0.14, Paint()..color = ink.color);
    // Arms and poles.
    final hand = shoulder + Offset(s * 0.35, s * 0.3);
    canvas.drawLine(shoulder, hand, ink..strokeWidth = s * 0.12);
    canvas.drawLine(hand, hand + Offset(-s * 0.2, s * 0.75), ink..strokeWidth = s * 0.06);
    canvas.restore();
  }

  void _hikers(Canvas canvas, Size size, double t) {
    for (var k = 0; k < 2; k++) {
      final speed = 0.012; // fraction of the width per second
      final u = ((t * speed + k * 0.09) % 1.1) - 0.05;
      final x = size.width * u;
      final ground = _groundAt(x);
      final s = size.height * 0.07;
      // Gait: step frequency ~1.8 Hz (scaled), joint angles from Fourier terms.
      final phase = t * 2 * math.pi * 0.9 + k * 1.7;
      _walker(canvas, Offset(x, ground), s, phase, k == 0 ? const Color(0xFF2EC4B6) : const Color(0xFFFFB547));
    }
  }

  double _groundAt(double x) {
    final pts = _trail;
    for (var i = 0; i + 1 < pts.length; i++) {
      if (pts[i].dx <= x && x <= pts[i + 1].dx) {
        final f = (x - pts[i].dx) / (pts[i + 1].dx - pts[i].dx);
        return pts[i].dy + (pts[i + 1].dy - pts[i].dy) * f;
      }
    }
    return pts.isEmpty ? 0 : pts.last.dy;
  }

  void _walker(Canvas canvas, Offset foot, double s, double phase, Color pack) {
    final ink = Paint()
      ..color = dark ? const Color(0xFFDCE7F7) : const Color(0xFF0B1E3A)
      ..strokeWidth = s * 0.13
      ..strokeCap = StrokeCap.round;
    final thigh = s * 0.42, shin = s * 0.42;
    // Hip flexion ±25°, knee flexes in swing; pelvis bobs at twice the step rate.
    double hipAngle(double ph) => 0.44 * math.sin(ph);
    double kneeAngle(double ph) => 0.15 + 0.55 * math.max(0, math.sin(ph + 1.2));
    final bob = s * 0.04 * math.cos(2 * phase);
    final hip = foot + Offset(0, -(thigh + shin) * 0.96 + bob);
    for (final ph in [phase, phase + math.pi]) {
      final a = hipAngle(ph);
      final kneeP = hip + Offset(math.sin(a) * thigh, math.cos(a) * thigh);
      final b = a - kneeAngle(ph);
      var footP = kneeP + Offset(math.sin(b) * shin, math.cos(b) * shin);
      // Feet do not go through the ground.
      if (footP.dy > foot.dy) footP = Offset(footP.dx, foot.dy);
      canvas.drawLine(hip, kneeP, ink);
      canvas.drawLine(kneeP, footP, ink);
    }
    final shoulder = hip + Offset(s * 0.06, -s * 0.5);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: shoulder + Offset(-s * 0.16, s * 0.22), width: s * 0.26, height: s * 0.36),
            Radius.circular(s * 0.06)),
        Paint()..color = pack);
    canvas.drawLine(hip, shoulder, ink..strokeWidth = s * 0.18);
    canvas.drawCircle(shoulder + Offset(s * 0.05, -s * 0.16), s * 0.11, Paint()..color = ink.color);
    // Arm swing in opposition and a trekking pole.
    final arm = 0.5 * math.sin(phase + math.pi);
    final hand = shoulder + Offset(math.sin(arm) * s * 0.4, math.cos(arm) * s * 0.4);
    canvas.drawLine(shoulder, hand, ink..strokeWidth = s * 0.1);
    canvas.drawLine(hand, Offset(hand.dx + s * 0.15, foot.dy), ink..strokeWidth = s * 0.05);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.dark != dark || old.level != level;
}
