import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/connection_manager.dart';
import '../../domain/sensor_kind.dart';
import '../../session/live_session.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import 'session_screen.dart';

IconData activityIcon(RideActivity activity) => switch (activity) {
      RideActivity.mountainBike => Icons.directions_bike_rounded,
      RideActivity.skiSnowboard => Icons.downhill_skiing_rounded,
      RideActivity.hiking => Icons.hiking_rounded,
    };

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connection = context.watch<ConnectionManager>();
    final hasAccelerometer = connection.activeKinds.contains(SensorKind.accelerometer);
    final isPhone = connection.dataSource == DataSource.phone;
    return Scaffold(
      appBar: AppBar(title: const Text('Scegli l\'attività')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          children: [
            FadeSlideIn(
              child: Text(
                isPhone
                    ? 'Modalità demo: la sessione usa accelerometro, giroscopio, magnetometro e barometro di questo telefono.'
                    : 'La sessione usa i sensori della SensorTile e viene salvata nel Data Logger.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 18),
            for (final (i, activity) in RideActivity.values.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FadeSlideIn(
                  index: i + 1,
                  child: _ActivityCard(
                    activity: activity,
                    enabled: hasAccelerometer,
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => SessionScreen(activity: activity)),
                    ),
                  ),
                ),
              ),
            if (!hasAccelerometer)
              Text(
                'L\'accelerometro non è attivo: controlla la connessione o le Impostazioni.',
                style: TextStyle(color: Palette.warning, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity, required this.enabled, required this.onTap});

  final RideActivity activity;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      onTap: enabled ? onTap : null,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  gradient: const LinearGradient(colors: Palette.brandGradient),
                  boxShadow: [
                    BoxShadow(
                      color: Palette.cyan.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(activityIcon(activity), color: const Color(0xFF00202E), size: 29),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activity.label,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(activity.subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
