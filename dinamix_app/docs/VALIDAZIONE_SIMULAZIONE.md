# DYNAMIX — Validazione sul simulatore fisico

Generato da `tool/simulation_report.dart` (algoritmo `dynamix-1.0.0`).

> **Questi risultati verificano il codice e la matematica, NON il mondo reale.** Il simulatore usa modelli semplificati (in particolare la caduta di una persona è un pendolo inverso) e parametri dei sensori illustrativi. Nessuna percentuale qui sotto è un'accuratezza del sistema su persone o dispositivi reali. Le soglie sono provvisorie (docs/SOGLIE.md).

## Protocollo

- 25 scenari × 12 semi × 3 sorgenti = 900 simulazioni, più 300 picchi isolati.
- Le regole sono state sviluppate guardando i semi 1–8. **Questo rapporto usa solo i semi 9–20, mai usati durante lo sviluppo** (insieme di test separato).
- La sorgente "Telefono 100 Hz" non è mai stata usata durante lo sviluppo.
- Ogni seme cambia rumore, bias, errori di scala, assi di rotazione, ampiezze e fasi.
- Tempo di calcolo: 52 s per 1200 simulazioni (44 ms ciascuna, circa 20 s di dati a 50–200 Hz).

## Riepilogo

| Misura | Valore [IC 95% Wilson] |
|---|---|
| Scenari con categoria e allarme attesi | 99.6% [98.9–99.8] |
| Allarme: veri positivi (TP) | 72 |
| Allarme: falsi positivi (FP) | 1 |
| Allarme: falsi negativi (FN) | 0 |
| Allarme: veri negativi (TN) | 983 |
| Precisione TP/(TP+FP) | 98.6% [92.6–99.8] |
| Recall TP/(TP+FN) | 100.0% [94.9–100.0] |
| F1 | 0.993 |
| Falsi allarmi per ora di attività normale simulata | 0.18 (su 5.54 h) |
| Picchi isolati con allarme | 0 su 300 |
| Scenari "fisicamente ambigui" (allarme accettato in entrambi i casi) | 37 allarmi su 144 |

Con 0 eventi su n prove, il limite superiore al 95% del tasso è circa 3/n (regola del tre).

## Tempo di rilevamento (eventi pericolosi)

Dal momento dell'impatto all'allarme. Include la fase di osservazione post-evento (T_post = 8 s), necessaria per la regola anti-falsi allarmi (§28.4).

| Mediana | 95° percentile | Massimo | n |
|---|---|---|---|
| 8.45 s | 8.52 s | 8.54 s | 72 |

## Risultati per scenario

Valori mediani dell'evento più severo, su tutte le sorgenti e i semi.

| Scenario | Superati | Categoria più frequente | Livello | Allarmi | a max (m/s²) | G max | Jerk max (m/s³) | Durata (s) | ω max (rad/s) | Δv urto (m/s) | Confidenza |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Smartphone completamente fermo | 36/36 | nessun evento (36) | — | 0 | — | — | — | — | — | — | — |
| Smartphone in tasca mentre si cammina | 36/36 | Corsa o camminata (36) | 0 | 0 | 8.6 | 0.88 | 408 | 6.03 | 1.8 | 0.53 | 0.79 |
| Smartphone mentre si corre | 36/36 | Corsa o camminata (27) | 1 | 0 | 23.9 | 2.44 | 1139 | 6.05 | 4.4 | 1.39 | 0.81 |
| Smartphone mosso con la mano | 33/36 | Telefono manipolato o ruotato (33) | 1 | 0 | 5.6 | 0.58 | 81 | 4.64 | 2.2 | 1.03 | 0.54 |
| Smartphone lasciato cadere da 0.30 m | 36/36 | Telefono lasciato cadere (36) | 2 | 0 | 212.8 | 21.70 | 6566 | 0.69 | 10.2 | 2.39 | 0.81 |
| Smartphone lasciato cadere da 0.50 m | 36/36 | Telefono lasciato cadere (36) | 2 | 0 | 216.4 | 22.07 | 7668 | 0.78 | 10.8 | 2.99 | 0.82 |
| Smartphone lasciato cadere da 0.75 m | 35/36 | Telefono lasciato cadere (35) | 2 | 1 | 220.2 | 22.46 | 6904 | 0.85 | 10.8 | 3.63 | 0.98 |
| Smartphone lasciato cadere da 1.00 m | 36/36 | Telefono lasciato cadere (36) | 2 | 0 | 233.7 | 23.83 | 7284 | 0.89 | 9.5 | 4.22 | 0.98 |
| Smartphone lasciato cadere da 1.50 m | 36/36 | Telefono lasciato cadere (25) | 2 | 11 | 231.6 | 23.62 | 9725 | 1.07 | 11.5 | 5.19 | 0.77 |
| Smartphone che cade da una tasca | 36/36 | Telefono lasciato cadere (36) | 2 | 0 | 236.4 | 24.10 | 7529 | 0.87 | 10.3 | 3.72 | 0.82 |
| Smartphone che subisce un urto | 36/36 | Telefono urtato (36) | 1 | 0 | 119.6 | 12.20 | 3628 | 0.41 | 0.0 | 0.62 | 0.60 |
| Smartphone lanciato su una superficie morbida | 36/36 | Situazione ambigua (26) | 3 | 26 | 80.7 | 8.23 | 2967 | 1.04 | 10.5 | 4.41 | 0.50 |
| Persona che cade con lo smartphone in tasca | 36/36 | Impatto potenzialmente pericoloso (27) | 3 | 36 | 96.3 | 9.82 | 3487 | 0.40 | 4.6 | 3.12 | 0.62 |
| Frenata improvvisa (telefono nel supporto) | 36/36 | Frenata o accelerazione (36) | 2 | 0 | 6.4 | 0.65 | 57 | 2.95 | 0.0 | 0.00 | 0.88 |
| Accelerazione improvvisa | 36/36 | Frenata o accelerazione (36) | 1 | 0 | 4.9 | 0.50 | 56 | 3.22 | 0.0 | 0.00 | 0.87 |
| Vibrazioni prolungate | 36/36 | Vibrazioni prolungate (30) | 0 | 0 | 5.4 | 0.56 | 461 | 6.05 | 0.0 | 0.08 | 0.74 |
| Rotazione improvvisa | 36/36 | Situazione ambigua (32) | 1 | 0 | 16.3 | 1.67 | 467 | 0.28 | 19.7 | 0.99 | 0.21 |
| Impatto seguito da immobilità | 36/36 | Possibile caduta della persona (36) | 3 | 36 | 142.2 | 14.50 | 5532 | 0.40 | 7.0 | 4.61 | 0.52 |
| Frenata con GPS disturbato | 36/36 | Frenata o accelerazione (36) | 2 | 0 | 6.4 | 0.65 | 57 | 2.96 | 0.0 | 0.00 | 0.88 |
| Scuotimento violento di 0.17 s | 36/36 | Telefono urtato (21) | 2 | 0 | 46.6 | 4.75 | 1776 | 0.20 | 4.0 | 1.83 | 0.54 |
| Scuotimento violento di 0.33 s | 36/36 | Telefono scosso (36) | 2 | 0 | 49.4 | 5.04 | 1807 | 0.37 | 4.0 | 2.45 | 0.60 |
| Scuotimento violento di 0.50 s | 36/36 | Telefono scosso (24) | 2 | 0 | 43.9 | 4.48 | 1628 | 0.54 | 4.0 | 2.13 | 0.55 |
| Scuotimento ripetuto per diversi secondi | 36/36 | Telefono agitato ripetutamente (29) | 1 | 0 | 34.9 | 3.56 | 1717 | 6.05 | 6.0 | 1.65 | 0.94 |
| Movimento sportivo intenso (MTB con salto) | 36/36 | Movimento sportivo (36) | 2 | 0 | 36.3 | 3.70 | 1002 | 5.19 | 0.0 | 3.34 | 0.80 |
| Smartphone appoggiato sul tavolo | 36/36 | Appoggiato o spostato (36) | 1 | 0 | 39.9 | 4.07 | 1883 | 0.51 | 7.4 | 0.51 | 0.89 |

## Per sorgente

| Sorgente | Scenari superati | FP | FN |
|---|---|---|---|
| Telefono 200 Hz | 99.7% [98.1–99.9] | 0 | 0 |
| Telefono 100 Hz | 99.7% [98.1–99.9] | 0 | 0 |
| SensorTile 50 Hz | 99.3% [97.6–99.8] | 1 | 0 |

## Verifica fisica della caduta libera

Telefono 200 Hz. Confronto con T = √(2h/g) e v = √(2gh).

| Altezza | T teorico (s) | T misurato, mediana (s) | v teorica (m/s) | g·T misurato (m/s) |
|---|---|---|---|---|
| 0.30 m | 0.247 | 0.240 | 2.43 | 2.30 |
| 0.50 m | 0.319 | 0.310 | 3.13 | 2.99 |
| 0.75 m | 0.391 | 0.385 | 3.84 | 3.73 |
| 1.00 m | 0.452 | 0.445 | 4.43 | 4.32 |
| 1.50 m | 0.553 | 0.545 | 5.42 | 5.30 |

## Matrice di confusione (scenario → categoria assegnata)

| Scenario | Categorie (conteggio) |
|---|---|
| fermo | nessun evento: 36 |
| camminata_tasca | Corsa o camminata: 36 |
| corsa | Corsa o camminata: 27, Situazione ambigua: 9 |
| mano | Telefono manipolato o ruotato: 33, Situazione ambigua: 3 |
| caduta_tavolo | Telefono lasciato cadere: 168, Situazione ambigua: 12 |
| caduta_tasca | Telefono lasciato cadere: 36 |
| urto | Telefono urtato: 36 |
| lancio_morbido | Situazione ambigua: 26, Telefono lasciato cadere: 10 |
| caduta_persona | Impatto potenzialmente pericoloso: 27, Possibile caduta della persona: 9 |
| frenata | Frenata o accelerazione: 36 |
| accelerazione | Frenata o accelerazione: 36 |
| vibrazioni | Vibrazioni prolungate: 30, nessun evento: 5, Corsa o camminata: 1 |
| rotazione | Situazione ambigua: 32, Telefono manipolato o ruotato: 4 |
| impatto_immobilita | Possibile caduta della persona: 36 |
| gps_disturbato | Frenata o accelerazione: 36 |
| scossa | Telefono scosso: 60, Appoggiato o spostato: 24, Telefono urtato: 21, Situazione ambigua: 3 |
| scossa_ripetuta | Telefono agitato ripetutamente: 29, Situazione ambigua: 7 |
| mtb_salto | Movimento sportivo: 36 |
| appoggio_tavolo | Appoggiato o spostato: 36 |

## Casi non superati

| Sorgente | Scenario | Categoria | Livello | Allarme | Motivi |
|---|---|---|---|---|---|
| Telefono 200 Hz | Smartphone mosso con la mano | Situazione ambigua | 1 | no | Telefono manipolato o ruotato e Possibile caduta della persona quasi equivalenti |
| Telefono 100 Hz | Smartphone mosso con la mano | Situazione ambigua | 1 | no | Telefono manipolato o ruotato e Possibile caduta della persona quasi equivalenti |
| SensorTile 50 Hz | Smartphone mosso con la mano | Situazione ambigua | 1 | no | Telefono manipolato o ruotato e Possibile caduta della persona quasi equivalenti |
| SensorTile 50 Hz | Smartphone lasciato cadere da 0.75 m | Situazione ambigua | 3 | sì | Telefono lasciato cadere e Impatto potenzialmente pericoloso quasi equivalenti; 3 gruppi di indizi concordi |

## Limiti

- I modelli di moto sono semplificati e le categorie attese sono definite da chi ha scritto il simulatore: un modello che li supera può comunque sbagliare su dati reali.
- Il lancio del telefono su superficie morbida e la caduta da tasca possono risultare ambigui: con un solo sensore inerziale la caduta libera di un oggetto e quella di una persona da ~1 m non sono separabili con certezza (relazione §9.4).
- Le metriche reali vanno misurate con la procedura della relazione §14 e §29.

