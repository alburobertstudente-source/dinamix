import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Slow aurora behind every screen.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 28));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _AuroraPainter(_controller, Theme.of(context).brightness == Brightness.dark),
        ),
      );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.time, this.dark) : super(repaint: time);

  final Animation<double> time;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = dark ? Palette.darkBackground : Palette.lightBackground);
    final t = time.value * 2 * math.pi;
    final alpha = dark ? 1.0 : 0.45;
    _blob(canvas, size, Offset(0.15 + 0.12 * math.sin(t), 0.1 + 0.06 * math.cos(t)), 0.85,
        Palette.brand.withValues(alpha: 0.34 * alpha));
    _blob(canvas, size, Offset(0.92 + 0.08 * math.cos(t * 2), 0.42 + 0.1 * math.sin(t)), 0.7,
        Palette.cyan.withValues(alpha: 0.16 * alpha));
    _blob(canvas, size, Offset(0.25 + 0.15 * math.cos(t), 0.98 + 0.05 * math.sin(t * 2)), 0.8,
        const Color(0xFF3B3FE0).withValues(alpha: 0.2 * alpha));
  }

  void _blob(Canvas canvas, Size size, Offset center, double radius, Color color) {
    final c = Offset(center.dx * size.width, center.dy * size.height);
    final r = radius * size.width;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.dark != dark;
}

/// Logo drawing itself at startup, then fading out on the first screen.
class IntroOverlay extends StatefulWidget {
  const IntroOverlay({super.key});

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2300))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) setState(() => _done = true);
        })
        ..forward();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done || MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final v = _controller.value;
          final fade = 1 - const Interval(0.8, 1, curve: Curves.easeIn).transform(v);
          final draw = const Interval(0, 0.6, curve: Curves.easeInOutCubic).transform(v);
          final word = const Interval(0.45, 0.75, curve: Curves.easeOutCubic).transform(v);
          return Opacity(
            opacity: fade,
            child: ColoredBox(
              color: Palette.darkBackground,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DinamixLogo(size: 120, progress: draw),
                    const SizedBox(height: 22),
                    Opacity(
                      opacity: word,
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - word)),
                        child: const Text(
                          'DINAMIX',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Content that fades and rises into place, staggered by [index].
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.distance = 22});

  final Widget child;
  final int index;
  final double distance;

  @override
  Widget build(BuildContext context) {
    const baseMs = 480;
    final delayMs = math.min(index, 10) * 70;
    final totalMs = baseMs + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(delayMs / totalMs, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, distance * (1 - value)), child: child),
      ),
    );
  }
}

/// Slight shrink under the finger.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool value) {
    if (widget.onTap != null && _down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.965 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Primary action: gradient, glow and a light sweep passing over it.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.colors = Palette.brandGradient,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final List<Color> colors;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> with SingleTickerProviderStateMixin {
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return PressScale(
      onTap: widget.onPressed,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: widget.colors),
            boxShadow: [
              if (enabled)
                BoxShadow(
                  color: widget.colors.first.withValues(alpha: 0.38),
                  blurRadius: 26,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (enabled)
                  RepaintBoundary(child: CustomPaint(painter: _ShinePainter(_shine))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: const Color(0xFF00202E), size: 21),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF00202E),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShinePainter extends CustomPainter {
  _ShinePainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    // The band crosses during the first third, then the button rests.
    final v = progress.value * 3;
    if (v > 1) return;
    final x = -size.width * 0.4 + v * size.width * 1.8;
    final rect = Rect.fromLTWH(x, 0, size.width * 0.4, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Glowing orb with expanding rings: the visual state of the sensor.
class StatusOrb extends StatefulWidget {
  const StatusOrb({
    super.key,
    required this.icon,
    required this.color,
    this.size = 188,
    this.active = false,
    this.spinning = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool active;
  final bool spinning;

  @override
  State<StatusOrb> createState() => _StatusOrbState();
}

class _StatusOrbState extends State<StatusOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.color),
      duration: const Duration(milliseconds: 500),
      builder: (context, color, _) {
        final c = color ?? widget.color;
        return SizedBox.square(
          dimension: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(widget.size),
                  painter: _OrbPainter(_controller, c, widget.active, widget.spinning),
                ),
              ),
              KeyedSwitcher(
                value: widget.icon,
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  widget.icon,
                  size: widget.size * 0.27,
                  color: c,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.time, this.color, this.active, this.spinning) : super(repaint: time);

  final Animation<double> time;
  final Color color;
  final bool active;
  final bool spinning;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    final coreR = maxR * 0.5;
    final v = time.value;

    final ringCount = active || spinning ? 3 : 1;
    for (var i = 0; i < ringCount; i++) {
      final p = (v + i / ringCount) % 1;
      final r = coreR + (maxR - coreR) * p;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withValues(alpha: (1 - p) * (active || spinning ? 0.55 : 0.2)),
      );
    }

    canvas.drawCircle(
      center,
      coreR * 1.5,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: coreR * 1.5)),
    );
    final disc = Rect.fromCircle(center: center, radius: coreR);
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0.05)],
        ).createShader(disc),
    );

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        transform: GradientRotation(v * 2 * math.pi * (spinning ? 3 : 1)),
        colors: [
          color.withValues(alpha: 0),
          color,
          color.withValues(alpha: 0),
        ],
        stops: const [0.25, 0.75, 1],
      ).createShader(disc);
    canvas.drawCircle(center, coreR, sweep);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.color != color || old.active != active || old.spinning != spinning;
}

/// Number that rolls up to its value.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.style,
    this.decimals = 0,
    this.suffix = '',
    this.duration = const Duration(milliseconds: 1100),
  });

  final double value;
  final TextStyle style;
  final int decimals;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text('${v.toStringAsFixed(decimals)}$suffix', style: style),
      );
}

/// AnimatedSwitcher that cross-fades whenever [value] changes.
///
/// Keying the child directly by its value breaks when the value goes
/// A -> B -> A faster than [duration]: the outgoing A is still in the Stack
/// when the new A arrives, and two children share a key. Here every change
/// gets a fresh key, so fast sensor-driven updates are always safe.
class KeyedSwitcher extends StatefulWidget {
  const KeyedSwitcher({
    super.key,
    required this.value,
    required this.duration,
    required this.child,
    this.transitionBuilder = AnimatedSwitcher.defaultTransitionBuilder,
  });

  final Object? value;
  final Duration duration;
  final Widget child;
  final AnimatedSwitcherTransitionBuilder transitionBuilder;

  @override
  State<KeyedSwitcher> createState() => _KeyedSwitcherState();
}

class _KeyedSwitcherState extends State<KeyedSwitcher> {
  late Object? _value = widget.value;
  int _generation = 0;

  @override
  void didUpdateWidget(KeyedSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _value) {
      _value = widget.value;
      _generation++;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: widget.duration,
        transitionBuilder: widget.transitionBuilder,
        child: KeyedSubtree(key: ValueKey<int>(_generation), child: widget.child),
      );
}
