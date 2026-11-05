import 'package:flutter/material.dart';

import '../theme.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: style)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// Persistent notice: demo data can never be mistaken for SensorTile data.
class SimulationBanner extends StatelessWidget {
  const SimulationBanner({super.key, this.phone = false});

  final bool phone;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: phone ? Palette.cyan : Palette.simulation,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          phone
              ? 'MODALITÀ DEMO: dati dai sensori del telefono, non dalla SensorTile'
              : 'MODALITÀ SIMULAZIONE: i dati non provengono dal SensorTile',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
}

class SignalBars extends StatelessWidget {
  const SignalBars(this.rssi, {super.key});

  final int rssi;

  int get _level => rssi >= -60 ? 4 : (rssi >= -70 ? 3 : (rssi >= -80 ? 2 : (rssi >= -90 ? 1 : 0)));

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.primary;
    final idle = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 4,
            height: 5.0 + i * 4,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i < _level ? active : idle,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Vector version of the DinamiX mark: mountain outline and blue X.
class DinamixLogo extends StatelessWidget {
  const DinamixLogo({super.key, this.size = 36, this.progress = 1});

  final double size;

  /// 0 to 1: the mountain draws itself, then the X appears.
  final double progress;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter(progress));
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final disc = (progress * 3).clamp(0.0, 1.0);
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2 * Curves.easeOutBack.transform(disc),
        Paint()..color = Colors.white);
    final mountain = Paint()
      ..color = const Color(0xFF1E272E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s * 0.08, s * 0.56)
      ..lineTo(s * 0.36, s * 0.18)
      ..lineTo(s * 0.54, s * 0.38)
      ..lineTo(s * 0.68, s * 0.22)
      ..lineTo(s * 0.92, s * 0.56);
    final drawn = ((progress - 0.2) / 0.5).clamp(0.0, 1.0);
    if (drawn > 0) {
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * drawn), mountain);
      }
    }
    final cross = Paint()
      ..color = Palette.brand
      ..strokeWidth = s * 0.14
      ..strokeCap = StrokeCap.butt;
    final x = ((progress - 0.65) / 0.35).clamp(0.0, 1.0);
    if (x > 0) {
      void bar(Offset from, Offset to) =>
          canvas.drawLine(from, Offset.lerp(from, to, Curves.easeOutCubic.transform(x))!, cross);
      bar(Offset(s * 0.32, s * 0.36), Offset(s * 0.68, s * 0.78));
      bar(Offset(s * 0.70, s * 0.36), Offset(s * 0.30, s * 0.88));
    }
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.progress != progress;
}
