import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/dinamix_app.dart';
import '../../domain/sensor_kind.dart';
import '../../session/live_session.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/effects.dart';
import 'activity_screen.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = summary;
    final bigNumber = numericStyle.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: theme.colorScheme.onSurface,
    );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Center(
              child: StatusOrb(
                icon: s.samples > 0 ? Icons.check_rounded : Icons.sensors_off_rounded,
                color: s.samples > 0 ? Palette.ok : Palette.warning,
                size: 158,
                active: true,
              ),
            ),
            FadeSlideIn(
              child: Text(
                s.samples > 0 ? 'Sessione completata' : 'Nessun dato ricevuto',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
            ),
            const SizedBox(height: 4),
            FadeSlideIn(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(activityIcon(s.activity), size: 17, color: muted),
                  const SizedBox(width: 6),
                  Text('${s.activity.label} · ${formatDuration(s.duration)}',
                      style: TextStyle(color: muted)),
                ],
              ),
            ),
            if (s.source == DataSource.phone) ...[
              const SizedBox(height: 10),
              const Center(child: TagChip('DEMO · SENSORI DEL TELEFONO', color: Palette.cyan)),
            ] else if (s.source == DataSource.simulated) ...[
              const SizedBox(height: 10),
              const Center(child: TagChip('SIMULATO', color: Palette.simulation)),
            ],
            const SizedBox(height: 22),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                FadeSlideIn(
                  index: 1,
                  child: _Stat(
                    label: 'Picco di accelerazione',
                    child: CountUp(value: s.peakG, decimals: 2, suffix: ' g', style: bigNumber),
                  ),
                ),
                FadeSlideIn(
                  index: 2,
                  child: _Stat(
                    label: 'Accelerazione media',
                    child: CountUp(value: s.meanG, decimals: 2, suffix: ' g', style: bigNumber),
                  ),
                ),
                FadeSlideIn(
                  index: 3,
                  child: _Stat(
                    label: 'Rotazione massima',
                    child: CountUp(value: s.peakRotationDps, suffix: ' dps', style: bigNumber),
                  ),
                ),
                FadeSlideIn(
                  index: 4,
                  child: _Stat(
                    label: 'Picchi oltre soglia',
                    child: CountUp(value: s.impacts.toDouble(), style: bigNumber),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${formatCount(s.samples)} campioni di accelerazione. Analisi sperimentale, non un sistema di sicurezza.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            if (s.sessionId != null) ...[
              GradientButton(
                label: 'Apri analisi',
                icon: Icons.analytics_rounded,
                onPressed: () {
                  context.read<NavController>().openAnalysis(s.sessionId!);
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Chiudi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(fit: BoxFit.scaleDown, child: child),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      );
}
