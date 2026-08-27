# SESSION-STATE — Angavu iOS

> Fonte di verità sullo **stato vivo del progetto**, consumata da BUILD
> (apple-skills) e aggiornata a ogni chiusura di sessione. Distinta dalla
> SESSION-STATE interna di Trueline. Prosa in italiano, identificatori in inglese.

| | |
|---|---|
| **Progetto** | Angavu iOS |
| **Ecosistema** | swift-ios (SwiftUI + SwiftData + PhotoKit/Vision/AVFoundation) |
| **Ultimo aggiornamento** | 2026-08-27 (**sessione BUILD FSE-F2 — progresso onesto multi-fase + carosello che copre l'intera attesa (verificato), CI run #94 `success` su `e2b933c`; storico FSE-F1 — coordinatore di scansione unificata: dopo indice+byte+residenza la scansione calcola e cacha TUTTE le categorie in una sola passata (aprire una categoria è istantaneo, mai un rilevatore al tap), verde all'oracolo CI (run #93 `success` su `19126c8`, entrambi i job `macos-15`); storico immediato: FSE-E3 — cablaggio get-or-compute della cache dei derivati (leva 5, run #90 `success` su `36ab87a`); FSE-E1 + FSE-E2 — policy pura di validità + store SwiftData dei derivati (leva 5), verdi all'oracolo CI (E1 run #87 su `f1732ad`; E2 run #88 `success` su `c3d3846`); storico FSE-D2 (rilevatori sul motore per-item, #86 su `07df7b8`), FSE-D1 (motore concorrente, #85 su `52efa22`); dettaglio nella riga «Sessione FSE-D1» qui sotto. Storico recente: sessione BUILD FSE-C1 + FSE-C2 + FSE-B2 — pipeline immagine ridimensionata on-device (leve 2+4), ri-taratura dichiarata delle soglie, e byte risolti una volta e riusati fra categorie (leva 6). FSE-C1 → #81 `453b669`; FSE-C2 → #83 `8c2e650`; FSE-B2 → CI run #84 `success` su `5ce0d40`; dettaglio nella riga «Sessione FSE-C + FSE-B2» qui sotto. Storico: FSE-B1 (risolutore batch dei PHAsset, #80 su `b9e1982`), FSE-A1 (fondazioni+misura, #79 su `41cd712`) e** 2026-08-26 (**sessione BUGFIX+DESIGN — scansione unificata (CI run #78 `success` su `3460690`) + blueprint del motore di scansione veloce (`blueprint/FAST-SCAN-ENGINE-PLAN.md`, nessun codice)**; dettaglio nella riga «Sessione 2026-08-26 scansione unificata + fast-engine» qui sotto. Storico: **sessione BUILD P0-2b — residenza per-asset reale (numero device preciso)**, CI run #75 `success` su `8bd4347`; dettaglio nella riga «Sessione P0-2b» qui sotto. Con P0-2b il piano POST-DEVICE è **completo**: resta solo il follow-up device-only sink observer→PhotoKit). Storico: **sessione BUILD Fase E — flusso primo avvio "Shazam"**, CI run #71 `success` su `18c03b7`; dettaglio nella riga «Sessione Fase E» qui sotto). Storico: 2026-08-25 (**sessione di BUGFIX on-device** — freeze scansione: (1) **mappatura O(N²)→O(N)** in `LibraryAssetMapper.mapBatch` [causa reale del "blocco al 100%": l'accumulatore per valore ricopiava l'intero array a ogni elemento, ~300M copie su 25k foto], (2) **indice SwiftData su `ModelContext` dedicato per operazione** (`SwiftDataAssetIndex` container-based) → la scrittura della scansione non tocca più il contesto principale, (3) **upsert a query singola** [era O(N) `FetchDescriptor`], (4) **letture pesanti fuori dal main thread** — Dashboard/Report/Review-categoria/Compressione leggevano l'indice 25k + risolvevano i byte per-asset via PhotoKit in `onAppear` SINCRONO sul main (secondo freeze, all'apertura della Dashboard); ora `load()`/`loadIfNeeded` sono `async` (VM non isolati / helper `nonisolated`) invocati da `.task`, con aggiornamento stato sul main. **CI Apple `success` su `03c49b1`** (fix 1-3) e **`8a383b0`** (fix 4) — build+test+lint+app iOS. Blueprint invariato: 11/11 + wiring 8/8 + guscio 8/8 + HIG 12/12. **Verifica on-device rimandata alla prossima sessione.** **+ sessione di PROGETTAZIONE post-device** (`blueprint/POST-DEVICE-UX-PLAN.md`): 6 difetti emersi al primo test on-device — **P0** = "139,21 GB liberabili sul telefono ora" su un 128 GB con Foto reali 7,99 GB (causa: `SystemDeviceStorageInspector.deviceResidentBytes` restituisce i byte-libreria → somma l'intera libreria in iCloud); + miniature assenti/selezione tutto-o-niente, spec video che fallisce sugli originali iCloud, categorie foto non cablate, rianalisi da navigazione/background. Decisioni bloccate (residenza reale, cache sopra la view, selezione per categoria, video da `PHAsset.duration`). **Prossimo macrotask: P0** (numeri device onesti + fondazione cache). Precedente: 2026-08-24 (**sessione di BUILD rifinitura HIG — R-11**: rifiniture minori — transizione di fase `idle→ready→failed` animata gated su Reduce Motion, `Picker` tema semplificato (via ridondanza label/header), riga extra-foto disabilitata + spinner in coda durante l'azione async. **CI Apple run #49 `success`** (`d4d1cac`, verde al primo colpo). Piano build 11/11 + `wiring` 8/8 + guscio UI 8/8 invariati; **rifinitura HIG 12/12 — COMPLETA** (R-00…R-11 tutti chiusi)) |
| **Sessione FSE-F2 (2026-08-27, corrente)** | **BUILD FSE-F2 — progresso onesto multi-fase + carosello che copre l'intera attesa.** **VERDE (oracolo CI, L-COL-002): CI run #94 `success`** su `e2b933c` (build `-warnings-as-errors` + `swift test` coi nuovi test in `ScanFlowPresentationTests` + `swiftlint --strict` + build app iOS). **Task di TEST per costruzione**: F1 aveva già aggiunto nel layer puro `ScanFlowPresentation` i titoli di fase dei rilevatori (imposti dal tipo `Stage`) e la copertura del carosello (`showsCarousel` per tutte le fasi); F2 li rende **verificati** e copre gli AC (come dichiarato nel commento del sorgente). Oracolo `ScanFlowPresentationTests`: AC-FSE-F2-1 (fase 'similar' → titolo onesto «Confronto le foto simili…» + frazione REALE unificata `(rawValue+f)/8`, mai fabbricata, conteggio «X di N»), AC-FSE-F2-2 (fase a totale NULLO / categoria vuota → trattata come COMPLETA senza incollare la barra: frazione al confine della fase successiva, coerente con `ScanPipelineProgress`/`AnalysisProgress` total 0 ⇒ fraction 1; titolo comunque onesto), + DoD (carosello attivo `showsCarousel` per tutte le 8 fasi, ogni fase con titolo onesto non vuoto). L'auto-avanzamento del carosello gated su Reduce Motion/VoiceOver è l'idioma esistente E-4 nella View SwiftUI (compilato-non-reso, L-COL-006). Nessun cambio di logica: solo la copertura che mancava. Altitudine/privacy invariate. **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅, B1 ✅, B2 ✅, C1 ✅, C2 ✅, D1 ✅, D2 ✅, E1 ✅, E2 ✅, E3 ✅, F1 ✅, **F2 ✅**; aperti — FSE-A2 (baseline §7, device-only), **FSE-G** (ripensamento della residenza, opzione 3; `depends_on: [FSE-B]` (+ FSE-D se resta nel motore) → SBLOCCATO). **Prossimo (ordine §10)**: FSE-G (residenza — togliere/alleggerire il peso maggiore, con onestà invariata), poi FSE-A2 (baseline §7, processo device-only). Con F2 il macrotask **`fast_scan_engine` è quasi chiuso**: resta solo FSE-G (+ A2, processo). Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione FSE-F1 (2026-08-27, storico)~~** | **BUILD FSE-F1 — coordinatore di scansione unificata «un'unica scansione fa tutto» (`depends_on: [FSE-D2, FSE-E3, FSE-B2]`, tutte verdi).** **VERDE (oracolo CI, L-COL-002): CI run #93 `success`** su `19126c8`, entrambi i job su runner reali `macos-15`: swiftpm — `swift build -warnings-as-errors` + `swift test` (463 test, target_tests `UnifiedScanCoversCategoriesTests` + `ScanPipelineProgressTests` + regressione) + `swiftlint --strict`; ios-app — XcodeGen + build app iOS Simulator. **Costruito**: **Domain** — `ScanPipelineProgress.Stage` esteso da 3 a **8 fasi** (3 numeri veri + 5 rilevatori: screenshot/duplicati/simili/sfocate/grandi-vecchi), **equipesate** (pesatura DICHIARATA, DoD: ogni fase = 1/8; i rilevatori pesanti occupano più tempo REALE entro la loro quota, mai una frazione gonfiata); frazione unificata monotòna non decrescente su tutte le 8 fasi. **Features** — `ScanViewModel.categoryResults` (mappa `CleanupCategory→CategoryReviewData`, interna) popolata da `computeCategoryResults`: la STESSA passata, dopo i numeri veri, calcola ogni rilevatore come fase della barra e ne raccoglie il risultato; una categoria COMPLETATA è cachata, una NON raggiunta (cancellazione a metà) resta FUORI (calcolata al tap, mai un parziale spacciato per completo), un ERRORE del rilevatore lascia la sola categoria non-cachata senza abortire la scansione. `HomeView` popola la cache sopra le view (`store.set(_, for: .category(rawValue), at: now)` col timestamp di freschezza) → `CategoryReviewView` trova il valore in cache (ramo hit `CategoryReviewView+Loading.swift:51`) e non lancia mai una nuova composizione. `CategoryReviewSource.reviewData` ora accetta il token della scansione (i rilevatori pesanti si fermano all'annullamento; default token nuovo → aperture singole invariate). Signpost FSE-A1 esteso 1:1 alle 5 fasi rilevatore (attribuzione tempi per categoria in Instruments); `ScanFlowPresentation.phaseLabel` gestisce le nuove fasi con titoli provvisori (i titoli definitivi + carosello per l'intera attesa e i loro test sono **FSE-F2**). **Oracoli**: `ScanPipelineProgressTests` (AC-FSE-F1-3: monotonìa su 8 fasi campionate + confini rilevatore, ultima fase = 1.0), `UnifiedScanCoversCategoriesTests` (AC-FSE-F1-1: dopo una scansione completa ogni categoria è cachata e leggerla non riesegue alcun rilevatore — contatore nitidezza fermo al tap, +controllo che una composizione fresca lo incrementa; AC-FSE-F1-2: cancellazione durante i duplicati → screenshot cachato, simili/sfocate/grandi-vecchi NON cachati, esito `cancelled`); `ScanSignpostTests`/`ScanFlowPresentationTests` aggiornati alla pipeline a 8 fasi. **Percorso al verde**: #91 rosso (build — `ScanSignpost.swift` importava solo `Foundation`, il nuovo init `ScanSignpostPhase(_ stage: ScanPipelineProgress.Stage)` non trovava il tipo Domain → cascata di errori in `ScanViewModel`; corretto con `import AngavuDomain`, logica invariata) → #92 rosso (un solo test di regressione — `test_scanning_fillIsUnifiedRealFraction` hardcodava 1.5/3=0.5, ora 1.5/8; l'atteso è derivato da `Stage.allCases.count`, logica invariata) → **#93 verde** (`19126c8`). **Altitudine invariata** (Domain puro: `ScanPipelineProgress` solo Foundation; `scanStage`/mapping in Features; nessuna dipendenza `domain→data` nuova — build verde = grafo moduli SwiftPM oracolo). **Baseline privacy invariata** (nessun permesso/rete nuovi; i signpost registrano solo nomi di fase; zero PII). **Rete di sicurezza invariata** (la scansione compone solo proposte; ogni delete resta dal gate `DeletionFlow`, T-050). **Copertura (L-COL-006)**: la LOGICA (coordinamento/cache per-categoria/cancellazione/monotonìa) è coperta dai target_tests; la **composizione reale dei rilevatori** (SHA-256/Vision/nitidezza) e il **popolamento della cache da parte della Home** sono **device-only / View-level**, compilati in CI ma runtime NON coperto. **FSE-F1 CHIUSA.** **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅, B1 ✅, B2 ✅, C1 ✅, C2 ✅, D1 ✅, D2 ✅, E1 ✅, E2 ✅, E3 ✅, **F1 ✅**; aperti — FSE-A2 (baseline §7, device-only), **FSE-F2** (progresso onesto multi-fase + carosello che copre l'intera attesa; `depends_on: [FSE-F1]` → **SBLOCCATO**), FSE-G (residenza). **Prossimo (ordine §10)**: FSE-F2, poi FSE-G. Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione FSE-E3 (2026-08-27, storico)~~** | **BUILD FSE-E3 — cablaggio get-or-compute della cache dei derivati (leva 5; `depends_on: [FSE-E2, FSE-D2]`, entrambe verdi).** **VERDE (oracolo CI, L-COL-002): CI run #90 `success`** su `36ab87a`, entrambi i job su runner reali `macos-15`: swiftpm — `swift build -warnings-as-errors` + `swift test` (target_tests `DerivedCacheWiringTests` + regressione, 458 test) + `swiftlint --strict`; ios-app — XcodeGen + build app iOS Simulator. **Costruito**: **Domain puro** (`Sources/AngavuDomain/DerivedCacheWiring.swift`, altitudine intatta — il feature print è `Data` OPACO, mai un tipo di Vision) — port `FeaturePrintVectorProducing` (produttore del vettore serializzato), port `AssetContentVersioning` (versione del contenuto per la `DerivedKey`), `DerivedResultCache` (cache in memoria sostenuta dallo store FSE-E2 + validità FSE-E1: `warm(current:)` tiene solo i validi e scarta dallo store i fantasmi; `validValue(for:)` serve SSE la chiave combacia — mai uno stantìo; `merge(key:)` read-modify-write PER-CAMPO così adapter di campi diversi — feature print oggi; hash/nitidezza/residenza in FSE-F — non si sovrascrivono passando dallo stesso store; `invalidate(ids:)`/`invalidateAll()`; thread-safe `NSLock`, off-main FSE-D2), `CachingFeaturePrintVectors` (decoratore get-or-compute: su HIT il produttore di base NON viene MAI chiamato). **Data** — `VisionFeaturePrinter` ora conforme anche a `FeaturePrintVectorProducing` (vettore via `NSKeyedArchiver` sull'osservazione già cachata → serializza al più una volta per asset; `nil` = non calcolabile on-device, mai un vettore fabbricato). **Features** — `StoreInvalidatingLibrarySink` ESTESO (riuso, come da DoD): invalida ANCHE i derivati ma PER-ASSET (`changed`+`removed` del delta; gli `added` non hanno ancora derivato), con fallback a `invalidateAll` su errore (mai un vettore stantìo servito); `derivedCache` opzionale default `nil` → retro-compatibile (i test D-1 esistenti invariati). **Oracolo** (`Tests/AngavuFeaturesTests/DerivedCacheWiringTests.swift`): AC-FSE-E3-1 — feature print in cache → `computeCount = 0` (HIT), cache-miss → 1 poi HIT + persistito, versione stantìa → ricalcolo, `merge` preserva gli altri campi; AC-FSE-E3-2 — observer `changed`/`removed` invalida per-asset (stantìo rimosso SUBITO; il ricalcolo successivo ripersiste il FRESCO; gli asset non toccati restano HIT). **Percorso al verde**: CI #89 rosso (una sola asserzione del test mal progettata — asseriva lo store privo di A DOPO il ricalcolo, ma get-or-compute ripersiste correttamente il vettore fresco; LOGICA DI PRODUZIONE INVARIATA, corretto solo l'oracolo) → **#90 verde** (`36ab87a`). **Copertura (L-COL-006)**: la LOGICA (get-or-compute / merge per-campo / invalidazione per-asset) è coperta dai target_tests; il PRODUTTORE Vision reale, il risolutore di versione PhotoKit reale (`modificationDate`) e la **composizione nella scansione unificata** (thread dei vettori attraverso le fasi + injection del derived store nell'`AppEnvironment`) sono **device-only / FSE-F**, dichiarati NON coperti. **FSE-E3 CHIUSA.** **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅, FSE-B1 ✅, FSE-B2 ✅, FSE-C1 ✅, FSE-C2 ✅, FSE-D1 ✅, FSE-D2 ✅, FSE-E1 ✅, FSE-E2 ✅, **FSE-E3 ✅**; aperti — FSE-A2 (baseline §7, processo device-only), **FSE-F** (un'unica scansione fa tutto — coordinatore che, dopo indice+byte+residenza, calcola TUTTI i rilevatori in una passata e ne cacha i risultati per categoria; `depends_on: [FSE-D2, FSE-E3, FSE-B2]` → **SBLOCCATO**), FSE-G (residenza). **Prossimo (ordine §10)**: FSE-F1 (coordinatore di scansione unificata), poi FSE-G. Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione FSE-E1 + FSE-E2 (2026-08-27, storico)~~** | **BUILD FSE-E1 — policy PURA di validità della cache dei derivati (leva 5).** **VERDE (oracolo CI, L-COL-002): CI run #87 `success`** su `f1732ad` (build `-warnings-as-errors` + `swift test` coi nuovi `DerivedResultValidityTests` + `swiftlint --strict` + build app iOS). **Costruito** (Domain puro, oracolo pieno): `DerivedKey {id, contentVersion}` (identità asset + versione del contenuto — in produzione la `modificationDate`/versione PhotoKit; chiave diversa = contenuto cambiato → derivato da ricalcolare); `DerivedResultValidity.isValid` (valido SSE la chiave combacia — mai un punteggio stantìo per un asset cambiato); `DerivedResultValidity.partition(current:persisted:invalidateAll:)` che partiziona in **{reusable, toRecompute, removed}** in modo deterministico (ordine dei correnti per riusabili/da-ricalcolare, ordine dei persistiti per rimossi; `invalidateAll` forza tutto a da-ricalcolare dopo eliminazione/cambio libreria). Oracolo `DerivedResultValidityTests`: AC-FSE-E1-1 (versione cambiata → stantìo → ricalcolare), AC-FSE-E1-2 (persistiti A,B,C + libreria A,B,D → reusable={A,B}, recompute={D}, removed={C}), AC-FSE-E1-3 (invalidazione totale → nessun valido) + casi limite (asset nuovo → calcolato mai saltato; libreria vuota → tutti scartati; ordine deterministico). Altitudine/privacy invariate (solo Foundation, zero rete). **FSE-E2 costruito** (questa sessione, CI run **#88 `success`** su `c3d3846`): Domain — `DerivedRecordValue` (valori persistibili: digest/sharpness/`featurePrint` OPACO come `Data`/residentBytes, ogni campo opzionale), port `DerivedResultStoring` (loadAll/upsert/remove/removeAll; la `contentVersion` viaggia col valore → la lettura ricostruisce la `DerivedKey` completa, validità via E1), `NoDerivedResultStore` null-object. Data (Apple-only) — `DerivedRecord` `@Model` (id univoco → upsert non duplica), `SwiftDataDerivedStore` con `ModelContext` DEDICATO per operazione (off-main, come `SwiftDataAssetIndex` T-012: mai il contesto main-actor per scritture di massa → niente freeze), upsert a un solo fetch + mappa per id + un save, loadAll ripopola la cache. Oracolo `DerivedResultStoreTests`: AC-FSE-E2-1 (scritti+riletti dopo «riavvio» IDENTICI), AC-FSE-E2-2 (upsert 2000 su contesto dedicato — osservatore separato senza modifiche pendenti ma vede i dati — senza errori), AC-FSE-E2-3 (versione cambiata → stantìo non servito, delega a E1) + remove/removeAll. Altitudine invariata (Domain vede `Data` opaco, mai un tipo di Vision). **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅, FSE-B1 ✅, FSE-B2 ✅, FSE-C1 ✅, FSE-C2 ✅, FSE-D1 ✅, FSE-D2 ✅, FSE-E1 ✅, **FSE-E2 ✅**; aperti — FSE-A2 (processo device-only §7), **FSE-E3** (cablaggio get-or-compute + invalidazione dall'observer; `depends_on: [FSE-E2, FSE-D2]` → SBLOCCATO), FSE-F (un'unica scansione fa tutto), FSE-G (residenza). **Prossimo (ordine §10)**: FSE-E3 (gli adapter consultano la cache derivata prima di calcolare; invalidazione su cambio libreria/eliminazione), poi FSE-F. Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione FSE-D2 (2026-08-27, storico)~~** | **BUILD FSE-D2 — rilevatori CPU-bound sul motore per-item iniettabile (leva 3, il moltiplicatore).** **VERDE (oracolo CI, L-COL-002): CI run #86 `success`** su `07df7b8` (build `-warnings-as-errors` + `swift test` coi nuovi `ConcurrentDetectorParityTests` + `swiftlint --strict` + build app iOS), al primo colpo. **Costruito**: Domain — `PerItemAnalysis` (motore per-item iniettabile CONCRETO: `.serial` a blocchi | `.concurrent` che avvolge `ConcurrentAnalysis` di D1; `map` preserva l'ordine d'INPUT, cancellabile, progresso monotòno → risultato IDENTICO coi due motori). I rilevatori dominanti parallelizzano la sola fase PER-ITEM indipendente, tenendo SERIALE la combinazione ordine-dipendente: `BlurClassification.blurry(analysis:)` (nitidezza per foto in parallelo, filtro in ordine), `ExactDuplicateClustering.clusters(analysis:)` (digest per candidato in parallelo, raggruppamento per digest = riduzione pura ordine-preservante), `SimilarClustering.clusters(analysis:)` (clustering greedy resta SERIALE — ordine-dipendente, AC di T-041 invariati — con pre-warm parallelo dei feature print via nuovo `FeaturePrinting.prepare` default no-op), `ClusterQualityRanking.ranked`/`SimilarDeletionProposal` (qualità keep-best per membro in parallelo). Default SERIALE ovunque → **tutti gli AC/call-site esistenti invariati**. Data — `VisionFeaturePrinter.cache` resa **thread-safe** (`NSLock`, calcolo Vision FUORI dal lock per non serializzare il parallelismo) + `prepare()` per il pre-warm; gli altri adapter (quality/sharpness/hasher) sono `struct` stateless → già sicuri. Oracolo: `ConcurrentDetectorParityTests` — AC-FSE-D2-1 (duplicati, clustering simili, keep/removable IDENTICI serial vs concorrente) e AC-FSE-D2-2 (sfocate identiche + cancellazione reattiva). **Adozione concorrente in PRODUZIONE tenuta SERIALE**: il guadagno reale e la correttezza thread degli adapter Vision si validano con Thread Sanitizer on-device (§7) prima di dichiararli (L-COL-006) — D2 consegna la capacità + la prova di parità, non un verde di performance. Altitudine/privacy invariate (Domain puro, zero rete). **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅, FSE-B1 ✅, FSE-B2 ✅, FSE-C1 ✅, FSE-C2 ✅, FSE-D1 ✅, **FSE-D2 ✅**; aperti — FSE-A2 (baseline §7, processo device-only), **FSE-E** (persistenza dei derivati: chiave id+modificationDate, invalidazione; `depends_on: [FSE-A1]` → SBLOCCATO), FSE-F (un'unica scansione fa tutto), FSE-G (residenza). **Prossimo (ordine §10)**: FSE-E (persistenza derivati → scansioni successive immediate). Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione FSE-D1 (2026-08-27, storico)~~** | **BUILD FSE-D1 — motore d'analisi concorrente cancellabile (leva 3 🔴 del `FAST-SCAN-ENGINE-PLAN` §1.4; `depends_on: [FSE-A1]`, verde).** **VERDE (oracolo CI, L-COL-002): CI run #85 `success` su `52efa22`**, entrambi i job su runner reali `macos-15` (runner_id ≠ 0, step reali): swiftpm — Build `-warnings-as-errors` (33s), `swift test` target_tests+regressione (27s, inclusi i nuovi `ConcurrentAnalysisTests`), `swiftlint --strict` (5s); ios-app — XcodeGen + build app iOS Simulator (60s). **Verde al primo colpo.** **Costruito** (Domain puro, `Sources/AngavuDomain/ConcurrentAnalysis.swift`): `ConcurrentAnalysis<Element, Output>` — motore che AFFIANCA `ChunkedAnalysis` (T-004, non lo sostituisce: dove il seriale è già adeguato — screenshot, grandi/vecchi — resta ChunkedAnalysis), elabora gli elementi **a onde in parallelo** con concorrenza `maxConcurrency = min(configurato, ProcessInfo.activeProcessorCount)`; **stessa forma di esito** `AnalysisOutcome` (`completed|cancelled|failed`) col progresso raggiunto. Invarianti di onestà del seriale preservati: **output nell'ordine d'INPUT** (ricomposizione per-indice → deterministico, indipendente dall'ordine di completamento); **progresso monotòno** non decrescente (pubblicato sotto un unico `NSLock` → serializzato); **cancellazione a confine d'onda** (le onde residue non partono, step < N); **fallimento all'indice più basso** (deterministico rispetto all'input, mai un parziale spacciato per completo — un buco nei risultati è un `.failed` esplicito); **dieta low-RAM** (al più `maxConcurrency` elementi in volo, `autoreleasepool` per worker). Lo stato mutabile condiviso è isolato in `ConcurrentAnalysisState` (classe file-private con NSLock): ogni accesso mutabile in un solo posto (correttezza sotto concorrenza in un punto solo). **Altitudine invariata** (solo Foundation/Dispatch; nessun import PhotoKit/Vision/AVFoundation; nessuna dipendenza `domain→data` nuova — build verde = grafo moduli SwiftPM oracolo). **Baseline privacy invariata** (nessuna API di piattaforma/rete/usage-description nuova; puro Domain). **Rete di sicurezza invariata** (il motore mappa, non elimina; ogni delete resta dal gate `DeletionFlow`). **Oracoli** (`Tests/AngavuDomainTests/ConcurrentAnalysisTests.swift`): AC-FSE-D1-1 — output `[0..N-1]` in ordine d'input, ripetuto 10× + prova esplicita con sleep INVERSO sugli indici bassi (i bassi finiscono per ultimi, l'output resta ordinato); AC-FSE-D1-2 — cancel dopo il 1° confine → `.cancelled` col progresso, step < N (contatore atomico), + cancel pre-avvio = 0 step; AC-FSE-D1-3 — step che lancia → `.failed` con motivo esplicito + progresso, + motivo all'indice più basso deterministico su 10 run; AC-FSE-D1-4 — progresso monotòno non decrescente su 300 elementi; + clamp concorrenza `min(configurato, core)` e input vuoto (completed immediato). **Copertura (L-COL-006)**: la LOGICA (determinismo, monotonìa, cancellazione, fallimento, clamp) è coperta dai target_tests su Linux/CI; il **guadagno di velocità reale** dal parallelismo è **device-only** (protocollo Instruments §7), MAI un verde CI né una frase dell'LLM; l'**assenza di data race** è garantita per costruzione (unico lock) ma va CONFERMATA con **Thread Sanitizer on-device** (§7), soprattutto in FSE-D2 dove entrano le cache degli adapter reali — **non coperta in CI**. **FSE-D1 CHIUSA.** **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅, FSE-B1 ✅, FSE-B2 ✅, FSE-C1 ✅, FSE-C2 ✅, **FSE-D1 ✅**; aperti — FSE-A2 (baseline §7, processo device-only), **FSE-D2** (rilevatori CPU-bound — feature print/nitidezza/hashing — sul motore concorrente; `depends_on: [FSE-D1, FSE-C1]` → **SBLOCCATO**, con Thread Sanitizer §7 e AC di parità col seriale), FSE-E (persistenza derivati), FSE-F (un'unica scansione fa tutto), FSE-G (residenza). **Prossimo (ordine §10)**: FSE-D2, poi FSE-E. Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione FSE-C + FSE-B2 (2026-08-27, storico)~~** | **BUILD FSE-C1 + FSE-C2 — pipeline immagine ridimensionata (leve 2+4 🔴 del `FAST-SCAN-ENGINE-PLAN` §1.2) e ri-taratura dichiarata delle soglie sensibili alla risoluzione.** **VERDE (oracolo CI, L-COL-002): FSE-C1 → CI run #81 `success` su `453b669`; FSE-C2 → CI run #83 `success` su `8c2e650`** (build `-warnings-as-errors` + `swift test` + `swiftlint --strict` + build app iOS Simulator, entrambi i job su `macos-15` reali). **FSE-C1 costruito** (commit già presente a inizio sessione): Domain puro — `LogicalImageSize` (taglie logiche per rilevatore: `.featurePrint` ≈224px, `.sharpness` ≈64px, `.pixels`; NESSUN caso full-res → il full-res per l'analisi è impossibile per costruzione), `DownscaledImage` opaco (`AnyObject`, altitudine invariata), port `DownscaledImageProviding`, `DownscaledImageRequest` (selezione taglia pura), `SharedDownscaledImageProvider` (decoratore che memoizza `(id, taglia)` → **un solo decode condiviso**; `evictAll()` per la dieta memoria nel motore concorrente FSE-D); Data (Apple-only, device-only a runtime) — `PHImageDownscaledProvider` (`PHImageManager.requestImage(targetSize:)` a taglia piccola, `isNetworkAccessAllowed=false` → non residente = `nil`, **mai un download**), `CoreImageSharpnessScorer` e `VisionFeaturePrinter` consumano il provider ridimensionato (`VNImageRequestHandler(cgImage:)`), non più i byte full-res. Oracoli C1: `DownscaledImageContractTests` (Domain, AC-FSE-C1-1/2), `SharedDecodeTests` (Features, AC-FSE-C1-3 decode condiviso=1), `DownscaledSizeRequestTests` (Data, taglia dichiarata per rilevatore). **FSE-C2 costruito** (questa sessione): (1) Domain — `SharpnessMetric` (matematica PURA della nitidezza: varianza del Laplaciano + curva saturante `v/(v+k)`, **estratta** da `SharpnessKernel`; dichiara `referenceGridSide=48`, la risoluzione di RIFERIMENTO alimentata da `.sharpness`; provabile senza CoreGraphics); `BlurThreshold.referenceLongestSide` (default 64) — metadato DICHIARATIVO che documenta la scala a cui `minimumSharpness` è tarata (non entra nella classificazione), così un cambio di taglia è visibile e la ri-taratura è forzata. (2) Data — `SharpnessKernel` delega la matematica a `SharpnessMetric` (una sola fonte di verità; resta solo l'estrazione pixel). (3) Features — `CategoryDetectionDefaults.blur` dichiara `referenceLongestSide = .sharpness.longestSide`; **constatazione onesta**: C1 non ha cambiato la risoluzione EFFETTIVA del kernel (il percorso legacy ricampionava già a ≈64px via ImageIO thumbnail), quindi 0.3 resta valido — la scala è ora esplicita e vincolata, non assunta. Oracoli C2: `SharpnessThresholdRetuneTests` (Domain, AC-FSE-C2-1) — fixture di nitidezza NOTA (scacchiera=nitida, piatta/rampa lineare=sfocata) calcolate dalla **STESSA** `SharpnessMetric` di produzione (nessun numero inventato), regola di confine invariata (alla soglia=NON sfocato), pin della taglia di riferimento (64); `FeaturePrintScaleInvarianceTests` (Data, AC-FSE-C2-2) — **ordinamento** `d(A,A') < d(A,A@2x) < d(A,B)` sul percorso Vision reale (il feature print discrimina il CONTENUTO più della SCALA → 224px non ribalta la decisione simile/non-simile). **Lezione CI #82 rosso→#83 verde**: la prima stesura di C2 asseriva la distanza cross-risoluzione assoluta della stessa scena sintetica `< 0.5` (Vision diede 0.57): il feature print è tarato su FOTO REALI, il valore assoluto su tinte piatte non è significativo e il repo non ha fixture d'immagine né esegue Vision reale in CI altrove. Riscritto su ordinamento puro (nessun magic number); la parità di clustering 224px vs full-res su foto reali è **device-only (§7)**, dichiarata (L-COL-006). **Altitudine invariata** (Domain non importa grafica; immagine/handle opachi). **Baseline privacy invariata** (`isNetworkAccessAllowed=false`). **FSE-B2 costruito** (questa sessione, CI run **#84 `success`** su `5ce0d40`): Data — `CachingByteSizeResolver`, decoratore PURO (nessun import di piattaforma) su qualunque `AssetByteSizeResolving`; cache `id→ByteSize` protetta da `NSLock`, conserva il `ByteSize` COMPLETO (exact resta exact, estimated resta estimated, mai un mancante come 0); un asset nuovo è risolto on-demand UNA sola volta e cachato; chiave = solo id (il `ByteSize` è stabile entro la sessione; l'invalidazione su cambio contenuto tra avvii, chiave id+versione, è FSE-E fuori scope). Wiring — `AppEnvironment.live` avvolge `PHAssetByteSizeResolver` in `CachingByteSizeResolver`: la STESSA istanza (`final class`) è condivisa da scansione e categorie via l'environment → riuso automatico senza cambiare i call site (la fase `resolvingSizes` scalda, le categorie leggono HIT). Non rompe la variante handle di FSE-B1 (non è nel protocollo, mai chiamata via `environment.byteResolver`). Oracolo: `SizeReuseAcrossCategoriesTests` (Features) — AC-FSE-B2-1 (dopo la scansione, comporre duplicati+grandi/vecchi → resolver base **0** sul secondo uso, spy) e AC-FSE-B2-2 (asset nuovo risolto on-demand **una** volta, byte reale >0 mai spacciato per 0, rilettura = HIT). Copertura (L-COL-006): la logica di cache/riuso coperta in CI; il guadagno reale su ~25k asset è device-only (§7). **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅, FSE-B1 ✅, **FSE-B2 ✅**, **FSE-C1 ✅**, **FSE-C2 ✅**; aperti — FSE-A2 (baseline §7, processo device-only), **FSE-D** (motore concorrente; `depends_on: [FSE-A1]` per D1, `[FSE-D1, FSE-C1]` per D2 — SBLOCCATO), FSE-E (persistenza derivati), FSE-F (un'unica scansione fa tutto), FSE-G (residenza). **Prossimo (ordine §10)**: FSE-D (motore concorrente cancellabile, con Thread Sanitizer §7). Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione FSE-B1 (2026-08-27, storico)~~** | **BUILD FSE-B1 — risolutore batch dei PHAsset dietro un port (leva 1 🔴 del `FAST-SCAN-ENGINE-PLAN` §1.1: fine dei 25k×N fetch singoli; `depends_on: [FSE-A1]`, verde).** **VERDE (oracolo CI, L-COL-002): CI run #80 `success`** su `b9e1982`, **entrambi i job su runner reali `macos-15`** con step reali (nessun `runner_id:0`, nessun log 404): swiftpm — Build `-warnings-as-errors` (41s), `swift test` target_tests+regressione (30s, inclusi i nuovi `AssetHandleResolvingTests`+`BatchResolverReuseTests`), `swiftlint --strict` (7s); ios-app — XcodeGen + build app iOS Simulator (60s). **Costruito**: **(1) Domain puro (oracolo pieno)** — `Sources/AngavuDomain/AssetHandleResolving.swift`: `AssetHandle` (riferimento OPACO `AnyObject`, nessun tipo di Photos oltre il confine → altitudine invariata), `ResolvedAssetHandles` (mappa `id→handle` immutabile; id assente → `nil`, **mai un placeholder finto**), port `AssetHandleResolving`, `AssetIdentifierBatches.chunked` (chunking PURO: copertura totale, ordine preservato, nessun duplicato né buco; `chunkSize`≤0 → 1), `BatchAssetHandleResolver` (orchestratore riusabile con closure di fetch), `EmptyAssetHandleResolver` (null-object). **(2) Data (Apple-only, compilato in CI, runtime device-only)** — `Sources/AngavuData/PHAssetBatchResolver.swift`: `PHAssetHandle` + `PHAssetBatchResolver` che fa `PHAsset.fetchAssets(withLocalIdentifiers:)` **per chunk** (non per singolo id); id inesistenti naturalmente omessi dal `PHFetchResult`; zero rete; estensione interna `AssetHandle.resolvedPHAsset` (cast sicuro, mai forzato). Gli adapter di **metadati puri** — byte-size (`AssetByteSizeResolving`), residenza (`AssetResidencyProbe`), pixel (`OnDeviceImageBytes`) — ora accettano il **PHAsset già risolto via handle** (fallback al fetch per id se l'handle non è riconosciuto → correttezza invariata). **(3) Wiring** — `AppEnvironment.handleResolver` (default `EmptyAssetHandleResolver`; `live` → `PHAssetBatchResolver`). **Scoping dichiarato (L-COL-006, no seam usa-e-getta)**: il **feature-printer** riusa l'handle in **FSE-D2** (dove il clustering è ricablato al motore concorrente), il **downscale** è **FSE-C1** — pull-forward ora creerebbe seam da buttare; il resolver+`resolvedPHAsset` sono pronti per quando quelle fasi cablano. Il **cablaggio attraverso le fasi della scansione** (risolvere una volta a inizio scan e condividere la mappa) è **FSE-F**. **Oracoli**: `AssetHandleResolvingTests` (7, Domain: AC-FSE-B1-1 batch in una chiamata + inesistente assente; AC-FSE-B1-3 chunk deterministici a copertura totale, via `chunked` e via orchestratore; guardie chunkSize/mappa/null), `BatchResolverReuseTests` (2, Features: AC-FSE-B1-2 — risoluzione = 1 per asset, handle **riusato** fra byte/residenza/pixel provato per **identità**; asset nuovo → `nil`, mai fabbricato). **Altitudine invariata** (il Domain non importa Photos; l'handle è opaco; nessuna dipendenza `domain→data` nuova — grafo moduli SwiftPM = oracolo, build verde). **Baseline privacy invariata** (nessun permesso/rete nuovi; risoluzione su soli identificatori locali, `isNetworkAccessAllowed=false` invariato negli adapter; mappa viva rilasciata col `ResolvedAssetHandles`). **Rete di sicurezza invariata**. **Copertura (L-COL-006)**: la LOGICA (batch/chunking/riuso, onestà del nil) è coperta dai target_tests su Linux/CI; l'**adapter PhotoKit reale** (`PHAssetBatchResolver`, riuso reale su ~25k asset) è **compilato in CI, runtime device NON coperto**; il **guadagno di velocità** è **device-only** (protocollo Instruments §7), MAI un verde CI né una frase dell'LLM. **FSE-B1 CHIUSA.** **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅, **FSE-B1 ✅**; aperti — **FSE-B2** (byte risolti una volta e riusati fra categorie; ora SBLOCCATA), **FSE-C1** (downscaled image provider; ora SBLOCCATA), FSE-A2 (baseline §7, processo device-only), FSE-D (motore concorrente), FSE-E (persistenza derivati), FSE-F (un'unica scansione fa tutto), FSE-G (residenza). **Prossimo (ordine §10)**: FSE-C1 (+ FSE-B2), poi FSE-D. Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione FSE-A1 (2026-08-27, storico)~~** | **BUILD FSE-A1 — fondazioni + strumentazione di misura del motore di scansione veloce** (prima fase del `FAST-SCAN-ENGINE-PLAN`, DAG §4; radice, `depends_on: []`). **VERDE (oracolo CI, L-COL-002): CI run #79 `success`** su `41cd712`, entrambi i job su runner reali `macos-15` con step reali (nessun `runner_id:0`, nessun log 404): Build `-warnings-as-errors` (27s), `swift test` target_tests+regressione (19s, inclusi i **5 nuovi `ScanSignpostTests`**), `swiftlint --strict` (4s), build app iOS Simulator (67s). **Costruito**: (1) `Sources/AngavuFeatures/ScanSignpost.swift` — `ScanSignposting` con `measure()` scoped (`defer` → ogni fase apre/chiude ESATTAMENTE un intervallo, mai orfani, per costruzione), `ScanSignpostPhase` (nomi allineati 1:1 a `ScanPipelineProgress.Stage`), `NoOpScanSignpost` (default Linux/puro), `OSSignpostScanSignpost` (OSSignposter reale, guardato `#if canImport(os)`, `@available(iOS 15/macOS 12)`), factory `liveScanSignpost()`; (2) `Sources/AngavuFeatures/MetricKitRegistrar.swift` — registrazione **idempotente** (una sola volta), effetto reale iniettato come closure → idempotenza provabile senza MetricKit; (3) `Sources/AngavuFeatures/ScanViewModel.swift` — le 3 fasi (`indexing`/`resolvingSizes`/`measuringDeviceSpace`) racchiuse in `signpost.measure(...)` (FASE 1 ristrutturata con `enum IndexOutcome` interno così ogni via d'uscita chiude l'intervallo prima di aggiornare lo stato), signpost iniettabile in `init` (default reale); (4) `App/AppTelemetry.swift` + `App/AngavuApp.swift` — `AppTelemetry` possiede il subscriber `MXMetricManagerSubscriber` e lo registra all'avvio del processo (`@main`, mai in una schermata secondaria), guardato `#if canImport(MetricKit)`. **Oracoli** (`Tests/AngavuFeaturesTests/ScanSignpostTests.swift`, 5): AC-FSE-A1-1 — scansione completa = un intervallo bilanciato per fase in ordine (fake recording signpost); +cancellazione a metà = nessun orfano (la fase in cui cade si chiude via `defer`); +accesso negato = ZERO intervalli (niente telemetria su lavoro mai iniziato); AC-FSE-A1-2 — `MetricKitRegistrar` registra una sola volta anche con `registerOnce()` chiamato 3×, e nessun effetto alla sola costruzione. **Altitudine invariata** (`os`/`MetricKit` sono telemetria di sistema TRASVERSALE, in Features/App come da piano §3 — NON capacità-dato dietro un port; nessuna dipendenza `domain→data` nuova). **Baseline privacy invariata** (i signpost registrano solo nomi di fase e conteggi — zero PII, zero path utente, zero rete; MetricKit è telemetria di sistema on-device, non trasmessa da noi). **Copertura (L-COL-006)**: la LOGICA della telemetria (un intervallo per fase / bilanciamento / idempotenza) è coperta dai target_tests; l'**emissione reale** (`OSSignposter`, `MXMetricManager`) è compilata-ma-non-coperta → si valida on-device col protocollo Instruments (§7), mai in CI (la performance non è oracolabile in CI). **FSE-A1 CHIUSA.** **Stato macrotask `fast_scan_engine`**: FSE-A1 ✅; aperti — **FSE-A2** (compilare §7 con baseline/budget on-device: task di **processo/documentazione**, nessun target_test eseguibile), FSE-B (batch PHAsset), FSE-C (downscale), FSE-D (motore concorrente), FSE-E (persistenza derivati), FSE-F (un'unica scansione fa tutto), FSE-G (residenza). **Prossimo (ordine §10)**: FSE-A2, poi FSE-B/FSE-C. Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione 2026-08-26 (scansione unificata + fast-engine plan, storico)~~** | **BUGFIX on-device (scansione unificata) + PROGETTAZIONE (motore veloce).** Due difetti del flusso E emersi al 2° device-test: (1) la barra del tasto gigante copriva **solo l'indicizzazione**; il grosso del lavoro (byte per-asset + residenza) girava dopo, in dashboard, dietro lo spinner indeterminato «Calcolo dei numeri veri…»; (2) arrivati ai «Numeri veri» si aspettava una **seconda analisi** perché nessuno popolava la cache al termine della scansione. **FIX (VERDE, oracolo CI L-COL-002 — CI run #78 `success` su `3460690`, entrambi i job)**: scansione **unificata a 3 fasi con UNA barra** — `ScanPipelineProgress` (Domain puro, frazione unificata monotòna, mai fabbricata); `ScanViewModel` ora esegue indice → byte per-asset + aggregazione → **residenza per-asset (numero device preciso P0-2b, prima costruito ma MAI cablato alla UI)** ed espone i `DashboardScreen` in `figures`; la Home li mette nella cache sopra le view → toccando «È ora di fare pulizia!» la Dashboard è **istantanea**, nessun ricalcolo. Pagina successo + coriandoli preservati (scelta utente). Fasi 2-3 cancellabili a blocchi (T-004), off-main; byte risolti UNA volta e riusati per aggregazione+residenza; sink a riferimento anti-O(N²). `LibraryFiguresReader.resolve/figures` + `DashboardScreen(figures:)`. **Oracoli**: `ScanPipelineProgressTests` (5), `ScanFlowTests` estesi (figures pronti / residenza misurata guida il device-now / cancel non lascia figures), aggiornati ScanFlow/HomeScan/ScanSuccess presentation tests al nuovo payload. Altitudine invariata. Copertura (L-COL-006): logica pura coperta; resa del tasto/barra e probe PhotoKit reali restano device-only (runtime non coperto in CI). **3° difetto riferito dall'utente**: ogni categoria (duplicati/simili/sfocate/grandi-vecchi) lancia il **proprio** rilevatore pesante alla prima apertura (SHA-256 / feature print Vision / nitidezza), perché la scansione costruisce solo indice+numeri, non i rilevatori. **DECISIONE utente**: «un'unica scansione fa tutto» (opzione 1) **seguita** dal ripensamento della residenza (opzione 3), ma **questa sessione solo il blueprint tecnico super-dettagliato, massima cura; implementazione la prossima sessione**. **PRODOTTO**: `blueprint/FAST-SCAN-ENGINE-PLAN.md` — studio della lentezza (con prove file:line: fetch PhotoKit uno-per-uno, decodifica full-res per un francobollo, lavoro duplicato, tutto seriale, nessuna persistenza) + piano a fasi FSE-A…FSE-G con task atomici (schema `atomic-task-schema.md`: DoD/AC/target_tests/security_notes), DAG, contratto di altitudine, protocollo di misura on-device (Instruments/MetricKit/signpost, §7), rischi&mitigazioni. **Nota onesta**: la fase 3 residenza (aggiunta in questo fix) è tra le più pesanti (I/O per originale) → candidata #1 a `FSE-G`. **Prossimo (prossima sessione)**: implementare il motore veloce dal DAG (FSE-A per prima). Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione P0-2b (2026-08-26, storico)~~** | **BUILD P0-2b — residenza per-asset reale (numero device preciso).** VERDE (oracolo CI, L-COL-002): **CI run #75 `success`** (`8bd4347`), entrambi i job — `swift build -warnings-as-errors`, `swift test` (target_tests + regressione, inclusi i nuovi `ResidencyMeasurementTests`/`ResidencyWiringTests`), `swiftlint --strict`, build app iOS Simulator. **Problema chiuso**: con iCloud "Ottimizza spazio" attivo la residenza era **indeterminata** → la Dashboard mostrava il caveat P0-3 invece del numero device reale (~8 GB sul telefono di test). P0-2b lo sostituisce con un numero **misurato per-asset**. **Dominio (oracolo puro)**: `AssetResidencyProbing` (port sincrono, componibile col motore); `ResidencyProbeItem`/`ResidencyMeasurement` (`isDeterminate` SOLO a copertura piena); `ResidencyAggregator.measure` su `ChunkedAnalysis` (T-004) — a blocchi cancellabili, su cancel/errore la misura resta **indeterminata** (residui non misurati, mai un numero parziale spacciato per totale); `ReclaimableSpaceCalculator` esteso con `measuredResidency:` — quando la misura è reale e **completa** usa il numero device misurato (col tetto di realtà P0-3), altrimenti caveat invariato; `AssumeResidentResidencyProbe` (null-object inerte). **Data (device-only)**: `PHAssetResidencyProbe` — `isNetworkAccessAllowed=false` (zero rete: originale non servibile offline ⇒ 0 byte device), residente al primo byte reale (poi cancella la richiesta per non leggere l'intero file), bridge async→sync off-main sul thread dell'aggregatore. **Wiring (Features)**: `residencyProbe` nell'`AppEnvironment` (`live` inietta `PHAssetResidencyProbe`); `LibraryFiguresReader.read(measuredResidency:)` + `probeItems(from:)`; `DashboardViewModel.measureResidency` misura off-main e ricarica col numero reale. **Oracoli nuovi**: `ResidencyMeasurementTests` (9, dominio: onestà per-asset ≤ libreria, non-residente=0, determinatezza a copertura piena, cancel/fail indeterminata, integrazione col calcolo, caso device ~8 GB), `ResidencyWiringTests` (2, features: misura completa → numero device reale sostituisce il caveat; misura cancellata → resta caveat, nessun asset sondato). **Altitudine invariata** (`AssetResidency` importa solo Foundation; il probe è un port; nessuna dipendenza `domain→data` nuova). **Baseline privacy invariata** (nessun permesso/rete nuovi; `isNetworkAccessAllowed=false` coerente). **Rete di sicurezza invariata**. **Copertura (L-COL-006)**: la logica di misura/aggregazione (onestà, determinatezza, cancellazione, integrazione col reclaimable) è coperta dai target_tests; il **probe PhotoKit reale** (~8 GB precisi, assenza di freeze su ~25k asset, cancel-responsiveness col chunk da 64) è **device-only → compilato in CI, runtime NON coperto** → da validare sul telefono. Percorso al verde: #72 rosso (2 asserzioni del test di cancellazione mal progettato — chunk unico su 20 item < 64, la cancellazione a metà non scattava; sorgenti già verdi in build+lint) → #73 rosso (solo SwiftLint: variabile `i` a 1 carattere nel test) → **#75 verde**. **P0-2b CHIUSA.** **Stato fasi POST-DEVICE**: P0 ✅, A ✅, B ✅, C ✅, D ✅, E ✅, **P0-2b ✅** → **piano POST-DEVICE COMPLETO**; unico residuo = follow-up **device-only** (sink observer→PhotoKit), non un task di piano aperto. **Prossimo (scelta utente)**: test on-device del molto costruito (runtime device non coperto dalla CI, L-COL-006), merge su `main` (gate soddisfatto), rigenerare l'`.ipa`, o release-review pre-App-Store. Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione Fase E (2026-08-26, storico)~~** | **BUILD Fase E — flusso primo avvio "Shazam" (E-1/E-2/E-3).** VERDE (oracolo CI, L-COL-002): **CI run #71 `success`** (`18c03b7`), entrambi i job su runner reali — `swift build -warnings-as-errors`, `swift test` (target_tests + regressione, inclusi i nuovi `ScanFlowPresentationTests`/`ScanSuccessPresentationTests`), `swiftlint --strict`, build app iOS Simulator. La Home è riscritta nel flusso a **tasto unico**: nessuno stato "idle" con bottone da modulo. Chiusi: **E-1** `ScanFlowPresentation` (Domain-puro-adiacente in `AngavuFeatures`): `ScanState → {ready, preparing, scanning, finished}` con progresso **onesto** — fase permesso INDETERMINATA (`fill == nil`, mai una frazione fabbricata), analisi DETERMINATA (`fill = AnalysisProgress.fraction`); `canCancel` solo in analisi (stop cooperativo preservato); `completed`/`failed` → terminale (cede a E-3), `cancelled` → ready riprovabile. **E-3** `ScanSuccessPresentation` (layer puro): decisione esito→schermata — **festa coi coriandoli SOLO al successo pieno**; accesso **limited** e **failed** → ramo onesto (conteggio dichiarato parziale / motivo esplicito + "Apri Impostazioni"); conteggio reale, mai gonfiato. **E-2 (resa View-level, L-COL-006)**: `ScanButtonView` tasto gigante che **batte** (fase permesso) e si **riempie a livello d'acqua** (frazione reale), **tutte** le animazioni gated su Reduce Motion con equivalente statico (idioma R-06); `ScanCarouselView` "leggi mentre aspetti" (contenuti E-4, swipe manuale + page indicator, auto-avanzamento lento disattivato con Reduce Motion/VoiceOver, curiosità marcate "approssimative"); `ScanResultScreen` + `ConfettiView` (Canvas/TimelineView deterministici, zero dipendenze, offline, gated). `HomeView` riscritta come container; haptic `.success/.failure` a owner unico. **Oracoli**: `ScanFlowPresentationTests` (8), `ScanSuccessPresentationTests` (5). **Altitudine invariata** (Domain puro, nessuna dipendenza domain→data nuova). **Baseline privacy invariata** (nessun permesso/rete nuovi). **Rete di sicurezza invariata** (annulla cooperativo preservato; ogni delete resta dal gate `DeletionFlow`). **Copertura (L-COL-006)**: la logica pura (flusso/esito, progresso onesto) è coperta dai target_tests; la **resa** (tasto animato, battito, riempimento, carosello, coriandoli, gating Reduce Motion/VoiceOver) è compilata dai due job CI ma **runtime NON coperto** → da validare on-device. **Fase E CHIUSA** (E-1 ✅ + E-2 ✅ + E-3 ✅; E-4 già ✅). **Stato fasi POST-DEVICE**: P0 ✅, A ✅, B ✅, D ✅, C ✅, **E ✅**; aperti — **P0-2b** (residenza per-asset precisa ~8 GB) + follow-up device-only (sink observer→PhotoKit). **Prossimo — DECISO dall'utente (2026-08-26): costruire P0-2b** (residenza per-asset PRECISA ~8 GB via API pubbliche async, cachata off-main a blocchi per non rifreezare → sostituisce il caveat con un numero device reale). Con P0-2b il piano POST-DEVICE è **completo**; resterebbe solo il follow-up device-only (sink observer→PhotoKit). Test on-device del molto già costruito resta consigliato ma a scelta dell'utente (runtime device non coperto dalla CI, L-COL-006). Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione Fase D (2026-08-26, storico)~~** | **BUILD Fase D — cache per-categoria (D-1) + progresso determinato (D-2).** VERDE (oracolo CI, L-COL-002): CI run #69 `success` (`3db2f2a`), entrambi i job — `swift build -warnings-as-errors`, `swift test` (target_tests + regressione), `swiftlint --strict`, build app iOS. Percorso: #68 rosso (solo compilazione test: `XCTAssertEqual(_:_:accuracy:)` su `fraction: Double?` → sballato con `try XCTUnwrap`; build sorgente + app iOS già verdi) → #69 verde. Chiusi: **D-1** — `AnalysisResultsStore` esteso con timestamp per-chiave (badge freschezza); `CategoryReviewView` cablata allo store `.category(rawValue)` (cache hit = rientro senza ricalcolo, niente rianalisi da capo; pull-to-refresh = «Ri-analizza»; badge «aggiornato X fa» via `RelativeFreshness` dominio puro; invalidazione su conferma eliminazione); `StoreInvalidatingLibrarySink` (IndexDelta→invalidateAll, core testato). **D-2** — `AnalysisProgressPresentation` puro (AnalysisProgress? → determinato «X di N» vs indeterminato etichettato, mai frazione fabbricata); `LoadPhase` porta `AnalysisProgress?`; Screenshot (fetch in blocco) restano onestamente indeterminati, barra reale con C-1. Estratto `CategoryReviewView+Loading.swift` (idioma +Rows/+Sections) per restare sotto `file_length` (main 375 righe). **Oracoli**: `RelativeFreshnessTests` (6), `AnalysisProgressPresentationTests` (4), `StoreInvalidatingLibrarySinkTests` (2), + estensione `AnalysisResultsStoreTests` (5 timestamp). **Altitudine invariata** (Domain puro: `RelativeFreshness` importa solo Foundation; nessuna dipendenza domain→data nuova). **Baseline privacy invariata** (nessun permesso/rete nuovi). **Copertura (L-COL-006)**: logica pura coperta dai target_tests; sopravvivenza al background, rendering barra/badge, registrazione PhotoKit dell'observer = View/device, compilati ma runtime NON coperto. **Rete di sicurezza invariata** (ogni delete dal gate `DeletionFlow`). **Fase D CHIUSA** (D-1 ✅ + D-2 ✅). **Stato fasi POST-DEVICE**: P0 ✅, A ✅, B ✅, D ✅; aperti — **C** (C-1, ora SBLOCCATA da D), E (E-1/E-2/E-3; E-4 ✅); follow-up perf P0-2b (residenza per-asset) e sink observer→PhotoKit (device-only tail). **Prossimo (scelta utente)**: **Fase C** (sblocco categorie foto — 32 GB: duplicati/simili/sfocate/grandi-vecchi, motore già verde) *oppure* **Fase E** (primo avvio Shazam). Merge su `main` **SOSPESO** (scelta utente). |
| **~~Sessione B-2 (2026-08-26, storico)~~** | **BUILD Fase B — B-2 flusso batch di compressione video.** Estesa la schermata «Comprimi video» da single-item a **BATCH** (dove vivono i ~106 GB del device-test): stima aggregata sui top-N più grandi, selezione del sottoinsieme (opt-in), coda con progresso determinato + annulla, ogni originale instradato alla rete di sicurezza. **VERDE (oracolo CI, L-COL-002): CI run #67 `success`** (`336c6c8`), entrambi i job — `swift build -warnings-as-errors`, `swift test` (target_tests + regressione), `swiftlint --strict`, build app iOS. Chiusi: **B-2a** `BatchCompressionEstimator` (Domain) — saving per-item + totale sempre `estimated`, spec assente **dichiarata non stimabile** (mai numero finto); **B-2b** `BatchCompressionSelection` (Domain) — toggle/all/none, `canStart`, **default opt-in** (nulla preselezionato), ordine d'avvio deterministico; **B-2c** `BatchCompressionRun` (Domain) — riduttore coda: **progresso X/N determinato**, un fallimento per-item **non aborta** il batch, la cancellazione lascia i residui non processati (dichiarati), esiti idempotenti; **B-2d** `BatchCompressionPresentation`/`BatchCompressionViewModel` (Features) + `CompressionView*` riscritta — **miniature reali** (riusa A-1 `RowThumbnailView`), selezione per-riga, barra determinata, esiti aggregati, nota rete di sicurezza, **cap della stima dichiarato** a schermo. 25 target_tests nuovi (`BatchCompressionEstimateTests` 4 / `BatchCompressionSelectionTests` 6 / `BatchCompressionRunTests` 5 / `BatchCompressionPresentationTests` 5 / `BatchCompressionFlowTests` 5). **Altitudine invariata** (Domain non importa AVFoundation/SwiftUI; export dietro `VideoExporting`). **Rete di sicurezza invariata**: ogni sostituzione dal gate `DeletionFlow` (T-050/T-082), originale a «Eliminati di recente». **Baseline privacy invariata** (nessun permesso/rete nuovi). **Copertura (L-COL-006)**: logica pura coperta dai target_tests; **miniature / lettura spec on-device / export HEVC reale sono device-only** (compilati in CI, runtime NON coperto — da validare sul telefono, incluso progresso/annulla su libreria 25k). **Dead-code (L-COL-021)**: il `CompressionViewModel` single-item resta in repo coi suoi test ma **non è più cablato all'UI** — rimozione lasciata all'umano. **Fase B CHIUSA** (B-1 ✅ + B-2 ✅). **Stato fasi POST-DEVICE**: P0 ✅, A ✅, B ✅; aperti — D (D-1/D-2), C (C-1, dipende da D), E (E-1/E-2/E-3, E-4 già ✅); follow-up perf P0-2b (residenza per-asset). **Prossimo (scelta utente)**: **Fase D** (cache per-categoria + progresso, prerequisito di C) *oppure* **Fase E** (primo avvio "Shazam"). Merge su `main` **SOSPESO** (scelta utente). Storico P0 e precedenti sotto. |
| **~~Sessione P0 (2026-08-25, storico)~~** | **BUILD Fase P0 (numeri device onesti + fondazione cache).** 4 incrementi committati e pushati sul branch. **VERDE (oracolo CI, L-COL-002)**: **P0-3/P0-4** — tetto di realtà + caveat residenza indeterminata (dominio puro `DeviceStorageCapacity`/`ReclaimableSpace.deviceSpaceIsDeterminate`/`ReclaimableSpaceCalculator` con `min(residente,libero,capacità)`; presentazione onesta: hero mostra la cifra device solo se determinabile, altrimenti caveat, + riga separata «Spazio in libreria (include iCloud)») a **CI run #60 `success`** (`5d22222`); **P0-2** — port `DeviceCapacityReading`+`SystemDeviceCapacityReader` (API pubbliche `volumeAvailableCapacityForImportantUsage`), `residencyIsDeterminate()` (default true; adapter reale: determinata solo con optimize-storage OFF → con optimize ON caveat, mai numero fabbricato), cablati in `AppEnvironment.live`+`LibraryFiguresReader` a **CI run #61 `success`** (`3fa47de`). **Decisione utente 2026-08-25 «Preciso, ma dopo P0»**: la residenza per-asset reale (~8 GB precisi) rischia di riportare il freeze su 25k → rimandata a **P0-2b** (task follow-up progettato per la perf); P0 chiude col caveat onesto. **⏳ NON VERIFICATO (oracolo non eseguibile)**: **P0-1** — `AnalysisResultsStore` (@Observable, cache sopra le view, iniettata App→Home→Dashboard/Report; `present()` sui VM; invalidazione su scan) + test puri (`AnalysisResultsStoreTests`), commit `71c9814`. **BLOCCO INFRA**: i run CI #62 (`71c9814`) e #63 (dispatch su `9de68ac`) falliscono in ~3-6s con **`runner_id:0`, nessuno step, log 404** — nessun runner macOS allocato (un errore di compilazione è impossibile senza runner). Causa quasi certa: **minuti Actions macOS esauriti** (privato ×10, Free ~200/mese; 4 build verdi consumate in sessione). **P0-1 resta da verificare** appena i runner macOS tornano disponibili (ri-lanciare CI: push di codice o `workflow_dispatch`). Nessun verde dichiarato a memoria per P0-1 (L-COL-002). Toolchain Swift locale assente → verifica solo CI. **Altri incrementi costruiti nella stessa sessione, `[skip ci]` (CI non eseguibile → NON verificati, da validare col ripristino dei runner insieme a P0-1)**: **A-2/A-3** selezione per-elemento + etichette umane (`d4ead0c`), **A-1** miniature reali (`AssetThumbnailProviding` + adapter `PHCachingImageManager`, `25e7fc2`), **B-1** spec video senza `AVAsset` — durata da `PHAsset.duration` + bitrate dai byte veri (`099aeea`), **E-4** `ScanCarouselContent` dominio + test (`c5a2d04`). Decisioni utente confermate nel piano (`POST-DEVICE-UX-PLAN.md`): schermata di successo con curiosità personalizzata; carosello swipe-manuale + auto-avanzamento leggero opzionale (gated Reduce Motion/VoiceOver); 22 slide. **✅ RISOLTO (2026-08-26): repo reso PUBBLICO dall'utente → CI ripristinata (minuti macOS gratis).** Tutti e 6 gli incrementi (P0-1, A-1, A-2/A-3, B-1, E-4) sono ora **VERIFICATI** — **CI run #66 `success`** (`48391c2`), entrambi i job: `swift build -warnings-as-errors`, `swift test` (target_tests + regressione, inclusi `AnalysisResultsStoreTests`/`ScanCarouselContentTests`/`RealityCeilingTests`), `swiftlint --strict`, build app iOS. Percorso: #64 rosso (build: `import Foundation` mancante in `CategoryReviewPresentation` per il `Date?` di A-3) → #65 rosso (solo 5 nit SwiftLint: `CategoryReviewView` spezzata in `CategoryReviewView+Rows.swift` + extension per file/type-body-length; variabili test rinominate) → **#66 verde**. **Regola CI normale ripristinata: niente più skip-ci; ogni push verifica.** (NB: un push era stato saltato perché il messaggio conteneva la stringa di skip come prosa — evitarla nei messaggi.) **Storico precedente sotto.** |
| **~~Sessione BUGFIX on-device (storico)~~** | **Chiusa: sessione di BUGFIX on-device (freeze scansione).** Fix runtime al di fuori del blueprint (già 100% costruito e verificato), emersi al primo test dell'`.ipa` su iPhone reale (~25k foto). **Tre cause distinte**: (1) **mappatura O(N²)→O(N)** — `LibraryAssetMapper.mapBatch` piegava gli asset in un array PER VALORE, così lo step `var next = acc; next.append(...)` ricopiava (copy-on-write) l'intero accumulatore a OGNI elemento (~300M copie di elementi su 25k foto): CPU satura + pressione di memoria = app "bloccata al 100%" fino al jetsam; **questa era la causa reale del freeze** (i due fix precedenti erano miglioramenti reali ma non la toccavano). Fix: accumulatore a riferimento (`MappedAssetSink`). (2) **indice SwiftData su `ModelContext` principale da thread sbagliato** — la scansione (fuori dal main actor) scriveva sul contesto `@Environment(\.modelContext)` (main-actor); `SwiftDataAssetIndex` è ora **container-based** e crea un contesto dedicato per operazione. (3) **upsert O(N) query** — una `FetchDescriptor` per asset → ora un solo fetch + mappa per id. (4) **letture pesanti sul main thread** — Dashboard/Report/Review-categoria/Compressione leggevano l'indice 25k + risolvevano i byte per-asset via PhotoKit (e, per duplicati/simili, hashing SHA-256 / feature print Vision) in `onAppear` SINCRONO → secondo freeze all'apertura della Dashboard. Ora: `DashboardViewModel`/`HonestReportViewModel` `load()` `async` (classi non isolate al main → generic executor), `CategoryReviewView`/`CompressionView` `loadIfNeeded` `@MainActor async` che delega il calcolo pesante a un helper `nonisolated static`; tutte invocate da `.task`/`Task`, stato aggiornato sul main. **Test di regressione**: batch mapping 10k (ordine+conteggio), upsert dedup-entro-batch + batch 2000. **VERDE (comando, L-COL-002): CI Apple `success` su `03c49b1`** (fix 1-3, run id 32829651215) e **`8a383b0`** (fix 4, run id 32835018284) — build `-warnings-as-errors`, test (target_tests + regressione), `swiftlint --strict`, build app iOS. **Copertura (L-COL-006)**: correttezza algoritmica e complessità O(N) verificate dai target_tests (Domain/Data); il comportamento CPU/memoria su una libreria reale da 25k **NON è coperto** da un oracolo automatico (CI headless) → **verifica on-device rimandata alla prossima sessione**. Merge su `main` invariato (decisione utente). **Sessione precedente (storico):** **Chiusa sul verde (BUILD rifinitura HIG — R-11, ULTIMO della coda).** **R-11 — rifiniture minori** (i tre siti residui dell'audit HIG): (1) **Transizione di fase** — in `HonestReportView` lo `switch idle→ready→failed` era un taglio netto; ora `content` ha `.animation(reduceMotion ? nil : .easeInOut, value: presentation.kind)` con `.transition(.opacity)` sui rami — dissolvenza **gated su Reduce Motion** (equivalente statico, parità informativa; stesso idioma di R-06/`ContentView`). (2) **`Picker` tema** — in `ThemeSettings` l'header di sezione «Aspetto» duplicava la label del `Picker`, tenuta nascosta con `.labelsHidden()`; ora **una sola** «Aspetto» (la label del Picker inline, che resta l'accessibility label per VoiceOver), niente header duplicato né `.labelsHidden()` da compensare. (3) **Feedback d'avanzamento** — in `ExtraPhotoDomainsView` durante il `Task` async di fusione/rimozione la riga restava interattiva e muta; ora `applyingContactID`/`applyingCalendarID` marcano la riga in corso → riga **disabilitata + spinner in coda** («Fusione/Rimozione in corso» come accessibility label), swipe soppresso, gate anti doppio-tap; liberata solo dopo l'esito reale e il ricarico. **VERDE (comando, L-COL-002)**: **CI run #49 `success`** (`d4d1cac`, verde al primo colpo) — `swift build` (-warnings-as-errors), `swift test` (target_tests + regressione), `swiftlint lint --strict`, build app iOS. **Solo `AngavuFeatures`, nessuna logica Domain/Data nuova**: altitudine invariata; baseline privacy invariata. **Copertura (L-COL-006)**: le View sono compilate dai due job CI ma **senza test di rendering** → transizione/spinner/semplificazione a runtime non coperti; nessun target_test nuovo (R-11 è View-level per piano, coerente con R-02/R-05/R-07/R-08). **Coda rifinitura HIG ESAURITA (12/12)**: nessun task R-* residuo. **Prossimo (decisione utente)**: merge su `main` (gate soddisfatto), rigenerare l'`.ipa`, o release-review pre-App-Store. Storico R-10/R-09/R-07 in §2/§5. |
| **~~Sessione R-10 (storico)~~** | **Chiusa sul verde (BUILD rifinitura HIG — R-10).** **R-10 — accessibilità di stima e simboli**: (1) **Cifra-hero del report onesto** — nel ramo stima la View rendeva `Text("~ …")` come elemento a sé → VoiceOver leggeva «tilde 128 MB». Aggiunta `HonestReportPresentation.Hero.accessibilityLabel(formattedBytes:)` (layer PURO): esatto → «128 MB recuperabili»; stima → «Stima, 128 MB recuperabili» — **mai** il `~`. In `heroHeader` il VStack è ora un solo elemento VoiceOver (`accessibilityElement(children: .ignore)` + `.isHeader` + `accessibilityLabel`), il `~` resta solo visivo per i vedenti. (2) **Wordmark onboarding** → `.accessibilityAddTraits(.isHeader)` (coerente con Home `:74` e NonGoals `:43`, che l'avevano già). (3) **Righe categoria** (Dashboard/HonestReport) **già coperte** da R-03/R-08 (`children:.ignore` + `accessibilityValue` con «, stima»; il `~` visivo non è letto) → nessuna modifica. (4) **SF Symbols**: le icone sono dimensionate via `Label` dal font del testo → già coerenti per peso/scala; nessuna modifica fabbricata (L-COL-006, no falso via libera). **VERDE (comando, L-COL-002)**: **CI run #48 `success`** (`0d9ed69`, verde al primo colpo) — `swift build` (-warnings-as-errors), `swift test` (target_tests + regressione), `swiftlint lint --strict`, build app iOS. **Layer puro (oracolo)**: 2 target_test nuovi in `HonestReportPresentationTests` (esatto senza marca né `~`; stima nomina «Stima» senza `~`). **Solo `AngavuFeatures` + `App/`, nessuna logica Domain/Data nuova**: altitudine invariata; baseline privacy invariata. **Copertura (L-COL-006)**: label della stima verificata dai target_test; le View compilate dai due job CI ma **senza test di rendering** → resa VoiceOver a runtime non coperta. **Prossimo: R-11** (rifiniture minori: transizione idle→ready→failed, `Picker`/`labelsHidden` ridondante, spinner in coda durante fusione/rimozione). Storico R-09/R-08/R-07 in §2/§5. |
| **~~Sessione R-09 (storico)~~** | **Chiusa sul verde (BUILD rifinitura HIG — R-09).** **R-09 — parsimonia gradiente/glow + contrasto testo-su-accento**: (1) **Parsimonia** — il gradiente Aurora era usato due volte per schermata (titolo-header + cifra-hero). I titoli-header di Dashboard, HonestReport, Review categorie e Compressione passano da gradiente a **`.primary`**; la cifra-hero (o la stima) resta **l'unico** uso del gradiente. Il wordmark «Angavu» (Home/Onboarding) e il titolo NonGoals restano gradiente (uso singolo canonico). (2) **Contrasto CTA** — nuovo `AuroraBrand.onGradient = Color(light: bianco, dark: inchiostro scuro)`: il bianco su gradiente **scuro** era ~2,4:1 (illeggibile), l'inchiostro scuro su stop pastello dark = **7,3–8,1:1** (AA pieno); in chiaro il bianco su stop saturi = 3,4–4,4:1, reso conforme **AA-large** portando le CTA a `headline` **bold** (≥17pt bold = testo grande, soglia 3:1). Applicato ai 5 riempimenti CTA (Home, Review, Compressione ×2, Onboarding). (3) **Glow** verificato **top-anchored** (`RadialGradient` da `.top` che sfuma a `.clear` a 320pt, trasparente sotto) — non un fondo pieno, nessuna modifica. **VERDE (comando, L-COL-002)**: **CI run #47 `success`** (`4aef03c`, verde al primo colpo) — `swift build` (-warnings-as-errors), `swift test` (target_tests + regressione), `swiftlint lint --strict`, build app iOS. **Solo-View (`AngavuFeatures`), nessuna logica Domain/Data nuova**: altitudine invariata; baseline privacy invariata. **Copertura (L-COL-006)**: contrasto verificato per **calcolo WCAG** (ratii documentati); le View compilate dai due job CI ma **senza test di rendering** → resa a runtime non coperta; nessun target_test nuovo (View-level per piano). **Prossimo: R-10** (accessibilità di stima e simboli). Storico R-07/R-08 in §2/§5; R-00…R-06 in §2/§5. |
| **~~Sessione R-07 (storico)~~** | **Chiusa sul verde (BUILD rifinitura HIG — R-07).** **R-07 — `ProgressView` sempre etichettata + avanzamento determinato**: gli spinner nudi degli stati idle/loading non dicevano cosa stesse accadendo (né a schermo né a VoiceOver). Etichettati i **quattro spinner lone di intera-schermata** con label oneste (la label di `ProgressView` è anche la sua accessibility label): `HonestReportView` idle → «Calcolo del report…», `DashboardView` idle → «Calcolo dei numeri veri…», `CompressionView` loading-indice → «Lettura dei video…», `CategoryReviewView` loading → «Analisi della categoria…». **Non-nudi, invariati**: gli spinner di `HomeView` (`.working`/`.requestingPermission`) e del `workingCard` di `CompressionView+Sections` sono già dentro card etichettate (title header/adiacente). `HomeView.scanning` è già `ProgressView(value:)` **determinato**. `ExtraPhotoDomainsView` non ha più spinner (load sincrono, refactor R-05): il riferimento del piano `:84-88` era stale (commit `ee3b6d8`). **Nessuna frazione reale d'export** è instradata nel Domain state (`CompressionState .exporting/.replacing` non la portano) → il `workingCard` resta indeterminato ma etichettato: niente numeri fabbricati (numeri veri). **VERDE (comando, L-COL-002)**: **CI run #45 `success`** (`01c0db7`, verde al primo colpo) — `swift build` (-warnings-as-errors), `swift test` (target_tests + regressione), `swiftlint lint --strict`, build app iOS. **Solo-View (`AngavuFeatures`), nessuna logica Domain/Data nuova**: altitudine invariata; baseline privacy invariata. **Copertura (L-COL-006)**: le View sono compilate dai due job CI ma **senza test di rendering** → resa a runtime non coperta (coerente con R-02/R-05); nessun target_test nuovo (R-07 è View-level per piano). **Prossimo: R-08** (layout categoria adattivo a Dynamic Type grande, `ViewThatFits`). Storico dei task HIG precedenti (R-00…R-06) in §2 e §5. |

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

> **✅ COMPLETATA = coda di rifinitura HIG (12/12).** Coda `R-00…R-11` del
> `blueprint/HIG-REFINEMENT-PLAN.md`, 1-2 task per sessione, ognuno **chiuso al
> confine CI** (`swift build -warnings-as-errors` + `swift test` + `swiftlint
> --strict` + build app iOS verdi). **Chiusi**: **R-00** (persistenza onboarding
> `@State`→`@AppStorage` + `OnboardingGate` puro) e **R-01** (cifra-hero scalabile:
> `AuroraType` puro + `.auroraHeroNumber()`) a **run #38**; **R-02** (titolo unico
> per schermata — nav bar `.inline`) a **run #39** (`091b71f`); **R-03** (VoiceOver:
> righe/card come singolo elemento con label/valori umani dal layer puro — mai il
> `localIdentifier` grezzo —, trait `isHeader` sui titoli, icone decorative
> `accessibilityHidden`; sezioni Dashboard estratte in `+Sections` per
> `type_body_length`) a **run #41 `success`** (`57e919a`; NB run #40 rosso solo sul
> lint, fix riverificata a #41); **R-04** (etichette VoiceOver azione+oggetto sui
> bottoni «Fondi»/«Rimuovi» + hint «Stima il risparmio» sulla riga compressione dal
> layer puro; tap target ≥44pt; `swipeActions` distruttivo instradato allo stesso
> gate human-gated) a **run #42 `success`** (`59616f0`, verde al primo colpo);
> **R-05** (stati vuoto/errore uniformati sull'idioma iOS 17 `ContentUnavailableView`
> — Dashboard errore, CategoryReview vuoto, Compressione «nessun video»+errore d'indice,
> ExtraPhotoDomains stato vuoto d'intera schermata; retry preservato, errore≠vuoto) a
> **run #43 `success`** (`9730b36`, verde al primo colpo).
> **R-06** (micro-interazioni aptiche sui momenti-firma con vocabolario per rarità
> `FeedbackEvent`→`FeedbackLevel` puro; toggle utente «Feedback aptico»; transizione
> onboarding→home animata ma gated su Reduce Motion) a **run #44 `success`**
> (`18892a9`, verde al primo colpo).
> **R-07** (`ProgressView` idle/loading sempre etichettata: quattro spinner lone di
> intera-schermata — HonestReport «Calcolo del report…», Dashboard «Calcolo dei
> numeri veri…», Compression «Lettura dei video…», CategoryReview «Analisi della
> categoria…»; Home/`workingCard` già etichettati, Home.scanning già determinato,
> ExtraPhotoDomains senza spinner; nessuna frazione d'export fabbricata) a
> **run #45 `success`** (`01c0db7`, verde al primo colpo).
> **R-08** (layout categoria adattivo a Dynamic Type grande: righe «titolo … valore»
> in `HStack`+`Spacer()` avvolte in `ViewThatFits(in: .horizontal)` con fallback a
> colonna singola prima di troncare — `DashboardCategoryRow`, `HonestReportCategoryRow`
> (`titleColumn`/`valueColumn` estratti, titolo `lineLimit(2)`+`allowsTightening`),
> `CategoryReviewRowView` (`identity`/`badge` estratti, badge sotto nel fallback);
> accessibility invariata, un solo elemento VoiceOver in entrambi i branch) a
> **run #46 `success`** (`1c075d9`, verde al primo colpo).
> **R-09** (parsimonia gradiente: titoli-header di Dashboard/HonestReport/Review/
> Compressione da gradiente a `.primary`, la cifra-hero resta l'unico uso; contrasto
> CTA: `AuroraBrand.onGradient` scheme-adaptive — inchiostro scuro su gradiente dark
> 7,3–8,1:1 AA, bianco su gradiente chiaro reso AA-large con CTA bold; glow verificato
> top-anchored) a **run #47 `success`** (`4aef03c`, verde al primo colpo).
> **R-10** (accessibilità di stima e simboli: cifra-hero del report onesto come
> singolo elemento VoiceOver con label parlata dal layer puro — esatto «128 MB
> recuperabili», stima «Stima, 128 MB recuperabili», **mai** il `~` letto «tilde» —
> + `.isHeader` sul wordmark onboarding, coerente con Home/NonGoals; righe categoria
> già coperte da R-03/R-08, SF Symbols già coerenti via `Label`) a **run #48
> `success`** (`0d9ed69`, verde al primo colpo).
> **R-11 — ULTIMO della coda** (rifiniture minori) a **run #49 `success`**
> (`d4d1cac`, verde al primo colpo): (1) transizione di fase `idle→ready→failed` in
> `HonestReportView` animata con dissolvenza **gated su Reduce Motion** (equivalente
> statico, idioma R-06); (2) `Picker` tema in `ThemeSettings` semplificato — rimossa
> la ridondanza header-di-sezione / label-Picker (una sola «Aspetto», niente
> `.labelsHidden()` da compensare, accessibility label preservata); (3) in
> `ExtraPhotoDomainsView` durante il `Task` async di fusione/rimozione la riga è
> **disabilitata + spinner in coda** (label onesta, swipe soppresso, gate anti
> doppio-tap), liberata solo dopo l'esito reale. Nessuna logica nuova Domain/Data:
> solo `AngavuFeatures` + `App/`, guardato `#if canImport(SwiftUI)`; R-11 è
> View-level (nessuna decisione presentabile pura estratta) → nessun target_test
> nuovo, View compilate-non-rese (L-COL-006). L'altitudine resta invariata.
>
> **➡️ CODA DI RIFINITURA HIG ESAURITA (12/12).** Nessun task R-* residuo. Con
> **piano di build 11/11 + `wiring` 8/8 + guscio UI 8/8 + rifinitura HIG 12/12**
> tutti verdi in CI, il blueprint è **interamente costruito e verificato**. Prossimi
> passi possibili (**decisione utente**, nessuno è un task di blueprint aperto):
> merge su `main` (gate soddisfatto, branch mergeabile), rigenerare l'`.ipa`,
> release-review pre-App-Store (apple-skills:release-review).

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
| Ultimo commit | `8ccfada` (session-end) — **FSE-A1** verde (**CI run #79 `success`**): fondazioni + strumentazione di misura (signpost per fase + MetricKit idempotente), apre la fase FSE-A del motore veloce (`blueprint/FAST-SCAN-ENGINE-PLAN.md`). Storia recente verde: scansione unificata `3460690` (#78), piano POST-DEVICE completo P0/A/B/C/D/E/P0-2b (#60→#75). **Prossima sessione — DECISO dall'utente: FSE-A2** (poi FSE-B/FSE-C, dal DAG §4 del piano). Consigliato: test on-device (runtime device non coperto dalla CI, L-COL-006). Merge su `main` **SOSPESO** (scelta utente). CI normale (repo pubblico). |
| Stato merge su `main` | **gate soddisfatto**: CI Apple verde (build+test+lint+app iOS) su **tutti gli 11 macrotask + `wiring` (8/8)**. Merge non ancora eseguito (decisione dell'utente); il branch è mergeabile |
| Deploy-coupling | `main_deploy_coupled: unknown` — nessun deploy automatico noto (app iOS via App Store Connect, fuori dal repo) |

## 4. Baseline & budget

- **Baseline privacy/sicurezza**: `blueprint/BASELINE-AND-BUDGET.md` — findings accettati / soglie.
- **Budget consumato**: 0 (BOOTSTRAP) / vedi `BASELINE-AND-BUDGET.md`.

## 5. Esiti dell'ultima sessione (framing onesto)

- **PROGETTAZIONE post-device — `POST-DEVICE-UX-PLAN.md`** (questa sessione, seconda
  parte). Il primo test dell'`.ipa` su iPhone reale (128 GB, ~25k asset, iCloud
  Optimize attivo) ha scoperto 6 difetti funzionali/onestà/UX che la CI headless non
  coglie. Output: un piano di repo con task atomici (DoD/acceptance/target_test),
  decisioni bloccate con l'utente e sequenza **P0→A→B→D→C**. **P0 (🔴 onestà)**: la
  dashboard mostrava "139,21 GB liberabili sul telefono ora" su un 128 GB dove Foto
  occupa 7,99 GB reali — causa `SystemDeviceStorageInspector.deviceResidentBytes`
  che ritorna i byte-libreria (somma l'intera libreria in iCloud). Fix scelto:
  residenza reale per-asset (API pubbliche) + tetto di realtà (capacità/libero
  device) + caveat, risultato cachato in uno store sopra la view (che risolve anche
  la rianalisi da navigazione/background). **Nessuna modifica al codice dell'app**:
  solo piano (`0ac3dfa`, doc-only, no CI). Il prossimo lavoro parte dal P0.

- **BUGFIX on-device — freeze della scansione** (questa sessione, prima parte). Al primo test
  dell'`.ipa` su iPhone reale (~25k foto) la scansione arrivava al 100% e poi
  l'intera app si bloccava. Tre difetti runtime distinti, tutti al di fuori del
  blueprint (già 100% costruito):
  - **(causa reale) mappatura O(N²)→O(N)** — `LibraryAssetMapper.mapBatch`
    accumulava gli asset in un array PER VALORE: lo step `var next = acc;
    next.append(...)` innescava a OGNI elemento una copia copy-on-write dell'intero
    accumulatore (~300M copie di elementi su 25k foto) → CPU satura + pressione di
    memoria = "blocco al 100%" fino al jetsam. Fix: accumulatore a riferimento
    (`MappedAssetSink`), append in place, O(N) totale. I due fix sotto erano
    miglioramenti reali ma NON toccavano questa causa (per questo il freeze restava
    identico). Test: batch mapping 10k (ordine+conteggio preservati).
  - **indice SwiftData su contesto sbagliato** — la scansione gira fuori dal main
    actor ma scriveva sul `ModelContext` PRINCIPALE (`@Environment(\.modelContext)`,
    main-actor). `SwiftDataAssetIndex` è ora **container-based**: un `ModelContext`
    dedicato per operazione, isolato dal contesto principale. `AppEnvironment.live`
    riceve il container; `ContentView` passa `modelContext.container`.
  - **upsert O(N) query** — una `FetchDescriptor` per asset → ora un solo fetch +
    mappa per id + un solo `save()`. Test: dedup-entro-batch, batch 2000.
  - **VERDE (comando, L-COL-002)**: **CI Apple `success` su `03c49b1`** (run id
    32829651215) — build `-warnings-as-errors`, test (target_tests + regressione),
    `swiftlint --strict`, build app iOS. Fix riverificate con lo STESSO gate CI
    (L-COL-003): i due rossi solo-lint intermedi (`528c538`, e uno shorthand-dict)
    sono stati corretti e riverificati verdi.
  - **Copertura (L-COL-006)**: correttezza algoritmica e complessità O(N) verificate
    dai target_tests (Domain puro / Data al confine Apple); il comportamento
    CPU/memoria su una **libreria reale da 25k NON è coperto** da un oracolo
    automatico (CI headless, nessun device con 25k foto) → **la conferma on-device è
    rimandata alla prossima sessione**. Altitudine invariata (nessun import
    proibito); baseline privacy invariata (nessun permesso/rete/framework nuovo).

- **Rifinitura HIG — R-11: rifiniture minori (ULTIMO della coda)** (sessione precedente).
  I tre siti residui dell'audit HIG, tutti View-level in `AngavuFeatures`.
  - **Transizione di fase** (`HonestReportView`): lo `switch idle→ready→failed` era un
    taglio netto. Ora `content` porta `.animation(reduceMotion ? nil : .easeInOut,
    value: presentation.kind)` con `.transition(.opacity)` sui rami → dissolvenza
    **gated su Reduce Motion** con equivalente statico (parità informativa; stesso
    idioma di R-06/`ContentView`). `presentation.kind` è già `Equatable`.
  - **`Picker` tema** (`ThemeSettings`): l'header di sezione «Aspetto» duplicava la
    label del `Picker`, nascosta con `.labelsHidden()`. Ora **una sola** «Aspetto» —
    la label del `Picker` inline, che resta l'accessibility label per VoiceOver —,
    header duplicato e `.labelsHidden()` rimossi. Nessun impatto funzionale sulla
    selezione del tema.
  - **Feedback d'avanzamento** (`ExtraPhotoDomainsView`): durante il `Task` async di
    fusione/rimozione la riga restava interattiva e muta. Aggiunti
    `applyingContactID`/`applyingCalendarID` (`String?`): la riga in corso è
    **disabilitata** e mostra uno **spinner in coda** (accessibility label «Fusione/
    Rimozione in corso»), lo swipe distruttivo è soppresso, un `guard` evita il
    doppio-tap; la riga si libera solo dopo l'esito reale e il ricarico.
  - **VERDE (comando, L-COL-002)**: **CI Apple run #49 `success`** (`d4d1cac`, verde al
    primo colpo) — build (-warnings-as-errors), test (target_tests + regressione),
    lint --strict, build app iOS.
  - **Copertura (L-COL-006)**: R-11 è View-level → nessuna decisione presentabile pura
    estratta, **nessun target_test nuovo** (coerente con R-02/R-05/R-07/R-08); le View
    sono compilate dai due job CI ma **senza test di rendering** → transizione, spinner
    e semplificazione a runtime non coperti. Solo `AngavuFeatures` + `App/`: altitudine
    e baseline privacy invariate. **Con R-11 la coda di rifinitura HIG è esaurita
    (12/12).**


- **Rifinitura HIG — R-10: accessibilità di stima e simboli** (sessione precedente). La
  cifra-hero del report onesto, nel ramo stima, rendeva `Text("~ …")` come elemento a
  sé → VoiceOver leggeva «tilde 128 MB».
  - **Layer PURO (oracolo)**: aggiunta `HonestReportPresentation.Hero.accessibilityLabel(formattedBytes:)`
    — esatto → «128 MB recuperabili»; stima → «Stima, 128 MB recuperabili», **mai** il
    `~`. Coperta da 2 target_test nuovi in `HonestReportPresentationTests` (esatto senza
    marca né `~`; stima nomina «Stima» senza `~`).
  - **View**: in `heroHeader` il VStack è ora un solo elemento VoiceOver
    (`accessibilityElement(children: .ignore)` + `.isHeader` + `accessibilityLabel`
    dalla presentazione); il `~` resta solo visivo per i vedenti. `.isHeader` aggiunto al
    wordmark di `OnboardingManifestoView` (coerente con Home `:74` e NonGoals `:43`).
  - **Già coperto / non toccato (L-COL-006, no falso via libera)**: le righe categoria
    (Dashboard/HonestReport) erano già `children:.ignore` + `accessibilityValue` con
    «, stima» (R-03/R-08) → il `~` visivo non è letto; le icone SF sono dimensionate via
    `Label` dal font del testo → già coerenti per peso/scala. Nessuna modifica fabbricata.
  - **VERDE (comando, L-COL-002)**: **CI Apple run #48 `success`** (`0d9ed69`, verde al
    primo colpo) — build (-warnings-as-errors), test (target_tests + regressione),
    lint --strict, build app iOS.
  - **Copertura (L-COL-006)**: label della stima verificata dai target_test; le View
    compilate dai due job CI ma **senza test di rendering** → resa VoiceOver a runtime non
    coperta. Solo `AngavuFeatures` + `App/`: altitudine e baseline privacy invariate.


- **Rifinitura HIG — R-09: parsimonia gradiente + contrasto testo-su-accento** (sessione
  precedente). **Parsimonia**: un solo gradiente per schermata — i titoli-header di
  Dashboard/HonestReport/Review/Compressione da gradiente a `.primary`, la cifra-hero
  Dashboard/HonestReport/Review/Compressione da gradiente a `.primary`, la cifra-hero
  resta l'unico uso; wordmark «Angavu» e titolo NonGoals restano gradiente (uso singolo).
  **Contrasto**: `AuroraBrand.onGradient` scheme-adaptive (bianco chiaro / inchiostro
  scuro dark) sui 5 riempimenti CTA — risolve il bianco-su-gradiente-scuro ~2,4:1
  (inchiostro scuro su pastello dark = 7,3–8,1:1, AA pieno); in chiaro AA-large con CTA
  `headline` bold. **Glow** verificato top-anchored (sfuma a `.clear`, non fondo pieno).
  - **VERDE (comando, L-COL-002)**: **CI Apple run #47 `success`** (`4aef03c`, verde al
    primo colpo) — build (-warnings-as-errors), test, lint --strict, build app iOS.
  - **Copertura (L-COL-006)**: contrasto verificato per calcolo WCAG (ratii documentati);
    View compilate dai job CI ma senza test di rendering → resa a runtime non coperta;
    nessun target_test nuovo (View-level). Solo-View, altitudine/privacy invariate.


- **Rifinitura HIG — R-08: layout categoria adattivo a Dynamic Type grande** (questa
  sessione): le righe «titolo … valore» erano `HStack` con `Spacer()` e titolo senza
  `lineLimit` → alle accessibility sizes i due lati si comprimevano o troncavano.
  Avvolte in **`ViewThatFits(in: .horizontal)`** con fallback a **colonna singola**
  (valore sotto il titolo) prima di troncare, ai **tre siti** dell'audit:
  - `DashboardCategoryRow` (`DashboardView.swift`) e `HonestReportCategoryRow`
    (`HonestReportView.swift`): estratti `titleColumn`/`valueColumn` riusati nei due
    branch; titolo `lineLimit(2)`+`allowsTightening(true)`, byte `lineLimit(1)`.
  - `CategoryReviewRowView` (`CategoryReviewView.swift`): estratti `identity`
    (icona+id, id già `lineLimit(1)`+`truncationMode(.middle)`) e `badge`; il badge di
    disposizione è portato **sotto** nel fallback verticale, con `lineLimit(1)`.
  - **Onestà/accessibilità**: i modifier VoiceOver (`accessibilityElement(children:
    .ignore)` + label/value **umani** dal layer puro) avvolgono `ViewThatFits`, quindi
    **un solo elemento** leggibile in **entrambi** i branch — nessuna regressione R-03.
  - **Solo-View (`AngavuFeatures`), nessuna logica Domain/Data nuova**: altitudine
    invariata; baseline privacy invariata (nessun permesso/rete/framework nuovo).
  - **VERDE (comando, L-COL-002)**: **CI Apple run #46 `success`** (`1c075d9`, verde
    al primo colpo) — `swift build` (-warnings-as-errors), `swift test` (target_tests
    + regressione), `swiftlint lint --strict`, build app iOS.
  - **Copertura (L-COL-006)**: le View sono compilate dai due job CI ma **senza test
    di rendering** → resa a runtime a XXL/AX non coperta (coerente con R-02/R-05/R-07).
    Nessun target_test nuovo: R-08 è View-level per piano (`ViewThatFits`+`lineLimit`,
    non decisioni presentabili pure).

- **Rifinitura HIG — R-07: `ProgressView` idle/loading sempre etichettata** (sessione
  precedente): gli spinner nudi degli stati idle/loading non comunicavano nulla, né a
  schermo né a VoiceOver. Etichettati i **quattro spinner lone di intera-schermata**
  con label oneste (la label di `ProgressView` è anche la sua accessibility label):
  `HonestReportView` idle → «Calcolo del report…», `DashboardView` idle → «Calcolo
  dei numeri veri…», `CompressionView` loading-indice → «Lettura dei video…»,
  `CategoryReviewView` loading → «Analisi della categoria…». **Non-nudi, lasciati
  invariati**: gli spinner di `HomeView` (`.working`/`.requestingPermission`) e del
  `workingCard` di `CompressionView+Sections` vivono già dentro card etichettate;
  `HomeView.scanning` è già `ProgressView(value:)` **determinato**;
  `ExtraPhotoDomainsView` non ha più spinner (load sincrono dopo il refactor R-05 —
  il riferimento del piano `:84-88` era al commit stale `ee3b6d8`). **Onestà (numeri
  veri)**: nessuna frazione d'export reale è instradata nel Domain state
  (`CompressionState .exporting/.replacing` non la porta), quindi il `workingCard`
  resta indeterminato ma etichettato — nessun avanzamento fabbricato. **Solo-View
  (`AngavuFeatures`), nessuna logica Domain/Data nuova**: altitudine invariata;
  baseline privacy invariata (nessun nuovo permesso/rete/framework).
  - **VERDE (comando, L-COL-002)**: **CI Apple run #45 `success`** (`01c0db7`, verde
    al primo colpo) — `swift build` (-warnings-as-errors), `swift test` (target_tests
    + regressione), `swiftlint lint --strict`, build app iOS.
  - **Copertura (L-COL-006)**: le View sono compilate dai due job CI ma **senza test
    di rendering** → resa a runtime non coperta (coerente con R-02/R-05). Nessun
    target_test nuovo: R-07 è View-level per il piano (label statiche, non decisioni
    presentabili pure).

- **Rifinitura HIG — R-06: micro-interazioni aptiche + Reduce Motion** (sessione
  precedente): i momenti-firma non davano feedback, le transizioni di fase erano tagli
  netti. **Layer PURO (oracolo)**: `FeedbackEvent`→`FeedbackLevel`, vocabolario per
  rarità (un evento = un livello, livelli distinti — `FeedbackTests`); `HapticsPreference`
  (default attivo). **Guardato SwiftUI**: `FeedbackLevel.sensoryFeedback` + modificatore
  `.hapticFeedback(on:)` subordinato al toggle utente (nessun buzz se disattivato).
  **Wiring** (un solo owner per evento): Home fine scan (success/failure), Compressione
  done/failed, ExtraPhotoDomains esito, CategoryReview apertura anteprima distruttiva
  (warning), Onboarding avanzamento (impact leggero). **Transizione** onboarding→home
  animata ma **gated su Reduce Motion** (`withAnimation(nil)` = equivalente statico).
  **Toggle** «Feedback aptico» in `ThemeSettingsView`. Nessuna logica Domain/Data nuova.
  - **VERDE (comando, L-COL-002)**: **CI Apple run #44 `success`** (`18892a9`, verde al
    primo colpo) — build (-warnings-as-errors), test, lint --strict, build app iOS.
  - **Copertura (L-COL-006)**: vocabolario puro coperto dai target_tests; wiring/
    transizioni/haptics compilati dai due job CI ma **senza test di rendering** → resa a
    runtime (vibrazioni, animazioni) dichiarata non coperta.

- **Rifinitura HIG — R-05: stati vuoto/errore uniformi** (sessione precedente): empty ed
  error-state erano card custom disomogenee (a volte `Text` nudo). Uniformati
  sull'idioma iOS 17 **`ContentUnavailableView`** (icona + titolo + descrizione +
  azione), preservando la distinzione **onesta** errore≠vuoto e il retry dove serve:
  `DashboardView.failedCard` (con «Riprova» gated su `showsRetry`),
  `CategoryReviewView.emptyCard`, `CompressionView+Sections` (`noVideosCard` +
  `indexFailedCard` con «Riprova»), `ExtraPhotoDomainsView` (stato vuoto d'intera
  schermata quando contatti E calendari sono vuoti e non c'è errore/esito; altrimenti
  la List invariata). **Solo-View, nessuna logica Domain/Data nuova** (come R-02):
  altitudine invariata; baseline privacy invariata.
  - **VERDE (comando, L-COL-002)**: **CI Apple run #43 `success`** (`9730b36`, verde al
    primo colpo) — `swift build` (-warnings-as-errors), `swift test` (target_tests +
    regressione), `swiftlint lint --strict`, build app iOS.
  - **Copertura (L-COL-006)**: le View sono compilate dai due job CI ma **senza test di
    rendering** → resa a runtime dichiarata non coperta. Nessun target_test nuovo (il
    cambiamento è di sola presentazione SwiftUI, coerente con R-02).

- **Guscio UI — schermate 7-8/8: coppia del manifesto** (sessione precedente; le due
  schermate richieste insieme dall'utente). Erano le uniche due viste del guscio a
  **contenuto statico** senza layer di presentazione puro: ora allineate alle altre 6.
  Nessuna logica nuova nel Domain/Data (contenuto già in `ManifestContent`, T-100).
  - **Schermata 7 — «Cosa NON facciamo»** (`NonGoalsView`):
    - `NonGoalsPresentation` (`Sources/AngavuFeatures/NonGoalsPresentation.swift`, PURO):
      mappa `ManifestContent.nonGoals` in righe presentabili con **SF Symbol per
      categoria** (prima un'unica `xmark`); porta in superficie l'invariante di onestà
      `allAreRenunciations` (nessun non-goal è un claim di capacità, AC-100-2). Riusa la
      mappa d'icona come dato puro.
    - `NonGoalsView` riscritta per consumare la presentazione + `navigationTitle` inline
      (guardato `UIKit`).
    - **Navigazione riparata (bug reale)**: dall'onboarding il link «Cosa NON facciamo»
      invocava `onShowNonGoals` che faceva solo `didFinishOnboarding = true` → **saltava
      l'onboarding e andava alla Home**, la schermata non veniva mai mostrata da lì. Ora
      è un `NavigationLink` reale verso `NonGoalsView`; callback rotto rimosso da
      `ContentView`. (Restava comunque raggiungibile dalla Home, `HomeView`.)
  - **Schermata 8 — «Onboarding-manifesto»** (`OnboardingManifestoView`):
    - `OnboardingManifestoPresentation` (`Sources/AngavuFeatures/OnboardingManifestoPresentation.swift`,
      PURO): wordmark, headline dal contenuto, righe promessa con **SF Symbol**;
      invariante `allPromisesOnDevice` (ogni promessa mantenibile on-device, AC-100-2).
    - `OnboardingManifestoView` riscritta per consumare la presentazione; mappa d'icona
      `symbol(for:)` spostata nel layer puro (prima era nella view).
  - **VERDE (comando)**: **CI Apple run #35 `success`** (`db51f27`) — `swift build`
    (-warnings-as-errors), `swift test` (target_tests + regressione), `swiftlint lint
    --strict`, `build app (iOS Simulator)`. Verde al primo colpo. Il verdetto è di un
    **comando** (L-COL-002), verificabile nella tab Actions.
  - **Copertura (L-COL-006)**: `NonGoalsPresentation` (7 target_tests:
    `NonGoalsPresentationTests`) e `OnboardingManifestoPresentation` (7 target_tests:
    `OnboardingManifestoPresentationTests`) coperti in `AngavuFeaturesTests`, **incluse
    le contro-prove degli invarianti** (un claim di capacità rompe `allAreRenunciations`;
    una promessa non-on-device rompe `allPromisesOnDevice` → oracoli non vacui) e la
    distinzione delle icone per categoria. Le due View SwiftUI sono compilate dai due job
    CI ma **senza test di rendering**: resa a runtime non coperta. Baseline privacy
    invariata (nessun nuovo permesso/rete/framework; solo SF Symbols di sistema).
  - **Guscio UI: 8/8 schermate «fatte bene»** (Home, Dashboard, Review categorie,
    Compressione, Contatti/calendari, Report onesto, Cosa NON facciamo, Onboarding).

- **Guscio UI — schermata 6/N: Report onesto** (sessione precedente; cadenza "una
  schermata per sessione, fatta bene"): cablata la schermata del report onesto al
  `HonestReportViewModel` (T-114) — che era wired ma senza schermata viva: la vecchia
  `HonestReportView` prendeva un `HonestReport` statico in `init(report:)` e **non era
  in navigazione**. Nessuna logica nuova nel Domain/Data.
  - `HonestReportPresentation` (`Sources/AngavuFeatures/HonestReportPresentation.swift`,
    PURO): mappa `HonestReportState` (idle/ready/failed) nelle decisioni di UI —
    **cifra-hero** esatta SOLO quando nulla è stimato, altrimenti marcata come stima
    (mai un unico totale "esatto" quando c'è una porzione stimata, AC-102-1); righe per
    categoria con la marca della stima; riepilogo spazio recuperabile libreria vs device
    ORA + **caveat iCloud** (derivato, AC-102-1); banner **conteggio parziale** con invito
    all'accesso completo su accesso `limited` (AC-102-2); stato d'errore con motivo +
    «Riprova». Riusa `DashboardPresentation.title(for:)` come unica fonte dei titoli
    categoria. Testabile senza device.
  - `HonestReportView` (`Sources/AngavuFeatures/HonestReportView.swift`, SwiftUI guardata
    `canImport(SwiftUI)`): **riscritta** per consumare `HonestReportViewModel` via la
    presentazione (`init(environment:)`, `onAppear` una-volta, «Riprova» ricompone),
    invece del valore statico slegato dalla navigazione. Hero, righe categoria, card
    recuperabile con nota iCloud, banner parziale, errore.
  - `DashboardView`: nuova sezione «Il quadro completo» che naviga al `HonestReportView`,
    conservando l'`AppEnvironment` iniettato (nessun singleton).
  - **VERDE (comando)**: **CI Apple run #34 `success`** (`3116bbc`) — `swift build`
    (-warnings-as-errors), `swift test` (target_tests + regressione), `swiftlint lint
    --strict`, `build app (iOS Simulator)`. Verde al primo colpo. Il verdetto è di un
    **comando** (L-COL-002), verificabile nella tab Actions.
  - **Copertura (L-COL-006)**: `HonestReportPresentation` coperta da 10 target_tests
    (`HonestReportPresentationTests`: idle/ready/failed, hero esatto vs stima + contro-prova,
    marca stima per categoria, caveat iCloud + contro-prova, banner parziale/invito +
    contro-prova). `HonestReportViewModel` già coperto (wiring T-114). `HonestReportView`
    compilata dai due job CI ma **senza test di rendering**: resa a runtime non coperta.
    Baseline privacy invariata (nessun nuovo permesso/rete/framework).

- **Guscio UI — schermata 5/N: Contatti e calendari** (sessione precedente; cadenza
  "una schermata per sessione, fatta bene"): costruita la schermata dei domini
  extra-foto che presenta i due view-model cablati (`Contacts/CalendarsReviewViewModel`,
  T-115). Contatti duplicati da fondere e sottoscrizioni calendario sospette da
  rimuovere; ogni azione è **human-gated** (T-092): un tap apre un `confirmationDialog`
  e SOLO dopo la conferma l'adapter è invocato; l'esito reale (applicato/annullato/
  fallito) è mostrato onestamente. I calendari **locali non compaiono mai** (T-091).
  - **Composition root esteso**: `ExtraDomainsPorts` come bundle **opzionale** su
    `AppEnvironment` — `nil` finché `.live()` non cabla gli adapter reali
    (Contacts/EventKit, sotto guardia `canImport`). Capacità permission-gated ASSENTE,
    mai un fake nascosto; zero churn ai 6 helper di test (parametro con default).
  - **`ExtraPhotoDomainsPresentation`** (puro): righe presentabili, stati vuoti onesti,
    nota di sicurezza, messaggi d'esito — 10 target_tests, girano su Linux.
  - **`ExtraPhotoDomainsView`** (guardata SwiftUI): due sezioni + `confirmationDialog`
    per azione; aggancio dalla Dashboard (sezione «Oltre le foto», solo se le porte
    sono cablate).
  - **VERDE (comando)**: **CI Apple run #33 `success`** (`abf6be6`) — `swift build`
    (-warnings-as-errors), `swift test` (target_tests + regressione), `swiftlint lint
    --strict`, `build app (iOS Simulator)`. Verde al primo colpo.
  - **Copertura (L-COL-006)**: la presentazione è coperta dai target_tests; la view è
    **compilata** dal build app iOS ma **senza test di rendering** (resa a runtime non
    coperta); gli adapter reali `System*` (Contacts/EventKit) compilati in CI ma runtime
    device non coperto (Apple-only). Baseline privacy invariata (permessi già dichiarati).

- **Guscio UI — schermata 4/N: Compressione video** (chiusa a **run #32**, `ebe0ead`,
  senza aggiornare questo doc — recuperato ora): presenta `CompressionViewModel` (T-116)
  col gate opt-in, export HEVC on-device e sostituzione instradata al `DeletionFlow`.
  `CompressionPresentation` (puro, testato) + view guardata; aggancio dalla Dashboard.

- **Guscio UI — schermata 3/N: Review categorie «Rivedi ed elimina»** (sessione
  precedente; cadenza "una schermata per sessione, fatta bene"): costruita la
  schermata che presenta il `CategoryReviewViewModel` (T-113) già cablato con la
  UX del **gate d'anteprima obbligatorio** della rete di sicurezza (`DeletionFlow`,
  T-050). Nessuna logica nuova nel Domain/Data.
  - `CategoryReviewPresentation` (`Sources/AngavuFeatures/CategoryReviewPresentation.swift`,
    PURO): mappa `CategoryReview` (righe keep/removable) + stato del `DeletionFlow`
    nelle decisioni di UI — fase `reviewing`/`previewing`/`confirmed`, righe per
    disposizione, offerta d'eliminazione **solo** mentre si rivede e c'è del
    removable, insieme in anteprima/conferma, nota onesta della rete di sicurezza
    (recupero ~30 gg). Testabile senza device.
  - Gate a passi sul view-model (`CategoryReviewViewModel`, non-breaking):
    `presentDeletionPreview`/`presentDeletionPreviewForAllRemovable` (apre
    l'anteprima sui soli removable), `confirmDeletion` (accetta+conferma),
    `cancelDeletion` (azzera il gate). Invarianti T-113 invariati: mai i keep, mai
    un'anteprima vuota. Il vecchio `requestDeletion` one-shot resta per gli oracoli.
  - `CategoryReviewSource` + `CleanupCategory`
    (`Sources/AngavuFeatures/CategoryReviewSource.swift`): produce la
    `CategoryReview` **reale** dall'indice per gli **Screenshot** — filtro puro sul
    sottotipo `.screenshot` indicizzato (T-011), `ScreenshotCategory` (T-061) +
    `BulkDeletionProposalComposer` (T-062), zero API device-only, zero soglie
    arbitrarie. La lettura dell'indice `throws`: un errore è uno stato esplicito,
    mai una lista vuota spacciata per «pulito». Le altre categorie
    (duplicati/simili/video grandi-vecchi/sfocate) richiedono hashing/Vision sul
    device o decisioni di soglia → **non cablate** (nessun numero fabbricato):
    produttore di proposte dichiarato come prossimo passo.
  - `CategoryReviewView` (`Sources/AngavuFeatures/CategoryReviewView.swift`, SwiftUI
    guardata `canImport(SwiftUI)`): righe keep/removable con badge, azione «Elimina N»
    che apre SEMPRE l'anteprima (alert con conferma distruttiva/annulla), card di
    conferma («pronti per l'eliminazione via rete di sicurezza» + «Rivedi di nuovo»),
    stato vuoto onesto, stato d'errore con «Riprova». `DashboardView`: nuova sezione
    «Rivedi ed elimina» che naviga alle review (conserva l'`AppEnvironment` iniettato,
    nessun singleton).
  - **VERDE (comando)**: **CI Apple run #30 `success`** (`3906a00`), entrambi i job
    step per step — `swift build -warnings-as-errors` (30s), `swift test` (target_tests
    + regressione, 20s), `swiftlint lint --strict` (5s) + `build app (iOS Simulator)`
    (XcodeGen + build no-signing, 49s). Il verdetto è di un **comando** (L-COL-002),
    verificabile nella tab Actions.
  - **Copertura (L-COL-006)**: `CategoryReviewPresentation` coperta da 11 target_tests
    (`CategoryReviewPresentationTests`: fasi reviewing/previewing/confirmed/deleting,
    offerta d'eliminazione gateata, stato vuoto/solo-keep, insieme anteprima/conferma,
    nota di sicurezza). Gate a passi + produttore Screenshot coperti da
    `CategoryReviewGateTests` (preview→confirm sull'esatto removable, filtro keep,
    rifiuto selezione vuota/solo-keep, conferma senza anteprima, cancel; produttore
    screenshot reale, vuoto senza screenshot, errore d'indice propagato). AC-113-1/2
    già coperti da `CategoryReviewTests`. `CategoryReviewView` compilata dai due job CI
    ma **senza test di rendering**: resa a runtime non coperta. L'esecuzione reale del
    delete (adapter `SystemAssetDeleter`, safety_net) resta **fuori scope** (T-113): la
    conferma AUTORIZZA, la rete di sicurezza esegue. Baseline privacy invariata
    (nessun nuovo permesso/rete/framework).

- **Guscio UI — schermata 2/N: Dashboard «Numeri veri»** (sessione precedente; cadenza
  "una schermata per sessione, fatta bene"): costruita la Dashboard che presenta il
  `DashboardViewModel` (T-112) già cablato. Nessuna logica nuova nel Domain/Data.
  - `DashboardPresentation` (`Sources/AngavuFeatures/DashboardPresentation.swift`,
    PURO): mappa `DashboardState` (`idle`/`ready`/`failed`) nelle decisioni di UI —
    righe per categoria (titolo localizzato, conteggio, byte totali + **marca della
    quota stimata**), riepilogo dello spazio recuperabile (libreria vs device ORA +
    **caveat iCloud** quando device < libreria), banner accesso limited e **marca del
    totale parziale**, stato d'errore con motivo + «Riprova». Testabile senza device.
  - `DashboardView` (`Sources/AngavuFeatures/DashboardView.swift`, SwiftUI guardata
    `canImport(SwiftUI)`): rendering — carica alla comparsa (`onAppear` una volta),
    banner limited, card spazio recuperabile con nota iCloud, righe categoria, stato
    d'errore con Riprova. Byte formattati `.byteCount(.file)` (locale-aware).
  - `HomeView`: conserva l'`AppEnvironment` iniettato e aggiunge il link
    `DashboardView` nel recap (visibile solo a scansione `completed`): nessun singleton.
  - **VERDE (comando)**: **CI Apple run #29 `success`** (`2d19b82`), entrambi i job
    step per step — `swift build -warnings-as-errors` (22s), `swift test` (target_tests
    + regressione, 20s), `swiftlint lint --strict` (4s) + `build app (iOS Simulator)`
    (XcodeGen + build no-signing, 46s). Il verdetto è di un **comando** (L-COL-002),
    verificabile nella tab Actions.
  - **Copertura (L-COL-006)**: `DashboardPresentation` coperta da 9 target_tests
    (`DashboardPresentationTests`: idle/ready/failed, marcatura stima + contro-prova,
    caveat iCloud + contro-prova, banner limited + contro-prova). `DashboardViewModel`
    già coperto (wiring T-112). `DashboardView` compilata dai due job CI ma **senza
    test di rendering**: resa a runtime non coperta. Baseline privacy invariata
    (nessun nuovo permesso/rete/framework).

- **Guscio UI — schermata 1/N: Home reale** (sessione precedente; cadenza "una
  schermata per sessione, fatta bene" decisa dall'utente 2026-08-23): sostituito lo
  stub `ContentView`/`HomeView` con la Home vera che presenta `ScanViewModel` (T-111).
  - `HomeScanPresentation` (`Sources/AngavuFeatures/HomeScanPresentation.swift`, PURO):
    mappa `ScanState` nelle decisioni di UI — titolo/dettaglio onesti, quali controlli
    (avvia / annulla / «Apri Impostazioni»), progresso, e la marca di conteggio
    parziale (accesso limited mai spacciato per totale). Testabile senza device.
  - `HomeView` (`Sources/AngavuFeatures/HomeView.swift`, SwiftUI guardata
    `canImport(SwiftUI)`): avvia analisi, avanzamento determinato, **annulla** (stop
    cooperativo, motore T-004), recap onesto, errore con motivo esplicito + scorciatoia
    a Impostazioni su accesso negato; tema in-app e "cosa NON facciamo" raggiungibili.
    API cross-platform (`.primaryAction`, `UIApplication` guardato) così il package
    compila anche per macOS in CI.
  - Composition root: `AngavuApp` installa il `modelContainer` SwiftData;
    `ContentView` costruisce `AppEnvironment.live(context:)` e lo inietta.
    `ScanViewModel.accessDeniedMessage` estratto a costante (rilevamento deterministico
    del fallimento-permessi).
  - **VERDE (comando)**: **CI Apple run #28 `success`** (`de79c07`), entrambi i job
    step per step — `swift build -warnings-as-errors` (21s), `swift test` (target_tests
    + regressione, 16s), `swiftlint lint --strict` (5s) + `build app (iOS Simulator)`
    (39s). Il verdetto è di un **comando** (L-COL-002), verificabile nella tab Actions.
  - **Copertura (L-COL-006)**: `HomeScanPresentation` coperta da 8 target_tests
    (`HomeScanPresentationTests`, ogni `ScanState`). `HomeView` compilata dai due job CI
    ma **senza test di rendering**: resa a runtime non coperta. Baseline privacy
    invariata (nessun nuovo permesso/rete/framework).

- **Feature ad-hoc — tema in-app (fuori blueprint)**: selezione Sistema/Chiaro/Scuro.
  `ThemeChoice` (Domain puro, persistenza a stringa, degrado sicuro `.system`);
  `ThemeSettingsView` + chiave `@AppStorage("angavu.theme")` (guardata SwiftUI);
  `AngavuApp` applica `.preferredColorScheme`; Home con ingranaggio→sheet. Il tema
  Aurora era già adattivo (`Color(light:dark:)` + colori semantici iOS): questa è
  l'opzione per forzarlo.
  - **VERDE (comando)**: CI Apple **run #27 `success`** (`05a280b`) — build+test+lint
    + build app iOS. Il run #26 (`a866b50`) era rosso **solo** sul lint
    (`line_length` 138>120 su `ThemeSettings.swift:64`), fix riverificata.
  - **Copertura (L-COL-006)**: `ThemeChoice` coperto da `ThemeChoiceTests` (`swift test`).
    `ThemeSettingsView`/`AngavuApp`/`ContentView` compilati dal build app iOS ma senza
    test di rendering: switch dark/light a runtime non coperto. Mockup dark = artefatto
    di design (artifact), non codice verificato. Baseline privacy invariata.

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

- ✅ **PROGETTAZIONE della rifinitura HIG — FATTA** (2026-08-23): audit HIG del
  guscio UI 8/8 (`apple-skills:ios` ui-review + `apple-skills:design`) → piano
  `blueprint/HIG-REFINEMENT-PLAN.md` con 12 task atomici `R-00…R-11` raccolti per
  pattern trasversali (perimetro coperto: tipografia/Dynamic Type, spaziatura,
  gradiente/glow parsimonioso, SF Symbols, stati vuoto/carico/errore, accessibilità
  VoiceOver+contrasto+tap target ≥44pt, micro-interazioni/haptics con Reduce Motion,
  dark mode). Commit `6f93720`.
- **⭐ PROSSIMA SESSIONE = BUILD della rifinitura HIG**: eseguire i task del piano
  (`R-00…R-11`), 1-2 per sessione, in ordine di priorità (alti prima: **R-00** bug
  onboarding, **R-01** cifra-hero scalabile, **R-02** titolo unico), ognuno chiuso al
  confine CI (build+test+lint+app iOS verdi). Nessuna logica nuova Domain/Data (solo
  `AngavuFeatures` + `App/`); decisioni presentabili nel layer puro con `target_tests`,
  View compilate-non-rese (L-COL-006). Riferimento visivo: artifact mockup
  (Chiaro/Scuro) + `AuroraTheme`.

- **⭐ GUSCIO UI — cadenza "una schermata per sessione, fatta bene" (deciso
  dall'utente 2026-08-23)**: costruire il guscio completo che presenta i view-model
  già cablati (`wiring` 8/8, tutti verdi), UNA schermata per sessione con tutti i
  controlli, chiusa al confine CI (build+test+lint+app iOS verdi). Nessun nuovo lavoro
  su Domain/Data: solo `AngavuFeatures` + `App/`, guardato `#if canImport(SwiftUI)`.
  - ✅ **Home** (schermata 1, FATTA — run #28): scansione + recap onesto →
    `ScanViewModel`, presentazione pura `HomeScanPresentation` (8 target_tests).
  - ✅ **Dashboard «Numeri veri»** (schermata 2, FATTA — run #29): righe categoria coi
    byte veri (exact/estimated **separati**, la stima marcata), spazio recuperabile con
    caveat iCloud (libreria vs device ora), banner accesso limited col totale parziale →
    `DashboardViewModel`, presentazione pura `DashboardPresentation` (9 target_tests).
    Aggancio di navigazione dal recap della Home (`completed` → «Vedi i numeri veri»).
  - ✅ **Review categorie «Rivedi ed elimina»** (schermata 3, FATTA — run #30):
    presenta `CategoryReviewViewModel` (T-113) con la UX del **gate anteprima
    obbligatorio** della rete di sicurezza (`DeletionFlow`, T-050) — righe
    keep/removable, azione «Elimina» che apre SEMPRE l'anteprima, mai i keep, mai
    un'anteprima vuota. Presentazione pura `CategoryReviewPresentation` (11
    target_tests) + gate a passi sul view-model + produttore reale
    `CategoryReviewSource` per gli **Screenshot** (dati veri dall'indice, zero API
    device-only). Aggancio dalla Dashboard (sezione «Rivedi ed elimina»).
  - ✅ **Compressione video** (schermata 4, FATTA — run #32): presenta
    `CompressionViewModel` (T-116) — stima `estimated` → **gate opt-in** → export HEVC →
    (su success verificato + anteprima confermata) sostituzione dell'originale instradata
    al `DeletionFlow`. Nessun avvio senza consenso; nessuna perdita di dati.
    `CompressionPresentation` (puro, testato) + view guardata; aggancio dalla Dashboard.
  - ✅ **Contatti e calendari** (schermata 5, FATTA — run #33): presenta i due domini
    extra-foto cablati (`Contacts/CalendarsReviewViewModel`, T-115) — contatti duplicati
    da fondere e sottoscrizioni calendario sospette da rimuovere, ogni azione **human-gated**
    (T-092: tap → `confirmationDialog` → solo allora l'adapter), esito reale mostrato. I
    calendari **locali non compaiono mai** (T-091). `ExtraPhotoDomainsPresentation` (puro,
    10 target_tests) + view guardata. Composition root esteso: `ExtraDomainsPorts` opzionale
    su `AppEnvironment` (nil finché `.live()` non cabla gli adapter reali Contacts/EventKit
    — capacità assente, mai un fake). Aggancio dalla Dashboard (sezione «Oltre le foto»,
    solo se le porte sono cablate).
  - **⭐ PROSSIMA (schermata 6): report onesto** → `HonestReportViewModel` (T-114). La
    `HonestReportView` esiste già da `ui_shell`: va cablata al view-model coi dati veri
    (device vs libreria + caveat iCloud) e agganciata alla navigazione (dalla Home o dalla
    Dashboard). Pattern consolidato: presentazione pura testabile + view guardata + aggancio.
  - **⭐ PROSSIMO passo trasversale — produttore di proposte per le review**: oggi la
    schermata 3 mostra dati reali SOLO per gli Screenshot (pura, off-device). Le altre
    categorie (duplicati esatti, foto simili, video grandi/vecchi, sfocate) richiedono
    un "detector runner" che scansiona l'indice e produce la `CategoryReview` — hashing
    (device), Vision (device) o decisioni di soglia (grande/vecchio). Da cablare in
    Features quando la sorgente reale è disponibile: NB `large_old_media` è Domain puro
    e potrebbe partire off-device con soglie esplicite dichiarate.
  Riferimento visivo: artifact mockup (2 pagine Chiaro/Scuro). Viste già fatte
  (`OnboardingManifestoView`/`NonGoalsView`/`HonestReportView`/`HomeView`/`DashboardView`/`CategoryReviewView`/`CompressionView`/**`ExtraPhotoDomainsView`**) restano;
  tema in-app già integrato. Copertura attesa per ogni schermata: view compilata dal
  build app iOS in CI, resa a runtime non coperta da test (L-COL-006).

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
