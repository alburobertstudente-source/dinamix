# DinamiX: rilevamento di movimenti anomali con i sensori del telefono

## Relazione tecnica, FASE A (studio e progettazione)

Stato: **solo progettazione**. Questa fase non modifica il codice.
Tutte le soglie numeriche di questo documento sono **provvisorie** e servono
solo a costruire simulatore e test. Ognuna va sostituita con un valore ricavato
dai dati raccolti nella procedura del §10. Nessuna soglia va intesa come limite
medico o di sicurezza.

Fuori dallo scope (§0): chiamate ai soccorsi, SMS, notifiche a contatti,
condivisione della posizione e procedure di emergenza.

---

## 0. Scope

Quando il sistema rileva un evento, si limita a:

1. registrare l'evento;
2. salvare i dati grezzi dei sensori in una finestra attorno all'evento;
3. calcolare intensità, durata e caratteristiche dell'accelerazione;
4. assegnare un livello di anomalia (0–4) e un indice di confidenza;
5. mostrare il risultato nella schermata diagnostica.

L'avviso a schermo già presente (`_showAlert` in `session_screen.dart`, con
vibrazione) è un'azione locale e non comunica con l'esterno. Nella FASE B
diventa un semplice indicatore diagnostico, senza logiche di emergenza.

---

## 1. Analisi del progetto esistente

### 1.1 Piattaforma

| Aspetto | Valore |
|---|---|
| Linguaggio / framework | Dart, Flutter (CI su 3.47.9 stable) |
| Piattaforma | Android (manifest, `MainActivity.kt`, `RecordingService.kt`) |
| Sensori del telefono | plugin `sensors_plus` 7.1.1 |
| Persistenza | SQLite (`sqflite`): tabelle `sessions`, `samples`, `events` |
| Stato / DI | `provider`, contenitore `AppServices` |

### 1.2 Flusso attuale dei dati del telefono

```
sensors_plus (EventChannel, 1 stream per sensore)
  → PhoneTransport: converte in mg / 0,1 dps / mGa / Pa,
    impacchetta come notifica BlueST (int16, tick a 10 ms)
  → ConnectionManager._onData → BlueStDecoder.decode(receivedAtMs = DateTime.now())
  → ReadingSink: SensorHub (grafici), SessionRecorder (DB), LiveSessionController
```

Questa scelta è ottima per riusare decoder, grafici, registrazione ed export
della SensorTile. Il rilevamento però ha bisogno di informazioni che lungo
questa catena si perdono.

### 1.3 Problemi rilevati (rilevanti per il rilevamento)

| # | Dove | Problema | Effetto |
|---|---|---|---|
| P1 | `live_session.dart` `_onAcceleration` | Urto rilevato quando il **modulo grezzo** dell'accelerometro (gravità inclusa) supera una soglia fissa | È proprio il metodo da evitare: dipende dall'orientamento, ignora la caduta libera e lo scuotimento genera falsi allarmi |
| P2 | `live_session.dart` `motionEnergy` | Media mobile esponenziale di \| \|f\| − 1 g \| | Invariante all'orientamento, ma mescola rumore, vibrazione e moto reale e non separa la gravità |
| P3 | `phone_transport.dart` | Il `timestamp` di `SensorEvent` (fornito da `sensors_plus` in µs, derivato da `elapsedRealtimeNanos`) viene **scartato** | Il tempo usato è `DateTime.now()` alla decodifica: include il jitter del canale piattaforma e i ritardi di batching. Il jerk (derivata) lo amplifica |
| P4 | `phone_transport.dart` | Tick BlueST a 10 ms su 16 bit (si azzera ogni 655,36 s) | Risoluzione temporale insufficiente per una derivata a 100–200 Hz |
| P5 | `DevicePhoneSensors` | Periodo richiesto 20 ms (50 Hz) | Per un urto breve, il picco campionato a 50 Hz può essere molto inferiore al vero (§3.8) |
| P6 | — | Nessun uso di `TYPE_LINEAR_ACCELERATION` (disponibile come `userAccelerometerEventStream`), `TYPE_GRAVITY`, `TYPE_ROTATION_VECTOR` né GPS | Manca la separazione della gravità e manca la velocità |
| P7 | — | Nessun accesso ai metadati del sensore (`getMaximumRange`, `getResolution`, `getMinDelay`, fornitore) | Impossibile riconoscere la saturazione e la risoluzione reale |
| P8 | `sensors_plus` | Nessun `maxReportLatencyUs` (FIFO batching) | Un evento per campione attraversa il canale piattaforma: costo di CPU e batteria più alto del necessario |
| P9 | stream separati | Accelerometro e giroscopio arrivano su stream indipendenti e non sincronizzati | La fusione deve allinearli nel tempo |

La quantizzazione int16 dell'impacchettamento (1 mg e 0,1 dps) **non** è un
problema: è più fine del rumore tipico di un MEMS consumer. Il fondo scala
(±32,767 g e ±3276,7 dps) supera i fondo scala dei telefoni.

### 1.4 Cosa si riusa senza modifiche

- tabella `events` (`at_ms`, `type`, `detail` JSON): adatta a salvare gli eventi rilevati;
- tabella `samples` e `SessionRecorder`: per i dati grezzi delle sessioni;
- `SeriesStats` (Welford), `PeakDetector`, `MinMaxBins`: per l'analisi a posteriori;
- `SimulatedTransport`: sorgente demo. Per i test del rilevamento serve un simulatore fisico separato (§9);
- `RecordingService` (servizio in primo piano) e `KeepAlive`.

---

## 2. Sensori: caratteristiche, errori e limiti

Non riporto valori numerici di precisione inventati: dipendono dal chip
montato su ogni modello. Per ogni sensore indico **cosa misurare sul
dispositivo** (§10.1) e **cosa leggere dalle API**.

### 2.1 Accelerometro (`TYPE_ACCELEROMETER`)

- **Misura la forza specifica**, non l'accelerazione: **f = a − g** (nel
  riferimento del telefono, con g = vettore gravità verso il basso). Da fermo
  legge +1 g verso l'alto; **in caduta libera legge ≈ 0**.
- Errori: offset (bias) per asse, errore di scala, non ortogonalità degli assi,
  dipendenza dalla temperatura, rumore bianco (densità in µg/√Hz da
  datasheet), quantizzazione, **saturazione** al fondo scala.
- Fondo scala: dipende dal chip. Si legge con `Sensor.getMaximumRange()`
  (m/s²). Gli urti contro superfici rigide possono superarlo: in quel caso il
  picco misurato è solo un **limite inferiore**.
- Frequenza: `getMinDelay()` dà il periodo minimo. Da Android 12 serve il
  permesso `HIGH_SAMPLING_RATE_SENSORS` per superare i 200 Hz. La frequenza
  richiesta è solo un suggerimento: va **misurata** dai timestamp.
- Filtro anti-aliasing: lo applica il chip in base all'ODR scelto dall'HAL ed
  è sconosciuto all'app. Va verificato confrontando spettri a frequenze diverse.

### 2.2 Giroscopio (`TYPE_GYROSCOPE`)

- Misura la velocità angolare ω (rad/s) nel riferimento del telefono.
  Android fornisce la versione con compensazione della deriva del sistema;
  `TYPE_GYROSCOPE_UNCALIBRATED` riporta anche il bias stimato.
- Errori: bias (deriva lenta, dipendente dalla temperatura), rumore (angle
  random walk), errore di scala, saturazione (fondo scala da `getMaximumRange()`).
- Conseguenza: integrare ω dà l'orientamento con un errore che cresce nel
  tempo. Serve una correzione dall'accelerometro (§3.2).

### 2.3 Gravità e accelerazione lineare (`TYPE_GRAVITY`, `TYPE_LINEAR_ACCELERATION`)

- Sono **sensori virtuali**: una fusione del produttore, non documentata, con
  latenza e comportamento che variano tra i dispositivi.
- `sensors_plus` espone solo `TYPE_LINEAR_ACCELERATION` (come
  `userAccelerometer`), non `TYPE_GRAVITY`.
- Uso proposto: **riferimento di confronto** nella diagnostica e misura di
  coerenza. La stima primaria resta la nostra (§3.2), perché è nota,
  testabile e uguale su tutti i dispositivi.

### 2.4 Orientamento (`TYPE_ROTATION_VECTOR`, `TYPE_GAME_ROTATION_VECTOR`)

- `GAME_ROTATION_VECTOR` non usa il magnetometro, quindi non risente dei
  disturbi magnetici, ma il suo yaw deriva.
- Per il rilevamento **non serve lo yaw**: basta la direzione della gravità
  (2 gradi di libertà). Il magnetometro (disturbato in auto, vicino a metalli,
  magneti delle custodie) **non entra** nella stima primaria.

### 2.5 Barometro (`TYPE_PRESSURE`)

- Utile come indizio di variazione di quota (caduta da un'altezza, scale).
- Limiti: risoluzione da verificare, sensibilità a vento, ventilazione e
  pressione dinamica in moto. Indizio debole, con peso basso nella confidenza.

### 2.6 GPS / velocità

- Oggi **non è presente** nel progetto: nessun pacchetto di localizzazione, e
  i permessi di posizione sono limitati a `maxSdkVersion=30` per il BLE.
- La velocità GNSS da effetto Doppler (`Location.getSpeed()`, con
  `getSpeedAccuracyMetersPerSecond()` da API 26) è molto più affidabile della
  velocità ricavata dalle posizioni.
- Limiti: frequenza tipica 1 Hz, latenza, assenza in galleria e in interni,
  multipath in città.
- Uso proposto: **opzionale e solo locale** (nessuna condivisione, §0), come
  verifica di coerenza della variazione di velocità. Richiede
  `ACCESS_FINE_LOCATION`, un costo di batteria e un consenso esplicito.

### 2.7 Disponibilità e sensori mancanti

All'avvio un modulo nativo (FASE B) interroga `SensorManager.getDefaultSensor`
per ogni tipo e salva: presenza, fornitore, fondo scala, risoluzione,
`minDelay`, `maxDelay`, FIFO, wake-up. Degradazione prevista:

| Mancante | Comportamento |
|---|---|
| Giroscopio | Gravità stimata con il solo filtro passa-basso. Confidenza ridotta durante le rotazioni. Rilevamento rotazioni disattivato |
| Barometro, GPS | Indizi corrispondenti assenti: la confidenza non li conta |
| Accelerometro | Rilevamento disattivato, stato mostrato in diagnostica |

---

## 3. Modello matematico

Notazione: riferimento del telefono B (assi Android). f_k = forza specifica
misurata al tempo t_k (m/s²). ω_k = velocità angolare (rad/s).
g₀ = 9,80665 m/s² (gravità **standard**, usata solo per esprimere i G).

### 3.1 Perché il modulo grezzo non basta

\|f\| = \|a − g\|. Da fermo vale g₀ in qualsiasi orientamento. Durante un moto
dipende dall'**angolo tra a e g**:

- un'accelerazione orizzontale di 1 g dà \|f\| = √2 g = 1,41 g;
- in caduta libera \|f\| = 0.

Una soglia su \|f\| non vede quindi la caduta libera e pesa in modo diverso la
stessa accelerazione secondo la direzione. Serve **a = f + g** con g stimata
nel riferimento B.

Nota sulla gravità locale: vale circa 9,78 m/s² all'equatore e circa
9,83 m/s² ai poli, e diminuisce con la quota. Inoltre l'accelerometro ha errori
di scala. Per questo il modulo a riposo si **calibra sul dispositivo**
(g_cal = media di \|f\| nei tratti fermi) invece di assumere g₀.

### 3.2 Stima della gravità: confronto delle alternative

| Metodo | Pro | Contro |
|---|---|---|
| A. Passa-basso su f (EMA, costante τ) | Semplice | **Sbaglia durante le rotazioni**: dopo una rotazione a gradino di un angolo θ, l'errore iniziale è \|Δg\| = 2 g sin(θ/2), cioè 1,41 g per θ = 90°, e decade con τ. Sbaglia anche durante le accelerazioni prolungate (frenata), che vengono scambiate per inclinazione |
| B. Sensore virtuale `TYPE_GRAVITY` | Già fuso dal produttore | Scatola nera: varia tra dispositivi e non si testa in simulazione |
| C. **Filtro complementare assistito dal giroscopio** (gravità come vettore) | Segue le rotazioni rapide grazie a ω e corregge la deriva con f. Costo O(1). Comportamento analizzabile | Va scelta la costante di tempo |
| D. EKF completo (quaternione e bias) | Ottimo se i modelli di rumore sono noti | Senza dati reali i parametri di rumore sarebbero inventati. Più complesso da verificare. Lo yaw non è osservabile senza magnetometro |

**Scelta: C.** Motivazione: per due sensori con rumori bianchi stazionari, il
filtro complementare coincide con il filtro di Kalman a regime. L'EKF
aggiungerebbe solo la stima adattiva delle covarianze, che oggi non sapremmo
inizializzare in modo onesto. Il disegno lascia la possibilità di passare a un
EKF in seguito: stessa interfaccia, confronto sui dati registrati.

Equazioni (vettore γ = −g, cioè la "reazione" che l'accelerometro legge da
fermo e che punta verso l'alto in B):

1. **Predizione con il giroscopio.** Un vettore fisso nel mondo, visto da un
   riferimento che ruota con ω, evolve come dγ/dt = −ω × γ. Discretizzazione
   esatta per ω costante nell'intervallo:
   γ⁻_k = R(−(ω_k − b̂_ω) Δt) γ_{k−1}, con R da Rodrigues.
2. **Correzione con l'accelerometro**, pesata dall'affidabilità:
   γ_k = γ⁻_k + α_k (f_k − γ⁻_k), con α_k = (Δt / (τ + Δt)) · w_k
   e w_k = exp(−((\|f_k\| − g_cal) / σ_f)²) · exp(−(\|ω_k\| / σ_ω)²).
   Quando f contiene accelerazione dinamica (\|f\| ≠ g_cal) o il telefono ruota
   forte, la correzione si spegne e prevale il giroscopio.
3. **Normalizzazione**: γ_k ← g_cal · γ_k / \|γ_k\|.

Parametri provvisori da validare: τ = 1,5 s, σ_f = 0,1 g_cal, σ_ω = 3 rad/s.

**Bias del giroscopio**: quando il rilevatore di quiete (§3.6) è attivo per
almeno T_q, b̂_ω viene aggiornato con la media di ω (EMA lenta).

### 3.3 Accelerazione dinamica e componenti

- **a_k = f_k − γ_k** (m/s²), modulo \|a_k\|, in G: G_k = \|a_k\| / g₀.
- Versore verticale (verso l'alto): u_k = γ_k / \|γ_k\|.
- **Verticale**: a_v = a·u (positiva verso l'alto).
- **Orizzontale**: a_h = a − a_v u, modulo \|a_h\|.
- **Longitudinale / laterale**: richiedono la direzione di marcia, che *non è
  osservabile* con un telefono libero in tasca. Si stimano solo se il
  telefono è **solidale al veicolo**, cioè con orientamento stabile rispetto
  alla gravità per tutta la finestra. Due modi: direzione principale (PCA)
  di a_h su una finestra di 10–30 s, con segno risolto dal confronto con la
  variazione di velocità GPS, oppure rotta GPS. Altrimenti si riportano solo
  verticale e orizzontale, e la UI lo dichiara.

### 3.4 Jerk

j(t) = da/dt, calcolato sul **vettore** a, che è robusto all'orientamento.
\|j\| non è la derivata di \|a\|.

La differenza finita semplice amplifica il rumore: se a ha rumore bianco con
deviazione σ, la differenza (a_k − a_{k−1}) / Δt ha deviazione
σ√2 / Δt. A 200 Hz e σ = 0,02 m/s² (valore **solo di esempio**) si otterrebbe
circa 5,7 m/s³ di puro rumore.

Scelta: **pendenza ai minimi quadrati** su una finestra mobile di N campioni,
con i timestamp reali, che quindi funziona anche con campionamento
irregolare:

  ĵ = Σ (t_i − t̄)(a_i − ā) / Σ (t_i − t̄)², con deviazione del rumore
  σ / √(Σ (t_i − t̄)²).

Con N campioni equispaziati Σ(t_i − t̄)² = Δt² N(N² − 1)/12, quindi la
varianza scende di un fattore N(N² − 1)/24 ≈ N³/24 rispetto al rapporto
incrementale, al prezzo di una banda ridotta (ritardo
≈ N Δt / 2). È l'equivalente del derivatore di Savitzky–Golay di grado 1,
generalizzato a Δt irregolari. N provvisorio: copertura di ~30 ms
(da verificare con il simulatore: banda contro rumore).

Se un intervallo supera 3 volte il periodo atteso (buco nei dati), lo stimatore
riparte e il campione viene marcato.

### 3.5 Grandezze integrali dell'evento

- **Variazione di velocità** Δv = ∫ a dt (vettore, tra inizio e fine evento).
  È la grandezza fisica di riferimento per la severità di un urto. È **molto
  meno sensibile del picco** al sottocampionamento, e per una vibrazione
  oscillatoria a media nulla vale ≈ 0: questo la distingue dagli urti.
  L'errore dovuto al bias residuo b_a cresce come \|b_a\| · T_evento, quindi è
  trascurabile per eventi brevi.
- **Durata** sopra i livelli di attivazione e di rilascio (§3.7).
- **Picco** di \|a\|, picco di \|j\|.
- **Rotazione**: picco di \|ω\| e angolo totale ∫\|ω\| dt.
- **Cambio di orientamento**: θ = arccos(u_pre · u_post), con u_pre medio
  nella finestra prima dell'evento e u_post dopo l'assestamento.
- **Caduta libera**: durata T_ff con \|f\| < f_ff. In caduta libera ideale
  vale h = ½ g T_ff², quindi T_ff = √(2h / g): 0,32 s per 0,5 m e 0,45 s per 1 m.
  È una relazione **fisica verificabile** con un esperimento sicuro
  (telefono lasciato cadere su un cuscino da altezze note, §10).
- **Quiete successiva**: dopo l'evento, varianza di \|f\| bassa e
  \|ω\| ≈ 0 per T_post.

**Attenzione alla caduta libera con rotazione.** Il sensore non è nel
baricentro del telefono: se il telefono ruota, l'accelerometro legge anche
ω × (ω × r) + ω̇ × r (r = posizione del sensore rispetto al baricentro, ignota).
Con ω = 20 rad/s e r = 5 cm il termine centripeto vale 20 m/s², circa 2 g.
Un telefono che cade ruotando **non legge zero**. Per questo f_ff non può
essere vicina a 0, e la caduta libera è valutata insieme a \|ω\|.

### 3.6 Rilevatore di quiete

Quiete quando, su una finestra di 0,5–1 s, std(\|f\|) < s_q e
max \|ω\| < ω_q. Serve per il bias del giroscopio, per g_cal, per la quiete
successiva all'evento e per la qualità del segnale.

### 3.7 Segmentazione degli eventi (non una soglia fissa)

La linea di base è **adattiva**: statistiche robuste di \|a\| (mediana e MAD)
su una finestra lunga (10–30 s) che esclude gli eventi in corso. Punteggio di
novità: z_k = (\|a_k\| − mediana) / (1,4826 · MAD + ε), dove 1,4826 rende la
MAD consistente con σ per una gaussiana.

- Inizio evento: z > z_on **oppure** caduta libera (\|f\| < f_ff con \|ω\|
  compatibile), **oppure** \|j\| sopra la sua linea di base robusta.
- Fine evento: z < z_off (isteresi, con z_off < z_on) per almeno T_off.
- Buffer circolare: 5 s prima dell'evento e T_post dopo, salvati per intero.

Il livello di attivazione è quindi relativo all'attività in corso. In mountain
bike le accelerazioni "normali" sono molto più grandi che in camminata, e una
soglia fissa darebbe falsi allarmi continui o non vedrebbe nulla.

### 3.8 Frequenza di campionamento e picchi

Un impulso di durata T contiene energia fino a frequenze dell'ordine di 1/T.
Se il periodo di campionamento è confrontabile con T, il picco campionato
dipende dalla fase e può essere molto inferiore al vero.

Esempio: impulso semisinusoidale di 20 ms a 50 Hz. C'è un campione per impulso
e, secondo la fase, il campione cade ovunque tra lo zero e il picco.

Conseguenze di progetto:

1. richiedere la frequenza più alta disponibile (≤ 200 Hz senza permessi
   aggiuntivi) **durante le sessioni attive**;
2. basare la severità soprattutto su Δv e durata, che sono integrali e più
   robuste; il picco resta un indizio;
3. marcare la saturazione: il picco diventa un limite inferiore e la
   confidenza scende.

### 3.9 Filtri: riepilogo e motivazioni

| Filtro | Dove | Motivazione |
|---|---|---|
| Complementare assistito dal giroscopio | Gravità | §3.2 |
| Pendenza ai minimi quadrati | Jerk | Riduce la varianza di circa N³/24 e gestisce Δt irregolari |
| Statistiche robuste mobili (mediana / MAD) | Linea di base | Non sono trascinate dagli eventi stessi (punto di rottura del 50%) |
| Passa-alto implicito (a = f − γ) | Accelerazione dinamica | La gravità è la componente lenta |
| Energia per banda (es. < 3 Hz, 3–15 Hz, > 15 Hz, da verificare) | Vibrazioni e passo | Separa le vibrazioni (alta frequenza, a media nulla) dai moti del corpo |

Kalman/EKF: rimandato con motivazione nel §3.2. Il confronto andrà fatto sui
dati registrati, a parità di interfaccia.

---

## 4. Classificazione del pericolo

### 4.1 Principio

Due assi indipendenti, poi combinati:

1. **Anomalia statistica A**: quanto l'evento è insolito rispetto al
   comportamento normale *nello stesso contesto* (attività, posizione del
   telefono).
2. **Severità fisica S**: quanto l'evento è intenso in termini fisici
   (Δv, picchi, caduta libera, rotazione, orientamento, quiete successiva).

Un evento raro ma debole (prendere in mano il telefono in un modo insolito)
non è pericoloso. Un evento intenso ma normale per il contesto (atterraggio di
un salto in MTB) non è anomalo. Il livello alto richiede entrambi gli assi.

### 4.2 Vettore delle caratteristiche dell'evento

x = [ \|Δv\|, Δv_v, \|Δv_h\|, picco \|a\|, picco \|j\|, durata, T_ff, picco \|ω\|,
∫\|ω\|dt, θ_orientamento, quiete_post (s), Δv_GPS (se disponibile),
rapporto di energia ad alta frequenza ]

### 4.3 Anomalia A: distanza di Mahalanobis robusta

Per ogni contesto si mantiene una stima robusta di media μ e covarianza Σ
delle caratteristiche degli eventi normali (stimatore MCD, o shrinkage, sui
dati di riferimento del §10). Poi:

  D² = (x − μ)ᵀ Σ⁻¹ (x − μ).

Se le caratteristiche fossero gaussiane, D² seguirebbe una χ² con k gradi di
libertà, e la soglia per il livello 1 sarebbe un quantile (es. 99%). Poiché la
gaussianità **non è garantita** (le code sono pesanti), il quantile va
**ricalibrato empiricamente** sui dati normali registrati, scegliendo il
tasso di falsi allarmi accettato per ora di uso. Prima di avere dati si usano
scale fisiche provvisorie (§4.6).

### 4.4 Severità S: indizi fisici

Ogni indizio è trasformato in [0, 1] con una funzione logistica
φ(x) = 1 / (1 + exp(−(x − x₀)/s)), che è continua: niente salti tra
"sotto soglia" e "sopra soglia". I parametri x₀ e s hanno un significato
fisico dichiarato:

| Indizio | Grandezza | Ancoraggio fisico (provvisorio) |
|---|---|---|
| Urto | \|Δv\| | Velocità di impatto equivalente: v = √(2gh) dà 3,1 m/s per 0,5 m e 4,4 m/s per 1 m |
| Caduta | T_ff | Altezza equivalente h = ½ g T_ff² |
| Rotazione | ∫\|ω\|dt, picco \|ω\| | Rotazione rispetto a quella tipica della gestione a mano, da misurare |
| Orientamento | θ | Passaggio da una postura all'altra (es. verticale → orizzontale ≈ 90°) |
| Inattività | quiete_post | Assenza di movimento dopo l'urto |
| Coerenza GPS | Δv_GPS contro Δv_IMU orizzontale | Concordanza di segno e ordine di grandezza |

### 4.5 Combinazione in livelli

Sia S_tot = 1 − Π (1 − w_i φ_i) (combinazione "OR morbida", in [0, 1]) e sia
n_c il numero di indizi **indipendenti** concordi (φ_i > 0,5).

| Livello | Condizione (struttura; valori da calibrare) |
|---|---|
| **0** Movimento normale | D² sotto il quantile normale |
| **1** Movimento anomalo | D² sopra il quantile, S_tot bassa |
| **2** Accelerazione intensa | S_urto alta (Δv o picco), ma n_c ≤ 1 |
| **3** Potenzialmente pericoloso | S_urto alta **e** almeno un altro indizio concorde (caduta libera precedente, cambio di orientamento, quiete successiva, calo di velocità GPS coerente) |
| **4** Estremamente anomalo, da verificare subito | Condizioni del livello 3 con valori estremi (saturazione, Δv molto alta) **e** n_c ≥ 3 **e** quiete successiva confermata |

**Classificazione in due tempi.** Il livello 3 è *provvisorio* entro
~0,2–0,5 s dalla fine dell'urto. Il livello 4 si può confermare solo dopo
T_post, perché la quiete successiva richiede tempo. La diagnostica mostra
entrambi i momenti, e la latenza è misurata nei test.

**Isteresi e refrattarietà:** un solo evento per episodio; una ripetizione
ravvicinata aggiorna l'evento esistente invece di crearne uno nuovo.

### 4.6 Soglie

- In assenza di dati si usano solo gli ancoraggi fisici del §4.4, marcati
  `PROVVISORIO` nel codice e nella documentazione.
- Calibrazione: si sceglie il tasso di falsi allarmi per ora sui dati normali,
  poi si misura la sensibilità sugli esperimenti controllati del §10. Le curve
  ROC per livello vanno riportate con intervalli di confidenza
  (Wilson/Clopper–Pearson), dato il numero ridotto di prove.
- Le soglie sono **specifiche del contesto** (attività dell'app: MTB, sci,
  escursionismo) e della posizione del telefono.

---

## 5. Affidabilità e falsi positivi

| Causa di falso positivo | Contromisura | Motivazione |
|---|---|---|
| Prendere in mano o posare il telefono | \|Δv\| piccola, nessuna caduta libera, rotazione tipica della gestione, nessuna quiete successiva anomala | Gestire il telefono sposta pochi decimetri a bassa velocità |
| Rotazione del dispositivo | Gravità assistita dal giroscopio (§3.2) | Con il solo passa-basso una rotazione di 90° genera fino a 1,41 g di falsa accelerazione |
| Vibrazioni (veicolo, sterrato) | Energia ad alta frequenza, Δv ≈ 0, linea di base adattiva | Le vibrazioni sono oscillatorie e a media nulla |
| Posizione del telefono | Caratteristiche invarianti all'orientamento (moduli, verticale/orizzontale) e linea di base per contesto | Tasca, zaino e manubrio cambiano solo le ampiezze tipiche |
| Telefono caduto (non la persona) | Indizi da validare: caduta libera pulita (\|f\| ≈ 0) con forte rotazione, poi quiete *su superficie piana*. Il corpo umano che cade produce di solito una caduta libera parziale | **Ipotesi**, non dimostrata: è il punto più critico da validare (§11) |
| Dati mancanti | Buchi > 3 periodi: stimatori azzerati, qualità ridotta, nessun evento costruito sui buchi | |
| GPS impreciso | Usato solo con `speedAccuracy` sotto soglia e dato recente (< 2 s); altrimenti ignorato | |

### 5.1 Qualità del segnale Q ∈ [0, 1]

Q = q_rate · q_buchi · q_saturazione · q_gravità · q_bias · q_timing, dove:

- q_rate = min(1, f_misurata / f_richiesta);
- q_buchi = 1 − frazione di intervalli > 3 periodi nella finestra;
- q_saturazione = 1 se nessun asse ha raggiunto il 98% del fondo scala, altrimenti 0,5;
- q_gravità = exp(−((\|γ_pre\| − g_cal) / σ)²) e coerenza tra u predetto dal
  giroscopio e u misurato dall'accelerometro dopo l'assestamento;
- q_bias: 0,5 finché b̂_ω non è stato stimato almeno una volta;
- q_timing: 0,5 se si usano tempi di ricezione invece dei timestamp hardware
  (es. dati BlueST dalla SensorTile).

### 5.2 Confidenza del rilevamento

C = Q · E, dove E cresce con il numero di indizi indipendenti concordi e con
la loro distanza dal limite di decisione. Esempio di forma: E = 1 − Π(1 − e_i),
con e_i = \|2φ_i − 1\| per gli indizi concordi.

Va dichiarato che C **non è una probabilità calibrata** finché non viene
confrontata con dati etichettati (diagramma di affidabilità). Nella UI si
mostra come "indice di confidenza", non come percentuale di accuratezza.

---

## 6. Architettura software proposta

### 6.1 Moduli separati

```
acquisition/   Sorgenti → MotionSample { tUs (hardware), tipo, x, y, z, accuratezza }
               · PhoneMotionSource   (nativo Kotlin, §6.2)
               · BlueStMotionAdapter (da SensorReading: SensorTile, q_timing ridotta)
               · ReplaySource        (sessioni registrate)  · SimulatorSource (§9)
preprocess/    Allineamento acc/giro, buchi, saturazione, unità SI, rate meter
estimation/    GravityTracker (§3.2), GyroBias, StillnessDetector, LinearAcc, JerkEstimator
features/      RobustBaseline, EventSegmenter, EventFeatures (§3.5, §4.2)
classify/      AnomalyModel (§4.3), SeverityModel (§4.4), LevelCombiner (§4.5), Confidence (§5)
events/        DetectionEvent → tabella events (JSON) + finestra grezza → samples
ui/diagnostics Schermata "Rilevamento" (§8)
```

- Ogni stadio è una **funzione pura o un oggetto con stato esplicito**, in
  Dart senza dipendenze da Flutter, e quindi testabile con `flutter test` e
  riproducibile sulle sessioni registrate (`ReplaySource`).
- Interfaccia unica: `DetectionEngine.ingest(MotionSample) → DetectionState`.
  La UI legge lo stato sui propri frame, come fa già `LiveSessionController`.
- `LiveSessionController` resta per la UI della sessione. Il suo `level` e
  `onImpact` vengono alimentati dal nuovo motore (sostituzione mirata di P1/P2).

### 6.2 Acquisizione: confronto delle alternative

| Opzione | Pro | Contro |
|---|---|---|
| 1. Mantenere `sensors_plus` e usare i suoi `timestamp` | Modifica minima, risolve P3/P4 | Nessun batching (P8), nessun metadato (P7), nessun `TYPE_GRAVITY`/`ROTATION_VECTOR` |
| 2. **Modulo Kotlin con `SensorManager`** (EventChannel proprio) | Timestamp nativi, metadati, `maxReportLatencyUs` (FIFO), callback di accuratezza, tutti i tipi di sensore, consegna a blocchi (meno passaggi sul canale) | Codice nativo da mantenere, già presente nel progetto (`MainActivity.kt`) |

**Proposta:** opzione 1 come primo passo (immediato e testabile), poi
opzione 2 se le misure di consumo e di jitter del §10.4 lo giustificano.
Il percorso BlueST esistente (grafici, registrazione, export) **non cambia**:
il motore è un consumatore in più.

### 6.3 Real-time, batteria, ciclo di vita

- Costo di calcolo O(1) per campione (filtro: decine di operazioni; jerk:
  O(N) con N piccolo; quantili mobili con stimatori approssimati o finestre
  brevi). A 200 Hz il costo dominante previsto è il **passaggio degli eventi**
  dal nativo a Dart, non la matematica: da misurare (§10.4).
- Campionamento configurabile: 50 / 100 / 200 Hz. Fuori dalle sessioni,
  frequenza bassa o sensori spenti.
- Ciclo di vita: in background Android limita i sensori; la registrazione
  continua solo con il servizio in primo piano già esistente. Il tipo
  `connectedDevice` è pensato per i dispositivi collegati: per i soli sensori
  del telefono va **verificato** quale `foregroundServiceType` richieda
  Android 14+ (punto aperto, §11).
- Permessi: nessuno per accelerometro e giroscopio fino a 200 Hz;
  `HIGH_SAMPLING_RATE_SENSORS` oltre; `ACCESS_FINE_LOCATION` solo se il GPS
  viene attivato dall'utente.

### 6.4 Registrazione e analisi successiva

- Evento: `events.type = 'detection'`, `detail` = JSON con versione
  dell'algoritmo, parametri, caratteristiche x, D², S, livello provvisorio e
  confermato, Q, C, timestamp di inizio e fine.
- Dati grezzi della finestra (pre e post) in `samples`, nella sessione attiva
  o in una sessione automatica dedicata.
- **Versionare l'algoritmo** (`algoVersion`) e salvare i parametri: ogni
  evento resta rianalizzabile con versioni successive tramite `ReplaySource`.

---

## 7. Pseudocodice del ciclo principale

```text
on MotionSample s:
  pre = preprocess.push(s)                  # allinea acc/giro, buchi, saturazione
  if pre.gap: estimators.resetLocal(); quality.markGap()
  if pre.gyro: gravity.predict(pre.omega - gyroBias.value, pre.dt)
  if pre.acc:
      gravity.correct(pre.f, weight(|pre.f|, |omega|))
      a     = pre.f - gravity.gamma                     # m/s², riferimento B
      u     = gravity.gamma / |gravity.gamma|
      a_v   = dot(a, u);  a_h = a - a_v * u
      j     = jerk.push(pre.t, a)                       # pendenza LS
      still = stillness.push(|pre.f|, |omega|)
      if still.longEnough: gyroBias.update(omega); gCal.update(|pre.f|)
      baseline.pushUnlessInEvent(|a|, |j|)
      z = baseline.score(|a|, |j|)
      seg = segmenter.push(t, z, freeFall(|pre.f|, |omega|), a, omega, u)
      if seg.closed:
          x      = features(seg, preBuffer, postBuffer, gps)
          A      = anomaly.mahalanobis(x, context)
          S      = severity.score(x)
          level  = combine(A, S)             # provvisorio
          C      = quality.Q() * evidence(S)
          events.save(level, C, x, rawWindow)
      if seg.postWindowElapsed:
          confirm(level, postStillness)      # eventuale passaggio a 4
  quality.update(rate, saturation, gravityConsistency)
```

---

## 8. Schermata diagnostica "Rilevamento" (FASE B)

- Valori numerici: f_x, f_y, f_z; a_x, a_y, a_z; \|a\| in m/s² e in G; a_v e
  \|a_h\|; \|j\|; \|ω\|; frequenza misurata per sensore; jitter dei timestamp.
- Stato dei sensori: presenza, fondo scala, risoluzione, saturazione,
  bias del giroscopio stimato, g_cal.
- Livello corrente (0–4), confidenza C e qualità Q con i singoli fattori.
- Grafici in tempo reale (riusando `charts.dart` e `ChannelBuffer`): \|f\|,
  \|a\|, a_v / \|a_h\|, \|j\|, \|ω\|, punteggio z, con le soglie provvisorie
  disegnate e marcate come tali.
- Elenco degli eventi registrati, con dettaglio delle caratteristiche e
  apertura della finestra grezza nell'analisi esistente.

---

## 9. Simulatore (FASE B)

Generatore **fisico** e deterministico (seed): si definiscono traiettoria e
orientamento nel mondo, R(t) e a_w(t), e si sintetizzano le letture:

- f_B = Rᵀ(a_w − g_w) + ω × (ω × r) + ω̇ × r + b_a + scala + rumore,
  poi quantizzazione e saturazione;
- ω_B = ω + b_ω(t) + rumore;
- timestamp con jitter e buchi configurabili; GPS a 1 Hz con rumore, ritardo
  e perdite.

Scenari: fermo, camminata, corsa, gestione a mano (prendere e posare),
rotazione improvvisa, vibrazioni (più bande), accelerazione progressiva e
improvvisa, frenata brusca (telefono fisso e in tasca), impatto, caduta libera
del telefono da altezze diverse, caduta della persona (modello semplificato e
dichiarato tale), GPS disturbato o assente.

Per ogni scenario i test verificano: livello atteso, latenza di
rilevamento, intensità misurata contro quella vera (Δv, picco), falsi
positivi e falsi negativi. Inclusi test Monte Carlo su più seed.
**La simulazione verifica il codice e la matematica, non il mondo reale.**

---

## 10. Validazione sperimentale (da fare, nessun dato inventato)

### 10.1 Caratterizzazione del dispositivo

- Telefono fermo per 10 min: rumore (deviazione standard per asse), bias,
  **varianza di Allan** di accelerometro e giroscopio, g_cal.
- Sei posizioni statiche (±X, ±Y, ±Z): offset ed errori di scala.
- Frequenza effettiva e jitter dai timestamp, a 50, 100 e 200 Hz.

### 10.2 Esperimenti controllati sicuri

- **Caduta del telefono su cuscino** da altezze misurate (0,3 / 0,5 / 1 m):
  confronto tra T_ff misurato e √(2h/g), e verifica di Δv rispetto a √(2gh).
- Rotazioni a mano a velocità diverse: assenza di falsa accelerazione.
- Gestione quotidiana (prendere, posare, tasca, borsa) per ore: tasso di falsi
  allarmi per ora.
- Veicolo con telefono fisso (passeggero, in sicurezza): frenate normali
  contro velocità GPS.
- Attività dell'app (MTB, sci, escursionismo): raccolta dei dati normali per
  la linea di base e per Σ.

**Nessuna prova di caduta di persone.** Eventuali dati di cadute umane solo da
dataset pubblici, citati, e con il limite dichiarato della diversa posizione
del sensore.

### 10.3 Metriche

Sensibilità e specificità per livello, falsi allarmi per ora, latenza (mediana
e 95° percentile), errore su Δv e T_ff, sempre con intervalli di confidenza.

### 10.4 Prestazioni e consumi

`dumpsys batterystats` / Battery Historian e tempo di CPU per campione, a
50, 100 e 200 Hz, con e senza batching (opzione 1 contro opzione 2, §6.2).

---

## 11. Punti aperti da validare sperimentalmente

1. Costante di tempo τ e pesi σ_f, σ_ω del filtro di gravità.
2. Lunghezza della finestra del jerk (banda contro rumore) alla frequenza reale.
3. Distinguibilità tra **telefono caduto** e **persona caduta**: è l'ipotesi
   più debole del progetto.
4. Soglie: f_ff, z_on/z_off, T_post, quantile di D², parametri delle
   logistiche, pesi w_i.
5. Stima di longitudinale e laterale con telefono non fissato (probabilmente
   non affidabile).
6. Effetto del filtro anti-aliasing interno e della frequenza sul picco
   misurato.
7. Saturazione: frequenza degli urti che superano il fondo scala.
8. `foregroundServiceType` corretto per i soli sensori del telefono (Android 14+).
9. Costo energetico reale delle opzioni di acquisizione.
10. Calibrazione dell'indice di confidenza C in probabilità.

---

## 12. Piano della FASE B (proposto, da approvare)

1. **Timestamp hardware** in `PhoneTransport` (P3/P4): `MotionSample` con
   `tUs` e adattatore per il motore; il percorso BlueST resta invariato.
2. `estimation/`: GravityTracker, GyroBias, StillnessDetector, Jerk, con test
   unitari analitici (rotazione nota, caduta libera, gradino).
3. Simulatore fisico e scenari del §9, con i test del §9.
4. `features/` e `classify/` con soglie `PROVVISORIO`, test per scenario.
5. Registrazione degli eventi e `ReplaySource`.
6. Schermata diagnostica "Rilevamento".
7. Sostituzione della logica P1/P2 in `LiveSessionController`.
8. Misure di consumo; acquisizione Kotlin nativa (opzione 2) solo se giustificata.
9. Documentazione di formule e soglie in `docs/TECHNICAL.md`.

Il sistema **non va dichiarato affidabile né adatto ad applicazioni di
sicurezza** finché la validazione del §10 non è stata completata e documentata.
