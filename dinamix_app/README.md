# DinamiX

App Android (Flutter) per ricevere, visualizzare, registrare ed esportare i dati di una
**SensorTile.box PRO (STEVAL-MKBOXPRO)** via Bluetooth Low Energy, con il protocollo ST **BlueST**.

Fa parte del project work DinamiX: monitoraggio delle sollecitazioni meccaniche su caschi per sci,
mountain bike e arrampicata.

> **Stato di verifica.** L'APK è stato compilato su GitHub Actions con Flutter 3.47 e tutti gli 87 test automatici
> sono passati. L'app **non è ancora stata provata su un telefono né con la SensorTile.box PRO**: il passo
> successivo è la [prova su hardware](docs/HARDWARE_TEST.md).

## Avvio rapido

**Senza installare nulla:** puoi far compilare l'APK a GitHub, seguendo [questa guida](docs/GITHUB_APK.md).

Per compilare in locale, requisiti: Flutter stabile 3.27 o successivo, Android Studio con Android SDK, telefono Android con BLE.
Un emulatore non ha il Bluetooth reale: per la scheda serve un telefono fisico.

Dalla cartella del progetto, genera i file Gradle (quelli già presenti non vengono sovrascritti):

```bash
flutter create --platforms=android --project-name dinamix --org com.dinamix .
```

Scarica le dipendenze:

```bash
flutter pub get
```

Esegui i test:

```bash
flutter test
```

Avvia sul telefono collegato:

```bash
flutter run
```

Crea l'APK di release:

```bash
flutter build apk --release
```

L'APK si trova in `build/app/outputs/flutter-apk/app-release.apk`. Per ora è firmato con la chiave di
debug: va bene per l'installazione diretta, per il Play Store serve una chiave propria.

## Funzioni

- **Dispositivi:** scansione, riconoscimento della scheda e del firmware dal catalogo ST, RSSI, dispositivi già usati.
- **Connessione:** riconnessione automatica con attesa crescente, timeout, associazione con PIN, gestione dei permessi.
- **Live:** valori e grafici in tempo reale, con grafici separati per X, Y e Z e frequenza misurata.
- **Data Logger:** avvio, pausa, ripresa, stop, nome della sessione, salvataggio su SQLite, registrazione a schermo spento.
- **Analisi:** grafici, confronto tra sensori, minimo, massimo, media, deviazione standard, variazioni, picchi.
- **Esportazione:** CSV e JSON tramite la condivisione di Android.
- **Diagnostica:** servizi e caratteristiche, pacchetti grezzi, errori, stima dei pacchetti persi, console, rapporto copiabile.
- **Sessione attiva:** scelta dell'attività, scudo animato che reagisce ai sensori, picchi in tempo reale, riepilogo finale.
- **Modalità demo:** usa accelerometro, giroscopio, magnetometro e barometro del telefono (ad esempio Samsung S23 Ultra).
  I dati sono reali ma non vengono dalla SensorTile: banner sempre visibile, sessioni e file marcati `TELEFONO`.
- **Simulazione:** per provare l'interfaccia senza scheda né sensori. Banner sempre visibile, dati marcati fino ai file esportati.

## Cosa dipende dal firmware

L'app legge le funzioni disponibili dalla tabella GATT della scheda e mostra solo quelle.
Con i firmware ST standard (dal catalogo ufficiale):

| Dato | Entry/Expert Mode | FP-SNS-STBOX1 BLESensors |
|---|---|---|
| Accelerometro, giroscopio, magnetometro | Sì | Sì |
| Temperatura, pressione | Sì | Sì |
| Umidità | No | Sì |
| Batteria | Sì | Sì |
| Quaternioni, bussola, angoli di Eulero | Sì | No |
| Attività, contapassi, livello microfono | Sì | No |
| QVAR (touch), contatore eventi | Sì | No |

L'elenco esatto varia con la versione del firmware.

**Limiti di questa versione:**

- **Rilevamento caduta:** nessun firmware ST in catalogo per questa scheda espone la funzione, e il
  valore di soglia nel vostro progetto non è ancora definito. L'app offre un'analisi *sperimentale* dei
  picchi sulle registrazioni: **non è un sistema di sicurezza**.
- **Impatti brevi:** lo streaming BLE ha una frequenza limitata e stabilita dal firmware, quindi può attenuare i picchi
  più brevi. Un rilevamento affidabile richiede elaborazione sulla scheda, cioè un firmware modificato.
- **Frequenza di campionamento:** è stabilita dal firmware. L'app la misura ma non può cambiarla.
- **Audio:** lo streaming audio non è supportato. Sono letti solo i livelli del microfono.
- **Funzioni non decodificate:** caratteristiche come MLC, FSM, FFT e PnPL compaiono in Diagnostica, ma non hanno un grafico.

## Documentazione

- [Documentazione tecnica](docs/TECHNICAL.md): architettura, protocollo, formati dei pacchetti, fonti, licenze.
- [Procedura di prova su hardware](docs/HARDWARE_TEST.md): cosa verificare con la scheda.
