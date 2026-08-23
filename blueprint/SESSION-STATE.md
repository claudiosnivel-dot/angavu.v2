# SESSION-STATE — Angavu iOS

> Fonte di verità sullo **stato vivo del progetto**, consumata da BUILD
> (apple-skills) e aggiornata a ogni chiusura di sessione. Distinta dalla
> SESSION-STATE interna di Trueline. Prosa in italiano, identificatori in inglese.

| | |
|---|---|
| **Progetto** | Angavu iOS |
| **Ecosistema** | swift-ios (SwiftUI + SwiftData + PhotoKit/Vision/AVFoundation) |
| **Ultimo aggiornamento** | 2026-08-23 (BUILD `wiring` **completo 8/8**, CI verde run #17→#25) |
| **Sessione corrente** | **Chiusa sul verde**. Macrotask `wiring` **done, 8/8**: T-110 (run #17), T-111 (run #19), T-112 (run #20), T-113 (run #21), T-114 (run #22), T-115 (run #23), T-116 (run #24), T-117 (run #25) — tutti `success` in CI. **Piano di build 11/11 + `wiring` (DI-009) completi.** Nessun macrotask residuo: prossimi passi = rigenerare l'`.ipa`, merge su `main` (decisione utente), release-review pre-App-Store |

---

## 1. Stato dei macrotask

> Stati: `todo` | `in_progress` | `done`. Ordine del piano di build (00-INDEX §2).
> Il checkpoint qui è la **verifica apple-skills** (swift build/test, SwiftLint,
> grafo moduli), non un checkpoint Trueline (policy di repo).

| Macrotask | Stato | Checkpoint | Note |
|---|---|---|---|
| `foundation` | done | **CI verde** (build+test+lint, run #3) | T-001…T-004 chiusi; lint SwiftLint ora **coperto** in CI (non più solo sandbox) |
| `library_index` | done | **CI verde** (build+test+lint, run #3) | T-010…T-014; AC-010/011/012/013/014 verdi (SwiftData test incluso su runner macOS 14) |
| `dashboard` | done | **CI verde** (build+test+lint, run #6) | T-020/T-021/T-022 (Domain puro) + 3 target-test (AC-020-1/2, AC-021-1/2, AC-022-1/2). T-021 riusa `DeletedAssetSize` (no duplicazione) |
| `safety_net` | done | **CI verde** (build+test+lint, run #3) | T-050/T-051/T-052; gate anteprima + eliminazione batch verificati. T-052 anticipa il caveat iCloud (T-021, dashboard) con modello minimo |
| `exact_duplicates` | done | **CI verde** (build+test+lint+app iOS, run #7) | T-030/T-031/T-032; candidati per byte-size, cluster SHA-256 (hashing cancellabile T-004), keep-one deterministico. Adapter reale `PHAssetContentHasher` compilato in CI (streaming SHA256, zero rete); AC-030/031/032 verdi via target_tests Domain puro |
| `similar_photos` | done | **CI verde** (build+test+lint+app iOS, run #8) | T-040/T-041/T-042/T-043; feature print Vision dietro port, clustering greedy per soglia con fallback dHash/Hamming (cancellabile T-004), best-of-cluster e `DeletionProposal`. Adapter reali (`VisionFeaturePrinter`/`PerceptualDHasher`/`VisionQualityScorer`) compilati in CI; AC-040/041/042/043 verdi via target_tests Domain puro |
| `large_old_media` | done | **CI verde** (build+test+lint+app iOS, run #9) | T-060/T-061/T-062; interamente Domain puro. Video grandi+vecchi (soglie congiunte, ordine size desc→età), categorie screenshot (subtype indicizzato) + screen recording (euristica dichiarata sulle risoluzioni schermo iniettate), proposta in blocco (keep vuoto) nel gate anteprima (T-050). AC-060/061/062 verdi via target_tests Domain puro; nessun adapter Apple-only |
| `blurry_photos` | done | **CI verde** (build+test+lint+app iOS, run #10) | T-070/T-071; nitidezza dietro `SharpnessScoring` + soglia (regola di confine: strettamente sotto = blurry; alla soglia/non calcolabile = non blurry), aesthetics iOS 18 come progressive enhancement (`BlurScore`). Riusa `VisionQualityScorer` (esteso ad `AestheticsScoring`) + kernel nitidezza/pixel condiviso. AC-070/071 verdi via target_tests Domain puro |
| `video_compression` | done | **CI verde** (build+test+lint+app iOS, run #11) | T-080/T-081/T-082; stima `estimated` + gate opt-in, export HEVC cancellabile (adapter AVFoundation guardato, API async iOS18/macOS15), sostituzione solo dopo export verificato + anteprima via DeletionFlow. AC-080/081/082 verdi via target_tests (HEVCExportTests via fake) |
| `extra_photo_domains` | done | **CI verde** (build+test+lint+app iOS, run #12) | T-090/T-091/T-092; `DI-007`. Contatti duplicati (cluster per nome normalizzato + numero/email condiviso), calendari-spam (solo sottoscrizioni sospette, mai i locali), applicazione confermata (gate `proposed→confirmed`, esito applied/cancelled/failed). Domain puro; adapter Contacts/EventKit guardati (compilati in CI, runtime device non coperto). NS…UsageDescription contatti/calendario sincere |
| `ui_shell` | done | **CI verde** (build+test+lint+app iOS, run #13) | T-100/T-101/T-102. Manifesto+non-goals come dati (coerenti VISION §4), navigazione col gate anteprima (unico `DeletionEntryPoint`→`DeletionFlow`), `HonestReport`. Design HIG: brand token "Aurora" dall'Android ricostruiti nativi (`AuroraTheme`) + 3 schermate SwiftUI. AC-100/101/102 verdi via target_tests; nuovo target `AngavuFeaturesTests` |
| `wiring` | done | **CI verde** run #17→#25 (T-110…T-117, tutti `success`) | **8/8**: T-110 composition root (`AppEnvironment`+`live`), T-111 `ScanViewModel`, T-112 `DashboardViewModel`, T-113 `CategoryReviewViewModel` (delete via `DeletionFlow`), T-114 `HonestReportViewModel` (+`LibraryFiguresReader` condiviso), T-115 `ContactsReviewViewModel`/`CalendarsReviewViewModel`, T-116 `CompressionViewModel`, T-117 `ScreenResolutionProviding`+factory. Fix lungo il percorso: `AnalysisProgress: Sendable`. Seam onesta caveat iCloud: `DeviceStorageInspecting` (residenza best-effort, raffinabile) |

## 2. Macrotask corrente

> **Piano di build completo (11/11) + `wiring` (DI-009) completo (8/8).** Nessun
> macrotask aperto: l'ultimo, `wiring`, è verde in CI (run #25). Le prossime
> sessioni non hanno un "macrotask corrente" da costruire — solo rigenerazione
> dell'`.ipa`, merge su `main` (decisione utente), release-review pre-App-Store, o
> rifinitura design/animazioni HIG.

- **Chiuso (wiring, DI-009)**: cablaggio dati completo — 7 view-model/seam dietro
  i port dell'`AppEnvironment`, tutti verificati dai target_tests in
  `AngavuFeaturesTests` (le View SwiftUI dal build app in CI). Altitudine invariata
  (Domain puro). Dettaglio in §5 (Storico wiring).

- **Chiuso (build-11)**: `ui_shell` — implementazione **completa** dei 3 task
  atomici (T-100/T-101/T-102). Domain puro + Features platform-puro (verificati dai
  target_tests) + presentazione SwiftUI nativa HIG guardata `#if canImport(SwiftUI)`:
  - **T-100 — manifesto e "cosa NON facciamo" come dati**: `ManifestContent`
    (`Sources/AngavuDomain/ManifestContent.swift`) con `ManifestPromise`/`NonGoal`
    (id stabili), derivati voce per voce dal VISION-AND-CONSTRAINTS §4. Invarianti di
    onestà: un non-goal è **rinuncia**, mai claim di capacità
    (`anyNonGoalClaimsCapability` falso, AC-100-2), e ogni promessa è mantenibile
    on-device (`allPromisesAchievableOnDevice`, AC-100-2); i non-goals includono per
    id "niente cache di sistema", "no ads", "zero backend" (AC-100-1).
  - **T-101 — navigazione col gate anteprima**: `Sources/AngavuFeatures/Navigation.swift`.
    `AppSection` + **unico** `DeletionEntryPoint.route` che pilota il `DeletionFlow`
    condiviso (T-050); `SectionNavigator` mappa solo le sezioni che eliminano asset
    (le read-only → nil). Ogni percorso passa da `previewing` prima di `confirmed`
    (AC-101-1/2), nessun bypass — provato dalla traccia degli stati.
  - **T-102 — report onesto**: `HonestReport`/`HonestReportComposer`
    (`Sources/AngavuDomain/HonestReport.swift`) compone `DashboardAggregate` +
    `ReclaimableSpace` + `PhotoAccessDecision` senza coniare tipi nuovi. Con porzione
    stimata `singleExactTotalBytes == nil` (mai un unico totale "esatto"), caveat
    iCloud segnalato, e con accesso limited conteggi parziali + invito all'accesso
    completo (AC-102-1/2).
  - **Design HIG (promemoria macrotask)**: brand token d'**identità** "Aurora"
    estratti dall'Android (`ui/theme/Color.kt`: accenti viola/fucsia/blu/azzurro +
    gradiente + glow) e **ricostruiti nativi** in `AuroraTheme` — colori semantici di
    sistema per fondi/testo, SF Symbols, tipografia di sistema/Dynamic Type, dark mode.
    Lo scaffolding Material 3 **non** è stato portato. Schermate
    `OnboardingManifestoView`, `NonGoalsView`, `HonestReportView`; `App/ContentView`
    collega onboarding → home → "cosa NON facciamo".
  - **Test**: `ManifestContentTests` (AC-100-1/2 + guardie non vacue),
    `NavigationPreviewGateTests` (AC-101-1/2 + gate non aggirabile + selezione vuota,
    nel nuovo target `AngavuFeaturesTests`), `HonestReportTests` (AC-102-1/2) —
    Domain/Features puri, girano ovunque.
  - **Copertura dichiarata**: le 3 schermate SwiftUI + `AuroraTheme` sono **compilate**
    dai due job CI (`swift build` su macOS + build app iOS) ma **senza test di
    rendering** (styling out_of_scope dei target_tests): resa a runtime non coperta,
    solo compilazione. Baseline privacy invariata (nessun nuovo permesso/rete).
- **Verifica — VERDE (comando reale, L-COL-002/006)**: **CI Apple run #13 `success`**
  (commit `82b431b`, runner `macos-15`), entrambi i job verdi step per step —
  `swift build` (warnings-as-errors), `swift test` (target_tests + regressione),
  `swiftlint lint --strict` + `build app (iOS Simulator)`. `validate_blueprint.mjs
  blueprint` → exit 0.

- **Chiuso (build-10)**: `extra_photo_domains` (`DI-007`) — implementazione
  **completa** dei 3 task atomici (T-090/T-091/T-092), Domain puro
  (`Sources/AngavuDomain/DuplicateContacts.swift`, `SpamCalendars.swift`,
  `ExtraDomainApply.swift`) + adapter Data guardati
  (`Sources/AngavuData/ContactsProvider.swift`, `CalendarsProvider.swift`):
  - **T-090 — contatti duplicati dietro adapter Contacts**: port `ContactsProviding`
    (Data) + `DuplicateContactDetection` (Domain). Regola dichiarata: duplicati sse
    **stesso nome normalizzato E** almeno un punto di contatto (numero/email
    normalizzato) condiviso — omonimi senza contatto condiviso **mai** fusi (nessun
    falso positivo, AC-090-1). `ContactMergeProposal {primary=id minore, duplicates}`
    è **solo dati** (AC-090-2). Adapter reale `SystemContactMerger` (CNSaveRequest:
    fonde punti di contatto ed elimina i duplicati).
  - **T-091 — calendari-spam dietro adapter EventKit**: port `CalendarsProviding`
    (Data) + `SpamCalendarDetection` (Domain) con `SpamCalendarHeuristic` **dichiarata**
    (sospetto sse `kind == .subscription` e — se forniti — titolo con marcatori; i
    calendari locali **mai** toccati, AC-091-1). `SpamCalendarRemovalProposal` solo
    dati (AC-091-2). Adapter reale `SystemCalendarsProvider` (map `EKCalendarType`) +
    `SystemCalendarSubscriptionRemover` (`EKEventStore.removeCalendar`).
  - **T-092 — applicazione confermata**: `ExtraActionConfirmation` (gate
    `proposed→confirmed`) + `ExtraActionApplicator`. Senza conferma l'adapter non è
    **mai** invocato → esito `.cancelled` (AC-092-1); con conferma delega e propaga
    l'esito reale `applied|cancelled|failed` (AC-092-2). Port dei side-effect
    (`ContactMerging`, `CalendarSubscriptionRemoving`) nel Domain, fake-abili.
  - **Altitudine/privacy**: il Domain non importa Contacts/EventKit (00-INDEX §1bis);
    `NSContactsUsageDescription` + `NSCalendarsFullAccessUsageDescription` sincere in
    Info.plist; `PrivacyInfo.xcprivacy` con framing onesto (Contacts/EventKit sono
    permission-gated, **non** required-reason API → array vuoto per verità, non per
    dimenticanza). Azioni distruttive human-gated (L-COL-005), zero rete.
  - **Test**: `DuplicateContactsTests` (AC-090-1/2 + omonimi non fusi + email
    condivisa), `SpamCalendarsTests` (AC-091-1/2 + locale con marcatore mai spam +
    default conservativo), `ExtraDomainApplyTests` (AC-092-1/2 + failure propagata +
    gate idempotente) — tutti Domain puro via fake dei port, girano su Linux.
  - **Copertura dichiarata**: i 4 adapter (`SystemContactsProvider`,
    `SystemContactMerger`, `SystemCalendarsProvider`,
    `SystemCalendarSubscriptionRemover`) sono **compilati** in CI ma **senza test
    unitario dedicato** (Apple-only, richiedono rubrica/calendario reali): runtime sul
    device NON coperto, solo compilazione. Dichiarato apertamente.
- **Verifica — VERDE (comando reale, L-COL-002/006)**: **CI Apple run #12 `success`**
  (commit `f742aad`, runner `macos-15`), entrambi i job verdi step per step —
  `swift build` (warnings-as-errors), `swift test` (target_tests + regressione),
  `swiftlint lint --strict` + `build app (iOS Simulator)`. `validate_blueprint.mjs
  blueprint` → exit 0.

- **Storico (build-8)**: `blurry_photos` — implementazione **completa** dei 2 task
  atomici (T-070/T-071), Domain puro (`Sources/AngavuDomain/BlurryPhotos.swift`) +
  adapter Data guardati:
  - **T-070 — nitidezza dietro adapter + soglia**: port `SharpnessScoring` (`Double?`;
    `nil` = non calcolabile on-device) + `BlurThreshold` + `BlurClassification`.
    **Regola di confine dichiarata** (AC-070-2): `blurry` sse nitidezza
    **strettamente sotto** soglia; **alla** soglia o **non calcolabile** → NON sfocato
    (nessun falso positivo su asset non verificabili). Batch `blurry(among:)` a blocchi
    cancellabili (motore T-004), solo foto (i video esclusi). Adapter reale
    `CoreImageSharpnessScorer` (varianza del Laplaciano) via kernel condiviso.
  - **T-071 — aesthetics come progressive enhancement iOS 18**: port `AestheticsScoring`
    + `BlurScore {sharpness, aesthetics?}` con `usesAesthetics`/`combined` +
    `BlurAssessment.assess`. Su iOS 18 il termine aesthetics concorre (AC-071-1); su
    iOS 17 (`aesthetics == nil`) degrada alla sola nitidezza, marcato "senza aesthetics",
    senza fallire (AC-071-2). `assess` → `nil` solo se la nitidezza non è calcolabile.
    Reuse: `VisionQualityScorer` (di `similar_photos`) esteso ad `AestheticsScoring`.
  - **Reuse/altitudine**: estratti `SharpnessKernel` (matematica nitidezza) e
    `OnDeviceImageBytes` (lettura pixel zero-rete) in
    `Sources/AngavuData/ImageAnalysisSupport.swift`, condivisi con `VisionQualityScorer`
    (rifattorizzato a comportamento identico): un solo posto per nitidezza e pixel. Il
    Domain non importa Core Image/Vision (00-INDEX §1bis).
  - **Test**: `BlurClassificationTests` (AC-070-1/2 + `nil` mai flaggato + batch
    foto/cancel), `AestheticsEnhancementTests` (AC-071-1/2 + `assess` nil senza
    nitidezza) — tutti Domain puro, girano su Linux.
  - **Copertura dichiarata**: gli adapter (`CoreImageSharpnessScorer`, conformità
    aesthetics di `VisionQualityScorer`) sono **compilati** in CI ma **senza test
    unitario dedicato** (Apple-only, richiedono foto reali/device): runtime sul device
    NON coperto, solo compilazione. Dichiarato apertamente.
- **Verifica — VERDE (comando reale, L-COL-002/006)**: **CI Apple run #10 `success`**
  (commit `38df675`, runner `macos-15`), entrambi i job verdi step per step —
  `swift build` (warnings-as-errors), `swift test` (target_tests + regressione),
  `swiftlint lint --strict` + `build app (iOS Simulator)`. `validate_blueprint.mjs
  blueprint` → exit 0.

- **Storico (build-7)**: `large_old_media` — implementazione **completa** dei 3 task
  atomici (T-060/T-061/T-062), **interamente Domain puro**
  (`Sources/AngavuDomain/LargeOldMedia.swift`), nessun adapter Data:
  - **T-060 — video grandi e vecchi**: `LargeOldThresholds {minBytes,
    olderThanOrEqualTo}` (soglie **congiunte**: grande *e* vecchio) +
    `LargeOldVideoSelection.select` su `[SizedAsset]` — filtra i soli `.video`
    oltre entrambe le soglie e ordina deterministicamente (dimensione desc, poi
    età più-vecchio-prima, poi id). Un video senza `creationDate` non è
    verificabile come vecchio → **escluso** (nessun falso positivo, AC-060-2).
  - **T-061 — screenshot e screen recording**: `ScreenshotCategory.screenshots`
    filtra dal subtype `.screenshot` già indicizzato da `library_index` (T-011);
    `ScreenRecordingHeuristic` è **euristica dichiarata** — un video le cui
    dimensioni pixel coincidono (orientamento a parte) con una risoluzione schermo
    nota **iniettata dal chiamante** (Domain puro, nessun tipo di piattaforma).
    Una foto non è mai screen recording (AC-061-1/2).
  - **T-062 — proposta in blocco**: `BulkDeletionProposal {removable, keep vuoto}`
    (categoria a **eliminazione diretta**: non si "tiene la migliore") +
    `BulkDeletionProposalComposer.presentInSafetyNet` che porta il `DeletionFlow`
    (T-050) in `previewing` — la conferma resta impossibile senza anteprima
    mostrata *e* accettata: nessuna eliminazione in autonomia (AC-062-1/2).
  - **Test**: `LargeOldVideoTests` (AC-060-1/2, incl. esclusione senza data e
    tie-break età), `ScreenshotCategoryTests` (AC-061-1/2), `BulkDeletionProposalTests`
    (AC-062-1/2, incl. gate anteprima) — tutti Domain puro, girano su Linux.
  - **Copertura dichiarata**: macrotask **interamente Domain puro** → nessun adapter
    Apple-only, nessun caveat "compilato-ma-non-testato". L'euristica screen-recording
    dipende dalle risoluzioni schermo reali iniettate a runtime (cablaggio in
    `ui_shell`/Data, fuori scope qui): dichiarato apertamente.
- **Verifica — VERDE (comando reale, L-COL-002/006)**: **CI Apple run #9 `success`**
  (commit `9090c7f`, runner `macos-15`), entrambi i job verdi step per step —
  `swift build` (warnings-as-errors), `swift test` (target_tests + regressione),
  `swiftlint lint --strict` + `build app (iOS Simulator)`. `validate_blueprint.mjs
  blueprint` → exit 0.

- **Storico (build-6)**: `similar_photos` — implementazione **completa** dei 4 task
  atomici (T-040/T-041/T-042/T-043), Domain puro (`Sources/AngavuDomain/SimilarPhotos.swift`)
  + 3 adapter Data guardati:
  - **T-040 — feature print + distanza semantica**: port `FeaturePrinting` nel
    Domain (esagonale, come `AssetContentHashing`); il Domain riceve SOLO un `Float`
    di distanza (`SemanticDistance.between`), non importa Vision (AC-040-2 provato da
    una scansione dei sorgenti Domain). Adapter reale `VisionFeaturePrinter`
    (`VNGenerateImageFeaturePrintRequest` + `computeDistance`), pixel on-device con
    `isNetworkAccessAllowed=false` (zero rete), cache per-id.
  - **T-041 — clustering per soglia con fallback dHash**: `SimilarClustering.clusters`
    — passaggio incrementale greedy deterministico (ogni candidato entra nel primo
    cluster il cui rappresentante è simile), a blocchi **cancellabili** (motore
    T-004). Priorità alla distanza semantica; **fallback** dHash/Hamming quando il
    feature print manca; un asset senza feature print né dHash non è mai raggruppato
    (nessun falso "via libera"). dHash a 64 bit prodotto da `PerceptualDHasher`
    (ImageIO/CoreGraphics, 9×8 grigi, cross-Apple); la distanza di Hamming è
    aritmetica pura nel Domain.
  - **T-042 — best-of-cluster ("tieni la migliore")**: port `QualityScoring` +
    `QualityScore {sharpness, faceQuality?, aesthetics?}` (aesthetics **solo iOS 18**,
    progressive enhancement: assente su iOS 17, `overall` omette il termine senza
    fallire) + `ClusterQualityRanking.ranked` (migliore per punteggio, tie-break per
    id). Adapter reale `VisionQualityScorer` (varianza del Laplaciano in CoreGraphics
    + `VNDetectFaceCaptureQuality` + `VNCalculateImageAestheticsScores` guardato `#available`).
  - **T-043 — proposta di eliminazione**: `DeletionProposal {keep, removable}` per
    cluster, **solo dati** per `safety_net`; cluster singolo → removable vuoto;
    nessuna eliminazione in autonomia (anteprima obbligatoria a valle, T-050).
  - **Test**: `FeatureDistanceTests` (AC-040-1/2, incl. scansione no-import-Vision),
    `SimilarClusterTests` (AC-041-1/2/3, con recorder che prova i residui non
    processati su cancel), `KeepBestScoringTests` (AC-042-1/2), `SimilarDeletionProposalTests`
    (AC-043-1/2) — tutti Domain puro, girano su Linux.
  - **Copertura dichiarata**: i 3 adapter (`VisionFeaturePrinter`, `PerceptualDHasher`,
    `VisionQualityScorer`) sono **compilati** in CI (runner `macos-15`) ma **senza
    test unitario dedicato** (Apple-only, richiedono foto reali/device): correttezza
    a runtime NON coperta, solo compilazione. Dichiarato apertamente.
- **Verifica — VERDE (comando reale, L-COL-002/006)**: **CI Apple run #8 `success`**
  (commit `7aee6d1`, runner `macos-15`), entrambi i job verdi step per step —
  `swift build` (warnings-as-errors), `swift test` (target_tests + regressione),
  `swiftlint lint --strict` + `build app (iOS Simulator)`. `validate_blueprint.mjs
  blueprint` → exit 0.

- **Storico (build-5)**: `exact_duplicates` — implementazione **completa** dei 3
  task atomici (T-030/T-031/T-032), Domain puro (`Sources/AngavuDomain/ExactDuplicates.swift`)
  + adapter Data guardato (`Sources/AngavuData/AssetContentHashingAdapter.swift`):
  - **T-030 — candidati per dimensione**: `SizeCandidateGroup` +
    `SizeCandidateGrouping.candidateGroups` — raggruppa per byte-size, restituisce
    solo i gruppi con cardinalità > 1 (un asset di dimensione unica non ha
    duplicati → niente hashing). Ordine deterministico per dimensione crescente.
  - **T-031 — cluster SHA-256**: port `AssetContentHashing` + `AssetDigest` nel
    Domain (esagonale, come `AssetIndexReading/Writing`); `ExactDuplicateClustering.clusters`
    hasha i candidati **a blocchi cancellabili** riusando il motore T-004
    (`ChunkedAnalysis`), raggruppa per digest identico, esclude i non hashabili
    (nessun falso "via libera"). Adapter reale `PHAssetContentHasher` guardato
    `#if canImport(Photos) && canImport(CryptoKit)`: legge i byte on-device in
    **streaming** (`SHA256.update`, dieta low-RAM), `isNetworkAccessAllowed=false`
    (zero rete, nessun fetch iCloud).
  - **T-032 — keep-one**: `KeepOneProposal` + `KeepOneSelection` — proposta
    deterministica (keep = id minore, arbitrario ma stabile); **nessuna
    eliminazione**, solo dati per `safety_net` (anteprima obbligatoria a valle).
  - **Test**: `SizeCandidateGroupingTests` (AC-030-1/2), `ExactDuplicateClusterTests`
    (AC-031-1/2, con fake hasher che prova la non-hashatura dei residui su cancel),
    `KeepOneSelectionTests` (AC-032-1/2) — tutti Domain puro, girano su Linux.
  - **Copertura dichiarata**: `PHAssetContentHasher` è **compilato** in CI (runner
    `macos-15`) ma **senza test unitario dedicato** (Apple-only, richiede foto
    reali/device): correttezza a runtime sul device NON coperta, solo compilazione.
- **Verifica — VERDE (comando reale, L-COL-002/006)**: **CI Apple run #7 `success`**
  (commit `497f463`, runner `macos-15`), entrambi i job verdi step per step —
  `swift build/test/lint` (Build warnings-as-errors, Test target_tests+regressione,
  SwiftLint) + `build app (iOS Simulator)`. `validate_blueprint.mjs blueprint` → exit 0.

- **Storico (build-4)**: `dashboard` — implementazione **completa** dei 3 task
  atomici (T-020/T-021/T-022), tutto nel **Domain puro** (`Sources/AngavuDomain/Dashboard.swift`):
  - **T-020 — aggregazione numeri veri**: `DashboardCategory` (photo/video/screenshot,
    **disgiunte**: uno screenshot non è anche foto), `SizedAsset` (accoppia
    `LibraryAsset` + `ByteSize` senza toccare l'indice Data → altitudine
    preservata), `CategoryBytes` con **quota exact separata da estimated** (mai
    fuse in un "esatto"), `DashboardAggregator.aggregate`.
  - **T-021 — caveat iCloud**: `ReclaimableSpace` (`reclaimableLibrarySpace` vs
    `reclaimableDeviceSpaceNow`, caveat derivato quando device < libreria) +
    `ReclaimableSpaceCalculator` guidato da `ICloudOptimizeStorage`. **Riusa
    `DeletedAssetSize`** anticipato da T-052 (debito noto saldato, no duplicazione).
  - **T-022 — banner limited**: `DashboardBanner` + `DashboardBannerPolicy` che
    riusa `PhotoAccessPolicy` (unica fonte di `isPartialCount`).
  - **Test**: `DashboardAggregateTests` (AC-020-1/2), `ICloudCaveatTests`
    (AC-021-1/2), `LimitedAccessBannerTests` (AC-022-1/2) — tutti Domain puro,
    girano su Linux con toolchain.
  - **Nota debito saldato**: T-052 aveva anticipato il caveat iCloud con
    `DeletedAssetSize`; `dashboard` lo **condivide** invece di duplicarlo.
- **Verifica — VERDE (comando reale, L-COL-006)**:
  - `validate_blueprint.mjs blueprint` → exit 0 (oracolo strutturale).
  - **CI Apple run #6 `success`** (commit `7969aaf`, runner `macos-15`): job
    `swift build/test/lint` verde (Build warnings-as-errors, Test target_tests +
    regressione, SwiftLint) + job `build app (iOS Simulator)` verde. Il verdetto
    è di un **comando** (L-COL-002), verificabile nella tab Actions.

- **Storico build-3**: `safety_net` — implementazione **completa** dei 3 task
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
| Ultimo commit | `8241a0e` feat(wiring) T-117 — CI verde (run #25); `wiring` 8/8 chiuso |
| Stato merge su `main` | **gate soddisfatto**: CI Apple verde (build+test+lint+app iOS) su **tutti gli 11 macrotask + `wiring` (8/8)**. Merge non ancora eseguito (decisione dell'utente); il branch è mergeabile |
| Deploy-coupling | `main_deploy_coupled: unknown` — nessun deploy automatico noto (app iOS via App Store Connect, fuori dal repo) |

## 4. Baseline & budget

- **Baseline privacy/sicurezza**: `blueprint/BASELINE-AND-BUDGET.md` — findings accettati / soglie.
- **Budget consumato**: 0 (BOOTSTRAP) / vedi `BASELINE-AND-BUDGET.md`.

## 5. Esiti dell'ultima sessione (framing onesto)

- **BUILD `wiring` (DI-009) — completo 8/8** (questa sessione, T-112→T-117; T-110/T-111
  già chiusi): cablaggio dei dati veri in view-model osservabili dietro i port
  dell'`AppEnvironment`, verificati dai target_tests in `AngavuFeaturesTests`.
  - **T-112 `DashboardViewModel`** (run #20): righe categoria coi byte veri
    exact/estimated separati, banner limited, spazio recuperabile. Nuovo port onesto
    `DeviceStorageInspecting` iniettato senza default nascosto.
  - **T-113 `CategoryReviewViewModel`** (run #21): normalizza le 4 proposte
    (KeepOne/Deletion/Bulk/blurry) in keep/removable e instrada OGNI eliminazione al
    `DeletionFlow` (keep mai eliminati; nessuna anteprima vuota).
  - **T-114 `HonestReportViewModel`** (run #22): report onesto (device vs libreria +
    caveat iCloud). Estratto `LibraryFiguresReader` condiviso con la dashboard
    (meno duplicazione; `DashboardViewModel` rifattorizzato a comportamento identico).
  - **T-115 `ContactsReviewViewModel`/`CalendarsReviewViewModel`** (run #23): proposte
    extra-foto confermabili; applicazione dietro il gate `proposed→confirmed` (T-092);
    calendari locali mai toccati.
  - **T-116 `CompressionViewModel`** (run #24): stima → gate opt-in → export → (su
    success verificato + anteprima confermata) sostituzione con originale instradato
    al `DeletionFlow`. Nessun avvio senza consenso; nessuna perdita di dati.
  - **T-117 `ScreenResolutionProviding` + factory** (run #25): l'euristica
    screen-recording (T-061) consuma le risoluzioni dal provider invece di hardcoded.
- **VERDE (comando)**: **CI Apple run #17→#25 tutti `success`** (ultimo commit
  `8241a0e`), entrambi i job — `swift build -warnings-as-errors`, `swift test`,
  `swiftlint lint --strict` + `build app (iOS Simulator)`. Il verdetto è di un
  **comando** (L-COL-002), verificabile nella tab Actions.
- **Copertura dichiarata (L-COL-006)**: AC-110…117 coperti dai target_tests
  Domain/Features puri (`swift test`) in `AngavuFeaturesTests`. Le View SwiftUI sono
  **compilate** dal build app in CI ma **senza test di rendering**: resa a runtime non
  coperta. `DeviceStorageInspecting` reale è compilato in CI ma la residenza per-asset
  è **best-effort** (device==libreria), raffinabile con residenza iCloud reale (async):
  runtime device non coperto. Baseline privacy invariata (nessun nuovo permesso/rete).

- **BUILD `ui_shell` — implementazione completa** (build-11): T-100 (manifesto +
  non-goals come dati coerenti col VISION §4, con invarianti di onestà: rinuncia mai
  claim, promesse on-device), T-101 (navigazione con unico `DeletionEntryPoint` che
  attraversa il gate `previewing→confirmed`, nessun bypass), T-102 (`HonestReport`:
  stima marcata, caveat iCloud, conteggio parziale con invito all'accesso completo).
  Design HIG: brand token "Aurora" dall'Android ricostruiti nativi (`AuroraTheme`) +
  schermate `OnboardingManifestoView`/`NonGoalsView`/`HonestReportView`.
- **VERDE (comando)**: **CI Apple run #13 `success`** (commit `82b431b`), entrambi i
  job — `swift build/test/lint` + `build app (iOS Simulator)`; `validate_blueprint.mjs
  blueprint` → exit 0. `ui_shell` → `done`. **Piano di build completo (11/11).**
- **Copertura**: AC-100/101/102 coperti dai target_tests Domain/Features puri
  (`swift test`), incluso il nuovo target `AngavuFeaturesTests`. Le 3 schermate SwiftUI
  + `AuroraTheme` compilate dai due job ma senza test di rendering (styling out_of_scope):
  resa a runtime non coperta, solo compilazione. Baseline privacy invariata (nessun
  nuovo permesso/rete). Dichiarato apertamente.

### Storico build-10 (extra_photo_domains)

- **BUILD `extra_photo_domains` — implementazione completa** (build-10): T-090
  (contatti duplicati dietro `ContactsProviding`, cluster per nome normalizzato +
  numero/email condiviso, `ContactMergeProposal` solo dati), T-091 (calendari-spam
  dietro `CalendarsProviding`, solo sottoscrizioni sospette con euristica dichiarata,
  mai i locali, `SpamCalendarRemovalProposal` solo dati), T-092 (`ExtraActionConfirmation`
  gate + `ExtraActionApplicator`: senza conferma nessun effetto → `.cancelled`; con
  conferma propaga `applied|cancelled|failed`). Domain puro; adapter Contacts/EventKit
  guardati. Altitudine preservata: il Domain non importa Contacts/EventKit.
- **VERDE (comando)**: **CI Apple run #12 `success`** (commit `f742aad`), entrambi
  i job — `swift build/test/lint` + `build app (iOS Simulator)`; `validate_blueprint.mjs
  blueprint` → exit 0. `extra_photo_domains` → `done`.
- **Copertura**: AC-090/091/092 coperti dai target_tests Domain puri (`swift test`).
  I 4 adapter (`SystemContactsProvider`, `SystemContactMerger`, `SystemCalendarsProvider`,
  `SystemCalendarSubscriptionRemover`) compilati in CI ma senza test unitario dedicato
  (Apple-only, richiedono rubrica/calendario reali): runtime sul device non coperto,
  solo compilazione. Privacy: NS…UsageDescription contatti/calendario sincere;
  `PrivacyInfo` con framing onesto (permission-gated, non required-reason API).

### Storico build-8 (blurry_photos)

- **BUILD `blurry_photos` — implementazione completa** (build-8): T-070 (nitidezza
  dietro `SharpnessScoring` + soglia di sfocatura con regola di confine dichiarata —
  strettamente sotto = blurry; alla soglia o non calcolabile = non blurry, nessun
  falso positivo), T-071 (aesthetics iOS 18 come progressive enhancement, `BlurScore`
  che degrada alla sola nitidezza su iOS 17 marcandolo). Domain puro; reuse di
  `VisionQualityScorer` (esteso ad `AestheticsScoring`) e kernel nitidezza/pixel
  condiviso (`SharpnessKernel`/`OnDeviceImageBytes`). Altitudine preservata: il Domain
  non importa Core Image/Vision.
- **VERDE (comando)**: **CI Apple run #10 `success`** (commit `38df675`), entrambi
  i job — `swift build/test/lint` + `build app (iOS Simulator)`; `validate_blueprint.mjs
  blueprint` → exit 0. `blurry_photos` → `done`.
- **Copertura**: AC-070/071 coperti dai target_tests Domain puro (`swift test`). Gli
  adapter (`CoreImageSharpnessScorer`, conformità aesthetics di `VisionQualityScorer`)
  compilati in CI ma senza test unitario dedicato (Apple-only): runtime sul device non
  coperto, solo compilazione. Dichiarato apertamente.

### Storico build-7 (large_old_media)

- **BUILD `large_old_media` — implementazione completa** (build-7): T-060 (video
  grandi *e* vecchi con soglie congiunte, ordine size desc→età, esclusione degli
  asset senza data), T-061 (categoria screenshot dal subtype indicizzato +
  categoria screen recording da euristica dichiarata sulle risoluzioni schermo
  iniettate), T-062 (`BulkDeletionProposal` a keep vuoto → gate anteprima T-050).
  Macrotask **interamente Domain puro**: nessun import PhotoKit/Vision, riusa
  `SizedAsset`/`LibraryAsset.subtypes`/`DeletionFlow`.
- **VERDE (comando)**: **CI Apple run #9 `success`** (commit `9090c7f`), entrambi
  i job — `swift build/test/lint` + `build app (iOS Simulator)`; `validate_blueprint.mjs
  blueprint` → exit 0. `large_old_media` → `done`.
- **Copertura**: AC-060/061/062 coperti dai target_tests Domain puro (`swift test`).
  Nessun adapter Apple-only in questo macrotask → nessun caveat runtime-non-coperto.
  L'euristica screen-recording usa risoluzioni schermo reali iniettate a runtime
  (cablaggio in `ui_shell`/Data, fuori scope qui): dichiarato apertamente.

### Storico build-6 (similar_photos)

- **BUILD `similar_photos` — implementazione completa** (build-6): T-040 (feature
  print Vision dietro port, distanza semantica pura), T-041 (clustering greedy per
  soglia con fallback dHash/Hamming, a blocchi cancellabile via T-004), T-042
  (best-of-cluster per punteggio qualità; aesthetics iOS 18 come progressive
  enhancement), T-043 (`DeletionProposal` per cluster, solo dati). Altitudine
  preservata: il Domain non importa Vision (feature print/scoring dietro port del
  Data layer; distanza di Hamming del dHash aritmetica pura nel Domain).
- **VERDE (comando)**: **CI Apple run #8 `success`** (commit `7aee6d1`), entrambi
  i job — `swift build/test/lint` + `build app (iOS Simulator)`; `validate_blueprint.mjs
  blueprint` → exit 0. `similar_photos` → `done`.
- **Copertura**: AC-040/041/042/043 coperti dai target_tests Domain puro (`swift test`).
  I 3 adapter (`VisionFeaturePrinter`, `PerceptualDHasher`, `VisionQualityScorer`)
  compilati in CI ma senza test unitario dedicato (Apple-only): runtime sul device
  non coperto, solo compilazione. Dichiarato apertamente.

### Storico build-5 (exact_duplicates)

- **BUILD `exact_duplicates` — implementazione completa** (build-5): T-030
  (candidati per byte-size, solo gruppi con cardinalità > 1), T-031 (cluster per
  SHA-256 identico, hashing a blocchi cancellabile via T-004, adapter reale
  `PHAssetContentHasher` in streaming e zero rete), T-032 (keep-one deterministico,
  nessuna eliminazione). Altitudine preservata: lo SHA-256 è calcolato da un port
  del Data layer, il Domain raggruppa per digest identico (niente CryptoKit nel Domain).
- **VERDE (comando)**: **CI Apple run #7 `success`** (commit `497f463`), entrambi
  i job — `swift build/test/lint` + `build app (iOS Simulator)`; `validate_blueprint.mjs
  blueprint` → exit 0. `exact_duplicates` → `done`.
- **Copertura**: AC-030/031/032 coperti dai target_tests Domain puro (`swift test`).
  `PHAssetContentHasher` compilato in CI ma senza test unitario dedicato (Apple-only):
  runtime sul device non coperto, solo compilazione. Dichiarato apertamente.

### Storico build-4 (dashboard)

- **BUILD `dashboard` — implementazione completa** (build-4): T-020 (aggregazione
  per categoria, exact/estimated separati), T-021 (caveat iCloud, riusa
  `DeletedAssetSize`), T-022 (banner limited, riusa `PhotoAccessPolicy`). 3
  target-test nuovi (AC-020-1/2, AC-021-1/2, AC-022-1/2), tutti Domain puro.
- **VERDE (comando)**: `validate_blueprint.mjs blueprint` → exit 0; **CI Apple
  run #6 `success`** (build+test+lint+app iOS). `dashboard` → `done`.
- **Debito saldato**: T-052 anticipava il caveat iCloud → `dashboard` **condivide**
  `DeletedAssetSize`, non lo duplica.

### Storico build-3 (safety_net)

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
- **11 macrotask su 11 VERIFICATI** (oracolo Apple verde in CI): foundation,
  library_index, safety_net, dashboard, exact_duplicates, similar_photos,
  large_old_media, blurry_photos, video_compression, extra_photo_domains,
  **ui_shell** (run #13, `success`). **Piano di build di 00-INDEX §2 completo.**
  Nessun macrotask residuo.
- **Macrotask `wiring` COMPLETO** (`DI-009`, `12-wiring.md`): **8/8 verdi** in CI
  (run #17→#25, tutti `success`). Nessun task residuo. Dettaglio in §5 (Storico
  wiring). Nota di copertura ancora aperta: la residenza per-asset di
  `SystemDeviceStorageInspector` è best-effort (device==libreria); la residenza
  iCloud reale (async PhotoKit) è un raffinamento futuro dichiarato (L-COL-006).
- **Prossimi passi possibili** (nessun macrotask da costruire):
  1. **Rigenerare l'`.ipa`** (workflow `ipa.yml`, `workflow_dispatch`) per provare
     l'app cablata sull'iPhone.
  2. **Merge su `main`** (decisione utente; gate verde soddisfatto).
  3. **Release-review pre-App-Store** (`apple-skills:release-review`).
  4. Rifinitura design/animazioni HIG (`apple-skills:design`).
  Pattern consolidato: view-model `@Observable` dietro i port dell'AppEnvironment,
  test in `AngavuFeaturesTests`; le View verificate dal build app in CI. Ogni task
  chiude al confine con la CI verde. Poi rigenerare l'`.ipa`.
- Lavoro ulteriore possibile: rifinitura design/animazioni HIG
  (`apple-skills:design`) su `ui_shell`; merge su `main` (decisione utente);
  release-review pre-App-Store (`apple-skills:release-review`).
- **Confine Apple = CI GitHub Actions** (`.github/workflows/ci.yml`, runner
  `macos-15`): a ogni push gira `make build`/`test`/`lint` + build dell'app iOS per
  simulatore. È qui che l'oracolo Swift emette verde/rosso — **senza possedere un
  Mac**. Il verdetto è di un **comando** (L-COL-002), verificabile nella tab Actions.
- **Merge su `main`**: il gate è soddisfatto (CI verde). Il merge resta una
  decisione dell'utente; il branch è mergeabile quando vuoi.
- **Caveat minuti**: repo privato → minuti macOS ×10 (~200/mese piano Free). Il
  job `ios-app` è separato e disattivabile per risparmiare.
