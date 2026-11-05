import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/services.dart';
import '../../../settings/app_settings.dart';
import '../../brand/logo.dart';
import '../../theme.dart';
import '../../widgets/effects.dart';

/// Choice of the detection mode (specification "Architettura doppia"), shown
/// after the registration and from the settings. The engine is the same for both.
class ModeScreen extends StatelessWidget {
  const ModeScreen({super.key, this.onboarding = false});

  final bool onboarding;

  Future<void> _choose(BuildContext context, DetectionMode mode) async {
    final services = context.read<AppServices>();
    final navigator = Navigator.of(context);
    if (services.recorder.isActive || services.alerts.active) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Non si può cambiare modalità durante una registrazione o un allarme.')));
      return;
    }
    await services.changeMode(mode);
    if (!onboarding && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      backgroundColor: onboarding ? Colors.transparent : null,
      appBar: onboarding ? null : AppBar(title: const Text('Modalità di rilevamento')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            if (onboarding) ...[
              const Center(child: DynamixLockup(height: 40)),
              const SizedBox(height: 22),
              Text('Da dove vengono i dati?',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Puoi cambiare scelta in qualsiasi momento dalle Impostazioni.',
                  textAlign: TextAlign.center, style: TextStyle(color: muted)),
              const SizedBox(height: 22),
            ],
            _ModeCard(
              key: const Key('mode_phone'),
              icon: Icons.smartphone_rounded,
              title: DetectionMode.phone.label,
              subtitle: 'Accelerometro e giroscopio del telefono, senza dispositivi esterni.',
              selected: settings.detectionMode == DetectionMode.phone,
              onTap: () => _choose(context, DetectionMode.phone),
            ),
            const SizedBox(height: 14),
            _ModeCard(
              key: const Key('mode_sensortile'),
              icon: Icons.sensors_rounded,
              title: DetectionMode.sensorTile.label,
              subtitle: 'SensorTile.box PRO collegata via Bluetooth Low Energy, indossata dove preferisci.',
              selected: settings.detectionMode == DetectionMode.sensorTile,
              onTap: () => _choose(context, DetectionMode.sensorTile),
            ),
            const SizedBox(height: 22),
            const _Limits(),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: scheme.surface.withValues(alpha: 0.85),
            border: Border.all(color: selected ? Palette.cyan : scheme.outlineVariant, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(colors: Palette.brandGradient),
                ),
                child: Icon(icon, color: const Color(0xFF00202E), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3)),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                  color: selected ? Palette.cyan : scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// What DYNAMIX does and does not do (guided introduction, report §21).
class _Limits extends StatelessWidget {
  const _Limits();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget row(IconData i, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(child: Text(t, style: TextStyle(color: muted, height: 1.3))),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Come funziona', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            row(Icons.functions_rounded,
                'Ogni movimento viene analizzato: gravità separata, velocità, jerk, rotazioni, caduta libera e ciò che succede dopo.'),
            row(Icons.notifications_active_outlined,
                'Se un evento sembra pericoloso suona un allarme per 30 s: hai 60 s per annullarlo prima del messaggio al contatto.'),
            row(Icons.science_outlined,
                'Sistema sperimentale: non è un dispositivo medico né un sistema di sicurezza certificato.'),
            row(Icons.lock_outline_rounded, 'Nessun dato lascia il telefono, tranne l\'eventuale SMS al tuo contatto.'),
          ],
        ),
      ),
    );
  }
}
