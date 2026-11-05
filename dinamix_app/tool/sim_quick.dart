import 'package:dinamix/sensing/motion_sample.dart';
import 'package:dinamix/sensing/simulation/physics_simulator.dart';
import 'package:dinamix/sensing/simulation/scenarios.dart';
import 'package:dinamix/sensing/simulation/sim_runner.dart';

void main(List<String> args) {
  final seeds = args.isEmpty ? 1 : int.parse(args[0]);
  final filter = args.length > 1 ? args[1] : '';
  for (final (model, profile) in [
    (SensorModel.phone200, SourceProfile.phone),
    (SensorModel.sensorTile50, SourceProfile.sensorTile),
  ]) {
    for (var seed = 1; seed <= seeds; seed++) {
      for (final s in buildScenarios(seed)) {
        if (filter.isNotEmpty && !s.id.contains(filter)) continue;
        final r = runScenario(s, model, profile, seed: seed);
        final e = r.strongest;
        final f = e?.features;
        print('${r.passed ? "OK  " : "FAIL"} ${profile.name.padRight(18)} s$seed ${s.id.padRight(22)} '
            'ev=${r.events.length} ${e == null ? "-" : "${e.category.name}/L${e.level.value}"} '
            'alarm=${r.alarm} dv=${f?.dvImpact.toStringAsFixed(2)} ff=${f?.freeFallS.toStringAsFixed(3)} '
            'ffr=${f?.freeFallMeanFRatio.toStringAsFixed(2)} post=${f?.postureChangeDeg.toStringAsFixed(0)} '
            'alt=${f?.alternation.toStringAsFixed(2)} dom=${f?.dominance.toStringAsFixed(2)} p=${f?.pulseCount} '
            'b=${f?.bounces} res=${f?.resumeRatio.toStringAsFixed(2)} pre=${f?.preActivity.toStringAsFixed(2)} '
            'still=${f?.postStillS.toStringAsFixed(1)} dur=${f?.durationS.toStringAsFixed(2)} '
            'sus=${f?.sustainedS.toStringAsFixed(2)} hf=${f?.highFrequencyRatio.toStringAsFixed(2)} '
            'per=${f?.periodicity.toStringAsFixed(2)}@${f?.dominantFrequencyHz.toStringAsFixed(1)} '
            'Q=${f?.quality.toStringAsFixed(2)} ${e?.classification.reasons.join("; ") ?? ""}');
      }
    }
  }
}
