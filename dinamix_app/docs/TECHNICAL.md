# Documentazione tecnica

## 1. Hardware e firmware

| Elemento | Valore | Fonte |
|---|---|---|
| Scheda | SensorTile.box PRO, STEVAL-MKBOXPRO | Foto nella presentazione, data brief ST |
| MCU | STM32U585AI | Data brief ST |
| IMU a 6 assi | LSM6DSV16X (con Qvar) | Data brief ST |
| Altri sensori | LIS2DU12, LIS2MDL, LPS22DF, STTS22H, MP23DB01HP | Data brief ST |
| BLE | BlueNRG-LP oppure STM32WB07, secondo la revisione | Data brief ST |
| Firmware | "Standard ST" secondo il team; versione esatta da leggere in app | Risposta del team |

Il protocollo è lo stesso con entrambi i chip BLE.

## 2. Architettura

```
UI (lib/ui)                    schermate, grafici; si ridisegna solo su SensorHub.frame
   │  Provider
Servizi (lib/app/services.dart)  composizione e collegamenti
   │
   ├─ ConnectionManager        macchina a stati: connessione, riconnessione, notifiche
   │     ├─ BleTransport       interfaccia verso la radio
   │     │     ├─ FbpTransport         hardware reale (flutter_blue_plus)
   │     │     ├─ PhoneTransport       demo: sensori del telefono (sensors_plus)
   │     │     └─ SimulatedTransport   simulatore, classe separata
   │     └─ BlueStDecoder      byte → SensorReading
   │
   ├─ SensorHub      (ReadingSink)  buffer circolari per la UI
   └─ SessionRecorder(ReadingSink)  salvataggio a blocchi → SessionStore → SQLite
```

Flusso di un pacchetto: notifica BLE → `ConnectionManager._onData` → decoder → scrittura nei buffer del
`SensorHub` e nella coda del `SessionRecorder`. La funzione finisce qui e non tocca né UI né disco.

**Scelte di progetto:**

- **Acquisizione separata dal ridisegno.** Un timer aggiorna `SensorHub.frame` a 5-30 Hz; i grafici sono `CustomPainter`
  che ridisegnano solo con quel segnale, senza ricostruire i widget.
- **Picchi sempre visibili.** I grafici tracciano minimo e massimo per colonna di pixel, invece di campionare a intervalli.
- **Disco fuori dal flusso BLE.** Le scritture sono a blocchi ogni secondo, in transazione e sempre in ordine. Se il disco
  fallisce i dati restano in coda; oltre 200.000 campioni i più vecchi vengono scartati e conteggiati.
- **Sessioni lunghe.** Analisi ed esportazione leggono a pagine da 5.000 righe, senza caricare tutto in memoria.
- **Schermo spento.** Un servizio Android in primo piano (`RecordingService.kt`) tiene vivo il processo solo durante la registrazione.
- **Recupero dopo un crash.** All'avvio le sessioni rimaste aperte vengono segnate come interrotte; i dati già scritti restano.
- **Provenienza dei dati.** `hardware`, `phone` o `simulated`: è impostata alla decodifica e arriva fino ai file. Il
  registratore rifiuta dati di provenienza diversa da quella della sessione, e la modalità non si può cambiare durante
  una registrazione.
- **Demo sul telefono.** `PhoneTransport` converte i valori Android (m/s², rad/s, µT, hPa) in pacchetti BlueST, così
  decoder, grafici, logger ed export sono gli stessi usati con la scheda. I sensori del telefono non sono quelli della
  SensorTile: fondo scala e frequenze sono diversi, quindi queste misure non sostituiscono le prove sul casco.
- **Animazioni.** Lo sfondo e lo scudo sono `CustomPainter` con confini di ridisegno propri, si fermano con l'app in
  background e lo sfondo rispetta l'impostazione di sistema che riduce le animazioni.

## 3. Struttura delle cartelle

```
lib/
  main.dart
  app/            composizione dei servizi, guscio dell'app, navigazione
  core/           log, errori centralizzati, servizio in primo piano
  domain/         SensorKind, SensorReading, sessioni, unità di misura
  ble/
    protocol/     UUID, advertising, catalogo firmware, decoder, stima perdite
    transport/    interfaccia, hardware, simulatore
    connection_manager.dart, device_scanner.dart
  data/           SensorHub, registratore, database
  analysis/       statistiche, riduzione per i grafici, picchi
  export/         CSV e JSON
  settings/       preferenze e dispositivi noti
  ui/             tema, widget, schermate
android/app/src/main/  manifest, MainActivity, RecordingService, icone
test/             test automatici
```

## 4. Dipendenze

| Pacchetto | Uso |
|---|---|
| flutter_blue_plus | BLE |
| permission_handler | permessi Android |
| sensors_plus | sensori del telefono nella modalità demo |
| provider | stato |
| sqflite, path | database |
| path_provider, share_plus, cross_file | esportazione e condivisione |
| shared_preferences | impostazioni |

I grafici sono scritti con `CustomPainter` per controllare il costo di ogni ridisegno.

### Licenze

`flutter_blue_plus` è **gratuito per uso personale, educativo e no-profit, ma richiede una licenza
commerciale per l'uso a scopo di lucro**. Il tipo di licenza è dichiarato in `FbpTransport._license`
(`License.nonprofit`). Prima di una pubblicazione commerciale serve acquistarla e cambiare quel valore,
oppure sostituire la libreria scrivendo un'altra implementazione di `BleTransport` (ad esempio con
`universal_ble`, licenza BSD-3), senza toccare il resto dell'app.

## 5. Permessi Android

| Versione | Permessi |
|---|---|
| Android 12+ | `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT` |
| Fino ad Android 11 | `BLUETOOTH`, `BLUETOOTH_ADMIN`, posizione |
| Registrazione | `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `POST_NOTIFICATIONS`, `WAKE_LOCK` |

La connessione richiede un PIN se il firmware lo impone. Il data brief ST indica `123456` per il firmware di fabbrica.
Se le notifiche vengono rifiutate, l'app chiede l'associazione ad Android e riprova una volta.

## 6. Protocollo BlueST

### Advertising

Manufacturer data, così come li restituisce `AdvertisementData.msd`.

**v2:**

| Offset | Byte | Campo |
|---|---|---|
| 0 | 2 | Company ID `0x0030`, little-endian |
| 2 | 1 | Versione SDK `0x02` |
| 3 | 1 | Device ID (`0x0D` = SensorTile.box PRO) |
| 4 | 1 | Firmware ID (`0xFF` = sperimentale) |
| 5 | 3 | Option byte |
| 8 | 6 | MAC, opzionale |

**v1:** versione `0x01`, device ID, maschera funzioni a 4 byte big-endian, MAC opzionale.

### UUID

`XXXXXXXX-SSSS-11e1-ac36-0002a5d5c51b`

| SSSS | Tipo | XXXXXXXX |
|---|---|---|
| `0001` | Funzione base | Maschera di bit, anche più funzioni insieme |
| `0002` | Funzione estesa | Identificativo |
| `0003` | General Purpose | Identificativo; formato definito dal modello JSON del firmware |
| `000E` | Debug | `1` console, `2` stderr |

Il catalogo ST indica le caratteristiche di debug col blocco `9ab4`, la specifica con `ac36`: l'app accetta entrambi.

### Pacchetto

```
| timestamp uint16 LE | dati funzione 1 | dati funzione 2 | ...
```

Più funzioni sulla stessa caratteristica compaiono nell'ordine della maschera, dal bit più alto. La massima
dimensione documentata è 20 byte. Tutti i valori sono little-endian.

### Formati decodificati

Offset calcolati dal termine del timestamp.

| Maschera / ID | Funzione | Formato | Conversione | Unità |
|---|---|---|---|---|
| `0x00800000` | Accelerometro | 3 × int16 | nessuna | mg |
| `0x00400000` | Giroscopio | 3 × int16 | ÷ 10 | dps |
| `0x00200000` | Magnetometro | 3 × int16 | nessuna | mGa |
| `0x00100000` | Pressione | int32 | ÷ 100 | hPa (mBar) |
| `0x00080000` | Umidità | uint16 | ÷ 10 | % |
| `0x00040000`, `0x00010000` | Temperatura | int16 | ÷ 10 | °C |
| `0x00020000` | Batteria | int16, int16, int16, uint8 | ÷ 10 %, ÷ 1000 V, mA (× 0,1 se bit `0x80`), stato `& 0x7F` | |
| `0x00000100` | Fusion compatta | n × (3 × int16) | ÷ 10000, qs = √(1 − qi² − qj² − qk²) | |
| `0x00000080` | Fusion | 3-4 × float32 | nessuna | |
| `0x00000040` | Bussola | uint16 | ÷ 100 | ° |
| `0x00000010` | Attività | uint8 `& 0x0F`, algoritmo opzionale | codice | |
| `0x00000001` | Contapassi | uint32, uint16 | nessuna | passi, passi/min |
| `0x04000000` | Microfono | uint8 per microfono | nessuna | dB |
| `0x20000000` | Switch | uint8 | 0/1 | |
| Estesa `0x0D` | Eulero | 3 × float32 | nessuna | ° |
| Estesa `0x16` | QVAR | int32, [uint8, int32, int32] | nessuna | LSB |
| Estesa `0x1D` | Contatore eventi | uint32 | nessuna | |

**Punti ricavati ma non confermati su una scheda reale:**

- L'intestazione di 2 byte anche nelle funzioni estese è dedotta dalla specifica e dal layout di QVAR.
  Verificala confrontando in Diagnostica i byte grezzi con l'app ST BLE Sensor.
- Le maschere sono quelle del ramo predefinito di `Feature.kt` nell'SDK Android ST, usato per tutte le schede tranne la
  SensorTile.box originale. I nomi in catalogo per la PRO sono coerenti.
- L'unità del timestamp non è documentata: la stima dei pacchetti persi impara l'intervallo tipico e resta una stima.

### Non implementato

Funzioni General Purpose (`0003`), comandi di configurazione, Ext Configuration (trasporto STL2), PnPL, MLC, FSM,
FFT e audio. Tra i firmware in catalogo per questa scheda, Datalog2, MLC, Piano e AI-SSM espongono soprattutto queste
funzioni, quindi con loro la schermata Live può risultare vuota. In quel caso la connessione fallisce con un messaggio chiaro.

## 7. Formato dei file esportati

**CSV.** Righe di metadati con `#`, poi una riga per canale:

```
timestamp_iso,timestamp_ms,device_ticks,sensor,channel,value,unit,source
2026-05-27T10:15:00.120Z,1779876900120,4821,acc,x,-12.0,mg,hardware
```

**JSON.** Oggetto con `format`, `session`, `sensors` (canali e unità), `events` (pausa, ripresa, perdite di collegamento)
e `samples` (`t`, `ticks`, `sensor`, `values`, con `null` per i valori assenti).

`timestamp` è l'orologio del telefono all'arrivo del pacchetto. `device_ticks` è il valore grezzo del firmware.
Le unità nei file sono sempre quelle originali del protocollo, indipendentemente dalle impostazioni.

## 8. Test

```bash
flutter test
```

| File | Copre |
|---|---|
| `decoder_test.dart` | Decodifica con vettori calcolati a mano, pacchetti troncati |
| `protocol_test.dart` | UUID, advertising v1/v2, stima dei pacchetti persi |
| `units_and_analysis_test.dart` | Unità, statistiche, riduzione, picchi, analisi a pagine |
| `connection_manager_test.dart` | Connessione, errori, disconnessioni, riconnessioni, associazione |
| `recorder_export_test.dart` | Registrazione, pausa, errori di disco, recupero, CSV, JSON |
| `widget_test.dart` | Banner di simulazione, buffer, hub, marcatura dei dati simulati |
| `demo_mode_test.dart` | Conversioni dei sensori del telefono, provenienza, sessione attiva, picchi |
| `screenshots_test.dart` | Immagini delle schermate per il controllo visivo (solo con `--dart-define=SCREENSHOTS=true`) |

**Non coperti dai test automatici:** `FbpTransport`, `SqliteSessionStore`, il servizio Android e le schermate.
Si verificano con la [prova su hardware](HARDWARE_TEST.md).

## 9. Fonti

- [Data brief STEVAL-MKBOXPRO](https://www.st.com/resource/en/data_brief/steval-mkboxpro.pdf)
- [BlueST-SDK.md, specifica v2](https://github.com/STMicroelectronics/BlueSTSDK_Android/blob/master/BlueST-SDK.md)
- [BlueSTSDK_Android, classi delle funzioni](https://github.com/STMicroelectronics/BlueSTSDK_Android)
- [BlueSTSDK_Python](https://github.com/STMicroelectronics/BlueSTSDK_Python)
- [Catalogo firmware ST (appconfig)](https://github.com/STMicroelectronics/appconfig)
- [FP-SNS-STBOX1](https://github.com/STMicroelectronics/fp-sns-stbox1)
- [flutter_blue_plus](https://pub.dev/packages/flutter_blue_plus)

I manuali UM2496 e UM3133 non sono stati consultati perché non si sono aperti durante lo sviluppo: i formati vengono dai sorgenti SDK ST.
