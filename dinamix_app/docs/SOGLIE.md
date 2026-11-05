# DYNAMIX — Formule e soglie del rilevamento

Algoritmo `dynamix-1.0.0`. **Tutte le soglie sono PROVVISORIE.** Ognuna ha un
ancoraggio fisico dichiarato ed è stata controllata solo sul simulatore
(`docs/VALIDAZIONE_SIMULAZIONE.md`). Vanno ricalibrate su dati reali
etichettati (relazione §14, §29). Nessuna è un limite medico o di sicurezza.

Il codice di riferimento è in `lib/sensing/`. I numeri tra parentesi quadre
rimandano alla relazione `docs/DYNAMIX_relazione_tecnica_FASE_A.md` nella
radice del repository.

## 1. Riferimenti e grandezze

| Grandezza | Formula | Codice |
|---|---|---|
| Forza specifica | f = a − g (riferimento B del dispositivo) [§3.2] | `MotionSample` |
| Orientamento | Quaternione B→W, filtro complementare tipo Mahony [§4] | `estimation/orientation.dart` |
| Accelerazione dinamica | a_W = R(q) f − (0, 0, g_cal) [§5.1] | `OrientationEstimator.dynamicWorld` |
| G | \|a\| / 9,80665 | `Frame.aNorm / g0` |
| Jerk | Pendenza ai minimi quadrati su ~30 ms, timestamp reali [§6.2] | `estimation/derivative.dart` |
| Variazione del jerk | 2·c₂ di un'interpolazione quadratica su ~80 ms | `LsDerivative.second` |
| Accelerazione angolare | α = dω/dt con lo stesso stimatore | `DetectionEngine._alpha` |
| Δv impulsivo | ∫ a_W dt sull'impulso dominante (trapezi) [§27.2] | `FeatureExtractor._pulses` |
| Δv cinematico | g · T_ff dopo una caduta libera [§9.2] | idem |
| Spostamento | Doppia integrazione con correzione ZUPT, solo se T ≤ 1 s (2 s con ZUPT) [§27.4] | `_kinematics` |
| Energia del segnale | ∫ \|a\|² dt | `signalEnergy` |
| Energia cinetica specifica | ½ \|Δv\|² (J/kg) | `specificKineticEnergy` |
| Altezza equivalente | h = Δv² / (2g) | `equivalentDropHeight` |

## 2. Stima dell'orientamento

| Parametro | Valore | Ancoraggio |
|---|---|---|
| Costante di tempo τ | 1,5 s (0,2 s nei primi 2 s) | Compromesso tra deriva del giroscopio e disturbi dinamici [§4.2] |
| σ_f del peso | 0,1 · g_cal | La correzione si spegne quando \|f\| si allontana da g |
| σ_ω del peso | 3 rad/s | La correzione si spegne nelle rotazioni rapide |
| Apprendimento del bias | λ = 0,02 per campione, dopo 1 s di quiete | Il bias è osservabile solo da fermo |

## 3. Quiete, caduta libera, segmentazione

| Parametro | Valore | Ancoraggio |
|---|---|---|
| Quiete: std(\|f\|) su 0,6 s | < 0,12 m/s² | Sopra il rumore tipico di un MEMS, sotto il tremore della mano |
| Quiete: max \|ω\| | < 0,08 rad/s (+0,05 finché il bias non è stimato) | Idem per il giroscopio |
| Caduta libera | \|f\| < 0,35 g + ω²·r_max **e** \|f_W,z\| < 0,35 g + ½ ω² r_max | In caduta libera f contiene solo il termine del braccio di leva ω×(ω×r) [§3.2, §9.1] |
| r_max | 8 cm (telefono), 5 cm (SensorTile) | Metà circa della dimensione massima del dispositivo |
| Avvio evento | z > 7 e \|a\| > 0,4 g, oppure caduta libera ≥ 60 ms, oppure \|ω\| > 5 rad/s | z robusto: (x − mediana) / (1,4826·MAD) [§8.2]. 60 ms ≈ caduta di 2 cm |
| Fine attività | z < 3 o \|a\| < 0,25 g per 0,7 s | Isteresi |
| Fase post-evento | 8 s | Serve a osservare rimbalzi, assestamento e immobilità [§9.3] |
| Episodio massimo | 6 s | Le attività lunghe vengono suddivise e la linea di base si adatta |
| Linea di base | Mediana e MAD su 20 s, aggiornamento troncato (winsor) a z = 3 | Un'attività sostenuta viene appresa, un evento isolato quasi no |
| Impulsi | Durata ≤ 0,25 s, livello max(0,3 g, 0,15 · picco) | I contatti di cadute e urti durano da decine a poche centinaia di ms |

## 4. Gruppi di indizi indipendenti (regola anti-falsi allarmi)

φ(x) = 1/(1 + e^{−(x − x₀)/s}) [§11.4].

| Gruppo | Formula | Ancoraggio |
|---|---|---|
| Urto | φ(Δv; 2,0 m/s; 0,35) | √(2gh) = 2 m/s per una caduta da 0,2 m |
| Caduta | max(caduta libera pura, φ(tempo con \|f\| < 0,75 g; 0,2 s; 0,05)) | Caduta libera pura: T_ff > 0,1 s con \|f\| residuo < 0,3 g |
| Postura | φ(cambio di orientamento; 50°; 8°) | Passaggio da verticale a orizzontale ≈ 90° |
| Inattività | φ(quiete dopo; 3 s; 0,8) · (non ripreso) · (attivo prima) | Passaggio da attività a immobilità, non immobilità continua |
| GPS | φ(calo di velocità; 3 m/s; 1) | Solo se presente |

**Allarme:** livello ≥ 3, che richiede una categoria pericolosa (o ambigua con
pericolo), urto > 0,5 e **almeno 2 gruppi** > 0,5, più la fase post-evento
osservata (≥ 2 s). Un picco isolato fornisce al massimo un gruppo e non può
attivare l'allarme: lo verifica un test property-based (`test/sensing/scenarios_test.dart`).

**Livello 4:** livello 3 con Δv ≥ 6 m/s (oppure saturazione con Δv ≥ 4 m/s),
3 o più gruppi e inattività confermata.

## 5. Categorie

Le categorie sono punteggi composti da funzioni logistiche delle
caratteristiche (`classify/classifier.dart`). L'uscita è **"Situazione ambigua"**
quando:

- il punteggio migliore è < 0,2;
- oppure il margine tra le prime due categorie è < 0,12 e una sola delle due è
  pericolosa;
- oppure la qualità dei dati è < 0,35.

Discriminanti principali (ipotesi fisiche da validare, relazione §9.4, §27.5):

| Categoria | Indizi |
|---|---|
| Telefono scosso | Impulsi alterni con dominanza bassa e ≥ 3 impulsi/s, oppure oscillazione periodica a 3–12 Hz |
| Corsa / camminata | Periodicità a 1,2–3,4 Hz |
| Telefono lasciato cadere | Caduta libera pura ≥ 0,1 s + urto + rimbalzi (o posizione finale piana) + nessuna ripresa |
| Frenata / accelerazione | Accelerazione orizzontale passa-basso > 0,12 g per ≥ 0,8 s |
| Vibrazioni prolungate | Quota di energia sopra 10 Hz > 0,45 per ≥ 2,5 s |
| Possibile caduta della persona | Cambio di postura + urto + caduta non pura + nessun rimbalzo + nessuna ripresa |
| Impatto potenzialmente pericoloso | Δv ≥ ~3 m/s con impulso dominante + nessuna ripresa, firma non da telefono libero |

## 6. Indice di confidenza e qualità

- **Q** = q_frequenza · q_buchi · q_saturazione · q_orientamento · q_giroscopio · q_tempi [§11.6]:
  - q_frequenza = min(1, f/50 Hz);
  - q_buchi diminuisce di 0,1 per ogni buco negli ultimi 10 s;
  - q_saturazione = 0,6 nei 10 s successivi a una saturazione;
  - q_tempi: timestamp hardware 1, ricostruiti 0,9, di ricezione 0,7.
- **C** = Q · √(punteggio migliore) · (0,5 + 0,5 · min(1, margine/0,3)).

**C è un indice euristico, non una probabilità calibrata.**
