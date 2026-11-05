# Ottenere l'APK con GitHub

GitHub compila l'app nel cloud. Sul PC non devi installare nulla.

## 1. Crea il repository

1. Accedi a [github.com](https://github.com), creando un account gratuito se non ce l'hai.
2. Apri [github.com/new](https://github.com/new).
3. Come nome scrivi `dinamix`, scegli **Private** e premi **Create repository**.

## 2. Carica i file

1. Estrai `dinamix_app.zip` sul PC e apri la cartella `dinamix_app`.
2. Nella pagina del repository, apri il link **uploading an existing file**.
3. Seleziona **tutto il contenuto** di `dinamix_app`, comprese le cartelle `.github`, `android`, `lib`, `test` e `docs`,
   e trascinalo nella pagina. Trascina il contenuto, non la cartella stessa.
4. Attendi il caricamento e premi **Commit changes**.

## 3. Controlla che il workflow ci sia

Sulla pagina principale del repository deve comparire la cartella `.github`. Se manca, il caricamento l'ha saltata:

1. Premi **Add file → Create new file**.
2. Come nome scrivi esattamente `.github/workflows/build-apk.yml`.
3. Incolla il contenuto del file `.github/workflows/build-apk.yml` che trovi nella cartella estratta.
   Se non lo vedi, abilita la visualizzazione degli elementi nascosti in Esplora file.
4. Premi **Commit changes**.

## 4. Attendi la compilazione

1. Apri la scheda **Actions**. Se GitHub lo chiede, abilita i workflow.
2. Apri l'esecuzione **Compila APK**. Se non è partita, premi **Run workflow**.
3. La prima compilazione richiede di solito 5-15 minuti.

| Esito | Significato |
|---|---|
| Verde | APK creato, analisi e test passati |
| Rosso, con `dinamix.apk` presente | APK creato, ma analisi o test falliti: va controllato |
| Rosso, senza APK | Compilazione fallita |

## 5. Scarica e installa

1. In fondo alla pagina dell'esecuzione, nella sezione **Artifacts**, scarica `dinamix.apk`.
   Se scarichi un archivio ZIP, estrailo. Il file resta disponibile per 30 giorni.
2. Copia l'APK sul telefono via cavo, oppure mandalo con Drive o email.
3. Aprilo sul telefono e, se richiesto, autorizza l'installazione da quella app.

L'APK è firmato con una chiave di debug: va bene per le prove, non per il Play Store. Google Play Protect può
mostrare un avviso, perché l'app non proviene dallo store.

## Se qualcosa fallisce

1. Nella pagina dell'esecuzione apri il passaggio con la **X rossa**.
2. Copia il messaggio d'errore, soprattutto le righe con `error`, e incollalo a Claude.
3. Sostituisci i file corretti nel repository, trascinandoli di nuovo con **Add file → Upload files**:
   la compilazione riparte da sola.

## Dopo l'installazione

Segui la [prova con la scheda](HARDWARE_TEST.md). Senza SensorTile puoi attivare **Impostazioni → Modalità simulazione**
per vedere l'interfaccia: in quel caso i dati non sono misure reali.
