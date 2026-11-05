# Prova con la SensorTile.box PRO

Questa procedura verifica ciò che i test automatici non possono coprire.

**Occorrente:** scheda carica, telefono Android con l'app installata, app **ST BLE Sensor** come confronto.

## 1. Identificazione

1. Apri **Dispositivi** e premi **Cerca**.
2. Controlla che la scheda compaia con l'etichetta verde **SensorTile.box PRO**, il nome del firmware e l'RSSI.

Se non compare, disattiva **Solo BlueST**. Se allora compare senza etichette, l'advertising non è nel formato atteso:
annota il nome e prosegui col punto 2.

## 2. Connessione

1. Premi **Connetti**. Se Android chiede un PIN, per il firmware di fabbrica inserisci `123456`.
2. Apri **Home → Diagnostica** e controlla: fase `ready`, elenco di servizi e caratteristiche, etichette `NOTIFICHE` e `DECODIFICATA`.
3. Premi **Copia rapporto** e conservalo: serve per qualunque correzione.

## 3. Correttezza dei dati

È il controllo più importante.

| Prova | Risultato atteso |
|---|---|
| Scheda ferma e piana | Modulo dell'accelerazione circa 1000 mg, su un solo asse |
| Girala di 90° | I circa 1000 mg passano a un altro asse |
| Scheda ferma | Giroscopio vicino a 0 dps |
| Ruotala | Il giroscopio reagisce sull'asse giusto, con valori in dps plausibili |
| Temperatura e pressione | Stanza plausibile: 15-35 °C, circa 950-1030 hPa |
| Batteria | Percentuale e tensione (3,2-4,2 V) coerenti con ST BLE Sensor |

Confronta gli stessi valori con ST BLE Sensor, chiudendola prima di riaprire DinamiX: la scheda accetta di norma una sola connessione.

Con Entry/Expert Mode prova anche QVAR, toccando gli elettrodi dorati. Se i valori di QVAR, Eulero o contatore eventi
non sono plausibili, l'intestazione delle funzioni estese potrebbe essere diversa: invia i byte grezzi mostrati in Diagnostica.

## 4. Grafici

1. In **Live** controlla X, Y e Z separati, la frequenza in Hz e il pallino verde.
2. Scuoti la scheda: i grafici devono scorrere fluidi e mostrare i picchi.
3. Cambia la finestra da 5 a 60 secondi.

## 5. Disconnessioni

1. Spegni la scheda o allontanati: l'app deve indicare **Riconnessione**.
2. Riaccendila: i dati devono riprendere da soli.
3. Premi **Disconnetti**: non deve riconnettersi.
4. Spegni il Bluetooth del telefono: l'app deve segnalarlo.

## 6. Registrazione ed esportazione

1. In **Logger**, registra per 1 minuto. Prova **Pausa** e **Riprendi**.
2. Spegni lo schermo per 2 minuti durante una registrazione: alla riaccensione i campioni devono essere aumentati.
3. Disconnetti la scheda durante una registrazione e ricollegala: in esportazione devono comparire gli eventi `link_lost` e `link_restored`.
4. Termina, apri la sessione ed esporta CSV e JSON. Apri il CSV in un foglio di calcolo.
5. Chiudi forzatamente l'app durante una registrazione e riaprila: la sessione deve risultare **INTERROTTA**, con i dati salvati.

## 7. Analisi

1. Apri una sessione in **Analisi** e controlla grafico e statistiche.
2. Confronta due sensori.
3. Fai alcuni urti, registrati, e cambia la soglia dei picchi nelle Impostazioni.

Le soglie restano sperimentali: una soglia di caduta va definita con prove dedicate. Questa app non è un sistema di sicurezza.

## 8. Lunga durata

Registra per almeno 30 minuti con i sensori attivi. Controlla stabilità, stima dei pacchetti persi in Diagnostica e consumo di batteria.

## In caso di problemi

| Sintomo | Cosa controllare |
|---|---|
| Scansione vuota | Bluetooth e permessi; fino ad Android 11 anche la posizione attiva |
| Connessione, poi nessun dato | Associazione in Android: rimuovila e ripeti. Dopo aver cambiato firmware, svuota la cache Bluetooth |
| "Il firmware non espone dati decodificabili" | Firmware come MLC o Datalog2: i dati usano funzioni non decodificate, vedi Diagnostica |
| Alcuni sensori senza notifiche | Entry/Expert Mode espone circa 15 funzioni decodificate e Android limita le notifiche simultanee: disattiva in Impostazioni i sensori che non servono e ricollegati |
| Errori in Diagnostica | Copia il rapporto: contiene UUID, byte grezzi ed errori |
| Errori di compilazione Gradle | Usa Flutter stabile aggiornato e ripeti `flutter clean` e `flutter pub get` |
