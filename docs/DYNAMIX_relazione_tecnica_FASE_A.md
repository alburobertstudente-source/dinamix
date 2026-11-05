# DYNAMIX — Relazione tecnica, FASE A (studio)

Versione 2 · sostituisce `FASE_A_rilevamento_movimento.md` (stessa matematica,
scope esteso a registrazione, allarme ed SMS).

**Stato: solo studio.** Nessun file dell'app è stato modificato. Tutte le soglie
numeriche sono **provvisorie**: servono a costruire simulatore e test, e vanno
sostituite con valori misurati secondo il §14. Nessuna soglia è un limite medico
o di sicurezza. Nessuna accuratezza è dichiarata, perché nessuna è stata misurata.

---

## Indice

1. Progetto esistente
2. Sensori: API, caratteristiche, limiti
3. Sistema di riferimento e modello del moto
4. Gravità e orientamento
5. Accelerazione dinamica, G, componenti direzionali
6. Jerk, velocità e accelerazione angolare
7. Filtraggio digitale
8. Finestre temporali ed eventi
9. Caduta del telefono e impatto pericoloso
10. GPS
11. Motore di classificazione
12. Allarme, conto alla rovescia, SMS
13. Registrazione utente, privacy, sicurezza
14. Simulazione e validazione
15. Architettura software e Android
16. Decisioni che spettano a te
17. Punti aperti e piano delle fasi successive
18. Quality assurance: cosa si può verificare, dove e come
19. Identità visiva e logo
20. Scenari animati
21. Esperienza utente e navigazione
22. Prestazioni grafiche e separazione dal motore
23. Preparazione alla distribuzione
24. Domande aggiuntive (oltre al §16)
25. Architettura doppia: SensorTile e sensori dello smartphone
26. Domande sulla modalità SensorTile
27. Analisi matematica completa di ogni movimento
28. Classificatore a sequenze di fasi e sistema anti-falsi allarmi
29. Piano di test per i movimenti brevi e intensi

---

## 1. Progetto esistente

### 1.1 Piattaforma

| Aspetto | Valore |
|---|---|
| Linguaggio / framework | Dart, Flutter (CI su 3.47.9 stable) |
| Piattaforma | Android (`MainActivity.kt`, `RecordingService.kt`) |
| Sensori del telefono | `sensors_plus` 7.1.1 |
| Persistenza | SQLite (`sqflite`): tabelle `sessions`, `samples`, `events` |
| Impostazioni | `shared_preferences` (`AppSettings`) |
| Stato / DI | `provider`, contenitore `AppServices` |
| Nome dell'app | "DinamiX" (la specifica usa "DYNAMIX": vedi §16) |

### 1.2 Flusso attuale dei dati del telefono

```
sensors_plus (un EventChannel per sensore)
 → PhoneTransport: unità BlueST (mg, 0,1 dps, mGa, Pa) impacchettate come
   notifiche BlueST (int16, tick a 10 ms)
 → ConnectionManager → BlueStDecoder (receivedAtMs = DateTime.now())
 → SensorHub (grafici) · SessionRecorder (DB) · LiveSessionController (sessione)
```

Questa scelta permette di riusare decoder, grafici, registrazione ed export della
SensorTile, e va mantenuta. Il rilevamento però avrà un ingresso proprio (§15).

### 1.3 Problemi rilevati

| # | Dove | Problema | Effetto |
|---|---|---|---|
| P1 | `live_session.dart` | Urto = **modulo grezzo** (gravità inclusa) sopra una soglia fissa | Metodo da evitare: dipende dall'orientamento, non vede la caduta libera, lo scuotimento dà falsi allarmi |
| P2 | `live_session.dart` | `motionEnergy` = media mobile di \|\|f\| − 1 g\| | Mescola rumore, vibrazioni e moto; nessuna separazione della gravità |
| P3 | `phone_transport.dart` | Il `timestamp` hardware di `SensorEvent` (fornito da `sensors_plus` in µs) viene **scartato**; si usa l'ora di ricezione | Jitter del canale piattaforma: il jerk lo amplifica |
| P4 | `phone_transport.dart` | Tick a 10 ms su 16 bit, che si azzera ogni 655,36 s | Risoluzione temporale insufficiente a 100–200 Hz |
| P5 | `DevicePhoneSensors` | Periodo richiesto 20 ms (50 Hz) | Picchi di urti brevi sottostimati (§8.4) |
| P6 | — | Nessun uso di gravità, accelerazione lineare, rotation vector o GPS | — |
| P7 | — | Nessun accesso al fondo scala e alla risoluzione dei sensori | Saturazione non riconoscibile |
| P8 | `sensors_plus` | Nessun batching FIFO (`maxReportLatencyUs`) | Più risvegli della CPU, più consumo |
| P9 | — | Accelerometro e giroscopio su stream non sincronizzati | Serve allinearli |
| P10 | `MainActivity` | `FlutterActivity` con motore Flutter **legato all'Activity** | Se l'utente chiude l'app dalle app recenti, il codice Dart si ferma anche con il servizio attivo: il monitoraggio continuo non è possibile così (§15.3) |
| P11 | `RecordingService` | Attivo solo durante le registrazioni, tipo `connectedDevice` | Non adatto a un monitoraggio dei soli sensori del telefono su Android 14+ (§15.3) |

Non sono problemi: la quantizzazione int16 (1 mg, 0,1 dps) è più fine del rumore
dei MEMS consumer, e il fondo scala del pacchetto (±32,767 g, ±3276,7 dps) supera
quello dei telefoni.

### 1.4 Da riusare

Tabelle `samples` ed `events`, `SessionRecorder`, `SeriesStats` (Welford),
`PeakDetector`, `MinMaxBins`, grafici (`charts.dart`, `ChannelBuffer`), export,
`RecordingService` (da estendere), schermate home, live e analisi.

---

## 2. Sensori: API, caratteristiche, limiti

Non riporto valori di precisione "tipici": dipendono dal chip di ogni modello.
Per ogni sensore indico cosa leggere dalle API e cosa misurare (§14.2).

### 2.1 Disponibilità tramite le API

| Sensore Android | `sensors_plus` 7.1.1 | Note |
|---|---|---|
| `TYPE_ACCELEROMETER` | sì | Forza specifica, m/s² |
| `TYPE_GYROSCOPE` | sì | rad/s, con compensazione della deriva di sistema |
| `TYPE_LINEAR_ACCELERATION` | sì (`userAccelerometer`) | Sensore virtuale del produttore |
| `TYPE_MAGNETIC_FIELD` | sì | µT |
| `TYPE_PRESSURE` | sì | hPa |
| `TYPE_GRAVITY` | **no** | Serve codice nativo |
| `TYPE_ROTATION_VECTOR`, `TYPE_GAME_ROTATION_VECTOR` | **no** | Serve codice nativo |
| Metadati (`getMaximumRange`, `getResolution`, `getMinDelay`, FIFO, fornitore) | **no** | Serve codice nativo |
| GPS | assente nel progetto | Serve un plugin o codice nativo |

Conclusione: per soddisfare i §2 e §3 della specifica serve un **modulo Kotlin di
acquisizione** (`SensorManager`), che il progetto ha già come base nativa
(`MainActivity.kt`).

### 2.2 Accelerometro

- Misura la **forza specifica** f = a − g (riferimento del telefono). Da fermo
  legge +1 g verso l'alto; **in caduta libera legge ≈ 0**.
- Errori: bias, errore di scala, non ortogonalità, dipendenza dalla temperatura,
  rumore, quantizzazione, **saturazione** al fondo scala (`getMaximumRange()`).
  Un urto su superficie rigida può superarlo: il picco è allora solo un limite
  inferiore.
- Frequenza: `getMinDelay()` indica il periodo minimo. Oltre 200 Hz, da
  Android 12 serve `HIGH_SAMPLING_RATE_SENSORS`. La frequenza richiesta è un
  suggerimento: va **misurata** dai timestamp.
- Filtro anti-aliasing interno: sconosciuto all'app, da caratterizzare (§14.2).

### 2.3 Giroscopio

- ω in rad/s. Errori: bias e deriva (dipendenti dalla temperatura), rumore
  (angle random walk), scala, saturazione.
- Integrare ω produce un errore di orientamento che cresce nel tempo: serve una
  correzione (§4).

### 2.4 Sensori virtuali (gravità, accelerazione lineare, rotation vector)

Sono fusioni del produttore, non documentate, con latenza e comportamento
variabili da modello a modello. **Uso proposto:** riferimento di confronto in
diagnostica e verifica di coerenza. La stima primaria è la nostra (§4): nota,
testabile in simulazione e uguale su tutti i dispositivi.

### 2.5 Magnetometro

È disturbato da veicoli, metalli e magneti delle custodie. **Non entra** nella
stima primaria: per il rilevamento serve la direzione della gravità, non lo yaw.
Può servire come indizio per la direzione di marcia (§5.3), con peso basso.

### 2.6 Barometro

Indizio debole di variazione di quota. È sensibile al vento e alla pressione
dinamica in movimento. Peso basso nella confidenza.

### 2.7 GPS

Trattato nel §10.

### 2.8 Riconoscimento automatico e degradazione

All'avvio il modulo nativo elenca i sensori presenti e salva per ciascuno: tipo,
fornitore, fondo scala, risoluzione, `minDelay`, `maxDelay`, FIFO, wake-up.

| Mancante | Comportamento |
|---|---|
| Giroscopio | Gravità con il solo passa-basso adattivo. Confidenza ridotta durante le rotazioni. Analisi delle rotazioni disattivata. La UI lo dichiara |
| GPS, barometro | Indizi assenti: non contano nella confidenza |
| Accelerometro | Rilevamento disattivato, stato mostrato |

---

## 3. Sistema di riferimento e modello del moto

### 3.1 Riferimenti

- **B (dispositivo)**: assi Android. x verso destra, y verso l'alto lungo lo
  schermo, z uscente dallo schermo, terna destrorsa.
- **W (mondo locale)**: z_W verso l'alto (opposto alla gravità). Yaw
  arbitrario senza magnetometro, quindi x_W e y_W sono definiti a meno di una
  rotazione attorno a z_W.
- **V (moto)**: x_V longitudinale (direzione di marcia), y_V laterale, z_V = z_W.
  Esiste solo se la direzione di marcia è stimabile (§5.3).

Rotazione q (quaternione unitario) da B a W: v_W = q ⊗ v_B ⊗ q*.

### 3.2 Equazione di misura

f_B = Rᵀ_{WB} (a_W − g_W) + ω × (ω × r) + α × r + b_a + n_a

con g_W = (0, 0, −g_loc), r la posizione dell'accelerometro rispetto al
baricentro del telefono (ignota, dell'ordine dei centimetri) e α = dω/dt.

Il termine ω × (ω × r) è importante: con ω = 20 rad/s e r = 5 cm vale
20 m/s² (≈ 2 g). Un telefono che cade **ruotando** non legge zero (§9.1).

### 3.3 Modulo misurato

\|f\| = √(f_x² + f_y² + f_z²). Da fermo vale g_loc in qualsiasi orientamento.
In moto dipende dall'angolo tra a e g:

- un'accelerazione orizzontale di 1 g dà \|f\| = √2 g = 1,41 g;
- la caduta libera dà \|f\| = 0.

Quindi \|f\| **non** è l'accelerazione dinamica. Viene calcolato e mostrato, ma
ha un uso diverso: è l'indizio diretto della caduta libera.

### 3.4 Gravità locale e calibrazione

g₀ = 9,80665 m/s² è la gravità **standard**, usata solo per convertire in G.
La gravità reale varia (circa 9,78 m/s² all'equatore, 9,83 m/s² ai poli, e
diminuisce con la quota), e l'accelerometro ha errori di scala. Per questo
g_cal = media di \|f\| nei tratti fermi, stimata sul dispositivo e aggiornata.
Facoltativa: calibrazione a 6 posizioni per offset e scala per asse.

---

## 4. Gravità e orientamento

### 4.1 Alternative

| Metodo | Pro | Contro |
|---|---|---|
| A. Passa-basso su f | Semplice | Durante le rotazioni: dopo una rotazione a gradino di θ, l'errore è 2 g sin(θ/2), cioè **1,41 g per 90°**, e decade con τ. Durante le accelerazioni prolungate (frenata) scambia accelerazione per inclinazione |
| B. `TYPE_GRAVITY` | Fusione già pronta | Scatola nera, varia tra dispositivi, non testabile in simulazione |
| C. **Filtro complementare non lineare su quaternione** (tipo Mahony) con giroscopio e accelerometro | Segue le rotazioni rapide e corregge la deriva. O(1). Analizzabile | Va scelta la costante di tempo |
| D. EKF (quaternione + bias) | Ottimo se i modelli di rumore sono noti | Senza dati reali le covarianze sarebbero inventate. Più difficile da verificare. Lo yaw non è osservabile senza magnetometro |

**Scelta: C**, con il bias del giroscopio stimato nei tratti fermi.

Motivazione: per due sensori con rumori bianchi stazionari, il filtro
complementare coincide con il Kalman a regime. L'EKF aggiungerebbe la stima
adattiva delle covarianze, che oggi non possiamo inizializzare in modo onesto.
L'interfaccia `OrientationEstimator` permette di confrontare C e D più avanti
sugli stessi dati registrati.

### 4.2 Equazioni

Stato: quaternione q (B → W) e bias b̂_ω.

1. Direzione "in alto" prevista in B: û = Rᵀ(q) e_z.
2. Direzione misurata: v = f / \|f\|.
3. Errore: e = v × û, cioè il vettore di rotazione che porta û su v.
4. Peso dell'accelerometro, che va a zero quando f non rappresenta la gravità:
   w = exp(−((\|f\| − g_cal)/σ_f)²) · exp(−(\|ω\|/σ_ω)²).
5. Velocità angolare corretta: ω_c = ω − b̂_ω + K_p w e.
6. Integrazione esatta per ω_c costante nell'intervallo:
   q_k = q_{k−1} ⊗ [cos(\|ω_c\|Δt/2), (ω_c/\|ω_c\|) sin(\|ω_c\|Δt/2)],
   poi normalizzazione.
7. Bias: quando il rilevatore di quiete (§8.3) è attivo per almeno T_q,
   b̂_ω ← b̂_ω + λ (ω − b̂_ω).

K_p equivale a una costante di tempo τ ≈ 1/K_p.
Valori provvisori: τ = 1,5 s, σ_f = 0,1 g_cal, σ_ω = 3 rad/s.

### 4.3 Incertezza dell'orientamento

Si stima e si mostra un'incertezza angolare σ_θ, che cresce con
\|b̂_ω‑residuo\|·t durante le fasi senza correzione e si riduce quando w è alto.
Entra nella qualità Q (§11.6).

---

## 5. Accelerazione dinamica, G, componenti direzionali

### 5.1 Accelerazione dinamica

- In B: **a_B = f_B − Rᵀ(q) (0, 0, g_cal)**.
- In W: **a_W = R(q) f_B − (0, 0, g_cal)**.

Non si sottrae mai 9,81 da un asse fisso.

### 5.2 G-force

G = \|a\| / g₀, istantaneo. Valore filtrato per la UI: media su 100 ms e picco
mobile su 1 s. Il rilevamento usa i valori **non filtrati** (§7).

### 5.3 Componenti direzionali

- **Verticale**: a_v = a_W · e_z. Sempre disponibile.
- **Orizzontale**: a_h = (a_W,x, a_W,y), con modulo \|a_h\|. Sempre disponibile.
- **Longitudinale e laterale**: servono l'angolo ψ tra x_W e la direzione di
  marcia. Tre stime possibili:
  1. **Rotta GPS** (bearing), valida solo sopra una velocità minima e con
     `bearingAccuracy` buona. Richiede anche lo yaw del telefono, cioè il
     magnetometro.
  2. **Regressione IMU–GPS**: con telefono **solidale** al veicolo, si cerca ψ
     che minimizza Σ\|R(ψ) a_h,i − (a_GPS,i, 0)\|². Soluzione in forma chiusa:
     ψ = atan2(Σ a_GPS,i a_h,y,i , Σ a_GPS,i a_h,x,i).
  3. **Direzione principale** di a_h (PCA) su 10–30 s. Il segno è ambiguo e va
     risolto con il GPS.

  Condizione di validità: orientamento del telefono stabile rispetto al veicolo
  (bassa \|ω\| relativa) per tutta la finestra. **Con il telefono in tasca la
  direzione di marcia non è osservabile**: in quel caso si mostrano solo
  verticale e orizzontale, con l'etichetta "direzione di marcia non
  determinabile".

---

## 6. Jerk, velocità e accelerazione angolare

### 6.1 Rumore della differenza finita

j[i] = (a[i] − a[i−1]) / Δt. Se a ha rumore bianco di deviazione σ, j ha rumore
σ√2/Δt. Esempio **numerico illustrativo** (σ non misurata): σ = 0,02 m/s² a
200 Hz dà 5,7 m/s³ di solo rumore. La differenza semplice resta disponibile in
diagnostica come "jerk istantaneo grezzo".

### 6.2 Derivata filtrata (scelta)

**Pendenza ai minimi quadrati** su N campioni, con i timestamp reali (funziona
anche con campionamento irregolare):

ĵ = Σ (t_i − t̄)(a_i − ā) / Σ (t_i − t̄)².

Con N campioni equispaziati Σ(t_i − t̄)² = Δt² N(N² − 1)/12, quindi la varianza
scende di N(N² − 1)/24 ≈ N³/24 rispetto alla differenza semplice. Il ritardo è
circa (N − 1)Δt/2. È il derivatore di Savitzky–Golay di grado 1, generalizzato
a Δt irregolari. N provvisorio: finestra di ~30 ms, da scegliere con il
simulatore (banda contro rumore).

Si calcola sul **vettore** a: \|j\| è invariante all'orientamento ed è diverso
dalla derivata di \|a\|.

### 6.3 Grandezze del jerk

Jerk istantaneo grezzo e filtrato, massimo e medio nella finestra, durata con
\|ĵ\| sopra la linea di base (§8.2). Direzione del cambiamento: versore ĵ/\|ĵ\|
in W (componenti verticale e orizzontale) e angolo tra a prima e dopo l'evento.

**Variazione del jerk** (snap, d²a/dt²): con la derivata seconda il rumore
cresce come 1/Δt². Non entra nella classificazione; è calcolata solo offline,
su dati registrati, se un'analisi ne mostra l'utilità.

### 6.4 Giroscopio

- ω = √(ω_x² + ω_y² + ω_z²) con il bias rimosso.
- **Accelerazione angolare** α = dω/dt con lo stesso stimatore a minimi
  quadrati (stessa motivazione del jerk).
- **Angolo ruotato** nella finestra: ∫\|ω\|dt (rotazione "percorsa"), e
  **cambio di orientamento netto**: angolo del quaternione q_pre* ⊗ q_post.
- Deriva: l'integrazione si usa solo su finestre brevi (≤ qualche secondo) e
  con il bias stimato. Per tempi lunghi vale l'orientamento fuso del §4.

---

## 7. Filtraggio digitale

### 7.1 Confronto

| Filtro | Proprietà | Uso in DYNAMIX |
|---|---|---|
| Passa-basso del 1° ordine (EMA) | Ritardo τ, attenuazione lenta | Valori della UI, linee di base lente |
| Passa-alto | Rimuove le componenti lente | Implicito in a = f − g; nessun passa-alto esplicito sul canale degli urti |
| **Butterworth** (IIR, biquad, trasformazione bilineare) | Banda passante massimamente piatta. Distorsione di fase: il ritardo di gruppo del 2° ordine in continua vale √2/(2π f_c), cioè **45 ms a 5 Hz** | Separazione in bande (§7.2), sempre in **parallelo** al canale grezzo. Offline: versione a fase nulla (avanti e indietro) |
| **Mediano** | Elimina gli impulsi | **Mai sul canale degli urti**: cancellerebbe proprio i picchi da rilevare. Solo per outlier di GPS e frequenza misurata |
| Complementare | Fonde due sensori con bande complementari | Orientamento (§4) |
| Kalman | Ottimo con modelli di rumore noti | Velocità GPS/IMU (§10.4); EKF per l'orientamento come alternativa futura |

### 7.2 Pipeline a bande (in parallelo, nessuna in serie al rilevamento)

```
grezzo f, ω (conservato sempre, per intero, nel buffer e nel DB)
 ├─ orientamento (§4) → a_B, a_W
 ├─ canale urti: a non filtrato + jerk a minimi quadrati
 ├─ banda "moto del corpo": Butterworth passa-basso, 2° ordine, f_c provvisoria 5 Hz
 ├─ banda "vibrazioni": Butterworth passa-alto, 2° ordine, f_c provvisoria 10 Hz → energia RMS
 └─ banda "postura": EMA, τ = 1 s
```

Le frequenze di taglio sono provvisorie: si scelgono con lo spettro dei dati
reali (camminata, corsa, veicolo) del §14. Il passo umano ha una cadenza
dell'ordine di 2 Hz, con armoniche. Ordine e ritardi vengono scritti nella
documentazione e nell'evento registrato (`algoVersion` + parametri).

Rumore del sensore: non si filtra a parte. Entra come σ nella linea di base
robusta (§8.2) e nella qualità.

---

## 8. Finestre temporali ed eventi

### 8.1 Statistiche per finestra

Finestre mobili (lunghezza provvisoria 1 s, passo 100 ms) su \|a\|, \|f\|,
\|ĵ\|, ω:

- media, varianza (Welford), deviazione standard, minimo, massimo;
- **RMS** = √((1/N) Σ a_i²);
- durata sopra un livello;
- energia E = Σ a_i² Δt_i, anche per banda (§7.2);
- numero di picchi (con refrattarietà);
- jerk massimo;
- angolo ruotato e cambio di orientamento netto.

Costo O(1) per campione grazie agli accumulatori a scorrimento, tranne il
massimo, per cui si usa una deque monotona (O(1) ammortizzato).

### 8.2 Linea di base adattiva e segmentazione

La linea di base è **robusta**: mediana e MAD di \|a\| e \|ĵ\| su 10–30 s, con
gli eventi in corso esclusi. Punteggio:

z = (x − mediana) / (1,4826·MAD + ε),

dove 1,4826 rende la MAD consistente con σ per una gaussiana e il punto di
rottura è del 50%, quindi gli eventi stessi non trascinano la linea di base.

- Inizio evento: z_a > z_on **oppure** caduta libera candidata (§9.1)
  **oppure** z_j > z_on.
- Fine evento: z < z_off (isteresi) per almeno T_off.
- Fasi: pre (5 s), evento, post (T_post, provvisorio 10 s).

La linea di base è relativa all'attività in corso (MTB, sci, escursionismo):
una soglia fissa darebbe falsi allarmi continui in MTB, oppure non vedrebbe
nulla in camminata.

### 8.3 Rilevatore di quiete

Quiete quando, su 0,5–1 s, std(\|f\|) < s_q e max ω < ω_q. Serve per il bias del
giroscopio, g_cal, la fase post-impatto e la qualità.

### 8.4 Campionamento e picchi

Un impulso di durata T contiene energia fino a frequenze dell'ordine di 1/T.
Esempio: un impulso di 20 ms campionato a 50 Hz dà un solo campione, che secondo
la fase cade ovunque tra lo zero e il picco. Quindi:

1. durante il monitoraggio si richiede la frequenza più alta disponibile fino
   a 200 Hz, e si misura quella reale;
2. la severità si basa soprattutto su **Δv** e durata, grandezze integrali e più
   robuste; il picco è un indizio;
3. la saturazione viene marcata: il picco diventa un limite inferiore e la
   confidenza scende.

### 8.5 Buffer circolare

Pre-evento 5 s + post-evento T_post, per accelerometro e giroscopio.
Dimensione: 15 s × 200 Hz × 7 valori (t + 6 assi) × 8 byte ≈ 168 kB.
Si salva per intero nel DB insieme all'evento.

---

## 9. Caduta del telefono e impatto pericoloso

### 9.1 Caduta libera

- Ideale: \|f\| ≈ 0 e T_ff = √(2h/g). Esempi: 0,39 s per 0,75 m (tavolo),
  0,45 s per 1 m. Relazione fisica **verificabile** in sicurezza (§14.2).
- Con rotazione, \|f\| ≈ \|ω × (ω × r) + α × r\|: si accetta la caduta libera
  quando \|f\| < f_ff(ω), una soglia che **cresce con ω²** perché il termine
  centripeto vale ω² r. r non è noto: si prende un limite superiore
  r_max (provvisorio 8 cm, dimensione massima di un telefono) e lo si raffina
  con i dati.
- Un telefono **lanciato** è in caduta libera durante il volo, come uno caduto.

### 9.2 Impatto

Picco \|a\| (marcando la saturazione), \|ĵ\| massimo, durata dell'impatto,
**Δv = ∫ a dt** (vettore, la grandezza fisica principale), energia nella banda
alta, rotazione durante l'urto.

Riferimento cinematico: velocità d'impatto v = √(2gh), cioè 3,8 m/s per 0,75 m.
Per una caduta libera seguita da un arresto, \|Δv\| ≈ v·(1 + e), dove e è il
coefficiente di restituzione.

### 9.3 Post-impatto

- **Rimbalzi**: un oggetto libero rimbalza con voli balistici; ogni volo dura
  t_b,k = 2 v_k / g con v_{k+1} = e·v_k. Quindi si osservano impatti successivi
  a **intervalli decrescenti in progressione geometrica**, con una caduta
  libera tra l'uno e l'altro. È una firma del **telefono libero**, non vincolato
  al corpo.
- **Assestamento**: tempo fino alla quiete.
- **Orientamento finale**: un telefono a riposo su una superficie ha la
  gravità quasi allineata a ±z_B (schermo in su o in giù).
- **Movimento successivo**: se riprende un moto "umano" (passi, raccolta), c'è
  ripresa dell'attività.
- L'immobilità **non** è prova di nulla: un telefono caduto da solo resta
  immobile esattamente come uno in tasca di una persona immobile. È un indizio,
  non una prova.

### 9.4 Indizi discriminanti (ipotesi da validare)

| Indizio | Telefono libero (caduto, lanciato) | Telefono addosso a una persona che cade |
|---|---|---|
| Caduta libera | Pulita (\|f\| ≈ 0 a meno del termine di rotazione), durata = √(2h/g) | Attesa **parziale** (il corpo non è in caduta libera pura): da misurare |
| Fase pre-impatto | Breve, coerente con h | Attesa più lunga e graduale: da misurare |
| Impatto | Superficie rigida: picco alto e breve, spesso saturo | Mediato dal corpo: atteso meno brusco e più lungo, da misurare |
| Rimbalzi | Frequenti, con intervalli in progressione geometrica | Attesi assenti o attenuati |
| Orientamento finale | Spesso ±z_B allineato alla gravità | Dipende dalla tasca |
| Rotazione | Spesso tumbling continuo | Rotazione del corpo (~90° complessivi) |

**Limite fisico (specifica §8.5).** Un telefono che scivola fuori dalla tasca
**durante** la caduta della persona produce una sovrapposizione di entrambe le
firme. Una caduta di persona su superficie rigida con il telefono in mano può
somigliare a un telefono lasciato cadere. In queste regioni la classificazione
**non è possibile** e il risultato è "evento incerto". Il sistema non deve
inventare una separazione: quando i punteggi delle categorie sono vicini
(margine sotto δ) o la qualità è bassa, l'uscita è "incerto".

### 9.5 Categorie

| Categoria | Firma principale (ipotesi) |
|---|---|
| Caduta accidentale dello smartphone | Caduta libera pulita, impatto rigido, rimbalzi geometrici, assestamento piano |
| Telefono urtato | Impatto senza caduta libera precedente, Δv piccola, nessun cambio di postura |
| Telefono manipolato | Rotazioni moderate, Δv piccola, nessun impatto, nessuna caduta libera |
| Impatto durante movimento | Impatto con attività in corso prima e dopo (passo, veicolo) |
| Possibile caduta della persona | Caduta parziale o assente, impatto mediato, cambio di postura, nessun rimbalzo, quiete o movimento ridotto dopo |
| Evento potenzialmente pericoloso | Δv alta e indizi concordi, categoria non separabile |
| Evento incerto | Margine tra le categorie insufficiente, oppure qualità bassa |

---

## 10. GPS

### 10.1 API

- `LocationManager` (`GPS_PROVIDER`), oppure il Fused Location Provider se sono
  presenti i servizi Google (scelta da verificare).
- Velocità: `getSpeed()` (Doppler, molto migliore della derivata della
  posizione), `getSpeedAccuracyMetersPerSecond()` (API 26+),
  `getAccuracy()`, `getBearingAccuracyDegrees()`.
- Timestamp: `getElapsedRealtimeNanos()`, sullo **stesso orologio** dei sensori.
  Allineamento diretto, nessun uso dell'ora di sistema.
- Frequenza tipica 1 Hz, con latenza, perdite in gallerie e interni, multipath.

### 10.2 Accelerazione GPS

a_GPS = (v_k − v_{k−1}) / (t_k − t_{k−1}). Rumore: σ_a ≈ √(σ²_{v,k} + σ²_{v,k−1})
/ Δt. Esempio illustrativo: σ_v = 0,5 m/s a 1 Hz dà ≈ 0,7 m/s². Con questo
rumore il GPS vede le frenate prolungate ma **non gli urti** (troppo brevi):
conferma, non rileva.

### 10.3 Qualità GPS

Un campione è valido se è recente (< 2 s), con `speedAccuracy` sotto soglia e
continuità (nessun salto di velocità fisicamente impossibile). Sui salti si
applica il filtro **mediano** (§7.1). Se il GPS manca, il sistema continua senza
il suo indizio.

### 10.4 Fusione con l'IMU (opzionale)

Filtro di Kalman 1D sulla velocità longitudinale (solo con direzione di marcia
nota, §5.3):

- predizione con a_long dall'IMU;
- correzione con v_GPS e varianza σ²_v da `speedAccuracy`.

Confronto per evento: Δv_IMU,orizzontale contro Δv_GPS nella stessa finestra.
Concordanza di segno e ordine di grandezza = coerenza tra i sensori (§11.4).

---

## 11. Motore di classificazione

### 11.1 Approcci a confronto

| | A. Regole fisiche e statistiche | B. Classificatore addestrato |
|---|---|---|
| Dati necessari | Nessuno per partire; dati reali per calibrare le soglie | **Molti eventi reali etichettati**, per categoria e per soggetto |
| Interpretabilità | Totale: ogni decisione ha una formula | Media (alberi) o bassa (reti) |
| Generalizzazione a nuovi telefoni e posizioni | Prevedibile (fisica) | Rischio di sovradattamento al dispositivo e alla posizione di raccolta |
| Probabilità calibrate | No: sono punteggi | Sì, dopo la calibrazione (Platt/isotonica) su un set di validazione |
| Verificabile oggi | Sì (simulatore + test) | **No**: non esistono dati etichettati |

Addestrare B sul simulatore significherebbe imparare il simulatore, non il
mondo reale. Addestrarlo su dati inventati è escluso dalla specifica.

**Scelta: architettura ibrida a due stadi.**

1. **Oggi: A**, con estrazione delle caratteristiche separata dalla decisione.
2. **Dopo la raccolta dati (§14.3): B** sulle **stesse caratteristiche**, con
   Gradient Boosting o Random Forest (adatti a poche centinaia di eventi e a
   caratteristiche tabellari, con importanza delle variabili ispezionabile).
   I modelli temporali (CNN 1D, LSTM) solo con dataset molto più grandi.
   B sostituisce A solo se lo **supera sul set di test**, con intervalli di
   confidenza, e la regola fisica resta come vincolo di sicurezza.

### 11.2 Caratteristiche dell'evento

x = [ \|Δv\|, Δv_v, \|Δv_h\|, picco \|a\|, saturazione, picco \|ĵ\|, durata, T_ff,
\|f\|_min nella caduta, picco ω, picco \|α\|, ∫ω dt, cambio di orientamento,
numero di rimbalzi, regolarità geometrica dei rimbalzi, tempo di assestamento,
orientamento finale, quiete_post, attività prima e dopo, energia per banda,
Δv_GPS, coerenza IMU–GPS, Q ]

### 11.3 Asse 1: anomalia statistica

Distanza di Mahalanobis robusta rispetto agli eventi **normali dello stesso
contesto**:

D² = (x − μ)ᵀ Σ⁻¹ (x − μ),

con μ e Σ stimati con MCD o shrinkage. Sotto ipotesi gaussiana D² seguirebbe una
χ²_k; poiché le code reali sono pesanti, il quantile si **ricalibra
empiricamente** sui dati normali per ottenere il tasso di falsi allarmi per ora
scelto. Finché non ci sono dati normali, l'asse 1 usa i punteggi robusti z del
§8.2.

### 11.4 Asse 2: severità fisica

Ogni indizio viene trasformato in [0, 1] con una logistica
φ(x) = 1 / (1 + e^{−(x − x₀)/s}), continua, quindi senza salti tra "sotto" e
"sopra" soglia. x₀ ha un **significato fisico dichiarato**:

| Indizio | Grandezza | Ancoraggio (provvisorio) |
|---|---|---|
| Urto | \|Δv\| | Velocità d'impatto equivalente √(2gh): 3,1 m/s (0,5 m), 4,4 m/s (1 m) |
| Caduta | T_ff | Altezza equivalente ½ g T_ff² |
| Postura | cambio di orientamento | ~90° (verticale → orizzontale) |
| Inattività | quiete_post | Secondi di quiete dopo l'urto |
| Coerenza | IMU contro GPS | Accordo di segno e ordine di grandezza |

S = 1 − Π(1 − w_i φ_i) ("OR morbida") e n_c = numero di indizi **indipendenti**
concordi.

### 11.5 Categoria, livello, incertezza

1. Punteggi di categoria s_c(x) con le regole della tabella del §9.5, ciascuno
   composto da logistiche.
2. Se il margine tra la prima e la seconda categoria è sotto δ, oppure se
   Q < Q_min, la categoria è **"Evento incerto"**.
3. Livello:

| Livello | Struttura (valori da calibrare) |
|---|---|
| 0 Movimento normale | D² sotto il quantile |
| 1 Anomalia lieve | D² sopra il quantile, S bassa |
| 2 Accelerazione intensa | Indizio d'urto alto, n_c ≤ 1 |
| 3 Potenzialmente pericoloso | Indizio d'urto alto **e** almeno un altro indizio concorde |
| 4 Estremamente anomalo | Livello 3 con valori estremi (saturazione, Δv molto alta) e n_c ≥ 3, confermato dopo T_post |

La classificazione avviene **in due tempi**: un livello provvisorio entro
~0,5 s dalla fine dell'urto, poi la conferma dopo T_post (servono rimbalzi,
assestamento e quiete). Con isteresi e refrattarietà, un episodio produce un
solo evento.

### 11.6 Qualità e confidenza

**Qualità** Q = q_rate · q_buchi · q_saturazione · q_orientamento · q_bias ·
q_timing:

- q_rate = min(1, f_misurata/f_richiesta);
- q_buchi = 1 − frazione di intervalli > 3 periodi;
- q_saturazione = 0,5 se un asse ha toccato il 98% del fondo scala;
- q_orientamento = dipende da σ_θ (§4.3);
- q_bias = 0,5 finché b̂_ω non è stato stimato;
- q_timing = 0,5 con tempi di ricezione invece di timestamp hardware (es. dati
  dalla SensorTile).

**Confidenza** C = Q · E, con E che cresce con n_c e con il margine di
categoria.

**C è un punteggio, non una probabilità.** Diventerà una probabilità solo dopo
la calibrazione su un set di validazione (diagramma di affidabilità, Expected
Calibration Error). La UI la mostra come "indice di confidenza", senza
percentuali di accuratezza.

---

## 12. Allarme, conto alla rovescia, SMS

### 12.1 Quando scatta (decisione da confermare, §16)

Proposta: allarme per **livello ≥ 3**, comprese le categorie "Possibile caduta
della persona", "Evento potenzialmente pericoloso" ed "Evento incerto".
L'allarme non scatta per "Caduta accidentale dello smartphone" e
"Telefono manipolato" solo se identificate con confidenza alta.

Motivazione: l'allarme è annullabile, mentre l'SMS parte solo dopo 60 s senza
risposta. Un falso allarme sonoro costa poco; un'emergenza mancata costa molto.
Il tasso di falsi allarmi va comunque misurato (§14.3).

### 12.2 Macchina a stati (persistita nel DB, con un ID per evento)

```
IDLE → DETECTED → ALARMING (0–30 s, suono) → COUNTDOWN (30–60 s, silenzioso)
     → SENDING → SENT | FAILED(retry) | UNKNOWN
Ogni stato da DETECTED a COUNTDOWN → CANCELLED (pulsante annulla)
```

- Il conto alla rovescia dura **60 s dal rilevamento**, l'allarme sonoro
  **30 s**: dai 30 ai 60 s c'è solo il conto alla rovescia visibile (e la
  vibrazione, se scelta).
- Il tempo si misura con `SystemClock.elapsedRealtime()`, che è monotono e non
  cambia se l'utente modifica l'ora di sistema.
- Il timer gira nel **servizio nativo**, non solo in Dart (§15.3): se il motore
  Flutter muore, il servizio prosegue e invia comunque. Lo stato persistito
  permette di riprendere dopo un riavvio del processo.

### 12.3 Suono

- `AudioAttributes.USAGE_ALARM`, cioè lo stream degli allarmi, indipendente dal
  volume dei media.
- Si richiede il massimo con `AudioManager.setStreamVolume(STREAM_ALARM, max)`,
  e al termine si ripristina il volume precedente. Non serve l'accesso alla
  modalità Non disturbare (l'eccezione di sicurezza riguarda gli stream di
  suoneria e notifiche): da verificare sul dispositivo.
- I controlli di Android restano attivi: l'utente può abbassare il volume o
  fermare l'allarme. La documentazione **non** dichiarerà il contrario.
- Suono: un file proprio, tono acuto a impulsi. Vibrazione in parallelo con
  `Vibrator`/`VibratorManager`.

### 12.4 Interfaccia di allarme

Schermata dedicata con conto alla rovescia, grande pulsante "Sto bene, annulla"
e categoria e livello rilevati. Per farla comparire anche a telefono bloccato:

- notifica con `fullScreenIntent` e Activity con `setShowWhenLocked(true)` e
  `setTurnScreenOn(true)`;
- da Android 14, `USE_FULL_SCREEN_INTENT` è concesso automaticamente solo alle
  app di chiamata e sveglia. Per DYNAMIX va probabilmente **chiesto all'utente**
  nelle impostazioni di sistema (da verificare). Senza il permesso resta una
  notifica ad alta priorità con suono.

Annullamento accidentale: pressione prolungata (~1 s) o scorrimento, per
evitare tocchi involontari in tasca. Da confermare (§16).

### 12.5 Contatto di emergenza

Impostazioni → "Emergency Contact":

- nome, numero, interruttore di attivazione;
- **verifica del numero**: normalizzazione E.164 (prefisso predefinito +39) e
  controllo di validità con una libreria telefonica (es. `phone_numbers_parser`,
  da valutare). Questo verifica il **formato**, non che il numero appartenga al
  contatto: la conferma vera è il test d'invio;
- **blocco dei numeri di emergenza** (112, 113, 115, 118 e brevi simili): un SMS
  automatico ai servizi di emergenza non è appropriato. Il servizio SMS del 112
  in Italia è un canale dedicato;
- **test dell'invio**: un SMS di prova con testo che dichiara esplicitamente il
  test, inviato **solo dopo una conferma esplicita** a ogni prova;
- stato mostrato in dashboard: configurato / non configurato / permesso SMS
  mancante / ultimo test riuscito.

### 12.6 Invio SMS

- `SmsManager.sendMultipartTextMessage` dopo `divideMessage`. Con caratteri non
  GSM‑7 (es. nomi accentati) il limite scende da 160 a 70 caratteri per parte.
- Dual SIM: `SmsManager` della SIM SMS predefinita (`SubscriptionManager`).
- Esito: `PendingIntent` di invio (`RESULT_OK`, `NO_SERVICE`, `RADIO_OFF`,
  `GENERIC_FAILURE`…) e di consegna, registrati nel DB.
- Assenza di rete: l'SMS usa la rete cellulare, non internet. Con
  `NO_SERVICE` o `RADIO_OFF` si ritenta con backoff (provvisorio 30 s, 1 min,
  2 min, 5 min) finché il servizio non torna, entro un limite di tempo.
- **Duplicati**: chiave di idempotenza = ID evento, e lo stato `SENT` blocca
  ogni reinvio. Se il processo muore durante `SENDING` l'esito è `UNKNOWN`.
  Proposta: **un solo** reinvio marcato "(ripetizione)", perché un SMS duplicato
  costa meno di un'allerta persa. Da confermare (§16).
- Testo (dalla specifica):
  "DYNAMIX: ALLERTA! [NOME] [COGNOME] ha ricevuto una botta forte e non ha
  disattivato l'allarme."
  Nota: il sistema rileva un *evento probabile*, non una certezza. Si può
  valutare una formulazione come "potrebbe aver ricevuto" (§16).
- Posizione GPS: prevista come opzione **futura** e disattivata di default,
  attivabile solo con consenso esplicito.

### 12.7 Permessi e limiti Android

- `SEND_SMS` è un permesso pericoloso, richiesto a runtime **solo** quando si
  attiva il contatto.
- **Google Play**: i permessi SMS sono soggetti a restrizioni e concessi solo
  per usi dichiarati e approvati. Oggi l'app è distribuita come APK e non è un
  problema immediato, ma per una pubblicazione su Play va verificata la policy
  (§17). L'alternativa conforme, `ACTION_SENDTO`, apre l'app SMS ma richiede un
  tocco dell'utente: non è automatica.
- Le restrizioni non vengono aggirate.

### 12.8 Test sicuri

`SmsSender` è un'interfaccia: nei test e nel simulatore si usa sempre
`FakeSmsSender`, che registra i messaggi e non invia nulla. Il `DryRun` è attivo
di default in modalità diagnostica/simulazione. L'invio reale avviene solo dal
pulsante di test con conferma, oppure da un evento reale con funzione attivata.

---

## 13. Registrazione utente, privacy, sicurezza

### 13.1 Profilo locale

- Nessun account online: l'architettura è interamente locale.
- Al primo avvio, finché il profilo non esiste, si apre la schermata di
  registrazione invece della dashboard. Contiene: logo, titolo, descrizione,
  Nome, Cognome, Età, "Registrati".
- Validazione:
  - Nome e Cognome: spazi iniziali e finali rimossi, 1–50 caratteri, lettere
    Unicode (accenti inclusi), spazi, apostrofi e trattini;
  - Età: intero tra 1 e 120 (intervallo da confermare);
  - pulsante attivo solo con tutti i campi validi e messaggi d'errore per
    campo.
- Modifica e **cancellazione del profilo** dalle impostazioni. La cancellazione
  elimina il profilo e il contatto; la cancellazione delle sessioni registrate
  è facoltativa e richiede una conferma separata.

### 13.2 Archiviazione protetta

Profilo e contatto vanno in uno storage cifrato con chiave nell'**Android
Keystore** (es. `flutter_secure_storage`), non nelle `SharedPreferences` in
chiaro. Il DB delle sessioni resta in SQLite nella memoria privata dell'app.
Backup automatico di Android: da escludere per i dati del profilo
(`allowBackup`/`dataExtractionRules`), da decidere.

### 13.3 Minimizzazione e GDPR

- Solo i dati richiesti (nome, cognome, età, contatto). Età e non data di
  nascita, come da specifica.
- Nessuna trasmissione: l'unica uscita di dati è l'SMS al contatto, attivato
  dall'utente.
- GPS: disattivato di default e attivato con consenso esplicito. La posizione
  non viene inviata finché la funzione futura non viene attivata.
- Informativa in-app su cosa si raccoglie, dove resta e come si cancella.
- **Da verificare con un esperto**, perché non è una consulenza legale:
  - se i dati di movimento e di caduta siano dati relativi alla salute
    (categoria particolare, art. 9 GDPR);
  - l'applicabilità dell'esenzione per uso personale (art. 2);
  - il trattamento del numero del contatto (dato di un terzo);
  - l'età minima per il consenso digitale (14 anni in Italia), se l'app è
    destinata anche a minori.

---

## 14. Simulazione e validazione

### 14.1 Simulatore fisico

Generatore deterministico (con seed) di traiettoria, orientamento e
interazioni. Applica l'equazione di misura del §3.2 con bias, scala, rumore,
quantizzazione, saturazione, timestamp con jitter e buchi, e GPS a 1 Hz con
rumore e perdite.

Modelli per scenario: urto come impulso a semiseno con durata e Δv parametrici;
rimbalzi con coefficiente di restituzione e; caduta della persona come pendolo
inverso (modello semplificato, dichiarato tale).

I 15 scenari della specifica (fermo, tasca camminando, corsa, mano, tavolo,
tasca, urto, superficie morbida, persona che cade, frenata, accelerazione,
vibrazioni, rotazione, impatto + immobilità, GPS disturbato) diventano file di
parametri. Per ognuno si registrano: accelerazione e G massimi, jerk massimo,
durata, velocità angolare, categoria prevista, confidenza e tempo di
rilevamento. Più seed per scenario (Monte Carlo).

**La simulazione verifica il codice e la matematica, non il mondo reale.** Le
metriche calcolate sul simulatore saranno etichettate "simulazione".

### 14.2 Caratterizzazione del dispositivo (reale)

- 10 min da fermo: rumore per asse, bias, **varianza di Allan** di
  accelerometro e giroscopio, g_cal.
- 6 posizioni statiche: offset e scala.
- Frequenza effettiva e jitter a 50, 100 e 200 Hz.
- **Caduta su cuscino** da altezze misurate (0,3 / 0,5 / 0,75 / 1 m): confronto
  di T_ff con √(2h/g) e di Δv con √(2gh). Rotazioni a mano: verifica dell'assenza
  di falsa accelerazione.

### 14.3 Dataset reale e metriche

- Raccolta etichettata di attività normali (ore di uso quotidiano, camminata,
  corsa, veicolo, MTB, sci, escursionismo) e di eventi controllati sicuri
  (cadute del telefono, urti, lanci su superficie morbida).
- **Nessuna caduta di persone provocata.** Per le cadute umane solo dataset
  pubblici citati, con il limite dichiarato della diversa posizione del sensore.
- Separazione **per soggetto e per sessione**, non per finestra: le finestre
  sovrapposte della stessa registrazione contaminerebbero training e test.
  Tre insiemi: addestramento, validazione (calibrazione di soglie e
  probabilità), test (usato una volta sola).
- Metriche: precisione TP/(TP+FP), recall TP/(TP+FN), F1, matrice di
  confusione per categoria, accuratezza per categoria, **falsi allarmi per ora**
  di uso normale, tempo di rilevamento (mediana e 95° percentile). Sempre con
  **intervalli di confidenza** (Wilson/Clopper–Pearson): con pochi eventi un
  valore puntuale sarebbe fuorviante.

---

## 15. Architettura software e Android

### 15.1 Moduli (nomi della specifica → posizione proposta)

| Modulo | Linguaggio | Posizione proposta |
|---|---|---|
| UserRegistration | Dart | `lib/profile/` |
| SensorManager (acquisizione, elenco sensori) | **Kotlin** + Dart | `android/.../sensing/`, `lib/sensing/acquisition/` |
| SensorDataProcessor (allineamento, buchi, saturazione) | Dart | `lib/sensing/preprocess/` |
| GravityCompensation + MotionEstimator | Dart | `lib/sensing/estimation/` |
| SignalFiltering | Dart | `lib/sensing/filters/` |
| JerkAnalyzer | Dart | `lib/sensing/estimation/` |
| ImpactDetector, FallDetection | Dart | `lib/sensing/events/` |
| DangerClassifier | Dart | `lib/sensing/classify/` |
| GPSAnalyzer | Kotlin (acquisizione) + Dart | `lib/sensing/gps/` |
| EmergencyAlertManager | **Kotlin** (suono, timer, schermata bloccata) + Dart (UI) | `android/.../alert/`, `lib/alert/` |
| EmergencyContactManager | Dart + Kotlin (SMS) | `lib/contact/`, `android/.../sms/` |
| DiagnosticsDashboard | Dart | `lib/ui/screens/detection_*` |
| SimulationEngine | Dart | `lib/sensing/simulation/` + `test/` |
| DataLogger | Dart | `lib/data/` (estende lo store esistente) |

La matematica (estimation, filters, events, classify) è in **Dart puro**, senza
Flutter, così è testabile con `flutter test`, riproducibile sui dati registrati
e condivisa con il percorso SensorTile. Interfaccia unica:
`DetectionEngine.ingest(MotionSample) → DetectionState`.

### 15.2 Acquisizione

`MotionSample { tNs (hardware), tipo, x, y, z, accuratezza }` da:

- **PhoneMotionSource** (Kotlin): `registerListener(..., periodUs,
  maxReportLatencyUs)` su un `HandlerThread` dedicato, consegna a blocchi
  tramite EventChannel;
- **BlueStMotionAdapter**: dati della SensorTile, con q_timing ridotta;
- **ReplaySource** (sessioni registrate) e **SimulatorSource**.

Il percorso BlueST esistente (grafici, registrazione, export) **non cambia**.

### 15.3 Esecuzione in background

| Vincolo | Conseguenza / proposta |
|---|---|
| P10: motore Dart legato all'Activity | Motore Flutter **posseduto dal servizio** (engine in cache e avviato dal servizio), che l'Activity riusa. Così il rilevamento sopravvive alla chiusura dell'Activity. Da verificare sperimentalmente |
| Sensori in background | Da Android 9 un'app in background non riceve i sensori continui: serve un servizio in primo piano per tutto il monitoraggio |
| Android 14+: tipo di servizio obbligatorio | `connectedDevice` presuppone un dispositivo collegato. Per i soli sensori del telefono il candidato è `health` (richiede uno tra `ACTIVITY_RECOGNITION`, `BODY_SENSORS`, `HIGH_SAMPLING_RATE_SENSORS`); con il GPS si aggiunge `location`. **Da verificare** |
| Ottimizzazione batteria, Doze, produttori aggressivi | Possibile richiesta di esenzione dall'ottimizzazione, spiegata all'utente. **Nessuna promessa** di funzionamento garantito in background |
| Recupero | Watchdog nel servizio: se il flusso dei campioni si ferma per più di X s, riavvia l'acquisizione, registra l'interruzione e la mostra in dashboard ("monitoraggio interrotto alle …") |
| Allarme e timer | Nel servizio nativo, con stato persistito (§12.2) |

### 15.4 Thread, memoria, batteria

- Acquisizione su un thread nativo dedicato. Calcolo O(1) per campione: il
  filtro richiede decine di operazioni, il jerk O(N) con N piccolo.
- Buffer circolari a dimensione fissa (§8.5); nessuna allocazione per campione
  (array tipizzati, come `ChannelBuffer`).
- Batteria: il costo dominante previsto è il **passaggio dei campioni** dal
  nativo a Dart e i risvegli della CPU, non la matematica. Si riduce con il
  batching FIFO e la consegna a blocchi. Frequenze configurabili 50/100/200 Hz.
  Il consumo si **misura** (`dumpsys batterystats`, Battery Historian, tempo di
  CPU per campione) e non si stima a parole.

### 15.5 Database (migrazione `sqflite` con `onUpgrade`)

```sql
ALTER TABLE samples ADD COLUMN t_ns INTEGER;          -- timestamp hardware, NULL per i dati storici

CREATE TABLE detection_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
  t_start_ns INTEGER NOT NULL, t_end_ns INTEGER NOT NULL,
  algo_version TEXT NOT NULL, params TEXT NOT NULL,    -- JSON
  level_provisional INTEGER NOT NULL, level_final INTEGER,
  category TEXT NOT NULL, confidence REAL NOT NULL, quality REAL NOT NULL,
  features TEXT NOT NULL,                              -- JSON delle caratteristiche
  label TEXT                                           -- etichetta manuale per il dataset (§14.3)
);

CREATE TABLE alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id INTEGER NOT NULL UNIQUE REFERENCES detection_events(id),
  state TEXT NOT NULL,                                 -- §12.2
  detected_at_ms INTEGER NOT NULL, cancelled_at_ms INTEGER,
  sms_attempts INTEGER NOT NULL DEFAULT 0, sms_result TEXT, sms_error TEXT,
  dry_run INTEGER NOT NULL
);
```

Profilo e contatto **non** vanno nel DB, ma nello storage cifrato (§13.2).
I dati grezzi dell'evento vanno in `samples` (sessione automatica "evento").

### 15.6 Interfaccia

- **Dashboard** (evoluzione della home attuale, senza valori tecnici):
  - stato DYNAMIX e del monitoraggio;
  - livello di rischio attuale;
  - sensori (OK / mancanti / degradati);
  - ultimo evento;
  - stato del contatto;
  - accessi a diagnostica e impostazioni.
- **Diagnostica "Rilevamento"**: f e a per asse, \|a\|, G grezzo e filtrato,
  jerk grezzo e filtrato, ω per asse e modulo, α, frequenza e jitter per
  sensore, Q con i singoli fattori, GPS (velocità, precisione, età del dato),
  livello, categoria, confidenza. Grafici temporali (riuso di `charts.dart`) con
  le soglie provvisorie disegnate e marcate. Registrazione ed export tramite
  l'export esistente, con le nuove colonne.

---

## 16. Decisioni che spettano a te

1. **Nome**: rinominare l'app da "DinamiX" a "DYNAMIX", e con quale logo?
2. **Livelli che fanno scattare l'allarme**: proposta ≥ 3, incerto compreso
   (§12.1).
3. **Annullamento**: tocco semplice, oppure pressione prolungata o
   scorrimento contro i tocchi involontari (§12.4).
4. **Esito `UNKNOWN` dell'SMS**: un reinvio marcato o nessuno (§12.6).
5. **Testo dell'SMS**: quello della specifica, oppure una formulazione che
   esprima l'incertezza (§12.6).
6. **Intervallo dell'età** ammesso e destinazione anche a minori (§13).
7. **GPS**: attivarlo già nella prima versione (permesso di posizione, consumo)
   o in un secondo momento.
8. **Distribuzione**: solo APK, oppure anche Google Play, che cambia i vincoli
   sugli SMS (§12.7).

---

## 17. Punti aperti e piano delle fasi successive

### 17.1 Da validare sperimentalmente

1. τ, σ_f, σ_ω del filtro di orientamento.
2. Finestra del jerk alla frequenza reale.
3. Frequenze di taglio delle bande.
4. Firme della caduta del telefono rispetto alla caduta della persona (§9.4):
   l'**ipotesi più debole** del progetto.
5. f_ff(ω) e r_max; z_on, z_off, T_post, δ; ancoraggi delle logistiche; pesi.
6. Stima di longitudinale e laterale (probabilmente non affidabile a telefono
   libero).
7. Frequenza effettiva e saturazione sul dispositivo.
8. Tipo di servizio in primo piano su Android 14+ e sopravvivenza del motore
   Flutter nel servizio.
9. Volume dell'allarme con la modalità Non disturbare e `USE_FULL_SCREEN_INTENT`.
10. Consumo energetico reale.
11. Calibrazione della confidenza.
12. Policy di Google Play sugli SMS e verifica GDPR.

### 17.2 Piano

- **FASE B (progettazione di dettaglio)**: interfacce Dart e Kotlin, formati
  degli eventi, schermate (wireframe), schema del DB definitivo, parametri del
  simulatore, piano di test. Si parte dopo le tue risposte al §16.
- **FASE C (implementazione progressiva)**, ogni passo testato a sé:
  1. registrazione e profilo cifrato;
  2. acquisizione Kotlin con timestamp e metadati;
  3. orientamento, a, jerk, α, con test analitici;
  4. simulatore e scenari;
  5. eventi e classificazione con soglie provvisorie;
  6. diagnostica;
  7. dashboard;
  8. allarme e servizio;
  9. contatto ed SMS (con `DryRun`).
- **FASE D (validazione)**: test automatici, metriche sul simulatore (marcate
  come tali), caratterizzazione del dispositivo, raccolta dati reali,
  calibrazione, consumi. Rapporto con risultati, errori e limiti.

DYNAMIX **non sarà dichiarato pronto per la sicurezza personale** senza una
validazione reale sufficiente e documentata.


---

# Parte II — QA, design, distribuzione (sezioni 21–27 della specifica)

## 18. Quality assurance: cosa si può verificare, dove e come

### 18.1 Ambienti disponibili (verificati, non presunti)

| Ambiente | Cosa permette | Cosa **non** permette |
|---|---|---|
| Container di sviluppo (questa sessione) | `flutter analyze`, unit e widget test, golden/screenshot, build Android dopo l'installazione dell'SDK | **Nessun emulatore**: `/dev/kvm` assente, e senza accelerazione l'emulatore non è utilizzabile. Nessun dispositivo reale |
| GitHub Actions (runner Linux) | Build release, Android Lint, test, e un **emulatore con KVM** per i test di strumentazione, se KVM è disponibile sul runner del repository (**da verificare** con una run di prova) | Dispositivi reali, sensori reali |
| Dispositivo reale (tuo) | L'unica verifica di sensori veri, suono, SMS reale, batteria e comportamento del produttore in background | Automazione completa |

Conseguenza: i punti 3–10 della procedura di verifica dell'APK della specifica
(installazione su **dispositivo reale**, registrazione, sensori, simulazione,
ciclo di vita) **non posso eseguirli io**. Li coprirò in due modi:

1. automatizzati su **emulatore in CI** (dove l'emulatore lo consente);
2. un **protocollo manuale** per il telefono reale (§18.5), con un log dei
   crash esportabile dall'app per riportarmi i problemi.

Il rapporto finale distinguerà sempre "verificato su emulatore API x",
"verificato su dispositivo y" e "non verificato".

### 18.2 Livelli di test

| Livello | Strumento | Copertura |
|---|---|---|
| Unit | `flutter test` | Matematica (orientamento con rotazioni note, caduta libera analitica, jerk su rampe e parabole, Δv), validazione del profilo, macchina a stati dell'allarme, idempotenza SMS (con `FakeSmsSender`), migrazioni del DB |
| Widget / UI | `flutter test` + golden | Ogni schermata, inclusi stati di errore, caricamento e vuoti; testo grande (scala 2,0); modalità chiara e scura; animazioni ridotte |
| Integration | `integration_test` su emulatore | Primo avvio → registrazione → dashboard; monitoraggio con sensori iniettati; allarme → annulla; allarme → 60 s → invio con `DryRun` |
| Instrumentation (Android) | JUnit + AndroidX Test (Kotlin) | Servizio in primo piano, acquisizione, timer nativo, `SmsManager` (sull'emulatore l'invio è locale), audio |
| Ciclo di vita | `adb` | Rotazione (`settings put system user_rotation`), background/foreground (`input keyevent HOME`), terminazione del processo (`am kill`) e riapertura, `am force-stop`, permessi revocati (`pm revoke`) durante l'uso, modalità aereo |
| Carico | Simulatore + `ReplaySource` | Motore a 200 Hz accelerati (×10–×100): tempo per campione, nessuna crescita di memoria |
| Prolungato | Emulatore in CI | Monitoraggio di 1–4 h (limite del job CI): `dumpsys meminfo` periodico, conteggio campioni persi, log |
| Stress UI | `adb shell monkey` | Eventi casuali con seed fisso, zero crash ammessi |
| Gestione errori | Unit + integration | Sensore mancante, GPS assente, permesso SMS negato, DB pieno, storage cifrato non leggibile |
| Statica | `flutter analyze`, **Android Lint** (`gradlew lint`) | Avvisi trattati come errori nella CI, con eccezioni documentate |

Sensori sull'emulatore: `adb emu sensor set acceleration x:y:z` e
`adb emu geo fix` permettono di **iniettare** valori. Verificano il percorso
dei dati, non il realismo del segnale (che resta compito del simulatore e dei
dati reali).

### 18.3 Crash e problemi da cercare (dove e come)

| Categoria | Verifica |
|---|---|
| Avvio, riapertura, rotazione, background | Test del ciclo di vita (§18.2). Logcat filtrato per `FATAL EXCEPTION`, `ANR`, `E/flutter` e salvato come artefatto della CI |
| Registrazione | Widget test con input limite (vuoto, solo spazi, 51 caratteri, emoji, età 0/121/"abc") |
| Sensori e monitoraggio prolungato | Test prolungato; watchdog del flusso; campioni persi contati |
| Permessi negati | Ogni permesso negato e revocato durante l'uso: l'app degrada e non crasha |
| GPS, allarme, SMS | Instrumentation su emulatore e protocollo manuale |
| Memoria e leak | `dumpsys meminfo` nel tempo; in Dart, controllo delle sottoscrizioni chiuse (`StreamSubscription`, `Timer`, `AnimationController`) con test di dispose |
| Thread bloccati e ANR | Nessun I/O sul thread UI nativo; StrictMode attivo nelle build di debug |
| Sincronizzazione | Un solo proprietario per lo stato dell'allarme (il servizio). Dart lo osserva e non lo duplica |
| Eccezioni non gestite | `FlutterError.onError` e `PlatformDispatcher.onError` in Dart, `Thread.setDefaultUncaughtExceptionHandler` in Kotlin: tutto in un **log locale** esportabile, senza invio automatico (privacy, §13) |

Problemi già noti dal codice attuale:

- crash della schermata Sessione corretto in questo branch (chiavi duplicate
  delle animazioni);
- il test degli screenshot falliva in silenzio, corretto e ora bloccante.

### 18.4 Requisiti per considerare "verificata" una versione

1. Build release senza errori; Lint senza errori.
2. Tutti i test automatici verdi.
3. Test su emulatore verdi su almeno **API 26, 30, 34 e 36** (minimo,
   intermedi, target).
4. Protocollo manuale eseguito su **almeno un dispositivo reale**, con modello
   e versione Android annotati.
5. Rapporto con: test superati e falliti, crash trovati, correzioni, problemi
   aperti, dispositivi, hash SHA-256 dell'APK verificato.

L'app **non sarà dichiarata priva di crash**: sarà dichiarato ciò che è stato
verificato, dove e su quale APK.

### 18.5 Protocollo manuale per il dispositivo reale (bozza)

1. Installazione pulita.
2. Prima apertura e logo.
3. Registrazione con errori voluti, poi valida.
4. Dashboard: stato dei sensori.
5. Diagnostica: valori stabili da fermo (|a| vicino a 0, G vicino a 0).
6. Rotazione lenta e rapida: nessuna falsa accelerazione.
7. Simulazione dalla diagnostica.
8. Allarme di prova: suono, schermata, annulla.
9. Allarme di prova senza annullare, con `DryRun`: verificare che "invio
   simulato" compaia nello storico.
10. Contatto: verifica del formato; test d'invio **reale** solo se lo confermi.
11. Background 10 min con schermo spento, poi riapertura.
12. Chiusura dalle app recenti: il monitoraggio prosegue? (§15.3)
13. Revoca dei permessi dalle impostazioni di sistema durante l'uso.
14. Export del log e invio a me in caso di problemi.

---

## 19. Identità visiva e logo

### 19.1 Concetto

**Concetto proposto per il logo:** "vettore in movimento". La **X** di DYNAMIX
è formata da due tratti che richiamano gli assi di un sensore inerziale, uno dei
quali termina con una piccola cuspide, come una traccia di accelerazione con un
picco. Il simbolo (la sola X stilizzata dentro una forma arrotondata) diventa
l'icona.

Alternative da mostrarti come bozze prima di scegliere:

- una "D" con un'onda di segnale interna;
- un rombo prospettico che ricorda le montagne.

### 19.2 Wordmark

Wordmark costruito e non "testo scritto con un font":

- base tipografica geometrica con licenza **SIL Open Font License**,
  incorporabile e ridistribuibile anche commercialmente (candidati: Sora,
  Space Grotesk, Inter Tight; scelta dopo le bozze);
- lettere ridisegnate come **tracciati vettoriali**: X modificata, crenatura
  manuale, spessori ottici.

Il logo finale è un tracciato, quindi non dipende dal font installato.

### 19.3 Asset da produrre

- **Sorgente**: SVG vettoriale.
- **App**: `CustomPainter`/`Path` generato dall'SVG, nitido a ogni scala.
- **Versioni**: chiara, scura, monocromatica.
- **Icona Android adattiva**: primo piano e sfondo separati, più un livello
  **monocromatico** per le icone a tema di Android 13+, con raster mdpi–xxxhdpi
  generati dall'SVG.
- **Splash nativa**: con l'API SplashScreen di Android 12+, che ammette solo
  icona e sfondo.
- **Splash animata Flutter**: subito dopo quella nativa, con il logo che "si
  disegna", durata ≤ 1,2 s, e senza animazione se è attiva l'opzione di
  riduzione delle animazioni.

### 19.4 Sistema grafico (design tokens)

Un unico file di token, che evolve l'attuale `theme.dart` (che ha già
`Palette` e il tema scuro):

- **Colori**: primario, secondario, superfici a 3 livelli e stati
  (ok/attenzione/pericolo/incerto). Contrasto **WCAG AA** verificato con un test
  automatico sui token (4,5:1 per il testo).
- **Tipografia**: scala a 7 passi (display → caption), numeri tabulari per i
  valori dei sensori.
- **Spaziature**: griglia a 4 dp. Raggi 8/14/20. Ombre a 3 livelli di elevazione.
- **Movimento**: durate 120/200/320 ms con curve standard. Ogni animazione
  rispetta l'impostazione "riduci animazioni" e il flag di accessibilità del
  sistema.
- **Componenti riutilizzabili**: pulsante primario e secondario, card di stato,
  badge del livello, indicatore di confidenza, riga del sensore, finestra di
  conferma, stato vuoto, stato di errore.
- **Modalità**: scura come predefinita, chiara completa (l'app ha già entrambe
  le basi).

Verifica visiva: golden test per ogni schermata in chiaro, scuro e testo
grande. **Il giudizio estetico finale resta tuo**: ti mostrerò le bozze prima
di integrarle.

---

## 20. Scenari animati

### 20.1 Tecnologie a confronto

| Tecnologia | Pro | Contro | Verdetto |
|---|---|---|---|
| Lottie | Molto diffusa | Richiede animazioni create in After Effects da un animatore. JSON pesanti per scene complesse. Personaggi limitati a ciò che è stato animato | Solo con asset di un designer |
| Rive | State machine interattive, runtime efficiente | Gli asset si creano nell'editor Rive (strumento grafico): non posso produrli in modo affidabile da codice | Ottima se fornisci o commissioni gli asset |
| Sprite | Semplici | Pesanti in MB a più densità; movimento a scatti se i fotogrammi sono pochi | No |
| 3D | Profondità reale | Costo di GPU e batteria non giustificato in una dashboard | No |
| **Vettoriale procedurale** (`CustomPainter`, già usato da `AuroraBackground` e `MotionShield`) | Zero asset; nitido a ogni densità; livello di dettaglio regolabile; personaggi con **cinematica reale** | Stile illustrato e non fotografico | **Scelta** |

### 20.2 Scena montana (procedurale)

- **Montagne**: 4–5 livelli di profilo generati una volta sola con rumore
  frattale (spostamento del punto medio, seed fisso, quindi sempre uguali), con
  neve sulle creste sopra una quota e ombreggiatura per pendenza rispetto alla
  direzione del sole.
- **Parallasse**: ogni livello si sposta con fattore 1/profondità, guidato
  dall'inclinazione del telefono (dall'orientamento già stimato dal motore,
  fortemente smorzato) oppure da un'oscillazione lenta.
- **Cielo e luce**: gradiente che segue un ciclo lento (alba → giorno →
  tramonto in alcuni minuti, oppure l'ora reale), con il colore della neve
  coerente.
- **Nuvole**: forme a più cerchi sfumati, con deriva a velocità diverse per
  livello.
- **Neve**: particelle con caduta a velocità terminale, oscillazione laterale e
  dimensione secondo la profondità. Numero adattivo (§22).

### 20.3 Personaggi con movimento naturale

Scheletro 2D (bacino, busto, testa, braccia e gambe a 2 segmenti) disegnato a
forme piene, nello stile delle illustrazioni moderne:

- **Camminata ed escursionismo**: angoli di anca, ginocchio e caviglia come
  serie di Fourier a 2–3 armoniche del ciclo del passo, con la forma delle
  curve dalla biomeccanica del passo. Oscillazione verticale del bacino a
  frequenza doppia del passo. Bastoncini in controfase.
- **Sci**: traiettoria a curve ad "S" lungo il pendio (spline). Inclinazione del
  corpo verso l'interno della curva secondo tan(φ) = v²/(g·R), quindi fisica
  reale. Flessione-estensione delle gambe a ogni cambio di curva. Scia di neve
  sollevata.
- **Contatto col terreno**: i piedi seguono il profilo del sentiero con
  cinematica inversa a 2 segmenti, così non "pattinano".

Pochi personaggi (1–3) sullo sfondo, piccoli, che **non coprono mai**
informazioni o pulsanti.

### 20.4 Integrazione e accessibilità

- La scena sta dietro la dashboard, con un velo che garantisce il contrasto
  AA dei testi sopra.
- Si ferma fuori schermo e in background, e rispetta "riduci animazioni" con
  tre opzioni: completa / leggera / statica.
- Il livello di pericolo resta sempre l'elemento più visibile. Con un livello
  ≥ 3 la scena si ferma, perché non deve distrarre.

---

## 21. Esperienza utente e navigazione

| # | Schermata | Funzione | Stato attuale |
|---|---|---|---|
| 1 | Splash animata | Marchio e caricamento | Da creare |
| 2 | Registrazione | Profilo (§13) | Da creare |
| 3 | Introduzione guidata (3 pagine) | Cosa fa e non fa DYNAMIX, permessi spiegati prima di chiederli, limiti dichiarati | Da creare |
| 4 | Dashboard | §15.6 + scena | Evoluzione della home |
| 5 | Monitoraggio | Sessione attiva | Evoluzione di `session_screen` |
| 6 | Diagnostica sensori | §15.6 | Nuova (rilevamento) + esistente (BLE) |
| 7 | Storico eventi | Lista e dettaglio, con etichettatura manuale per il dataset | Nuova (riusa l'analisi) |
| 8 | Impostazioni | Profilo, animazioni, campionamento, privacy, cancellazione dati | Evoluzione |
| 9 | Contatto di emergenza | §12.5 | Nuova |
| 10 | Informazioni | Versione, licenze (`showLicensePage`), privacy, limiti del sistema | Nuova |
| — | Allarme | Schermata a tutto schermo (§12.4) | Nuova |

Le schermate esistenti legate alla SensorTile (dispositivi, live, logger,
analisi) restano raggiungibili dalla diagnostica.

Regole comuni:

- ogni azione dà un riscontro visibile;
- ogni operazione distruttiva chiede conferma;
- stati di caricamento, vuoto ed errore per ogni lista;
- `Semantics` sulle icone e sugli indicatori;
- target di tocco ≥ 48 dp;
- testo scalabile fino a 2× senza overflow, verificato con golden test (il
  crash di oggi era proprio un overflow nascosto);
- **nessun pulsante senza funzione**: un test elenca i pulsanti di ogni
  schermata e verifica che abbiano `onPressed`.

---

## 22. Prestazioni grafiche e separazione dal motore

- **Separazione**: acquisizione su un thread nativo con timestamp hardware e
  FIFO. Motore di rilevamento in un **motore Flutter separato**, posseduto dal
  servizio (§15.3), quindi su un thread diverso da quello della UI. Un fotogramma
  lento della UI non può né perdere né ritardare i campioni del motore.
  Test: frequenza misurata dal motore con e senza animazioni, che deve restare
  invariata entro il jitter.
- **Rendering**: profili delle montagne calcolati una volta sola e messi in
  cache, ogni livello in un `RepaintBoundary`, animazione con sole
  trasformazioni dove possibile, particelle in `drawPoints`/`drawAtlas` (una
  sola chiamata), nessuna allocazione per fotogramma.
- **Livelli di qualità automatici**: si misura il tempo dei fotogrammi nei primi
  secondi (`FrameTiming`). Se il 90° percentile supera il budget (16,7 ms a
  60 Hz), si scende di livello (meno particelle, meno livelli, nessun
  personaggio), fino a una scena statica.
- **Misure** (CI e dispositivo): tempi di fotogramma con
  `integration_test` + `traceAction` (build e raster, 90° e 99° percentile),
  CPU e memoria con `dumpsys`, GPU con `dumpsys gfxinfo`, tempo di avvio con
  `am start -W`, batteria come nel §15.4. I numeri vengono **misurati e
  riportati**, non stimati.

---

## 23. Preparazione alla distribuzione

| Punto | Situazione attuale (verificata) | Proposta |
|---|---|---|
| Nome | `android:label="DinamiX"` | "DYNAMIX", se confermi (§24). Verificare la disponibilità del nome e del marchio (non verificabile da qui) |
| Package | `com.dinamix.dinamix` (generato da `flutter create --org com.dinamix`) | Su Google Play è **immutabile** dopo la pubblicazione: scegliere ora il definitivo, possibilmente su un dominio che controlli |
| Versioning | `version: 1.0.0+1` fisso: ogni APK ha versionCode 1 | versionCode crescente automatico in CI (numero della run), versionName semantico |
| **Firma** | Release firmata con la **chiave di debug**, rigenerata a ogni run CI | Causa dell'errore "App non installata" negli aggiornamenti. Serve una **chiave di upload** creata da te, conservata nei Secrets di GitHub e mai nel repository. Per Play: Play App Signing. **Non la creo né la modifico senza la tua autorizzazione** |
| Progetto Android | La cartella `android/` viene in buona parte **rigenerata** a ogni build da `flutter create` | Committare la configurazione Android completa (gradle, firma, manifest, risorse) per una build riproducibile |
| Formato | APK universale da 55 MB | APK per ABI (`--split-per-abi`) per l'installazione diretta, **AAB** per Play |
| SDK | min 24, target 36, compile 36 (valori predefiniti di Flutter 3.47) | Matrice di test §18.4. Android 7.0 (API 24) da mantenere solo se il test lo conferma |
| Permessi | BLE, servizio in primo piano, notifiche, wake lock | Aggiunte previste: tipo `health`/`location` del servizio, `SEND_SMS`, posizione, `USE_FULL_SCREEN_INTENT`, `VIBRATE`. Ognuno motivato e richiesto al bisogno |
| Backup | `allowBackup` non impostato (quindi attivo) | Escludere profilo e contatto dal backup (§13.2) |
| Offuscamento | Non configurato | R8 + `--obfuscate --split-debug-info` (simboli conservati per leggere i crash) |
| Privacy policy | Assente | Testo in-app e pagina pubblica (richiesta da Play) da scrivere sui contenuti reali del §13 |
| Licenze delle dipendenze | `flutter_blue_plus`: **gratuita solo per uso educativo/no-profit**, a pagamento per uso commerciale (nota già nel `pubspec`) | Da risolvere **prima** di una distribuzione commerciale: licenza o sostituzione |
| Google Play | — | Da verificare: dichiarazione dei permessi SMS (fortemente limitati), dichiarazione del servizio in primo piano con video, `USE_FULL_SCREEN_INTENT`, modulo Data safety, classificazione dei contenuti |
| Schermate di presentazione | — | Generabili dai golden test, poi rifinite |

**Non pubblico nulla autonomamente.**

---

## 24. Domande aggiuntive (oltre al §16)

9. **Firma**: autorizzi la creazione di una chiave di upload? La creeresti tu
   (ti guido) e la metteresti nei Secrets del repository. È necessaria per
   aggiornare l'app senza disinstallarla.
10. **Package name definitivo** (es. `it.<tuonome>.dynamix`).
11. **Logo**: preferisci vedere 3 bozze prima della scelta (consigliato)?
12. **Animazioni**: accetti lo stile illustrato procedurale (§20.1),
    oppure preferisci asset Rive o Lottie fatti da un designer, che possono
    rendere personaggi più ricchi ma vanno creati fuori da qui?
13. **Uso commerciale previsto?** Determina la questione della licenza di
    `flutter_blue_plus` e il percorso per Google Play.
14. **Dispositivo reale per i test**: modello e versione Android del telefono
    che userai, da annotare nel rapporto finale.


---

# Parte III — Architettura doppia

## 25. Architettura doppia: SensorTile e sensori dello smartphone

### 25.1 Cosa esiste già (verificato nel codice)

| Requisito | Stato nel progetto |
|---|---|
| Ricerca dispositivi | `DeviceScanner`, con filtro "Solo BlueST" e riconoscimento dall'advertising (company ID `0x0030`, device ID `0x0D` = SensorTile.box PRO, firmware ID dal catalogo ufficiale ST `appconfig`) |
| Connessione, associazione, riconnessione | `ConnectionManager`: macchina a stati, timeout di 20 s, associazione (`createBond`) se una caratteristica la richiede, riconnessione automatica con backoff esponenziale 1, 2, 4… fino a 30 s |
| Decodifica | `BlueStDecoder`: accelerometro (mg), giroscopio (0,1 dps), magnetometro, pressione, temperatura, batteria, quaternioni, Eulero, attività, contapassi, QVAR… (`docs/TECHNICAL.md` §6) |
| Perdita di pacchetti | `PacketLossEstimator`: stima dai salti del timestamp a 16 bit |
| Batteria e segnale | Funzione batteria (%, V, mA, stato), RSSI ogni 5 s, MTU |
| Simulatore | `SimulatedTransport`, classe separata, dati marcati `simulated` fino all'export |
| Prova su hardware | Procedura `docs/HARDWARE_TEST.md` (8 passi, confronto con l'app ST BLE Sensor) |

La Modalità 1 quindi **non va riscritta**: va collegata al motore comune
(§25.4) e completata nei punti del §25.3.

### 25.2 Modello esatto: cosa è noto e cosa va verificato

Noto dal **data brief** ST (`docs/TECHNICAL.md` §1):

- scheda **STEVAL-MKBOXPRO** (SensorTile.box PRO), MCU STM32U585AI;
- IMU a 6 assi **LSM6DSV16X** (con Qvar);
- LIS2DU12 (accelerometro), LIS2MDL (magnetometro), LPS22DF (pressione),
  STTS22H (temperatura), MP23DB01HP (microfono);
- BLE con BlueNRG-LP oppure STM32WB07, secondo la revisione.

**Non verificato su una scheda reale** (i manuali UM2496 e UM3133 non erano
stati consultati). Prima di implementare, si verifica sulla scheda:

| # | Da verificare | Perché conta per il motore | Come |
|---|---|---|---|
| V1 | Device ID e firmware ID nell'advertising | Modello e firmware esatti | Schermata Dispositivi (etichette) |
| V2 | Tabella GATT completa | Quali sensori sono **davvero** esposti | Diagnostica → "Copia rapporto" |
| V3 | **Quale accelerometro** alimenta la funzione BlueST (LSM6DSV16X o LIS2DU12) | Rumore, fondo scala, banda | Sorgente del firmware (FP-SNS-STBOX1) + prova statica |
| V4 | **Fondo scala** configurato dal firmware | Saturazione: il pacchetto int16 in mg arriva a ±32,767 g, ma il chip può saturare prima | Sorgente del firmware; urto controllato |
| V5 | Fondo scala del giroscopio rispetto al formato | Il formato 0,1 dps in int16 si ferma a **±3276,7 dps**: se il chip è configurato oltre, i valori vengono **tagliati dal formato** e non dal sensore | Sorgente del firmware; rotazione veloce controllata |
| V6 | **Unità del timestamp** (non documentata) | Tempi di campionamento, jerk, Δv | Regressione tick/orologio (§25.5) |
| V7 | Accelerometro e giroscopio **nello stesso pacchetto**? (2 + 6 + 6 + 6 = 20 byte con il magnetometro: entra esattamente in un pacchetto da 20 byte) | Se sì, sono sincronizzati alla sorgente (vantaggio rispetto al telefono) | Maschera della caratteristica nel rapporto |
| V8 | **Frequenza effettiva** delle notifiche | Sottocampionamento dei picchi (§8.4): via BLE la frequenza è limitata dall'intervallo di connessione e dal numero di notifiche per intervallo | Misura in Diagnostica a varie distanze |
| V9 | Orientamento degli assi della scheda e terna destrorsa | Sistema di riferimento | Prova a 6 posizioni + coerenza con il giroscopio (§25.6) |
| V10 | Perdita di pacchetti in uso (tasca, casco, distanza) | Qualità e buchi | Prova di lunga durata (HARDWARE_TEST §8) |
| V11 | Comportamento della batteria e durata | Monitoraggio prolungato | Prova di lunga durata |

Finché V1–V9 non sono verificati, i parametri della Modalità 1 restano
`NON VERIFICATO` nel codice e la UI lo mostra.

**Nessuna funzione BLE viene simulata se il firmware non la offre.** Il
simulatore attuale espone le funzioni del catalogo. Va **ridotto** alle sole
funzioni presenti nella tabella GATT reale (V2), appena disponibile un rapporto
di Diagnostica della scheda.

### 25.3 Lacune della Modalità 1 rispetto alla specifica

1. **Timestamp**: oggi si usa l'ora di ricezione, e i tick servono solo a
   stimare le perdite. Serve la ricostruzione del tempo di campionamento
   (§25.5).
2. **Qualità del collegamento** come ingresso del motore: perdite, RSSI,
   frequenza misurata e jitter entrano in Q (§11.6).
3. **Batteria della scheda**: avviso di batteria bassa e previsione di
   interruzione in dashboard.
4. **Collegamento perso durante o subito dopo un evento**: senza la fase
   post-evento il livello non può essere confermato. L'evento viene salvato
   con "collegamento perso dopo l'evento", con la categoria **incerto** al
   livello calcolato fino a quel punto. La perdita del collegamento da sola
   non alza il livello: il motivo più comune è la distanza, non un incidente.
   Da confermare (§26).
5. **Servizio in primo piano**: in questa modalità il tipo `connectedDevice`
   è quello corretto (nella Modalità 2 serve `health`, §15.3).

Possibile estensione futura, da valutare dopo V3–V8: l'LSM6DSV16X ha
rilevamento integrato di caduta libera e risveglio, e il firmware Datalog2
registra ad alta frequenza su scheda SD. Il primo non sarebbe limitato dalla
banda BLE. Il secondo è lo strumento ideale per raccogliere **dati di
riferimento ad alta frequenza** per la validazione (§14.3). Entrambi richiedono
firmware o funzioni (PnPL, MLC/FSM) oggi non decodificati dall'app.

### 25.4 Motore comune e formato normalizzato

Un solo `DetectionEngine` (§15.1). Le sorgenti producono lo stesso
`MotionSample`:

```
MotionSample {
  sourceId      // es. "sensortile:<MAC>", "phone", "sim:<scenario>", "replay:<sessione>"
  kind          // acc | gyro | mag | pressure | quat | gps
  tNs           // tempo di campionamento stimato, sull'orologio monotono del telefono
  tSigmaNs      // incertezza del tempo (hardware: piccola; BLE: dalla regressione §25.5)
  x, y, z       // unità SI: m/s², rad/s, µT; nel riferimento della sorgente
  flags         // saturato, buco precedente, interpolato, timestamp di ricezione
}

SourceDescriptor {
  mode          // sensortile | phone | simulated | replay
  model, firmware, sensors[] { tipo, fondo scala, risoluzione, frequenza nominale }
  measuredRateHz, jitter, packetLoss, battery, rssi
  frame         // matrice R_sorgente→B_std (convenzione comune: terna destrorsa x, y, z)
  calibration   // bias, scala, g_cal, rumore misurato (§14.2), parametri NON VERIFICATO/verificato
  placement     // tasca, mano, manubrio, casco, cintura (scelto dall'utente)
  timestampQuality // hardware | ricostruito | ricezione
}
```

- **Unità**: la conversione da BlueST (mg, 0,1 dps, mGa) a SI avviene
  nell'adattatore, una volta sola.
- **Riferimento**: ogni sorgente dichiara la sua R verso la convenzione
  comune. Il motore lavora solo nella convenzione comune e nei riferimenti W e V
  (§3.1).
- **Calibrazioni specifiche** (stesso algoritmo, parametri diversi):
  rumore e bias (dalla caratterizzazione §14.2 di **ciascun** hardware),
  fondo scala e soglia di saturazione, r_max del braccio di leva (§9.1: la
  scheda è più piccola del telefono), frequenza attesa, linee di base e Σ
  **per coppia (sorgente, posizione, attività)**.

Le firme degli eventi dipendono dalla **posizione**: per un sensore sul casco
le categorie "caduta del telefono dal tavolo" e "persona caduta" diventano
"casco caduto da solo" e "urto con la testa", con la stessa ambiguità di
principio (§9.4). Le regole sono comuni; le categorie mostrate e i parametri
dipendono dalla posizione dichiarata.

### 25.5 Ricostruzione del tempo per i dati BLE

Ogni pacchetto porta un tick a 16 bit di unità ignota (V6), mentre il telefono
registra l'istante di ricezione r_i.

1. **Srotolamento**: k_i = k_{i−1} + ((raw_i − raw_{i−1}) mod 65536). Dopo una
   pausa lunga il numero di giri n si stima con la ricezione:
   n = round(((r_i − r_{i−1})/b̂ − Δraw) / 65536).
2. **Modello**: r_i = a + b·k_i + L_i, dove L_i ≥ L_min è la latenza (BLE,
   pila Android, canale piattaforma): sempre positiva e variabile.
3. **Stima di a e b**: poiché la latenza è sempre ≥ 0, la retta corretta è
   l'**inviluppo inferiore** dei punti (k_i, r_i), non la retta dei minimi
   quadrati, che sarebbe spostata dalla latenza media. Si stima con
   programmazione lineare: min Σ(r_i − a − b k_i) con r_i ≥ a + b k_i, cioè il
   metodo classico della stima della deriva in sincronizzazione a una via.
   Si usa una finestra mobile, per seguire la deriva dei due quarzi.
4. **Risultati**:
   - tempo di campionamento t_i = a + b·k_i, privo del jitter di ricezione;
   - **periodo del tick** b, che dà l'unità del timestamp (risolve V6 per misura);
   - frequenza effettiva;
   - incertezza tSigma dalla dispersione residua;
   - buchi esatti dai salti di k (sostituisce la stima di `PacketLossEstimator`).
5. **Validazione**: con il simulatore (latenze sintetiche note) e sulla scheda
   reale, confrontando la stima di b con la frequenza nominale del firmware.

Sul telefono questo passo non serve: i timestamp sono hardware (§2).

### 25.6 Calibrazione all'avvio della sessione

- **Quiete iniziale** di 3–5 s (guidata dall'interfaccia): g_cal, bias del
  giroscopio, rumore effettivo e orientamento della gravità nella sorgente.
  Serve per il riferimento W e per riconoscere la posizione (es. casco
  dritto).
- **Controllo di coerenza degli assi** (V9): durante una rotazione, la
  variazione della gravità misurata dall'accelerometro deve coincidere con
  l'integrale del giroscopio, Δγ ≈ −∫ ω × γ dt. Se c'è un segno invertito o
  una permutazione degli assi, l'errore è grande e l'app lo segnala. È un test
  automatico, eseguibile anche sui dati del simulatore.

### 25.7 Interfaccia

- **Scelta della modalità**: dopo la registrazione, una schermata con due
  schede grandi:
  1. **SensorTile STMicroelectronics**, collegamento Bluetooth;
  2. **Sensori dello smartphone**.

  Per ciascuna sono indicati requisiti e disponibilità rilevata (Bluetooth
  presente? Sensori del telefono presenti? §2.8). Modificabile dalle
  impostazioni, ma **non durante una registrazione o un allarme** (regola già
  presente per le registrazioni).
- **Modalità attiva sempre visibile**: badge in dashboard e in diagnostica.
  - SensorTile: stato del collegamento, batteria, RSSI, perdite, frequenza.
  - Telefono: sensori presenti, mancanti e degradati.
- **Simulazione**: una terza modalità **solo nelle opzioni sviluppatore**, con
  banner permanente "SIMULAZIONE", dati marcati `simulated` fino all'export,
  e **SMS sempre in `DryRun`**: con una sorgente simulata l'invio reale è
  bloccato nel codice, non solo nella UI.
- La scelta della modalità **non** cambia regole e livelli: cambiano solo i
  parametri di calibrazione e le categorie legate alla posizione (§25.4).

### 25.8 Test specifici

- **Adattatori**: pacchetti BlueST reali catturati da Diagnostica (quando
  disponibili) usati come dati di test con i valori attesi in SI; eventi del
  telefono iniettati.
- **Equivalenza del motore**: lo stesso scenario simulato, generato come
  sorgente telefono e come sorgente SensorTile (con le rispettive frequenze,
  rumori e latenze), deve dare la stessa categoria. Le differenze ammesse
  sono solo quelle spiegate dalla qualità diversa.
- **Ricostruzione del tempo**: latenze sintetiche, deriva dei quarzi,
  azzeramenti del contatore, pause lunghe.
- **Disconnessioni durante un evento**: categoria "incerto" e nessun crash.

---

## 26. Domande sulla modalità SensorTile

15. **Hai la scheda ora?** Mi serve il "Copia rapporto" della Diagnostica
    dopo una connessione (V1, V2, V7) e, se possibile, una registrazione
    esportata di 1 minuto con la scheda ferma e poi ruotata (V6, V8, V9).
16. **Dove verrà indossata** la SensorTile (casco, cintura, zaino, bici)?
    Determina categorie e parametri (§25.4).
17. **Firmware**: è quello di fabbrica? Lo identifico dall'advertising (V1).
    Un firmware diverso, come Datalog2 per la raccolta dei dati, è
    accettabile?
18. **Collegamento perso dopo un urto**: confermi la proposta del §25.3.4
    (evento incerto, nessun aumento automatico del livello)?


---

# Parte IV — Analisi completa di ogni movimento

## 27. Analisi matematica completa di ogni movimento

### 27.1 Unità di analisi: il "movimento"

Ogni segmento delimitato dal segmentatore (§8.2) è un **movimento**, anche se
brevissimo (pochi campioni). Per ogni movimento si calcola l'insieme completo
di grandezze qui sotto, sempre sui **timestamp reali** (§2, §25.5) e sempre con
la loro **incertezza** quando non sono misure dirette. Il segmentatore usa
soglie adattive basse, cioè apre molti segmenti, e così nessun movimento breve
viene scartato prima dell'analisi. È la classificazione (§28) a decidere cosa è
normale.

Metodi numerici con passo irregolare:

- integrazione con la **regola dei trapezi** sui Δt reali;
- giroscopio e accelerometro allineati interpolando ω linearmente sui tempi
  dell'accelerometro, e l'orientamento con SLERP;
- **nessun ricampionamento** del canale grezzo per le grandezze di picco;
- buchi > 3 periodi: il movimento viene marcato e le grandezze integrali
  attraverso il buco non vengono calcolate (§27.4).

### 27.2 Grandezze calcolate

| Grandezza | Formula / metodo | Note |
|---|---|---|
| f_x, f_y, f_z | Grezzo | Conservato sempre |
| \|f\| | √(f_x² + f_y² + f_z²) | Indizio di caduta libera, **non** accelerazione dinamica (§3.3) |
| a (dinamica) | a_W = R(q) f − (0, 0, g_cal) (§5) | In W: verticale e orizzontale |
| Durata | t_fine − t_inizio, e durate sopra 1, 2, 3 volte la linea di base | |
| Δv | ∫ a_W dt (trapezi) | Vettore: modulo, direzione, verticale e orizzontale. Sempre calcolabile, con l'errore del §27.4 |
| v_iniziale, v_finale | Solo con un **vincolo** (§27.3) | Altrimenti "non stimabile" |
| Spostamento s | ∫∫ a_W dt², con correzione ZUPT (§27.3) | Solo con le condizioni del §27.4; sempre con σ |
| Jerk ĵ | Pendenza ai minimi quadrati (§6.2) | |
| Variazione del jerk (snap) | Coefficiente di 2° grado di un'interpolazione polinomiale locale ai minimi quadrati (Savitzky–Golay di grado 2), finestra più lunga del jerk | Il rumore cresce come 1/Δt²: peso basso, sempre con σ, mai da solo |
| ω, \|ω\| | Bias rimosso (§4.2) | |
| α = dω/dt | Pendenza ai minimi quadrati | |
| Orientamento | Angolo di q_inizio* ⊗ q_fine, rotazione percorsa ∫\|ω\|dt | Differenza tra netto e percorso = rotazione "avanti e indietro" |
| Energia del segnale | E_a = ∫ \|a\|² dt [m²/s³], anche per banda (§7.2) | Misura d'intensità, non energia fisica |
| Energia cinetica specifica | ½\|Δv\|² [J/kg] | Variazione di energia cinetica per unità di massa, se l'oggetto si arresta. Ordine di grandezza fisico dell'urto |
| Oscillazioni | Frequenza dominante (Goertzel o FFT corta, 0,5–1 s), periodicità (picco dell'autocorrelazione normalizzata), passaggi per lo zero della componente principale | §27.5 |
| Urti e rimbalzi | Picchi separati da cadute libere, intervalli t_k e rapporto t_{k+1}/t_k (§9.3) | |
| Vibrazioni successive | Energia nella banda alta dopo l'urto e tempo di smorzamento (inviluppo esponenziale) | |

### 27.3 Velocità e spostamento: quando sono stimabili

L'accelerometro dà solo **variazioni** di velocità: v(t) = v₀ + ∫a dt, e v₀ è
ignota. Diventa stimabile solo con un vincolo:

| Vincolo | Applicazione |
|---|---|
| Quiete prima o dopo (v = 0, rilevatore §8.3) | ZUPT (zero-velocity update): con quiete a entrambi gli estremi, l'errore di bias si corregge sottraendo la rampa lineare v_c(t) = v(t) − v(T)·(t − t₀)/(T − t₀), nell'ipotesi di un bias costante nell'intervallo |
| Caduta libera | Dopo T_ff di caduta libera partendo da fermo: v_impatto = g·T_ff (verticale) |
| GPS (veicolo, §10) | v₀ dalla velocità GPS prima dell'evento, con la sua precisione |
| Nessuno | v_iniziale e v_finale "non stimabili": si riporta solo Δv |

### 27.4 Limiti dell'integrazione (deriva)

Errori dominanti (calcolati, non misurati):

- **Fuga della gravità per errore d'orientamento**: un errore di 1° lascia
  g·sin(1°) ≈ 0,17 m/s² nell'accelerazione dinamica. Dopo T secondi:
  - errore di velocità ≈ 0,17·T m/s;
  - errore di spostamento ≈ ½·0,17·T² m.

  Esempi: **0,2 s → 3 mm**, 0,5 s → 2 cm, **1 s → 9 cm**, 2 s → 34 cm.
- **Bias residuo** b: velocità b·T, spostamento ½ b T².
- **Rumore bianco** σ a passo Δt: deviazione della velocità σ√(T·Δt),
  dello spostamento ≈ σ Δt^½ T^{3/2}/√3. Con i valori illustrativi
  σ = 0,02 m/s² a 200 Hz e T = 1 s si ottengono 1,4 mm/s e 0,8 mm:
  trascurabili rispetto alla fuga di gravità.
- **Saturazione**: l'integrale sottostima Δv (marcata, Q ridotta).
- **Sottocampionamento** di impulsi brevi (§8.4).

Regole:

1. Lo spostamento si calcola solo su finestre ≤ 1 s, o fino a 2 s con
   ZUPT a entrambi gli estremi.
2. Si riporta sempre con σ, propagato da σ_θ (§4.3), dal bias e dal rumore.
3. Non è mai trattato come una misura esatta.
4. Il GPS può confrontarlo solo su scale di metri e secondi, non per un
   evento sotto il secondo.

Δv invece resta affidabile sugli eventi brevi, perché l'errore cresce solo
linearmente con T: con T = 0,1 s e 1° di errore vale circa 0,017 m/s. Per
questo Δv, e non lo spostamento, è la grandezza principale.

### 27.5 Accelerazione alta e spostamento ridotto: lo scuotimento

Firma fisica di uno scuotimento con la mano:

- **alternanza**: la componente principale di a cambia segno a ogni
  mezzo ciclo;
- **Δv netto ≈ 0** sul segmento e su ogni ciclo, perché la mano riporta il
  telefono indietro;
- **ampiezza implicita coerente con una mano**: per un moto armonico,
  l'ampiezza dello spostamento è A_s = A_a/(2πf)². Per esempio 3 g a 5 Hz
  danno circa 3 cm, e 2 g a 3 Hz circa 5,5 cm. La stessa relazione,
  rovesciata, dice che uno scuotimento non produce mai un grande spostamento
  netto;
- **periodicità**: autocorrelazione con un picco alla frequenza dominante (già
  da 2–3 cicli);
- **rotazione avanti e indietro**: rotazione percorsa ≫ rotazione netta;
- **assenza** di caduta libera, assenza di rimbalzi geometrici, assenza di un
  cambio di postura stabile dopo, ripresa immediata del movimento.

Scuotimento violento brevissimo (0,1–0,5 s, quindi 1–3 cicli): la periodicità
è debole, e contano alternanza, Δv netto ≈ 0, assenza di una sequenza d'urto e
contesto dopo.

**Attenzione (specifica §2).** Lo spostamento ridotto **non** dimostra che un
evento sia innocuo. Anche un urto vero ha uno spostamento minimo: la distanza
di arresto è di millimetri o centimetri. Il discriminante non è lo spostamento
ma la **struttura**:

| | Scuotimento | Urto |
|---|---|---|
| Δv | Alternato, netto ≈ 0 | **Unidirezionale**, netto grande |
| Impulsi | Ripetuti, simili tra loro | Uno dominante, eventualmente con rimbalzi decrescenti |
| Prima | Moto della mano | Moto del corpo, veicolo o caduta libera |
| Dopo | Ripresa immediata | Assestamento, vibrazioni smorzate, cambio di postura, quiete |

Per questo lo spostamento ridotto entra **solo** come indizio a favore di
"scuotimento" e solo **insieme** all'alternanza e a Δv netto ≈ 0. Non entra
mai come attenuante generale.

### 27.6 Accelerazione moderata ma prolungata

Esempio: una frenata a 0,5 g per 3 s dà Δv ≈ 14,7 m/s, ma con jerk basso,
nessun impulso, direzione orizzontale stabile e, quando disponibile, una
velocità GPS coerente.

Classificazione: "frenata o accelerazione", non urto. La severità usa Δv, la
**durata**, il **tasso** (Δv/T) e il contesto, perché lo stesso Δv in 50 ms e in
3 s ha un significato fisico molto diverso. Le grandezze integrali da sole non
bastano: si valuta sempre anche il tasso.

---

## 28. Classificatore a sequenze di fasi e sistema anti-falsi allarmi

### 28.1 Modello a fasi (cuore del classificatore)

Un movimento è letto come una **sequenza di fasi fisiche**. Insieme di fasi:

```
Q  quiete            M  moto ordinario (mano, passo, veicolo)
S  scuotimento        F  caduta libera
I  impulso / urto     R  rimbalzo (volo balistico breve tra impulsi)
V  vibrazione smorzata  T  assestamento        P  nuova postura stabile
B  accelerazione sostenuta (frenata/accelerazione)
```

Ogni fase ha una **verosimiglianza per campione** calcolata dalle grandezze
del §27:

- F: \|f\| piccolo rispetto alla soglia f_ff(ω) (§9.1);
- I: \|ĵ\| e \|a\| alti con durata breve;
- S: alternanza e periodicità;
- e così via.

Ogni fase ha anche una **durata modellata** in modo esplicito, con
distribuzioni dalla fisica: per esempio F ha una durata compatibile con
√(2h/g) per altezze plausibili, e R con t = 2v/g.

È un **modello semi-Markov a stati nascosti** (HSMM). Con la decodifica di
Viterbi si ottiene la sequenza di fasi più probabile e la sua verosimiglianza.

Vantaggi:

- **Non richiede che tutte le fasi siano presenti** (specifica §3): le
  transizioni ammettono salti, per esempio M → I → P senza caduta libera.
- I parametri iniziali hanno un significato fisico, quindi il modello funziona
  **senza dati di addestramento inventati**.
- Con dati etichettati gli stessi parametri si **stimano** (EM o massima
  verosimiglianza supervisionata): è la parte "addestrabile".

### 28.2 Scenari come grammatiche di fasi

| Categoria | Sequenza tipica (fasi opzionali tra parentesi) |
|---|---|
| Telefono scosso intenzionalmente | M → S (breve) → M |
| Telefono agitato ripetutamente | M → S (lungo, periodico) → M |
| Appoggiato o spostato sul tavolo | M → I (debole) → Q, con postura piana |
| Lasciato cadere | (M) → F → I → (R → I)* → V → T → Q/P |
| Urta una superficie | M → I → (V) → M |
| Corsa, camminata | M periodico alla cadenza del passo |
| Movimento sportivo | M intenso, I ripetuti, contesto dell'attività |
| Frenata o accelerazione | M → B → M (tasso moderato, durata lunga) |
| Persona che cade con il telefono addosso | M → (F parziale) → I → (V) → P → (Q prolungata) |
| Impatto potenzialmente pericoloso | … → I forte → P/Q, senza ripresa |
| Situazione ambigua | Più grammatiche con verosimiglianze vicine |

Per ogni movimento si calcola la verosimiglianza di ogni grammatica con la
decodifica vincolata. Il **rapporto di verosimiglianza** tra la prima e la
seconda categoria è la base dell'incertezza: con un margine sotto δ, la
categoria è **"Situazione ambigua"**.

### 28.3 Combinazione con le caratteristiche e il machine learning

Lo stimatore finale ha tre ingressi:

1. le verosimiglianze delle grammatiche (§28.2);
2. le caratteristiche del §27.2;
3. la qualità Q (§11.6).

| Stadio | Decisore | Condizione |
|---|---|---|
| Oggi | Regole fisiche + HSMM con parametri fisici | Nessun dato necessario |
| Con dati reali etichettati | Gradient Boosting sulle stesse caratteristiche **più** le verosimiglianze HSMM; probabilità calibrate (isotoniche) su un set di validazione separato | Adottato solo se supera lo stadio precedente sul set di test, con intervalli di confidenza |

In entrambi gli stadi: **rilevamento fuori distribuzione**. Se le
caratteristiche sono lontane da tutto ciò che si è visto (D² del §11.3 sopra
il quantile alto), l'uscita è "Situazione ambigua" e non la classe più vicina.

### 28.4 Regole anti-falsi allarmi (vincoli verificabili)

L'allarme (§12) richiede **tutte** queste condizioni:

1. una categoria pericolosa (persona che cade, impatto pericoloso), oppure
   "ambigua" con severità alta (§11.4);
2. **almeno due gruppi di indizi indipendenti** concordi, per esempio
   l'impulso + (caduta libera o postura o quiete successiva o GPS). Picco
   d'accelerazione, jerk ed energia dello stesso impulso contano come **un
   solo gruppo**, perché sono la stessa informazione fisica;
3. la **fase post-evento** osservata (T_post), salvo i livelli estremi con
   saturazione e Δv molto alta: anche in quel caso l'allarme parte, ma con il
   conto alla rovescia di 60 s che lascia il tempo di annullarlo;
4. Q ≥ Q_min. Sotto, l'evento è "ambiguo per qualità dei dati", e se la
   severità è alta l'allarme scatta comunque: un dato scadente non deve
   nascondere un'emergenza. È una scelta da confermare (§16).

**Proprietà garantita dai test (property-based):** *nessun segnale composto da
un singolo picco isolato*, di qualsiasi ampiezza e orientamento, su fondo di
quiete o di moto ordinario, può soddisfare la condizione 2, e quindi non può
attivare l'allarme. Il test genera migliaia di picchi casuali (ampiezza,
durata, direzione, istante) e verifica l'assenza di allarmi.

### 28.5 Soglie adattive

- Linee di base robuste per (sorgente, posizione, attività) (§8.2, §25.4).
- Soglie delle verosimiglianze e δ **ricavate sui dati di validazione**,
  fissando il tasso di falsi allarmi per ora accettato e misurando il recall
  corrispondente.
- Prima dei dati reali sono marcate `PROVVISORIO`, con l'ancoraggio fisico
  dichiarato.

---

## 29. Piano di test per i movimenti brevi e intensi

### 29.1 Simulatore (automatico)

| Test | Generazione | Atteso |
|---|---|---|
| Scuotimento violento 0,1–0,5 s | 1–3 cicli sinusoidali, 2–6 g, 3–8 Hz, assi casuali | "Scosso", nessun allarme |
| Scuotimento ripetuto per secondi | 5–20 s, frequenza e ampiezza variabili | "Agitato", nessun allarme |
| Picchi alti con spostamento ridotto | Impulsi a semiseno di durata 5–50 ms **isolati** | Nessun allarme (proprietà §28.4) |
| Rotazioni rapide | ω fino al fondo scala, con braccio di leva r | Nessuna falsa accelerazione dinamica; nessun allarme |
| Urti morbidi e rigidi | Durata e Δv parametrici, rimbalzi con e | Categoria "urta una superficie" o "lasciato cadere" |
| Cadute da diverse altezze | h = 0,3–1,5 m, con e senza rotazione | T_ff entro la tolleranza di √(2h/g); "lasciato cadere" |
| Caduta con telefono in tasca | Modello a pendolo inverso del corpo (semplificato, dichiarato) | "Persona che cade" o "ambigua", mai "scosso" |
| Movimento sportivo intenso | Profili MTB, sci, corsa con urti ripetuti | Nessun allarme in assenza di sequenza d'urto con postura e quiete |
| Accelerazione moderata prolungata | 0,2–0,8 g per 1–5 s | "Frenata o accelerazione" |

Ogni test viene ripetuto su più seed e con entrambe le sorgenti (telefono e
SensorTile, §25.8). Per ogni caso si misurano: categoria, livello, confidenza,
**tempo di rilevamento**, errore su Δv e T_ff rispetto ai valori veri del
simulatore.

### 29.2 Prove reali (sicure)

- Scuotimenti, rotazioni, appoggi, urti con la mano: tutti su dispositivo reale.
- Cadute del telefono su cuscino e su superficie rigida protetta, da altezze
  misurate.
- Sport, con il telefono in tasca o nello zaino e la SensorTile nella posizione
  scelta.
- **Nessuna caduta di persone provocata.** Per "caduta con il telefono in
  tasca" si usano dataset pubblici di cadute (citati, con i limiti di posizione
  e popolazione dichiarati).
- Ogni prova viene etichettata nello storico eventi (campo `label`, §15.5).

### 29.3 Metriche e dimensione dei campioni

- Per categoria: TP, FP, FN, precisione, recall, F1, matrice di confusione;
  F1 macro sulle categorie.
- Allarme: **falsi allarmi per ora** di uso normale, falsi negativi sugli
  eventi pericolosi, tempo di rilevamento (mediana e 95° percentile).
- Intervalli di confidenza per ogni proporzione. Regola del tre: con **zero**
  falsi allarmi in n prove indipendenti, il limite superiore al 95% del tasso
  è circa 3/n. Per affermare un tasso inferiore all'1% per un tipo di prova
  servono quindi almeno ~300 prove senza falsi allarmi. Questo numero va tenuto
  presente prima di qualunque dichiarazione.
- Risultati del simulatore e risultati reali sempre **separati** ed etichettati.
  Nessuna soglia o percentuale viene dichiarata senza la misura che la
  sostiene.
