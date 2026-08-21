# SESSION-STATE — Angavu iOS

> Fonte di verità sullo **stato vivo del progetto**, consumata da BUILD
> (apple-skills) e aggiornata a ogni chiusura di sessione. Distinta dalla
> SESSION-STATE interna di Trueline. Prosa in italiano, identificatori in inglese.

| | |
|---|---|
| **Progetto** | Angavu iOS |
| **Ecosistema** | swift-ios (SwiftUI + SwiftData + PhotoKit/Vision/AVFoundation) |
| **Ultimo aggiornamento** | 2026-08-21 (BUILD library_index — implementazione, oracolo Swift pending) |
| **Sessione corrente** | build-2 (`library_index`) **chiusa**: codice completo, `swift build`/`test` pending al confine Apple; prossima sessione → prossimo macrotask |

---

## 1. Stato dei macrotask

> Stati: `todo` | `in_progress` | `done`. Ordine del piano di build (00-INDEX §2).
> Il checkpoint qui è la **verifica apple-skills** (swift build/test, SwiftLint,
> grafo moduli), non un checkpoint Trueline (policy di repo).

| Macrotask | Stato | Checkpoint | Note |
|---|---|---|---|
| `foundation` | done | swift build/test verdi (build-1) | T-001…T-004 chiusi; lint SwiftLint dichiarato non coperto qui (§7) |
| `library_index` | in_progress | oracolo Swift **pending** (confine Apple) | T-010…T-014 implementati; blueprint validator exit 0; `swift build`/`test` non eseguibili qui (no toolchain + PhotoKit/SwiftData Apple-only) |
| `dashboard` | todo | — | Dipende da library_index |
| `safety_net` | todo | — | Dipende da library_index (rete di sicurezza intoccabile) |
| `exact_duplicates` | todo | — | Dipende da library_index; elimina via safety_net |
| `similar_photos` | todo | — | Dipende da library_index; elimina via safety_net |
| `large_old_media` | todo | — | Dipende da library_index; elimina via safety_net |
| `blurry_photos` | todo | — | Dipende da library_index; elimina via safety_net |
| `video_compression` | todo | — | `DI-006`: primo candidato al de-scope |
| `extra_photo_domains` | todo | — | `DI-007`: indipendente dal cuore-foto |
| `ui_shell` | todo | — | Onboarding-manifesto + report onesto, trasversale |

## 2. Macrotask corrente

- **In corso**: `library_index` (build-2) — implementazione **completa** dei 5
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
| Ultimo commit | BUILD library_index (T-010…T-014, adapter guardati, test) |
| Stato merge su `main` | non ancora (gated dal verde apple-skills; `swift build`/`test` + lint da girare su toolchain Apple) |
| Deploy-coupling | `main_deploy_coupled: unknown` — nessun deploy automatico noto (app iOS via App Store Connect, fuori dal repo) |

## 4. Baseline & budget

- **Baseline privacy/sicurezza**: `blueprint/BASELINE-AND-BUDGET.md` — findings accettati / soglie.
- **Budget consumato**: 0 (BOOTSTRAP) / vedi `BASELINE-AND-BUDGET.md`.

## 5. Esiti dell'ultima sessione (framing onesto)

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
- **`library_index` implementato** (build-2), `in_progress` finché l'oracolo Swift
  non gira al confine Apple.
- **Prossimo macrotask** (prossima sessione): un nodo che dipende da
  `library_index` — candidati per il DAG (00-INDEX §2): `safety_net` (rete di
  sicurezza, intoccabile e propedeutica a ogni eliminazione), `exact_duplicates`,
  `dashboard`. Scelta all'apertura.
- **Confine Apple (obbligatorio prima del merge su `main`)**: girare
  `swift build -warnings-as-errors` + `swift test` (chiude `library_index`) e
  `make lint` (chiude l'oracolo T-003 di `foundation`, oggi non coperto). Solo
  allora il verde è reale e il merge valutabile.
