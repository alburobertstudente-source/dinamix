import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../alert/alert_manager.dart';
import '../../theme.dart';

/// Full-screen alert (specification §11): countdown, sound status and a
/// press-and-hold "I'm fine" button that avoids accidental cancels in a pocket.
class AlarmOverlay extends StatelessWidget {
  const AlarmOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertManager>();
    if (alerts.phase == AlertPhase.idle) return const SizedBox.shrink();
    return Positioned.fill(child: _AlarmView(alerts: alerts));
  }
}

class _AlarmView extends StatelessWidget {
  const _AlarmView({required this.alerts});

  final AlertManager alerts;

  @override
  Widget build(BuildContext context) {
    final active = alerts.active;
    final left = alerts.secondsLeft;
    final dry = alerts.current?.dryRun ?? false;
    final total = alerts.countdown.inSeconds;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: active
                ? const [Color(0xFF420812), Color(0xFF140306)]
                : const [Color(0xFF0B1424), Color(0xFF050A12)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(active ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                        color: active ? Palette.danger : Palette.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(active ? 'ALLERTA DYNAMIX' : 'Allerta conclusa',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    ),
                    if (dry)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Palette.warning.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                        child: const Text('PROVA', style: TextStyle(color: Palette.warning, fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
                const Spacer(),
                Text(alerts.title ?? '',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(alerts.detail ?? '',
                    textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFC9CE))),
                const SizedBox(height: 28),
                if (active)
                  Semantics(
                    liveRegion: true,
                    label: '$left secondi al messaggio di emergenza',
                    child: SizedBox.square(
                      dimension: 210,
                      child: CustomPaint(
                        painter: _RingPainter(left / total, alerts.soundOn),
                        child: Center(
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$left',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 64, fontWeight: FontWeight.w800, height: 1)),
                                Text(alerts.phase == AlertPhase.sending ? 'invio…' : 'secondi',
                                    style: const TextStyle(color: Color(0xFFFFC9CE))),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Text(alerts.outcome ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                const SizedBox(height: 18),
                if (active)
                  Text(
                    alerts.soundOn
                        ? 'Allarme sonoro in corso (30 s). Se stai bene, annulla.'
                        : dry
                            ? 'Prova: alla scadenza il messaggio NON verrà inviato.'
                            : 'Alla scadenza verrà inviato un SMS al contatto di emergenza.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE6D3D6), height: 1.35),
                  ),
                const Spacer(),
                if (active && alerts.phase != AlertPhase.sending)
                  _HoldToCancel(onCancel: alerts.cancel)
                else if (!active)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(onPressed: alerts.dismiss, child: const Text('Chiudi')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.pulsing);
  final double fraction;
  final bool pulsing;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 10;
    canvas.drawCircle(c, r, Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * fraction, false,
        Paint()
          ..color = Palette.danger
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.fraction != fraction || old.pulsing != pulsing;
}

/// Hold for one second to cancel: a deliberate gesture (report §12.4).
class _HoldToCancel extends StatefulWidget {
  const _HoldToCancel({required this.onCancel});
  final Future<void> Function() onCancel;

  @override
  State<_HoldToCancel> createState() => _HoldToCancelState();
}

class _HoldToCancelState extends State<_HoldToCancel> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.mediumImpact();
        widget.onCancel();
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Sto bene, annulla l\'allerta',
        hint: 'Tieni premuto per un secondo',
        onLongPress: widget.onCancel,
        child: GestureDetector(
          key: const Key('hold_to_cancel'),
          onTapDown: (_) => _hold.forward(),
          onTapUp: (_) => _hold.reverse(),
          onTapCancel: () => _hold.reverse(),
          child: AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => Container(
              height: 68,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withValues(alpha: 0.1),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: _hold.value,
                    child: Container(color: Palette.ok.withValues(alpha: 0.5)),
                  ),
                  const Center(
                    child: Text('Tieni premuto: STO BENE',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
