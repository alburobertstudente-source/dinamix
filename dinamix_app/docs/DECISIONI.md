# DYNAMIX — Decisioni prese durante lo sviluppo

Su richiesta ("continua senza chiedermi nulla"), le domande aperte della
relazione (§16, §24, §26) sono state risolte con le opzioni proposte. Ogni scelta
è reversibile.

| # | Domanda | Scelta | Motivo |
|---|---|---|---|
| 1 | Nome | Etichetta **DYNAMIX**. Il package resta `com.dinamix.dinamix` | Cambiare il package ora impedirebbe di aggiornare le installazioni esistenti senza disinstallare |
| 2 | Livelli che attivano l'allarme | **≥ 3**, compreso "ambiguo" con indizi di pericolo | Un allarme si annulla in un secondo; un'emergenza mancata no |
| 3 | Annullamento | **Pressione prolungata di 1 s** ("Tieni premuto: STO BENE") | Evita gli annullamenti involontari in tasca. Per l'accessibilità esiste l'azione "pressione lunga" di TalkBack |
| 4 | Esito SMS sconosciuto | **Un solo reinvio**, marcato "(ripetizione)" | Un duplicato costa meno di un'allerta persa |
| 5 | Testo dell'SMS | **Esattamente quello della specifica** | Richiesto in modo esplicito |
| 6 | Età | Intero da 1 a 120 | Valori fisicamente possibili |
| 7 | GPS | Il motore lo supporta (indizio e coerenza), ma l'**acquisizione GPS non è inclusa** in questa versione | Evita il permesso di posizione e il relativo consumo prima della validazione. La diagnostica lo dichiara |
| 8 | Distribuzione | Solo APK | La policy di Google Play sugli SMS va verificata prima |
| 9 | Chiave di firma | **Non creata** | La specifica vieta di modificare le credenziali senza autorizzazione. L'APK resta firmato con la chiave di debug di GitHub, quindi per aggiornare bisogna disinstallare |
| 10 | Package definitivo | Invariato (vedi 1) | — |
| 11 | Logo | Simbolo con la "X a due assi" e il picco d'accelerazione, scritta disegnata a mano | Prima delle tre bozze proposte nella relazione |
| 12 | Animazioni | Vettoriali procedurali (nessun asset esterno) | Producibili e verificabili qui |
| 13 | Uso commerciale | Assunto non commerciale (progetto scolastico) | `flutter_blue_plus` è gratuita solo per uso educativo o no-profit |
| 14 | Dispositivo di prova | Non noto | Vedi `docs/QA_RAPPORTO.md` |
| 15–17 | SensorTile | Profilo della scheda **NON VERIFICATO** (fondo scala, frequenza, unità del timestamp) | Nessuna scheda disponibile durante lo sviluppo |
| 18 | Collegamento perso dopo un urto | Evento incerto, nessun aumento automatico del livello | La causa più comune è la distanza |
| — | Qualità bassa con severità alta | Allarme comunque | Un dato scadente non deve nascondere un'emergenza |
| — | Monitoraggio in background | Servizio in primo piano: tipo `health` (solo telefono, Android 14+) o `connectedDevice` (SensorTile) | Il motore Dart vive nel processo dell'Activity: se l'utente chiude l'app dalle recenti il monitoraggio si ferma. Il limite è documentato |
