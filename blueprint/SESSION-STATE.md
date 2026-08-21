# SESSION-STATE — Angavu iOS

> Fonte di verità sullo **stato vivo del progetto**, consumata da BUILD
> (apple-skills) e aggiornata a ogni chiusura di sessione. Distinta dalla
> SESSION-STATE interna di Trueline. Prosa in italiano, identificatori in inglese.

| | |
|---|---|
| **Progetto** | Angavu iOS |
| **Ecosistema** | swift-ios (SwiftUI + SwiftData + PhotoKit/Vision/AVFoundation) |
| **Ultimo aggiornamento** | 2026-08-21 (BUILD safety_net — implementazione, oracolo Swift pending) |
| **Sessione corrente** | build-3 (`safety_net`): T-050/T-051/T-052 implementati; `swift build`/`test` pending al confine Apple (no toolchain qui). `library_index` (build-2) resta `in_progress` |

---

## 1. Stato dei macrotask

> Stati: `todo` | `in_progress` | `done`. Ordine del piano di build (00-INDEX §2).
> Il checkpoint qui è la **verifica apple-skills** (swift build/test, SwiftLint,
> grafo moduli), non un checkpoint Trueline (policy di repo).

| Macrotask | Stato | Checkpoint | Note |
|---|---|---|---|
| `foundation` | done | swift build/test verdi (build-1) | T-001…T-004 chiusi; lint SwiftLint dichiarato non coperto qui (§7) |
| `library_index` | in_progress | oracolo Swift **pending** (confine Apple) | T-010…T-014 implementati; blueprint validator exit 0; `swift build`/`test` non eseguibili qui (no toolchain + PhotoKit/SwiftData Apple-only) |
| `dashboard` | todo | — | Dipende da library_index; fornisce il caveat iCloud (T-021) consumato da safety_net T-052 |
| `safety_net` | in_progress | oracolo Swift **pending** (confine Apple) | T-050/T-051/T-052 implementati (Domain puro + coordinator Data). T-052 anticipa il caveat iCloud (T-021, dashboard) con modello minimo. `swift build`/`test` non eseguibili qui |
| `exact_duplicates` | todo | — | Dipende da library_index; elimina via safety_net |
| `similar_photos` | todo | — | Dipende da library_index; elimina via safety_net |
| `large_old_media` | todo | — | Dipende da library_index; elimina via safety_net |
| `blurry_photos` | todo | — | Dipende da library_index; elimina via safety_net |
| `video_compression` | todo | — | `DI-006`: primo candidato al de-scope |
| `extra_photo_domains` | todo | — | `DI-007`: indipendente dal cuore-foto |
| `ui_shell` | todo | — | Onboarding-manifesto + report onesto, trasversale |

## 2. Macrotask corrente

- **In corso (build-3)**: `safety_net` — implementazione **completa** dei 3 task
  atomici (T-050/T-051/T-052):
  - **Domain (puro)**: `DeletionFlow` — macchina a stati `idle → previewing →
    confirmed → deleting` con **gate anteprima obbligatoria** (nessuna transizione
    a `confirmed` senza anteprima mostrata *e* accettata; l'insieme confermato
    coincide col previewato). `DeletionSummary` + `DeletionSummaryComposer` —
    riepilogo onesto `{count, libraryBytesFreed, deviceBytesReclaimableNow,
    iCloudCaveat}`, caveat derivato quando i byte device liberabili < byte libreria.
  - **Data**: `AssetDeleting` (protocollo) + `BatchDeletionResult`
    `{success|cancelled|failed}` + `BatchDeletionCoordinator` (su `success` rimuove
    dall'indice, su `cancelled`/`failed` non tocca l'indice) + adapter reale
    `SystemAssetDeleter` guardato `#if canImport(Photos)` (`deleteAssets`, un solo
    alert per batch → "Eliminati di recente").
  - **Test**: `DeletionPreviewGateTests` (AC-050), `DeletionSummaryTests` (AC-052)
    nel Domain puro; `AssetDeletionTests` (AC-051) nel Data con fake deleter + fake
    index writer. Il coordinator è Swift puro: AC-051 girerebbe su Linux se ci fosse
    la toolchain.
  - **Nota dipendenza**: T-052 dichiara `depends_on: [T-051, T-021]`; **T-021 è in
    `dashboard` (todo)**. Il caveat iCloud è modellato al minimo indispensabile in
    `DeletedAssetSize` (byte device vs byte libreria); `dashboard` condividerà lo
    stesso concetto per l'aggregazione. Scelta pragmatica dichiarata (oracolo differito).
- **Verifica — framing onesto (L-COL-006)**:
  - **VERDE (comando reale)**: `validate_blueprint.mjs blueprint` → exit 0.
  - **PENDING al confine Apple**: `swift build -warnings-as-errors` e `swift test`.
    Toolchain Swift **assente** in questa sessione (`swift: command not found`);
    la parte PhotoKit è comunque Apple-only. Nessun verde dichiarato a memoria.
  - **NON COPERTO qui**: `swiftlint`.

- **Storico build-2**: `library_index` — implementazione **completa** dei 5
  task atomici (T-010…T-014):
  - **Domain (puro)**: `PhotoAccess` + policy (T-010), `LibraryAsset` +
    `LibraryAssetMapper` batch cancellabile (T-011), `ByteSize` + policy (T-014),
    `IndexDelta` + `IncrementalIndex.apply` idempotente (T-013), port
    `AssetIndexReading/Writing` + `AssetQuery` (T-012).
  - **Data (adapter guardati `#if canImport`)**: `PhotoLibraryAuthorizing` +
    `SystemPhotoLibraryAuthorizer`, `PhotoAssetEnumerating` +
    `SystemPhotoAssetEnumerator`, `PHAssetByteSizeResolver`,
    `PhotoLibraryChangeObserver`, `@Model AssetRecord` + `SwiftDataAssetIndex`.
  - **Test**: 4 target-test nel Domain puro (AC-010/011/013/014) + 1 nel Data
    (`SwiftDataIndexTests`, AC-012) guardato per SwiftData. Nuovo test target
    `AngavuDataTests`. `NSPhotoLibraryUsageDescription` sincera in Info.plist.
- **Verifica — framing onesto (L-COL-006)**:
  - **VERDE (comando reale)**: `validate_blueprint.mjs blueprint` → exit 0.
  - **PENDING al confine Apple**: `swift build -warnings-as-errors` e `swift test`
    (Domain + `AngavuDataTests`). **Non** eseguibili in questa sessione: la
    toolchain Swift è assente e PhotoKit/SwiftData sono **Apple-only** (non
    compilano su Linux). Nessun verde dichiarato a memoria: il macrotask resta
    `in_progress` finché l'oracolo Swift non gira su toolchain Apple.
  - **NON COPERTO qui**: `swiftlint` (come build-1, §7).
- **Chiuso (build-1)**: `foundation` — scaffold multi-modulo, oracolo di
  altitudine, gate warnings-as-errors, motore cancellabile (`swift build`/`test`
  verdi a build-1).

## 3. Stato git

> Mai lavorare su `main`. Merge gated dal verde apple-skills.

| Campo | Valore |
|---|---|
| Branch di lavoro | `claude/angavu-ios-app-wjq1jf` |
| Ultimo commit | BUILD safety_net (T-050/T-051/T-052, gate anteprima + coordinator, test) |
| Stato merge su `main` | non ancora (gated dal verde apple-skills; `swift build`/`test` + lint da girare su toolchain Apple per library_index + safety_net) |
| Deploy-coupling | `main_deploy_coupled: unknown` — nessun deploy automatico noto (app iOS via App Store Connect, fuori dal repo) |

## 4. Baseline & budget

- **Baseline privacy/sicurezza**: `blueprint/BASELINE-AND-BUDGET.md` — findings accettati / soglie.
- **Budget consumato**: 0 (BOOTSTRAP) / vedi `BASELINE-AND-BUDGET.md`.

## 5. Esiti dell'ultima sessione (framing onesto)

- **BUILD `safety_net` — implementazione completa** (build-3): T-050 (gate
  anteprima `DeletionFlow`), T-051 (`AssetDeleting` + `BatchDeletionCoordinator` +
  `SystemAssetDeleter` guardato), T-052 (`DeletionSummary` onesto con caveat iCloud
  minimo). 3 target-test nuovi (AC-050/051/052).
- **VERDE (comando)**: `validate_blueprint.mjs blueprint` → exit 0.
- **Oracolo Swift PENDING (confine Apple)**: `swift build -warnings-as-errors` e
  `swift test` **non eseguibili** — toolchain Swift assente (`swift: command not
  found`); parte PhotoKit Apple-only. `safety_net` resta `in_progress`. AC-050/052
  (Domain puro) e AC-051 (coordinator Swift puro) girerebbero su Linux con toolchain;
  l'adapter reale `deleteAssets` verificato solo al confine Apple.
- **Debito noto**: T-052 anticipa il caveat iCloud di T-021 (dashboard) con modello
  minimo — `dashboard` dovrà condividere/riusare `DeletedAssetSize`, non duplicarlo.

### Storico build-2 (library_index)

- **BUILD `library_index` — implementazione completa** (build-2): T-010…T-014
  (Domain puro + adapter Data guardati `#if canImport` + 5 target-test + nuovo
  target `AngavuDataTests` + `NSPhotoLibraryUsageDescription`).
- **VERDE (comando)**: `validate_blueprint.mjs blueprint` → exit 0.
- **Oracolo Swift PENDING (confine Apple)**: `swift build -warnings-as-errors` e
  `swift test` **non eseguibili in questa sessione** — toolchain Swift assente e
  PhotoKit/SwiftData Apple-only (non compilano su Linux). Il codice è scritto per
  restare verde su Linux (Data guardato) e per far girare 4/5 target-test nel
  Domain puro; il 5º (SwiftData) gira al confine Apple. **`library_index` resta
  `in_progress`**: nessun verde dichiarato a memoria (L-COL-006). Ri-verifica
  obbligatoria: `swift build`/`test` + `make lint` su toolchain Apple.
- **Foundation (build-1, storico)**: `swift build`/`test` verdi.

### Storico build-1 (foundation)

- **BUILD `foundation` completato** (build-1). Scaffold `Package.swift` a 3 moduli
  (AngavuDomain puro / AngavuData / AngavuFeatures) + app SwiftUI `App/` iOS 17.0.
- Oracoli eseguiti localmente (Swift 6.1.2 Linux, host): `swift build
  -warnings-as-errors` exit 0; `swift test` 11 pass / 2 skip / 0 fail.
- Altitudine imposta dal grafo: import `domain→data` produce errore di build
  (dipendenza circolare) — verificato da `AltitudeGraphTests`.
- **Non coperto qui**: `swiftlint` non installabile nel sandbox (proxy GitHub
  scoped). Dichiarato apertamente (L-COL-006); config + test pronti per il confine
  Apple. Nessun verde finto.
- **Copertura della sessione di chiusura**: nessun nuovo lavoro; solo
  consolidamento. La toolchain Swift **non è disponibile in questo ambiente di
  chiusura**, quindi gli oracoli `swift build`/`swift test` **non sono stati
  ri-eseguiti ora**: vale l'esito registrato a **build-1** (verde, legato ai
  comandi reali sopra). Ri-verifica al prossimo BUILD / al confine Apple
  (`swift build`/`test` + `make lint`). Nessun verde ridichiarato a memoria (L-COL-006).
- Nota toolchain: build/test girano su Swift Linux perché i moduli di
  `foundation` sono piattaforma-puri; PhotoKit/Vision/AVFoundation entrano dai
  macrotask successivi e richiederanno la toolchain Apple.

## 6. Prossimi passi

- Decision ledger **interamente confermato**: nessuna decisione pendente.
- **`library_index` + `safety_net` implementati**, entrambi `in_progress` finché
  l'oracolo Swift non gira al confine Apple.
- **Prossimo macrotask** (prossima sessione): candidati per il DAG (00-INDEX §2)
  che dipendono da `library_index`: `dashboard` (numeri veri + caveat iCloud T-021,
  che T-052 anticipa), `exact_duplicates`. Scelta all'apertura. `dashboard` è ora
  preferibile per chiudere il debito su T-021/T-052.
- **Confine Apple (obbligatorio prima del merge su `main`)**: girare
  `swift build -warnings-as-errors` + `swift test` (chiude `library_index` e
  `safety_net`) e `make lint` (chiude l'oracolo T-003 di `foundation`, oggi non
  coperto). Solo allora il verde è reale e il merge valutabile.
