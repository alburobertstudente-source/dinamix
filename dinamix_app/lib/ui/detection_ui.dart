import 'package:flutter/material.dart';

import '../sensing/classify/classifier.dart';
import 'theme.dart';

/// Colours of the levels 0–4: calm → danger, readable on both themes.
Color levelColor(int level) => switch (level) {
      0 => Palette.ok,
      1 => Palette.cyan,
      2 => Palette.warning,
      3 => const Color(0xFFFF7A45),
      _ => Palette.danger,
    };

String levelName(int level) =>
    DangerLevel.values.firstWhere((l) => l.value == level, orElse: () => DangerLevel.normal).label;

String categoryLabel(String name) {
  for (final c in MovementCategory.values) {
    if (c.name == name) return c.label;
  }
  return name;
}

IconData categoryIcon(String name) => switch (name) {
      'walkRun' => Icons.directions_walk_rounded,
      'shakeShort' || 'shakeRepeated' => Icons.vibration_rounded,
      'placed' => Icons.table_restaurant_rounded,
      'handled' => Icons.screen_rotation_rounded,
      'phoneDropped' => Icons.phone_android_rounded,
      'surfaceHit' => Icons.back_hand_outlined,
      'sport' => Icons.downhill_skiing_rounded,
      'brakeAccel' => Icons.speed_rounded,
      'vibration' => Icons.graphic_eq_rounded,
      'personFall' => Icons.personal_injury_outlined,
      'dangerousImpact' => Icons.warning_amber_rounded,
      _ => Icons.help_outline_rounded,
    };

/// Small level badge: coloured dot and "L2".
class LevelBadge extends StatelessWidget {
  const LevelBadge(this.level, {super.key, this.large = false});

  final int level;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = levelColor(level);
    return Semantics(
      label: 'Livello $level, ${levelName(level)}',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.withValues(alpha: 0.6)),
        ),
        child: ExcludeSemantics(
          child: Text('Livello $level',
              style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: large ? 14 : 11.5)),
        ),
      ),
    );
  }
}
