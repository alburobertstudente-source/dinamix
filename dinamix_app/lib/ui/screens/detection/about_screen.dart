import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../sensing/detection_engine.dart';
import '../../brand/logo.dart';
import '../../widgets/common.dart';

/// Information, privacy and limits (report §21, screen 10; §13.3).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget p(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(t, style: TextStyle(color: muted, height: 1.4)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Informazioni')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Center(child: DynamixLockup(height: 48)),
          const SizedBox(height: 10),
          Center(child: Text('Versione $appVersion · algoritmo $algorithmVersion', style: TextStyle(color: muted))),
          const SectionTitle('Cosa fa'),
          p('DYNAMIX analizza i movimenti con i sensori del telefono o di una SensorTile: separa la gravità, '
              'calcola accelerazione dinamica, variazione di velocità, jerk, rotazioni, caduta libera e ciò che '
              'accade dopo ogni evento, e assegna un livello da 0 a 4 con un indice di confidenza.'),
          const SectionTitle('Limiti'),
          p('È un sistema sperimentale. Non è un dispositivo medico né un sistema di sicurezza certificato. '
              'Le soglie sono provvisorie e sono state verificate solo su un simulatore fisico, non su dati reali.'),
          p('Alcuni eventi non sono distinguibili con i soli sensori inerziali: per esempio la caduta del '
              'telefono dalla tasca durante una caduta della persona. In questi casi il risultato è '
              '"Situazione ambigua".'),
          p('Android può fermare le app in background: tieni l\'app aperta o nelle app recenti durante il '
              'monitoraggio. La notifica "monitoraggio attivo" indica che sta funzionando.'),
          const SectionTitle('Privacy'),
          p('Nome, cognome, età e contatto di emergenza restano solo su questo telefono, in un archivio cifrato '
              '(Android Keystore), e sono esclusi dal backup. Eventi e registrazioni restano nella memoria '
              'dell\'app. Nessun dato viene inviato a server.'),
          p('L\'unica uscita di dati è l\'SMS al contatto che hai configurato, dopo 60 secondi senza '
              'annullamento. La posizione non viene raccolta né inviata.'),
          p('Puoi cancellare profilo, contatto, eventi e registrazioni dalle Impostazioni in qualsiasi momento.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'DYNAMIX',
              applicationVersion: appVersion,
              applicationIcon: const Padding(padding: EdgeInsets.all(12), child: DynamixMark(size: 56)),
            ),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Licenze del software'),
          ),
        ],
      ),
    );
  }
}
