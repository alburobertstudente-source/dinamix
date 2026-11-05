import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../ble/connection_manager.dart';
import '../../core/app_error.dart';
import '../../data/session_recorder.dart';
import '../../domain/sensor_kind.dart';
import '../../session/live_session.dart';
import '../../settings/app_settings.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/effects.dart';
import 'activity_screen.dart';
import 'summary_screen.dart';

/// Active session: live shield moved by the real sensors, recording in background.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.activity, this.controller, this.record = true});

  final RideActivity activity;

  /// Injected only by tests.
  final LiveSessionController? controller;
  final bool record;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with TickerProviderStateMixin {
  late final LiveSessionController _session;
  late final AnimationController _frame =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  late final AnimationController _alert =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final ConnectionManager _connection;
  final Stopwatch _elapsed = Stopwatch()..start();

  bool _ownsRecording = false;
  bool _finishing = false;
  double _alertG = 0;
  bool _alertIsTest = false;
  bool _alertVisible = false;

  // Values smoothed on screen frames, independent from the sensor rate.
  double _pitch = 0;
  double _roll = 0;
  double _energy = 0;
  double _spin = 0;

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _connection = services.connection;
    _session = widget.controller ??
        LiveSessionController(impactThresholdG: services.settings.impactThresholdG);
    _session.onImpact = (g) => _showAlert(g, test: false);
    _connection.addSink(_session);
    _frame.addListener(_tick);
    if (widget.record && !services.recorder.isActive) {
      _startRecording(services);
    }
  }

  Future<void> _startRecording(AppServices services) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await services.startRecording('${widget.activity.label} ${formatDateTime(now)}');
      _ownsRecording = services.recorder.isActive;
    } catch (e) {
      ErrorCenter.instance.reportAny(e, tag: 'Sessione', message: 'Registrazione non avviata');
    }
  }

  void _tick() {
    final s = _session;
    _pitch += (s.pitch.clamp(-1.0, 1.0) - _pitch) * 0.18;
    _roll += (s.roll.clamp(-1.0, 1.0) - _roll) * 0.18;
    _energy += (s.motionEnergy.clamp(0.0, 2.0) - _energy) * 0.12;
    _spin += 0.004 + math.min(s.rotationDps, 720) / 720 * 0.09;
  }

  void _showAlert(double g, {required bool test}) {
    if (!mounted || _alertVisible) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _alertG = g;
      _alertIsTest = test;
      _alertVisible = true;
    });
    _alert.forward(from: 0);
  }

  void _dismissAlert() => setState(() => _alertVisible = false);

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final navigator = Navigator.of(context);
    final services = context.read<AppServices>();
    _elapsed.stop();
    final source = _session.hasData ? _connection.dataSource : null;
    final id = _ownsRecording ? await services.recorder.stop() : null;
    if (!mounted) return;
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => SummaryScreen(
        summary: SessionSummary(
          activity: widget.activity,
          duration: _elapsed.elapsed,
          peakG: _session.peakG,
          meanG: _session.accelerationStats.mean.isNaN ? 0 : _session.accelerationStats.mean,
          peakRotationDps: _session.peakRotationDps,
          impacts: _session.impacts,
          samples: _session.samples,
          sessionId: id,
          source: source,
        ),
      ),
    ));
  }

  @override
  void dispose() {
    _connection.removeSink(_session);
    _session.onImpact = null;
    _frame.dispose();
    _alert.dispose();
    super.dispose();
  }

  (Color, String, String) get _status => switch (_session.level) {
        MotionLevel.waiting => (Palette.warning, 'In attesa dei dati', 'Il sensore non sta trasmettendo'),
        MotionLevel.calm => (Palette.cyan, 'Tutto OK', 'Ti stiamo monitorando'),
        MotionLevel.moving => (Palette.ok, 'In movimento', 'Sollecitazioni regolari'),
        MotionLevel.intense => (Palette.warning, 'Sollecitazioni alte', 'Movimento intenso rilevato'),
      };

  @override
  Widget build(BuildContext context) {
    final units = context.select<AppSettings, double>((s) => s.impactThresholdG);
    final recorder = context.watch<SessionRecorder>();
    final connection = context.watch<ConnectionManager>();
    final isPhone = connection.dataSource == DataSource.phone;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: AnimatedBuilder(
                  animation: _frame,
                  builder: (context, _) => _content(context, recorder, connection, isPhone, units),
                ),
              ),
            ),
            if (_alertVisible)
              Positioned.fill(
                child: _ImpactAlert(
                  animation: _alert,
                  g: _alertG,
                  test: _alertIsTest,
                  onDismiss: _dismissAlert,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, SessionRecorder recorder, ConnectionManager connection,
      bool isPhone, double thresholdG) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final (color, title, subtitle) = _status;
    final linkLost = !connection.isReady;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: Palette.brandGradient),
              ),
              child: Icon(activityIcon(widget.activity), color: const Color(0xFF00202E)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusDot(recorder.isActive ? Palette.danger : muted, size: 7),
                      const SizedBox(width: 6),
                      Text(recorder.isActive ? 'Registrazione attiva' : 'Sessione attiva',
                          style: TextStyle(color: muted, fontSize: 12)),
                    ],
                  ),
                  Text(widget.activity.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Text(
              '${_session.currentG.toStringAsFixed(2)} g',
              style: numericStyle.copyWith(color: Palette.cyan, fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        if (isPhone) ...[
          const SizedBox(height: 8),
          const TagChip('DEMO · SENSORI DEL TELEFONO', color: Palette.cyan),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = math.min(constraints.maxWidth, constraints.maxHeight);
              return Center(
                child: SizedBox.square(
                  dimension: side,
                  child: _MotionShield(
                    color: linkLost ? Palette.danger : color,
                    pitch: _pitch,
                    roll: _roll,
                    energy: _energy,
                    spin: _spin,
                    time: _elapsed.elapsedMilliseconds / 1000.0,
                  ),
                ),
              );
            },
          ),
        ),
        KeyedSwitcher(
          value: linkLost ? 'lost' : title,
          duration: const Duration(milliseconds: 260),
          child: Column(
            children: [
              Text(
                linkLost ? 'Collegamento perso' : title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: linkLost ? Palette.danger : color,
                ),
              ),
              Text(linkLost ? 'Tentativo di riconnessione in corso' : subtitle,
                  style: TextStyle(color: muted)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    _Metric('Durata', formatDuration(_elapsed.elapsed)),
                    _Metric('Picco', '${_session.peakG.toStringAsFixed(2)} g'),
                    _Metric('Rotazione', '${_session.rotationDps.toStringAsFixed(0)} dps'),
                    _Metric('Picchi', '${_session.impacts}'),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _SparklinePainter(_session.history, thresholdG, color),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GradientButton(
          label: 'Termina sessione',
          icon: Icons.stop_rounded,
          colors: const [Color(0xFFFF6B7A), Color(0xFFE5364B)],
          onPressed: _finish,
        ),
        TextButton(
          onPressed: () => _showAlert(thresholdG, test: true),
          child: Text('Prova avviso (test)', style: TextStyle(color: muted, fontSize: 13)),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: numericStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Shield tilting with the device, with rings and particles driven by the motion.
class _MotionShield extends StatelessWidget {
  const _MotionShield({
    required this.color,
    required this.pitch,
    required this.roll,
    required this.energy,
    required this.spin,
    required this.time,
  });

  final Color color;
  final double pitch;
  final double roll;
  final double energy;
  final double spin;
  final double time;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _FieldPainter(color, energy, spin, time)),
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.42,
                heightFactor: 0.42,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0014)
                    ..rotateX(-pitch * 0.7)
                    ..rotateY(roll * 0.7),
                  child: CustomPaint(painter: _ShieldPainter(color, energy)),
                ),
              ),
            ),
          ],
        ),
      );
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.color, this.energy, this.spin, this.time);

  final Color color;
  final double energy;
  final double spin;
  final double time;

  static const int _particles = 54;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    canvas.drawCircle(
      center,
      maxR,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.16 + energy.clamp(0.0, 1.0) * 0.14),
          color.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: maxR)),
    );

    final speed = 0.28 + energy.clamp(0.0, 2.0) * 0.5;
    for (var i = 0; i < 3; i++) {
      final p = (time * speed + i / 3) % 1;
      canvas.drawCircle(
        center,
        maxR * (0.36 + 0.62 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + energy.clamp(0.0, 1.0)
          ..color = color.withValues(alpha: (1 - p) * 0.5),
      );
    }

    // Fixed pseudo-random orbits: speed comes only from the measured rotation.
    final dot = Paint();
    for (var i = 0; i < _particles; i++) {
      final seed = i * 12.9898;
      final orbit = 0.46 + (math.sin(seed) * 0.5 + 0.5) * 0.5;
      final direction = i.isEven ? 1.0 : -0.7;
      final angle = seed + spin * direction * (1.4 - orbit);
      final r = maxR * orbit * (1 + energy.clamp(0.0, 1.0) * 0.04 * math.sin(time * 9 + i));
      dot.color = color.withValues(alpha: 0.2 + (math.cos(seed) * 0.5 + 0.5) * 0.55);
      canvas.drawCircle(
        center + Offset(math.cos(angle) * r, math.sin(angle) * r),
        1 + (i % 3) * 0.55,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FieldPainter old) => true;
}

class _ShieldPainter extends CustomPainter {
  _ShieldPainter(this.color, this.energy);

  final Color color;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final o = Offset((size.width - s) / 2, (size.height - s) / 2);
    Offset p(double x, double y) => o + Offset(x * s, y * s);
    final shield = Path()
      ..moveTo(p(0.5, 0.03).dx, p(0.5, 0.03).dy)
      ..lineTo(p(0.92, 0.18).dx, p(0.92, 0.18).dy)
      ..lineTo(p(0.92, 0.5).dx, p(0.92, 0.5).dy)
      ..cubicTo(p(0.92, 0.75).dx, p(0.92, 0.75).dy, p(0.7, 0.9).dx, p(0.7, 0.9).dy, p(0.5, 0.98).dx,
          p(0.5, 0.98).dy)
      ..cubicTo(p(0.3, 0.9).dx, p(0.3, 0.9).dy, p(0.08, 0.75).dx, p(0.08, 0.75).dy, p(0.08, 0.5).dx,
          p(0.08, 0.5).dy)
      ..lineTo(p(0.08, 0.18).dx, p(0.08, 0.18).dy)
      ..close();
    final rect = Offset.zero & size;
    canvas.drawPath(
      shield,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 + energy.clamp(0.0, 1.0) * 18),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.55), const Color(0xFF071019)],
        ).createShader(rect),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.028
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    final check = Path()
      ..moveTo(p(0.3, 0.5).dx, p(0.3, 0.5).dy)
      ..lineTo(p(0.45, 0.65).dx, p(0.45, 0.65).dy)
      ..lineTo(p(0.72, 0.36).dx, p(0.72, 0.36).dy);
    canvas.drawPath(
      check,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.07
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter old) => old.color != color || old.energy != energy;
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.thresholdG, this.color);

  final List<double> values;
  final double thresholdG;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final top = math.max(2.0, thresholdG * 1.1);
    double y(double v) => size.height - (v.clamp(0.0, top) / top) * size.height;
    final threshold = y(thresholdG);
    final dashed = Paint()
      ..color = Palette.danger.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, threshold), Offset(x + 5, threshold), dashed);
    }
    if (values.length < 2) return;
    final dx = size.width / (LiveSessionController.historyLength - 1);
    final start = size.width - (values.length - 1) * dx;
    final line = Path()..moveTo(start, y(values.first));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(start + i * dx, y(values[i]));
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(start, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => true;
}

class _ImpactAlert extends StatelessWidget {
  const _ImpactAlert({
    required this.animation,
    required this.g,
    required this.test,
    required this.onDismiss,
  });

  final Animation<double> animation;
  final double g;
  final bool test;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final v = animation.value;
        final shake = math.sin(v * math.pi * 7) * (1 - v) * 16;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Palette.danger.withValues(alpha: 0.28 * v),
                    Colors.black.withValues(alpha: 0.88 * v),
                  ],
                ),
              ),
            ),
            Center(
              child: Transform.translate(
                offset: Offset(shake, 0),
                child: Transform.scale(
                  scale: Curves.easeOutBack.transform(v.clamp(0.0, 1.0)),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          color: const Color(0xF2170B10),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Palette.danger, size: 60),
                const SizedBox(height: 12),
                Text(
                  test ? 'Prova avviso' : 'Picco rilevato',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  test ? 'Nessun dato è stato registrato come picco.' : '${g.toStringAsFixed(1)} g oltre la soglia',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Funzione sperimentale: non è un sistema di sicurezza e non chiama i soccorsi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 20),
                GradientButton(label: 'Sto bene', onPressed: onDismiss),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
