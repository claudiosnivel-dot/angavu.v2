# WIRING-CENSUS — Censimento del non-cablato (2026-08-29)

> Emerso dal 2° device-test. Ogni *decisione pura* e ogni *adapter isolato* è
> costruito e testato in CI, ma diversi **passi finali che mutano la libreria** o che
> reagiscono al **ciclo di vita** non sono mai stati collegati nell'app in esecuzione.
> La CI Apple non li vede: il cablaggio nella View è lo strato dichiarato non-coperto
> (L-COL-006). Questo documento è il riferimento vivo per il macrotask di cablaggio
> reale. **Metodo**: per ogni voce, incrocio `Sources/AngavuFeatures`+`App/` contro i
> test; "non cablato" = presente solo nei test o esposto ma mai consumato.

## 🔴 Critico — le funzioni che devono liberare spazio NON toccano la libreria

### C1 — Eliminazione foto (categorie): no-op
- **Sintomo device**: elimini gli screenshot, l'UI dice "fatto", ma nulla finisce in
  «Eliminati di recente» — perché non viene eliminato niente.
- **Causa**: `AppEnvironment` non espone alcun port deleter; `CategoryReviewViewModel.confirmDeletion()`
  (`:198`) fa solo avanzare il gate `DeletionFlow` a `.confirmed`; `SystemAssetDeleter`
  (il vero `PHPhotoLibrary.performChanges { deleteAssets }`) e `BatchDeletionCoordinator`
  sono usati **solo nei test**, 0 usi in Features/App.
- **Fix**: port deleter in `AppEnvironment` (`live()` → `SystemAssetDeleter` + coordinatore
  indice; null-object per i test) → invocazione async dal VM sugli id selezionati →
  la View attende l'esito reale (success/cancelled/failed), nessun falso successo →
  a valle invalidazione chirurgica (vedi C4/B1).

### C2 — Sostituzione compressa: no-op alla mutazione
- **Sintomo**: la compressione non libera spazio.
- **Causa**: l'export gira davvero (`BatchCompressionViewModel.start` → coordinator →
  `environment.videoExporter`), ma `apply()` (`:187`) chiama solo
  `CompressedReplacementPlanner.plan(...)` (decisione PURA) e registra "successo".
  La sostituzione reale non avviene: **0 occorrenze di `PHAssetCreationRequest`** in
  tutto il repo (il compresso non entra mai in libreria) e l'originale non è eliminato.
- **Fix**: executor di sostituzione (salva l'output compresso come nuovo asset via
  `PHAssetCreationRequest` + elimina l'originale via lo stesso deleter di C1, dopo
  verifica d'integrità T-082), dietro un port testabile.

> **Radice comune C1+C2**: manca un *executor di mutazioni della libreria*
> (elimina / salva-e-sostituisci). Sono la ragione dei "numeri che non calano".

## 🟠 Costruito ma non attivo (robustezza / velocità / correttezza cache)

### C3 — Persistenza cache derivati (FSE-E1/E2/E3): non cablata
- **Effetto**: la promessa "scansioni successive istantanee" non è attiva; hash/dHash/
  nitidezza si ricalcolano a ogni scansione.
- **Causa**: `SwiftDataDerivedStore`/`DerivedResultCache` mai costruiti in `live()`;
  l'unico riferimento è il parametro `derivedCache` (default `nil`) di
  `StoreInvalidatingLibrarySink`, a sua volta non cablato (C4).
- **Fix**: costruire lo store derivati in `live()` e iniettarlo nella scansione unificata.

### C4 — Observer cambio libreria + invalidazione: non registrato
- **Effetto**: dopo un cambio esterno della libreria (o dopo l'eliminazione, una volta
  cablata) la cache non si auto-invalida → numeri potenzialmente stantìi.
- **Causa**: `StoreInvalidatingLibrarySink` definito ma **0 istanze** fuori dai test;
  nessun `photoLibraryDidChange` registrato; `PhotoLibraryChangeObserver.register()`
  mai chiamato dall'app.
- **Nota collegata (B1 — invalidazione chirurgica)**: al delete parte comunque
  `store.invalidateAll()` (`CategoryReviewView:93`) che azzera TUTTA la cache →
  riaprire una categoria ricalcola ("le categorie grosse ripartono"). Va sostituito
  con la potatura dei soli id realmente eliminati (le altre categorie restano istantanee).

### C5 — Batch PHAsset resolver (FSE-B1, leva 1): non cablato
- **Effetto**: la risoluzione dei `PHAsset` non è in batch come previsto.
- **Causa**: `environment.handleResolver` esposto ma **mai letto** in Features; il
  cablaggio nelle fasi di scansione (previsto in FSE-F) non è avvenuto.

## 🟠 Ciclo di vita (background / foreground / chiusura)

### C6 — Nessuna gestione `scenePhase`; restore FSE-I1 non verificato/rotto sul device
- **Sintomo device**: quando l'app va in background e si riapre, riparte dalla prima
  schermata col tasto gigante (e, aprendo le categorie, ri-analizza).
- **Causa**:
  - **Zero gestione del ciclo di vita**: nessun `scenePhase`/`onChange`/notifiche
    `didEnterBackground`/`willEnterForeground` in tutto il progetto; nessuna persistenza
    di "dove eri" (solo onboarding+tema via `@AppStorage`).
  - L'**unico** ripristino è FSE-I1: `HomeView.task { restoreAtLaunchIfNeeded() }` →
    se l'indice persistito ha conteggio >0 (`LaunchRestoreCoordinator.decision()`),
    `goToDashboard = true`. La **persistenza dell'indice funziona** (`SwiftDataAssetIndex.upsert`
    fa `context.save()`, `count()` legge il container persistente), quindi la LOGICA è
    corretta e CI-verde — **ma la navigazione programmatica da `.task` al cold-launch è
    lo strato non testato (L-COL-006) ed è fragile**; inoltre non copre il
    **resume-da-sospensione** (il `.task` non rigira, non c'è `scenePhase`).
  - Anche se il restore atterrasse sulla dashboard, la cache dei risultati in memoria
    (`AnalysisResultsStore`) NON sopravvive al cold relaunch e i derivati non sono
    persistiti (C3) → aprire una categoria ricalcola comunque.
- **Fix**: gestione esplicita `scenePhase` (salvataggio/ripristino robusto dello stato di
  scansione + schermata), restore affidabile al foreground (non solo al primo `.task`),
  e — con C3 — categorie istantanee dopo il relaunch dai derivati persistiti.

## 🟡 Iniezione morta (innocua, ma sintomo)

### C7 — `featurePrinter` iniettato ma mai consumato
- Dopo FSE-H2 (feature print demoto), `environment.featurePrinter` non è più letto in
  Features. Dead injection. (Idem i dead-code già segnalati: `PerceptualDHasher.dHash(for:)`
  legacy full-res, `FeaturePrinting.prepare`, `OnDeviceImageBytes`,
  `SharpnessKernel.normalizedSharpness(from:data)`.) Rimozione NON autonoma (L-COL-005/021).

## ✅ Effettivamente cablato (da riverificare on-device, ma non no-op)
Scansione unificata, indice SwiftData (persistente), numeri dashboard, residenza
(trigger `DashboardView`), miniature (`environment.thumbnailProvider`), rilevatori
categorie (on-tap), **export** della compressione (non la sostituzione, C2), **extra-foto**
contatti/calendari (instradano a `merger`/`remover` reali via `ExtraActionApplicator`).

## Priorità di cablaggio proposta
1. **C1** eliminazione reale (funzione centrale rotta) + **B1** invalidazione chirurgica.
2. **C2** sostituzione compressa reale (seconda funzione che libera spazio).
3. **C6** ciclo di vita (`scenePhase` + restore affidabile) — la frustrazione d'uso.
4. **C4** observer/invalidazione automatica; **C3** persistenza derivati (velocità).
5. **C5** batch resolver; **C7** pulizia dead-code (con l'utente).

> **Nota di processo (perché è successo)**: ogni macrotask si è chiuso su "CI verde"
> della logica pura + adapter isolato, marcando il wiring come non-testabile in CI e
> rimandandolo; quel rimando non è mai stato incassato. Il gate "confine Apple = CI" non
> può vedere una UI scollegata. Serve un macrotask che possieda il **cablaggio end-to-end**
> con verifica on-device dichiarata come parte della definizione di "fatto".
