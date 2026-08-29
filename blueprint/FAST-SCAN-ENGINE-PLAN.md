# FAST-SCAN-ENGINE-PLAN — Angavu iOS

> **Output di una sessione di PROGETTAZIONE** (design/piano, 2026-08-26), **non** di
> build. Nessun codice è stato scritto per questo piano: l'implementazione è per la
> **prossima sessione** (decisione utente: «questa sessione solo il blueprint tecnico
> super-dettagliato, massima cura»).
>
> Nasce dal secondo giro di test on-device del flusso "Shazam" (Fase E) + dalla
> richiesta esplicita dell'utente: *dopo la scansione principale, aprire ogni
> categoria (duplicati, simili, sfocate, grandi/vecchi) fa ripartire una scansione
> mirata di minuti — che senso ha?* La risposta concordata: **un'unica scansione fa
> tutto** (opzione 1), ma solo se il **motore diventa molto più veloce** (leve 1-5),
> **seguito** dal ripensamento della fase di residenza (opzione 3). Questo piano
> progetta quel motore.
>
> **Confine di verifica onesto (L-COL-002 / L-COL-006).** La performance **non è
> oracolabile in CI**: il runner headless non ha una libreria reale da 25k asset né
> iCloud, e `swift test` non misura millisecondi. Perciò questo piano separa con cura:
> - la **logica pura** del motore (concorrenza deterministica, monotonìa del
>   progresso, chiave/invalidazione della cache, policy di residenza) è coperta da
>   `target_tests` come **oracolo** su Linux/CI;
> - il **guadagno di velocità** è **device-only** → validato con un **protocollo
>   Instruments** dichiarato (§7), mai un verde CI né una frase dell'LLM.
>
> **Altitudine invariata.** Il Domain resta puro (nessun import PhotoKit/Vision/
> AVFoundation/SwiftUI). Le capacità di piattaforma entrano SOLO dietro i port del
> Data; la presentazione vive in `AngavuFeatures` + `App/`. La regola-killer
> `domain → data` resta il gate assoluto (grafo dei moduli SwiftPM, 00-INDEX §7).

---

## 0. Come leggere questo piano

- **Severità delle leve**: 🔴 impatto dominante · 🟠 alto · 🟡 medio · 🟢 basso.
- **Fasi**: `FSE-A` (fondazioni + misura) → `FSE-B` (accesso batch) → `FSE-C`
  (pipeline immagine ridimensionata) → `FSE-D` (motore concorrente) → `FSE-E`
  (persistenza dei derivati) → `FSE-F` (integrazione: un'unica scansione fa tutto)
  → `FSE-G` (ripensamento residenza, opzione 3). Ordine = DAG (§4).
- **`file:line`**: riferimenti allo stato al commit `3460690` (scansione unificata,
  CI run #78 verde). Le righe slittano: verificarle prima di editare.
- **Manifesto** (`VISION-AND-CONSTRAINTS` §4): offline, on-device, **numeri veri mai
  gonfiati**, rete di sicurezza, zero rete/telemetria, no ads. Ogni task è misurato
  contro questo — in particolare le ottimizzazioni **non devono mai** introdurre un
  download iCloud (`isNetworkAccessAllowed = false` resta invariante) né un numero
  fabbricato.
- **Task atomici**: schema `references/blueprint/atomic-task-schema.md` (id univoco,
  `objective`, `definition_of_done`, `acceptance_criteria` given/when/then,
  `target_tests` con `covers:`, `security_notes`, `out_of_scope`). Namespace nuovo
  `FSE-###` per non collidere con i `T-###` del blueprint costruito.

---

## 1. Diagnosi — dove va il tempo oggi (con prove)

Ogni rilevatore fa una passata **per-asset**; gli adapter reali ripetono due pattern
costosissimi su ~25k foto. Evidenza al commit `3460690`:

### 1.1 Fetch PhotoKit uno-per-uno (leva 1 🔴)

Ogni adapter risolve il `PHAsset` con `PHAsset.fetchAssets(withLocalIdentifiers:
[id])` **per singolo asset**:

| Adapter | Sito | Note |
|---|---|---|
| Byte size | `Sources/AngavuData/AssetByteSizeResolving.swift:25` | 1 fetch/asset, e chiamato **3×** (scan fase 2 + duplicati + grandi/vecchi) |
| Feature print (Vision) | `Sources/AngavuData/FeaturePrintingAdapter.swift:65` | 1 fetch/asset |
| Residenza | `Sources/AngavuData/AssetResidencyProbe.swift:39` | 1 fetch/asset + resource data request |
| Pixel (nitidezza/similar) | `Sources/AngavuData/ImageAnalysisSupport.swift:21` | 1 fetch/asset |

`fetchAssets(withLocalIdentifiers:)` non è pensato per il loop: 25k invocazioni
singole pagano l'overhead di query del Photos framework ogni volta.

### 1.2 Decodifica a piena risoluzione per un francobollo (leva 2 🔴)

`OnDeviceImageBytes.data` e il feature printer chiedono
`deliveryMode = .highQualityFormat` — **l'immagine intera**:

- Vision (`FeaturePrintingAdapter.swift:71`) decodifica l'originale full-res, poi
  Vision lo normalizza internamente a una taglia piccola: la decodifica full-res è
  sprecata.
- La nitidezza (`ImageAnalysisSupport.swift:27` → `:90`) scarica l'intera immagine
  per poi generare una miniatura da **48px** (`SharpnessKernel.side`). Spreco enorme
  di CPU/memoria per pixel poi buttati.

### 1.3 Lavoro duplicato & doppia decodifica (leve 4/6 🟡)

- I byte per-asset sono risolti nella scansione (fase 2) **e di nuovo** in ogni
  categoria (`Sources/AngavuFeatures/CategoryReviewSource.swift:249`, duplicati e
  grandi/vecchi).
- Simili (Vision) e sfocate (Core Image) **decodificano ciascuna** ogni foto: due
  passate di decodifica separate sullo stesso set di immagini.

### 1.4 Tutto seriale (leva 3 🔴)

Il motore `ChunkedAnalysis` (`Sources/AngavuDomain/CancellableAnalysis.swift:103`)
processa **un elemento alla volta** su un solo thread. Su un iPhone con 5-6 core, i
rilevatori CPU/decodifica-bound (Vision, nitidezza) usano ~1/5 della macchina.

### 1.5 Nessuna persistenza dei derivati (leva 5 🔴 sull'uso ripetuto)

`AnalysisResultsStore` (`Sources/AngavuFeatures/AnalysisResultsStore.swift`) è una
cache **in memoria**: si perde a ogni cold-launch. I feature print / hash / nitidezza
/ residenza vengono **ricalcolati da zero a ogni avvio dell'app**, anche se la
libreria non è cambiata. Per un uso a sessioni brevi (≈3 h/settimana) è lo spreco
strutturale più grande sul lungo periodo.

### 1.6 Costo relativo per rilevatore (stima ingegneristica, NON misurata)

> Non esiste una misura reale: nessun device in CI. Sono stime d'ingegneria da
> validare col protocollo Instruments (§7). Dichiarate come tali (L-COL-006).

| Rilevatore | Costo | Driver di costo |
|---|---|---|
| Foto simili (Vision feature print) | 🔴 dominante | modello ML + decodifica full-res per foto |
| **Residenza device (fase 3, aggiunta in #78)** | 🔴 alto | legge un byte di *ogni* originale, fetch+semaphore per asset, timeout 10 s |
| Sfocate (Core Image nitidezza) | 🟠 alto | decodifica per foto (per un 48px) |
| Duplicati (SHA-256) | 🟡 medio | solo sui candidati per dimensione, non tutti |
| Byte size | 🟡 medio | ma risolto 3× |
| Screenshot / grandi-vecchi | 🟢 quasi gratis | filtro puro su indice + byte |

### 1.7 ⚠️ Rischio introdotto in #78 (da affrontare: `FSE-G`)

La **fase 3 (residenza su tutti gli asset)** aggiunta nella scansione unificata
(`Sources/AngavuFeatures/ScanViewModel.swift:134`, `AssetResidencyProbe.swift`) è, da
questa analisi, tra le cose **più pesanti** (I/O su ogni originale, fetch+semaphore
per asset). Sul device dell'utente potrebbe allungare parecchio la scansione. **Non è
stata misurata.** È il candidato principale a ottimizzazione o rimozione dal percorso
obbligatorio (§ `FSE-G`).

---

## 2. Principi di progetto del motore veloce

1. **Un decode, un fetch, un passaggio.** Ogni asset va toccato il minimo: il
   `PHAsset` risolto una volta (batch), l'immagine decodificata una volta alla taglia
   più piccola che serve, i byte risolti una volta e riusati.
2. **Parallelo ma limitato.** Concorrenza legata al numero di core attivi
   (`ProcessInfo.activeProcessorCount`), non illimitata: satura la CPU senza far
   esplodere la memoria (decodifiche in volo limitate).
3. **Deterministico nonostante il parallelismo.** L'ordine dei risultati non dipende
   dall'ordine di completamento: si scrive in posizioni pre-assegnate per indice
   d'input, poi si compone. Gli oracoli restano stabili.
4. **Onesto sempre.** Zero rete (`isNetworkAccessAllowed = false` ovunque), nessun
   numero fabbricato, nessuna lista vuota spacciata per "pulito" (un errore resta uno
   stato d'errore esplicito), cancellazione cooperativa preservata.
5. **Altitudine invariata.** La logica di orchestrazione/concorrenza/cache-policy è
   **pura** (Domain, solo Foundation/Dispatch/Swift Concurrency); PhotoKit/Vision/
   Core Image restano dietro i port nel Data.
6. **Cache coerente per costruzione.** Un derivato è valido solo se la chiave
   (`localIdentifier` + `modificationDate`) combacia: un asset modificato ricalcola,
   mai un punteggio stantìo servito per fresco (manifesto: numeri veri).
7. **Misurabile.** Ogni fase porta un `os_signpost`: il guadagno si prova con
   Instruments su device (§7), non a parole.

---

## 3. Architettura target (altitudine)

```
Domain (puro)                      Data (adapter di piattaforma)        Features/App
─────────────                      ──────────────────────────────      ────────────
ConcurrentAnalysis (FSE-D)   ◄──   PHAssetBatchResolver (FSE-B)         ScanCoordinator (FSE-F)
DerivedResultStore policy    ◄──   DownscaledImageProvider (FSE-C)      ScanPipelineProgress (esteso)
  (chiave id+modDate, FSE-E)       DerivedResultStoreSwiftData (FSE-E)  Dashboard/CategoryView
ResidencyPolicy (FSE-G)      ◄──   (adapter Vision/CoreImage aggiornati) (wiring)
```

Contratto di altitudine invariato (00-INDEX §1bis):

```yaml
architecture:
  layers:
    domain:  "Sources/AngavuDomain/**"
    data:    "Sources/AngavuData/**"
    feature: "Sources/AngavuFeatures/**"
    app:     "App/**"
  forbidden:
    - { from: domain, to: data }
    - { from: domain, to: feature }
    - { from: domain, to: app }
    - { from: data, to: feature }
    - { from: data, to: app }
    - { from: feature, to: app }
```

**Nota di altitudine sul motore concorrente.** `ConcurrentAnalysis` vive nel Domain e
usa solo `Dispatch`/Swift Concurrency + `CancellationToken` + closure; **non** importa
PhotoKit. I port dei rilevatori restano **sincroni di proposito** (come oggi:
`AssetResidencyProbing`, `FeaturePrinting`, `SharpnessScoring`, `AssetContentHashing`);
il motore li invoca in parallelo su una pool di worker off-main. Questo preserva sia
l'altitudine sia la testabilità con fake.

---

## 4. DAG delle fasi

```
FSE-A (fondazioni: signpost + protocollo di misura + baseline)
  └─ FSE-B (batch PHAsset resolver)
       ├─ FSE-C (downscaled image provider; decode unico condiviso)
       │    └─ FSE-D (motore concorrente, cancellabile, deterministico)
       │         └─ FSE-F (integrazione: un'unica scansione calcola tutto e cacha)
       └─ FSE-E (persistenza dei derivati; chiave id+modDate; invalidazione)
            └─ FSE-F
  FSE-G (ripensamento residenza) dipende da FSE-B (+ FSE-D se resta nel motore)

  FSE-H (simili/sfocate a memoria limitata → re-inclusi nella scansione), post-F1:
    FSE-H1 (BK-tree + clustering per dHash, Domain puro; depends_on: [])
    FSE-H2 (dHash reale + burst; feature print → conferma) depends_on: [H1, C1]
    FSE-H3 (autoreleasepool nel seriale + rimozione pre-warm) depends_on: [D2]
    FSE-H4 (re-inclusione simili/sfocate eager) depends_on: [H1, H2, H3]
```

Regola: ogni fase si chiude al confine CI (`swift build -warnings-as-errors` +
`swift test` + `swiftlint --strict` + build app iOS) per la **logica pura**; il
**guadagno** si valida on-device (§7) prima di dichiararlo.

---

## 5. Task atomici

> Molte `acceptance_criteria` qui sono deliberatamente sulla **logica pura**
> (concorrenza, cache-policy, monotonìa, determinismo) perché è ciò che un oracolo CI
> può provare. La velocità reale è un **goal** validato su device (§7), mai un AC.

### FSE-A — Fondazioni e strumentazione di misura

```yaml
- id: FSE-A1
  title: "Signpost e handle di telemetria per ogni fase del motore"
  macrotask: "fast_scan_engine"
  depends_on: []
  objective: >
    Rendere misurabile ogni fase (indice, byte, hashing, feature print, nitidezza,
    residenza) con os_signpost/MXSignpost, così Instruments e MetricKit possano
    attribuire il tempo e provare i guadagni. Nessuna logica di prodotto nuova.
  definition_of_done:
    - "Un tipo `ScanSignpost` (Features o App) che apre/chiude intervalli con nome per fase"
    - "Ogni fase della scansione unificata (ScanViewModel) è racchiusa in un intervallo signpost"
    - "Handle MetricKit (MXMetricManager) sottoscritto all'avvio dell'app (non lazy)"
  acceptance_criteria:
    - id: AC-FSE-A1-1
      given: "una scansione eseguita con i fake in test"
      when: "il coordinatore attraversa le fasi"
      then: "ogni fase apre e chiude esattamente un intervallo di misura (contatore pari, nessun intervallo orfano)"
    - id: AC-FSE-A1-2
      given: "l'app all'avvio"
      when: "si costruisce l'ambiente"
      then: "il subscriber MetricKit è registrato una sola volta (idempotente), mai in una schermata secondaria"
  target_tests:
    - file: "Tests/AngavuFeaturesTests/ScanSignpostTests.swift"
      covers: [AC-FSE-A1-1, AC-FSE-A1-2]
  security_notes:
    - "I signpost non registrano contenuti dell'utente né path; solo nomi di fase e conteggi. Zero PII, zero rete."
  out_of_scope:
    - "L'analisi Instruments vera e propria (protocollo §7, device-only)"

- id: FSE-A2
  title: "Protocollo di baseline on-device e budget di performance"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-A1]
  objective: >
    Fissare, PRIMA di ottimizzare, la baseline reale (tempi per fase su ~25k asset,
    Release, device dell'utente) e i budget-obiettivo, così ogni leva successiva si
    misura contro un numero, non un'impressione.
  definition_of_done:
    - "Sezione §7 di questo piano compilata con la procedura Instruments (Time Profiler, Allocations, Hangs)"
    - "Tabella baseline (vuota da riempire on-device) con: tempo totale, tempo per fase, picco di memoria, hang>250ms"
    - "Budget-obiettivo dichiarati per fase (goal, non AC)"
  acceptance_criteria:
    - id: AC-FSE-A2-1
      given: "il documento di piano"
      when: "si legge §7"
      then: "esiste una procedura ripetibile (build Release, dati reali, device, passi Instruments) e una tabella baseline da riempire"
    - id: AC-FSE-A2-2
      given: "un guadagno rivendicato in una fase successiva"
      when: "lo si dichiara"
      then: "è accompagnato da baseline+dopo misurati con la stessa procedura, mai da una stima spacciata per misura"
  target_tests:
    - file: "N/A — task di documentazione/processo (nessun oracolo CI); verificato dalla presenza di §7 e dalla checklist di review"
      covers: [AC-FSE-A2-1, AC-FSE-A2-2]
  out_of_scope:
    - "Qualsiasi ottimizzazione di codice (fasi FSE-B…FSE-G)"
```

> Nota su `FSE-A2`: è un task di **processo**, non di codice — dichiarato apertamente
> senza un `target_test` eseguibile (L-COL-006). È qui perché "massima cura" esige di
> misurare prima e dopo; senza baseline, ogni "più veloce" sarebbe una frase dell'LLM.

### FSE-B — Accesso PhotoKit in batch (leva 1)

```yaml
- id: FSE-B1
  title: "Risolutore batch dei PHAsset dietro un port"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-A1]
  objective: >
    Eliminare i 25k×N fetch singoli: risolvere i PHAsset in blocco (per chunk di
    identificatori, o riusando il PHFetchResult dell'enumerazione) una sola volta e
    riusarli in tutti gli adapter (byte, residenza, pixel, feature print).
  definition_of_done:
    - "Port `AssetHandleResolving` (Domain) che, dato un elenco di id, restituisce un accessor opaco riusabile per gli adapter"
    - "Adapter `PHAssetBatchResolver` (Data) che fetcha in batch (chunk configurabile) e mantiene una mappa id→PHAsset viva per la durata della scansione"
    - "Gli adapter esistenti (byte/residenza/pixel/feature) accettano il PHAsset già risolto invece di rifetcharlo"
  acceptance_criteria:
    - id: AC-FSE-B1-1
      given: "un fake resolver e una lista di 5 id di cui 1 inesistente"
      when: "si risolve in batch"
      then: "i 4 esistenti sono risolti in UNA chiamata di batch, l'inesistente è assente (mai un crash, mai un placeholder finto)"
    - id: AC-FSE-B1-2
      given: "una scansione che tocca lo stesso asset per byte E residenza E pixel"
      when: "gli adapter chiedono l'handle"
      then: "il PHAsset è fetchato una sola volta e riusato (contatore di fetch = 1 per asset), provato con un resolver spione"
    - id: AC-FSE-B1-3
      given: "un batch più grande del chunk configurato"
      when: "si risolve"
      then: "il resolver spezza in chunk deterministici e copre tutti gli id senza duplicati né buchi"
  target_tests:
    - file: "Tests/AngavuDomainTests/AssetHandleResolvingTests.swift"
      covers: [AC-FSE-B1-1, AC-FSE-B1-3]
    - file: "Tests/AngavuFeaturesTests/BatchResolverReuseTests.swift"
      covers: [AC-FSE-B1-2]
  security_notes:
    - "Nessun accesso rete; il resolver opera su identificatori locali. La mappa viva è rilasciata a fine scansione (nessuna ritenzione oltre l'uso)."
  out_of_scope:
    - "La decodifica delle immagini (FSE-C); la parallelizzazione (FSE-D)"

- id: FSE-B2
  title: "Byte size risolti una volta e riusati (fine della tripla risoluzione)"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-B1]
  objective: >
    I byte per-asset sono risolti nella scansione e riusati da dashboard e categorie
    (duplicati, grandi/vecchi), invece di essere ricalcolati 3×.
  definition_of_done:
    - "I byte risolti nella fase 'resolvingSizes' sono resi disponibili alle sorgenti di categoria (via cache derivata, FSE-E, o passaggio esplicito)"
    - "CategoryReviewSource non richiama byteResolver su tutta la libreria quando i byte sono già noti"
  acceptance_criteria:
    - id: AC-FSE-B2-1
      given: "una scansione completata che ha risolto i byte"
      when: "si compone la review di 'duplicati' o 'grandi/vecchi'"
      then: "non viene invocata una nuova risoluzione byte per gli asset già noti (contatore di risoluzione = 0 sul secondo uso), provato con un resolver spione"
    - id: AC-FSE-B2-2
      given: "un asset assente dai byte pre-risolti (nuovo)"
      when: "una categoria lo incontra"
      then: "i suoi byte sono risolti on-demand una sola volta, mai un valore mancante spacciato per 0"
  target_tests:
    - file: "Tests/AngavuFeaturesTests/SizeReuseAcrossCategoriesTests.swift"
      covers: [AC-FSE-B2-1, AC-FSE-B2-2]
  out_of_scope:
    - "La persistenza tra avvii (FSE-E)"
```

### FSE-C — Pipeline immagine ridimensionata (leve 2 + 4)

```yaml
- id: FSE-C1
  title: "Provider di immagine ridimensionata on-device, a taglia richiesta"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-B1]
  objective: >
    Sostituire la decodifica full-res con una richiesta a taglia piccola
    (requestImage(targetSize:) / preparingThumbnail), zero rete, alla dimensione che
    ogni rilevatore usa davvero (≈224px feature print, ≈64px nitidezza).
  definition_of_done:
    - "Port `DownscaledImageProviding` (Domain) che dato un handle e una taglia logica restituisce pixel/dati ridimensionati o nil"
    - "Adapter reale (Data) che usa PHImageManager.requestImage(targetSize:contentMode:) con isNetworkAccessAllowed=false, deliveryMode adeguato, resizeMode .fast/.exact dichiarato"
    - "Vision e nitidezza consumano il provider ridimensionato, non più i byte full-res"
  acceptance_criteria:
    - id: AC-FSE-C1-1
      given: "un provider fake che registra la taglia richiesta"
      when: "il rilevatore nitidezza chiede l'immagine"
      then: "la taglia richiesta è quella piccola dichiarata (es. 64px), mai la piena risoluzione"
    - id: AC-FSE-C1-2
      given: "un originale non residente (in iCloud)"
      when: "si chiede l'immagine ridimensionata con rete disabilitata"
      then: "il provider restituisce nil (mai un download); il rilevatore degrada onestamente (asset non analizzabile), mai un falso risultato"
    - id: AC-FSE-C1-3
      given: "la stessa immagine richiesta da similar E da sfocate nella stessa scansione"
      when: "entrambi i rilevatori la usano"
      then: "l'immagine è decodificata una sola volta per taglia condivisa (contatore di decode = 1), provato con un provider spione"
  target_tests:
    - file: "Tests/AngavuDomainTests/DownscaledImageContractTests.swift"
      covers: [AC-FSE-C1-1, AC-FSE-C1-2]
    - file: "Tests/AngavuFeaturesTests/SharedDecodeTests.swift"
      covers: [AC-FSE-C1-3]
  security_notes:
    - "isNetworkAccessAllowed=false invariante: nessun byte lascia il device, nessun fetch iCloud (00-INDEX §3)."
    - "Il valore assoluto di nitidezza cambia con la risoluzione: la SOGLIA di sfocatura va ri-tarata sulla nuova taglia e ri-dichiarata (vedi FSE-C2)."
  out_of_scope:
    - "La parallelizzazione (FSE-D); la persistenza (FSE-E)"

- id: FSE-C2
  title: "Ri-taratura dichiarata delle soglie sensibili alla risoluzione"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-C1]
  objective: >
    La nitidezza (varianza del Laplaciano) dipende dalla risoluzione: cambiando la
    taglia di decodifica la soglia di sfocatura va ri-tarata e RI-DICHIARATA, non
    lasciata a caso. La distanza semantica Vision è invariante alla taglia
    (feature print normalizzato) e va verificata come tale.
  definition_of_done:
    - "Soglia di sfocatura ridefinita per la nuova taglia in CategoryDetectionDefaults, con commento che dichiara la taglia di riferimento"
    - "Nota nel piano/README della categoria: 'sfocato' è un'euristica alla taglia X, ri-tarabile"
  acceptance_criteria:
    - id: AC-FSE-C2-1
      given: "un set di immagini di nitidezza note (fixture) alla nuova taglia"
      when: "si applica la soglia ri-tarata"
      then: "le nitide restano sopra soglia e le sfocate sotto, senza falsi positivi sulle nitide (regola di confine invariata: alla soglia = NON sfocato)"
    - id: AC-FSE-C2-2
      given: "due immagini simili a due risoluzioni diverse"
      when: "si calcola la distanza semantica del feature print"
      then: "la decisione simile/non-simile è stabile rispetto alla taglia (entro tolleranza dichiarata), altrimenti il task fallisce e la taglia va rivista"
  target_tests:
    - file: "Tests/AngavuDomainTests/SharpnessThresholdRetuneTests.swift"
      covers: [AC-FSE-C2-1]
    - file: "Tests/AngavuDataTests/FeaturePrintScaleInvarianceTests.swift"
      covers: [AC-FSE-C2-2]
  security_notes:
    - "Nessuna soglia inventata: se le fixture non reggono, la taglia si rivede — mai un falso 'sfocato' su asset non verificabile (manifesto)."
  out_of_scope:
    - "Slider utente delle soglie (fase successiva, fuori da questo piano)"
```

### FSE-D — Motore d'analisi concorrente

```yaml
- id: FSE-D1
  title: "Motore concorrente cancellabile, con progresso monotòno e output deterministico"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-A1]
  objective: >
    Affiancare a ChunkedAnalysis (T-004) un motore che elabora gli elementi in
    PARALLELO con concorrenza limitata al numero di core attivi, mantenendo: esito
    esplicito (completed|cancelled|failed), progresso monotòno, output nell'ordine
    d'input (deterministico), basso uso di RAM (in volo limitato).
  definition_of_done:
    - "`ConcurrentAnalysis` (Domain, solo Foundation/Dispatch/Concurrency) con la stessa forma di esito di AnalysisOutcome"
    - "Concorrenza = min(configurato, ProcessInfo.activeProcessorCount)"
    - "Risultati scritti in posizioni pre-assegnate per indice → ordine d'output deterministico indipendente dall'ordine di completamento"
    - "Checkpoint di cancellazione fra i batch; autoreleasepool per worker (dieta memoria)"
  acceptance_criteria:
    - id: AC-FSE-D1-1
      given: "N elementi con uno step che restituisce l'indice"
      when: "si esegue in parallelo e si ordina l'output"
      then: "l'output è esattamente [0..N-1] nell'ordine d'input, qualunque sia l'ordine di completamento (deterministico)"
    - id: AC-FSE-D1-2
      given: "un'analisi in corso su molti elementi"
      when: "si richiede la cancellazione dopo il primo batch"
      then: "termina .cancelled col progresso raggiunto, senza processare gli elementi residui (contatore di step < N)"
    - id: AC-FSE-D1-3
      given: "uno step che lancia su un elemento"
      when: "si esegue"
      then: "l'esito è .failed col motivo esplicito e il progresso raggiunto (mai un risultato parziale spacciato per completo)"
    - id: AC-FSE-D1-4
      given: "una serie di callback di progresso da worker concorrenti"
      when: "il motore le pubblica"
      then: "la sequenza di progresso osservata è monotòna non decrescente (nessun arretramento), serializzata da un lock"
  target_tests:
    - file: "Tests/AngavuDomainTests/ConcurrentAnalysisTests.swift"
      covers: [AC-FSE-D1-1, AC-FSE-D1-2, AC-FSE-D1-3, AC-FSE-D1-4]
  security_notes:
    - "Nessun import di piattaforma (altitudine). Nessuna race: accumulo per-indice o sink protetto da lock; da validare con Thread Sanitizer on-device (§7)."
  out_of_scope:
    - "L'uso del motore negli adapter reali (FSE-D2); resta a ChunkedAnalysis dove il seriale è già adeguato (screenshot, grandi/vecchi)"

- id: FSE-D2
  title: "Rilevatori CPU-bound portati sul motore concorrente"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-D1, FSE-C1]
  objective: >
    Far girare in parallelo i rilevatori dominanti (feature print Vision, nitidezza)
    e l'hashing dei candidati, riusando l'immagine ridimensionata (FSE-C) e il PHAsset
    batch (FSE-B), senza cambiare la logica di dominio (cluster/soglia/keep-best).
  definition_of_done:
    - "SimilarClustering, BlurClassification ed ExactDuplicateClustering accettano un motore iniettabile (ChunkedAnalysis | ConcurrentAnalysis) senza cambiare gli AC di dominio già verdi"
    - "Gli adapter reali sono thread-safe sotto esecuzione concorrente (cache interne protette)"
  acceptance_criteria:
    - id: AC-FSE-D2-1
      given: "il clustering dei simili con motore concorrente e i fake dei port"
      when: "si esegue sullo stesso input dei test seriali esistenti"
      then: "il risultato (cluster, keep, removable) è IDENTICO a quello del motore seriale (parità di comportamento)"
    - id: AC-FSE-D2-2
      given: "la classificazione sfocate con motore concorrente"
      when: "si esegue sullo stesso input dei test seriali"
      then: "l'insieme di sfocate è identico e la cancellazione resta reattiva"
  target_tests:
    - file: "Tests/AngavuDomainTests/ConcurrentDetectorParityTests.swift"
      covers: [AC-FSE-D2-1, AC-FSE-D2-2]
  security_notes:
    - "Le cache degli adapter (es. VisionFeaturePrinter.cache) diventano concorrenti: proteggerle (lock/attore) o renderle per-worker e fondere. Data race = bug di correttezza, non solo di perf → Thread Sanitizer on-device."
  out_of_scope:
    - "La persistenza dei feature print tra avvii (FSE-E)"
```

### FSE-E — Persistenza dei risultati derivati (leva 5)

```yaml
- id: FSE-E1
  title: "Policy pura della cache derivata con chiave id+modificationDate"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-A1]
  objective: >
    Definire, nel Domain puro, quando un derivato (feature print, hash, nitidezza,
    residenza) è ancora valido: valido sse la chiave (localIdentifier +
    modificationDate/versione contenuto) combacia; altrimenti va ricalcolato. Mai un
    punteggio stantìo servito per un asset cambiato.
  definition_of_done:
    - "Tipo `DerivedKey {id, contentVersion}` e policy `DerivedResultValidity` pura"
    - "Funzione che, dati gli asset correnti e i derivati persistiti, partiziona in {riusabili, da-ricalcolare}"
  acceptance_criteria:
    - id: AC-FSE-E1-1
      given: "un derivato persistito per (id=A, versione=1) e l'asset A ora a versione=2"
      when: "si valuta la validità"
      then: "il derivato è considerato STANTIO → A va ricalcolato (mai riusato)"
    - id: AC-FSE-E1-2
      given: "derivati per A,B,C e la libreria corrente A(v1),B(v1),D(v1)"
      when: "si partiziona"
      then: "riusabili={A,B}, da-ricalcolare={D}, e C è considerato rimosso (scartato dalla cache)"
    - id: AC-FSE-E1-3
      given: "una richiesta di invalidazione totale (dopo un'eliminazione o cambio libreria)"
      when: "si applica"
      then: "nessun derivato è considerato valido finché non ricalcolato"
  target_tests:
    - file: "Tests/AngavuDomainTests/DerivedResultValidityTests.swift"
      covers: [AC-FSE-E1-1, AC-FSE-E1-2, AC-FSE-E1-3]
  security_notes:
    - "I derivati sono dati on-device (vettori/score/hash), mai contenuto d'immagine grezzo esportabile; restano nel container locale, zero rete."
  out_of_scope:
    - "Lo storage SwiftData concreto (FSE-E2)"

- id: FSE-E2
  title: "Store SwiftData dei derivati, contesto dedicato per operazione"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-E1]
  objective: >
    Persistere i derivati fra gli avvii in SwiftData (come l'indice, T-013), con un
    ModelContext dedicato per operazione (lezione del bugfix on-device: mai il
    contesto main-actor per scritture di massa), così una ri-scansione ricalcola solo
    il nuovo/cambiato.
  definition_of_done:
    - "Modello SwiftData dei derivati + adapter di lettura/scrittura dietro un port"
    - "Scrittura a blocchi su ModelContext dedicato (container-based, off-main), come SwiftDataAssetIndex"
    - "Lettura che ripopola la cache in memoria all'avvio della scansione"
  acceptance_criteria:
    - id: AC-FSE-E2-1
      given: "derivati scritti in una sessione e l'app 'riavviata' (nuovo store dallo stesso container in test)"
      when: "si rilegge"
      then: "i derivati per asset invariati sono recuperati identici (nessun ricalcolo necessario)"
    - id: AC-FSE-E2-2
      given: "un upsert di 2000 derivati"
      when: "si scrive"
      then: "la scrittura usa un contesto dedicato (non il main), provato dal fatto che non tocca il contesto principale, e conclude senza errori"
    - id: AC-FSE-E2-3
      given: "un asset con versione cambiata"
      when: "si rilegge la cache"
      then: "il derivato stantìo NON è restituito come valido (delega a DerivedResultValidity, FSE-E1)"
  target_tests:
    - file: "Tests/AngavuDataTests/DerivedResultStoreTests.swift"
      covers: [AC-FSE-E2-1, AC-FSE-E2-2, AC-FSE-E2-3]
  security_notes:
    - "Store locale, zero rete/telemetria. I derivati non escono dal device. Cancellati insieme all'asset o su invalidazione."
  out_of_scope:
    - "La migrazione dello schema tra versioni dell'app (fuori piano)"

- id: FSE-E3
  title: "Cablaggio: gli adapter consultano la cache derivata prima di calcolare"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-E2, FSE-D2]
  objective: >
    Feature print/hash/nitidezza/residenza leggono dal derivato persistito quando
    valido; calcolano solo sul cache-miss e ci scrivono. Invalidazione agganciata a
    LibraryChangeObserver (T-013) e all'eliminazione confermata.
  definition_of_done:
    - "Gli adapter (o un decoratore) fanno get-or-compute sulla cache derivata"
    - "L'invalidazione per-asset scatta su cambio libreria / eliminazione (riusa StoreInvalidatingLibrarySink)"
  acceptance_criteria:
    - id: AC-FSE-E3-1
      given: "un feature print già in cache per A (versione corrente)"
      when: "il clustering chiede la distanza che coinvolge A"
      then: "l'adapter NON ricalcola il feature print di A (contatore di calcolo = 0), lo legge dalla cache"
    - id: AC-FSE-E3-2
      given: "un cambio libreria segnalato dall'observer per A"
      when: "arriva il delta"
      then: "il derivato di A è invalidato → il prossimo uso ricalcola (mai un vettore stantìo)"
  target_tests:
    - file: "Tests/AngavuFeaturesTests/DerivedCacheWiringTests.swift"
      covers: [AC-FSE-E3-1, AC-FSE-E3-2]
  out_of_scope:
    - "La UI del badge di freschezza (già esistente, D-1)"
```

### FSE-F — Integrazione: un'unica scansione fa tutto

```yaml
- id: FSE-F1
  title: "Coordinatore di scansione: tutte le categorie calcolate in un'unica passata, cachate"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-D2, FSE-E3, FSE-B2]
  objective: >
    Estendere la scansione unificata (ScanViewModel) perché, dopo indice+byte+
    residenza, calcoli ANCHE i rilevatori (duplicati, simili, sfocate, grandi/vecchi,
    screenshot) come fasi della stessa barra, e ne cachi i risultati per categoria →
    aprire una categoria è istantaneo, mai una nuova scansione al tap.
  definition_of_done:
    - "ScanPipelineProgress esteso alle fasi dei rilevatori (equipesate od opportunamente pesate, dichiarato)"
    - "Al termine, i CategoryReviewData di ogni categoria sono in AnalysisResultsStore (chiavi .category(...))"
    - "CategoryReviewView, su cache hit, non lancia mai una nuova composizione (già supportato, CategoryReviewView+Loading.swift:51) — ora la cache è popolata dalla scansione"
  acceptance_criteria:
    - id: AC-FSE-F1-1
      given: "una scansione unificata completata (fake dei port)"
      when: "si apre una qualsiasi categoria"
      then: "il dato proviene dalla cache senza invocare i rilevatori (contatore di calcolo categoria = 0), provato con sorgenti spione"
    - id: AC-FSE-F1-2
      given: "una scansione cancellata a metà delle fasi dei rilevatori"
      when: "termina"
      then: "le categorie già completate sono cachate; quelle non raggiunte restano non-cachate (verranno calcolate al tap) — mai un risultato parziale spacciato per completo"
    - id: AC-FSE-F1-3
      given: "la barra di progresso durante le fasi dei rilevatori"
      when: "si osserva la frazione unificata"
      then: "è monotòna non decrescente su tutte le fasi (indice→byte→residenza→rilevatori), nessun arretramento"
  target_tests:
    - file: "Tests/AngavuFeaturesTests/UnifiedScanCoversCategoriesTests.swift"
      covers: [AC-FSE-F1-1, AC-FSE-F1-2]
    - file: "Tests/AngavuDomainTests/ScanPipelineProgressTests.swift"
      covers: [AC-FSE-F1-3]
  security_notes:
    - "Nessuna eliminazione in scansione: si compongono solo proposte; ogni delete resta dal gate DeletionFlow (T-050)."
  out_of_scope:
    - "Il ridisegno della UI della schermata di successo (già deciso: coriandoli + 'È ora di fare pulizia!')"

- id: FSE-F2
  title: "Progresso onesto multi-fase e carosello che copre l'intera attesa"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-F1]
  objective: >
    L'unica attesa (ora più lunga perché fa tutto) resta leggibile: barra unificata +
    titolo di fase onesto ('Cerco i duplicati…', 'Confronto le foto simili…', …) +
    carosello 'leggi mentre aspetti' esteso a coprire tutta la durata.
  definition_of_done:
    - "Titoli di fase per i rilevatori in ScanFlowPresentation (layer puro, testato)"
    - "Il carosello resta attivo per tutte le fasi; auto-avanzamento gated su Reduce Motion/VoiceOver (idioma esistente E-4)"
  acceptance_criteria:
    - id: AC-FSE-F2-1
      given: "lo stato di scansione in fase 'similar'"
      when: "si deriva la presentazione"
      then: "il titolo di fase nomina onestamente l'attività corrente, e la frazione è quella reale della fase (mai fabbricata)"
    - id: AC-FSE-F2-2
      given: "una fase a totale nullo (categoria vuota)"
      when: "si deriva la presentazione"
      then: "la fase è trattata come completa senza incollare la barra, coerente con ScanPipelineProgress"
  target_tests:
    - file: "Tests/AngavuFeaturesTests/ScanFlowPresentationTests.swift"
      covers: [AC-FSE-F2-1, AC-FSE-F2-2]
  out_of_scope:
    - "Animazioni/haptics (già coperti da R-06/E-2)"
```

### FSE-G — Ripensamento della residenza (opzione 3)

```yaml
- id: FSE-G1
  title: "Decisione: dove e come misurare la residenza device (policy pura)"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-B1]
  objective: >
    Affrontare il rischio introdotto in #78 (residenza su ogni originale = I/O
    pesante). Decidere e implementare la strategia: (a) batch+parallela nel motore;
    (b) fuori dal percorso obbligatorio (lazy/background, il device-now compare quando
    pronto); (c) campionamento onesto con caveat. La policy che sceglie è PURA e
    testabile; l'invariante di onestà è assoluto: nessun numero device fabbricato o
    parziale spacciato per totale.
  definition_of_done:
    - "Policy `ResidencyStrategy` (Domain) che decide se/quanto sondare e come dichiarare il risultato (numero reale completo | caveat)"
    - "Se strategia (b/c): la dashboard mostra il caveat finché la misura reale e completa non è pronta, poi si aggiorna — mai un numero intermedio inventato"
    - "Il probe reale gira in batch (FSE-B) e, se resta nel motore, in parallelo (FSE-D)"
  acceptance_criteria:
    - id: AC-FSE-G1-1
      given: "una misura di residenza incompleta (campione o cancellata)"
      when: "la policy decide cosa mostrare"
      then: "restituisce il CAVEAT (deviceSpaceIsIndeterminate), mai un numero device (coerente con ReclaimableSpace/P0-3)"
    - id: AC-FSE-G1-2
      given: "una misura reale e completa (copertura piena)"
      when: "la policy decide"
      then: "restituisce il numero device misurato col tetto di realtà (P0-2b/P0-3), non l'euristica"
    - id: AC-FSE-G1-3
      given: "la strategia scelta = fuori dal percorso obbligatorio"
      when: "la scansione principale termina senza aver completato la residenza"
      then: "la scansione è comunque 'completed' (indice+numeri categoria pronti) e la residenza si completa dopo, senza bloccare l'atterraggio in dashboard"
  target_tests:
    - file: "Tests/AngavuDomainTests/ResidencyStrategyTests.swift"
      covers: [AC-FSE-G1-1, AC-FSE-G1-2, AC-FSE-G1-3]
  security_notes:
    - "isNetworkAccessAllowed=false invariante. Il campionamento, se scelto, non stima MAI un numero device: campiona solo per decidere se vale la pena la misura piena; sotto copertura piena resta il caveat."
  out_of_scope:
    - "La rimozione del probe P0-2b (resta l'unico modo onesto di avere il numero preciso); qui si decide DOVE eseguirlo"
```

### FSE-H — Simili/sfocate a memoria limitata, re-inclusi nella scansione unificata

> **Origine**: bugfix del device-test (2026-08-29). La scansione unificata (FSE-F1)
> crashava alla fase «simili» perché il clustering greedy sul feature print Vision è
> **O(N²) confronti + O(N) osservazioni Vision trattenute** (+ decodifiche senza
> `autoreleasepool` nel percorso seriale) → **jetsam**. Fix immediato: simili/sfocate
> **differite** al tap (`CleanupCategory.runsInUnifiedScan == false`). FSE-H le
> re-include con un algoritmo a **memoria limitata e O(N·log N)**, così l'obiettivo di
> FSE-F1 («un'unica scansione fa tutto») vale anche su una libreria reale.
>
> **Ricerca (deep search + Apple docs, §11)**: funnel a stadi dal più economico al più
> costoso — (0) **burst nativi** PhotoKit (gratis), (1) **dHash** a 64 bit (8 byte/foto),
> (2) **BK-tree** sui dHash (O(N·log N), non O(N²)), (3) **feature print Vision solo come
> conferma** rilasciata subito, (4) **`autoreleasepool`** per foto. Il codebase ha già
> `PerceptualDHasher`, `SimilarityCandidate.dHash`, `SimilarClustering.hammingDistance`
> e la miniatura C1: FSE-H **cabla e ri-architetta**, non riscrive da zero.

```yaml
- id: FSE-H1
  title: "BK-tree sui dHash + clustering simili a memoria limitata (Domain puro)"
  macrotask: "fast_scan_engine"
  depends_on: []
  objective: >
    Sostituire il clustering greedy O(N²) sul feature print con un clustering
    O(N·log N) a memoria limitata sui dHash a 64 bit, via BK-tree con distanza di
    Hamming. Nessuna ritenzione O(N) di osservazioni Vision: solo interi a 64 bit.
  definition_of_done:
    - "`BKTree` (Domain, puro Foundation): insert(id, hash) + query(hash, maxDistance) → id entro Hamming ≤ maxDistance, sfruttando la disuguaglianza triangolare"
    - "`SimilarClustering.clustersByHash` (Domain): raggruppa i candidati per vicinanza dHash via BK-tree; un candidato senza dHash resta singleton (mai un falso simile)"
    - "Il clustering per dHash NON trattiene immagini/feature print: solo i 64-bit + la struttura ad albero"
  acceptance_criteria:
    - id: AC-FSE-H1-1
      given: "un insieme di dHash e una soglia di Hamming d"
      when: "si interroga il BK-tree con query(h, d)"
      then: "restituisce ESATTAMENTE gli id entro Hamming ≤ d (parità con la ricerca lineare a forza bruta), provato su fixture"
    - id: AC-FSE-H1-2
      given: "un dataset di dHash raggruppato (cluster ben separati)"
      when: "si eseguono le query"
      then: "il numero di confronti di Hamming è STRETTAMENTE MINORE della ricerca lineare (< N per query), provato con un contatore — l'efficienza è un fatto, non una frase"
    - id: AC-FSE-H1-3
      given: "due candidati con dHash entro soglia e uno oltre soglia"
      when: "si esegue clustersByHash"
      then: "i primi due sono nello stesso cluster, il terzo in un cluster distinto; un candidato con dHash nil resta singleton (mai dichiarato simile)"
    - id: AC-FSE-H1-4
      given: "lo stesso input di candidati e soglia"
      when: "si confronta clustersByHash con un clustering di riferimento a forza bruta sulla distanza di Hamming"
      then: "i cluster sono IDENTICI (parità di comportamento): il BK-tree accelera, non cambia il risultato"
  target_tests:
    - file: "Tests/AngavuDomainTests/BKTreeTests.swift"
      covers: [AC-FSE-H1-1, AC-FSE-H1-2]
    - file: "Tests/AngavuDomainTests/DHashClusteringTests.swift"
      covers: [AC-FSE-H1-3, AC-FSE-H1-4]
  security_notes:
    - "Aritmetica pura (Hamming su UInt64): zero rete, zero piattaforma. Il dHash è percettivo, non contenuto d'immagine esportabile."
  out_of_scope:
    - "Il calcolo reale del dHash (FSE-H2); la conferma Vision (FSE-H2); la re-inclusione nella scansione (FSE-H4)"

- id: FSE-H2
  title: "dHash reale cablato dalla miniatura + raggruppamento burst; feature print demoto a conferma"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-H1, FSE-C1]
  objective: >
    Calcolare il dHash per-asset dalla miniatura piccola (C1, non i byte full-res),
    dietro un port; raggruppare le raffiche via PhotoKit (`burstIdentifier`, gratis);
    comporre i candidati col dHash REALE (non più nil). Il feature print Vision è
    demoto a CONFERMA opzionale delle sole coppie borderline, calcolata on-demand e
    rilasciata subito (mai una cache O(N)).
  definition_of_done:
    - "Port `AssetPerceptualHashing` (Domain) + adapter reale (Data) che riusa la miniatura C1 (`.pixels(64)`), `isNetworkAccessAllowed=false`, dentro `autoreleasepool`"
    - "Raggruppamento burst: asset con lo stesso `burstIdentifier` formano un cluster nativo (Tier 0), senza Vision; il `.userPick`/`.autoPick` guida il keep"
    - "`similarPhotosReview` compone i candidati col dHash reale; il feature print resta opzionale (conferma), mai il percorso principale"
  acceptance_criteria:
    - id: AC-FSE-H2-1
      given: "un provider di dHash fake e un asset con/senza dHash"
      when: "si compongono i candidati per la review dei simili"
      then: "il candidato porta il dHash quando disponibile; un asset senza dHash resta senza (nil), mai un valore fabbricato — provato con fake, CI"
    - id: AC-FSE-H2-2
      given: "una lista di asset con `burstIdentifier` (alcuni condivisi)"
      when: "si raggruppano i burst (logica pura, id finti)"
      then: "gli asset con lo stesso burstIdentifier sono nello stesso cluster, senza alcun calcolo Vision/dHash; id unici restano singleton"
    - id: AC-FSE-H2-3
      given: "due scatti quasi identici e due foto diverse (device-only, §7)"
      when: "si calcola il dHash reale dalla miniatura"
      then: "i quasi-identici sono entro soglia Hamming, i diversi oltre — validato on-device (Instruments/fixture reali), dichiarato non coperto in CI"
  target_tests:
    - file: "Tests/AngavuFeaturesTests/SimilarCandidatesUseDHashTests.swift"
      covers: [AC-FSE-H2-1]
    - file: "Tests/AngavuDomainTests/BurstGroupingTests.swift"
      covers: [AC-FSE-H2-2]
  security_notes:
    - "isNetworkAccessAllowed=false invariante (dHash dalla miniatura on-device, mai iCloud). Il burstIdentifier è metadato locale. Il feature print di conferma è rilasciato subito (nessuna ritenzione O(N))."
  out_of_scope:
    - "La struttura BK-tree (FSE-H1); la dieta memoria del seriale (FSE-H3)"

- id: FSE-H3
  title: "Dieta memoria del percorso seriale + rimozione del pre-warm eager dei feature print"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-D2]
  objective: >
    Eliminare la causa diretta del jetsam: avvolgere ogni elemento del percorso
    per-item SERIALE in `autoreleasepool` (parità col motore concorrente D2, che già
    lo fa), e rimuovere il pre-warm eager dei feature print in `SimilarClustering`
    (che pre-calcolava tutti i feature print su tutta la libreria senza riportare
    progresso — barra congelata + memoria eager).
  definition_of_done:
    - "`PerItemAnalysis.serialMap` avvolge ogni `transform` in `autoreleasepool` (i temporanei di decodifica/Vision si rilasciano per elemento, non si accumulano)"
    - "Rimosso il pre-warm eager in `SimilarClustering.clusters`: il clustering non pre-calcola più tutti i feature print"
  acceptance_criteria:
    - id: AC-FSE-H3-1
      given: "lo stesso input dei test seriali esistenti"
      when: "si esegue serialMap con l'autoreleasepool per elemento"
      then: "output, progresso monotòno e cancellazione sono INVARIATI (parità): l'autoreleasepool non cambia il risultato, solo il profilo di memoria"
    - id: AC-FSE-H3-2
      given: "una scansione reale su libreria grande (device-only, §7)"
      when: "si profila con Instruments Allocations"
      then: "il picco di memoria resta sotto la soglia di jetsam durante le fasi per-foto — dichiarato device-only, non oracolabile in CI"
  target_tests:
    - file: "Tests/AngavuDomainTests/PerItemAnalysisAutoreleaseTests.swift"
      covers: [AC-FSE-H3-1]
  security_notes:
    - "Nessun cambio di comportamento osservabile oltre la memoria; nessuna nuova API di piattaforma."
  out_of_scope:
    - "La re-inclusione nella scansione (FSE-H4)"

- id: FSE-H4
  title: "Re-inclusione di simili/sfocate nella scansione unificata"
  macrotask: "fast_scan_engine"
  depends_on: [FSE-H1, FSE-H2, FSE-H3]
  objective: >
    Ora che i simili (burst + dHash + BK-tree, memoria O(N)×8 byte) e le sfocate
    (`autoreleasepool` + miniatura piccola, memoria O(1) per foto) sono a memoria
    limitata, ri-attivarle come fasi EAGER della scansione unificata — l'obiettivo di
    FSE-F1 («aprire una categoria è istantaneo») torna valido per TUTTE le categorie.
  definition_of_done:
    - "`CleanupCategory.runsInUnifiedScan` torna true per similarPhotos e blurryPhotos"
    - "La scansione le calcola e cacha; il progresso è quello REALE della fase (non un flash istantaneo)"
    - "Le fasi signpost tornano a coprire tutte le categorie (attribuzione tempi 1:1)"
  acceptance_criteria:
    - id: AC-FSE-H4-1
      given: "una scansione unificata completata (fake dei port)"
      when: "si apre una qualsiasi categoria, incluse simili/sfocate"
      then: "il dato viene dalla cache senza invocare i rilevatori (contatore = 0 al tap) — si ripristina l'AC-FSE-F1-1 originale per TUTTE le categorie"
    - id: AC-FSE-H4-2
      given: "una scansione completa"
      when: "si osservano gli intervalli signpost"
      then: "ogni categoria (incl. simili/sfocate) apre e chiude esattamente un intervallo, in ordine, senza orfani — si ripristinano le fasi rilevatore in ScanSignpostTests"
    - id: AC-FSE-H4-3
      given: "una scansione unificata su libreria reale (~25k, device-only §7)"
      when: "si esegue con simili/sfocate re-incluse"
      then: "completa SENZA crash entro il budget di memoria (Instruments) — dichiarato device-only, la prova definitiva del fix"
  target_tests:
    - file: "Tests/AngavuFeaturesTests/UnifiedScanCoversCategoriesTests.swift"
      covers: [AC-FSE-H4-1]
    - file: "Tests/AngavuFeaturesTests/ScanSignpostTests.swift"
      covers: [AC-FSE-H4-2]
  security_notes:
    - "Nessuna eliminazione in scansione (proposte soltanto). Zero rete. Nessun falso simile/sfocato su asset non verificabile."
  out_of_scope:
    - "Slider utente delle soglie (fuori piano); la conferma Vision resta opzionale, non un requisito"
```

---

## 6. Onestà & privacy (baseline invariata)

- **Zero rete**: ogni lettura pixel/dati resta `isNetworkAccessAllowed = false`. Le
  ottimizzazioni non introducono mai un download iCloud (un originale non residente →
  `nil` → asset non analizzabile, dichiarato; mai un falso risultato).
- **Numeri veri**: nessuna soglia inventata (FSE-C2 ri-tara con fixture o si rivede);
  nessun numero device fabbricato o parziale (FSE-G); nessuna lista vuota spacciata
  per "pulito" (un errore resta `.failed` esplicito).
- **Rete di sicurezza**: la scansione compone solo proposte; ogni eliminazione resta
  dal gate `DeletionFlow` (T-050). Invariato.
- **Cache onesta**: un derivato è valido solo a chiave combaciante (id+versione);
  invalidazione su cambio libreria/eliminazione. Mai un punteggio stantìo per fresco.
- **Required-reason / PrivacyInfo**: nessuna nuova API di piattaforma sensibile oltre
  a quelle già dichiarate (PhotoKit); la persistenza dei derivati è storage locale.
  Verificare in implementazione che nessuna nuova required-reason API sia toccata.

## 7. Protocollo di misura on-device (device-only, L-COL-006)

La CI **non** misura la performance. Il guadagno si prova così, e solo così:

1. **Build Release** dell'app (non Debug, non Simulator): le ottimizzazioni del
   compilatore cambiano il comportamento; il Simulator usa CPU/memoria dell'host.
2. **Dati reali**: il device dell'utente (~25k asset, iCloud "Ottimizza spazio"
   attivo). Librerie vuote nascondono il costo vero.
3. **Instruments** (apple-skills:performance):
   - **Time Profiler** — tempo per fase (attribuito via i signpost di FSE-A1); hot
     path; verifica che il lavoro pesante sia **fuori dal main thread** (Main Thread
     Checker attivo).
   - **Allocations** — picco di memoria durante la scansione (il parallelismo +
     decodifica non deve far esplodere la RAM → jetsam); `autoreleasepool` per worker.
   - **Hangs** — nessun blocco main-thread > 250 ms.
   - **Thread Sanitizer** (in un run dedicato) — nessuna data race nel motore
     concorrente e nelle cache degli adapter (FSE-D2).
4. **MetricKit** (FSE-A1) — in campo, `MXSignpost` sulle fasi + hang/memory/exit
   payload per regressioni sui device reali.
5. **Tabella baseline → dopo** (da riempire on-device; goal, non AC):

   | Metrica | Baseline (#78) | Dopo FSE-B/C | Dopo FSE-D | Dopo FSE-E (2ª scansione) | Budget-obiettivo |
   |---|---|---|---|---|---|
   | Tempo totale scansione (25k) | _da misurare_ | | | | _da fissare in FSE-A2_ |
   | di cui feature print (similar) | | | | | |
   | di cui nitidezza | | | | | |
   | di cui residenza | | | | | |
   | Picco memoria | | | | | < soglia jetsam |
   | Hang > 250 ms | | | | | 0 |
   | 2ª scansione (cache calda) | n/d | n/d | n/d | _≈ istantanea_ | |

   Nessuna cella si dichiara verde a memoria: o è misurata con questa procedura, o
   resta vuota.

## 8. Rischi & mitigazioni

| Rischio | Mitigazione |
|---|---|
| **Data race** nel motore concorrente / cache adapter | Accumulo per-indice o sink con lock; cache adapter per-worker o protette; Thread Sanitizer on-device (§7). AC di parità (FSE-D2) provano l'identità col seriale. |
| **Picco di memoria** da decodifiche parallele | Downscale (FSE-C) taglia i pixel; concorrenza limitata ai core; `autoreleasepool` per worker; Allocations (§7). |
| **Cache stantìa** serve numeri vecchi | Chiave id+modificationDate (FSE-E1); invalidazione su change/delete (FSE-E3); AC dedicati. |
| **Non-determinismo** dei risultati per parallelismo | Output per-indice pre-assegnato + ordinamento stabile; AC di determinismo (FSE-D1-1) e di parità (FSE-D2). |
| **Soglie sballate** cambiando risoluzione | FSE-C2 ri-tara con fixture; se non reggono, si rivede la taglia — mai un falso "sfocato". |
| **Prima scansione più lunga** (fa tutto) | Barra unificata + carosello (FSE-F2); persistenza (FSE-E) rende immediate le successive; residenza ripensata (FSE-G) toglie il peso maggiore dal percorso obbligatorio se necessario. |
| **Simili: O(N²) confronti + O(N) feature print Vision trattenuti → jetsam** (crash osservato al device-test) | Funnel a memoria limitata **FSE-H**: burst nativi (gratis) → dHash 64-bit (8 byte/foto) → BK-tree (O(N·log N)) → feature print Vision solo come conferma rilasciata subito; `autoreleasepool` per foto. Fino a FSE-H, simili/sfocate restano differite al tap (`runsInUnifiedScan == false`). |
| **Regressione di onestà** (rete/numeri finti) | Invarianti §6 come `security_notes` per-task; AC che provano `nil` su non-residente e caveat su misura incompleta. |

## 9. Cosa NON è in questo piano (out of scope)

- Slider utente delle soglie di rilevamento (fase successiva pianificata).
- Migrazione dello schema SwiftData dei derivati tra versioni dell'app.
- Modifiche alla UI della schermata di successo (già decise: coriandoli + «È ora di
  fare pulizia!» → dashboard istantanea).
- Qualsiasi implementazione: **questa sessione produce solo il piano**. La build parte
  la prossima sessione, dal DAG (§4), FSE-A per prima.

## 10. Ordine consigliato per la prossima sessione

1. **FSE-A** (signpost + baseline): senza misura non si dichiara nulla.
2. **FSE-B** (batch) + **FSE-C** (downscale): leve a basso rischio, guadagno grande e
   indipendente dal parallelismo.
3. **FSE-D** (motore concorrente): il moltiplicatore, con Thread Sanitizer.
4. **FSE-E** (persistenza): rende immediate le scansioni successive.
5. **FSE-F** (un'unica scansione fa tutto): l'obiettivo dell'utente, ora sostenibile.
6. **FSE-G** (residenza): togliere/alleggerire il peso maggiore, con onestà invariata.
7. **FSE-H** (simili/sfocate a memoria limitata → re-inclusi nella scansione):
   H1 (BK-tree, Domain puro) → H2 (dHash reale + burst) + H3 (autoreleasepool seriale)
   → H4 (re-inclusione eager). Aggiunto dopo il device-test (crash jetsam alla fase
   simili). Con FSE-H l'obiettivo di FSE-F1 («aprire una categoria è istantaneo») vale
   per TUTTE le categorie anche su una libreria reale.

Ogni fase chiude al confine CI per la logica pura; il guadagno si valida on-device
(§7) prima di dichiararlo.

## 11. Ricerca (deep search + Apple docs) alla base di FSE-H

Il funnel a stadi di FSE-H è fondato su ricerca esterna (2026-08-29), non su intuizione:

- **dHash (difference hash) + BK-tree** — l'algoritmo concreto (miniatura 9×8 in scala
  di grigi → 64 bit; distanza di Hamming; BK-tree sfrutta la disuguaglianza triangolare
  per trovare i vicini in ~O(log N) invece di O(N²); soglia ~2 bit per quasi-duplicato,
  più alta per «simile»):
  [Ben Hoyt, *Duplicate image detection with perceptual hashing*](https://benhoyt.com/writings/duplicate-image-detection/)
  · [image-ndd-lsh (GitHub)](https://github.com/mendesk/image-ndd-lsh)
  · [*A Survey on Locality Sensitive Hashing* (arXiv 2102.08942)](https://arxiv.org/pdf/2102.08942)
- **Burst nativi PhotoKit** — `PHAsset.burstIdentifier`, `mediaSubtypes.photoBurst`,
  `burstSelectionTypes` (`.userPick`/`.autoPick`), `fetchAssets(withBurstIdentifier:)`:
  [Apple Developer — fetchAssets(withBurstIdentifier:)](https://developer.apple.com/documentation/photokit/phasset/1624723-fetchassetswithburstidentifier)
- **Feature print Vision + memoria** — usarlo solo come conferma, rilasciato subito:
  [Apple Developer — VNGenerateImageFeaturePrintRequest](https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest)
- **`autoreleasepool` per il processing di molte foto** (la causa «crash dopo N foto» è
  l'accumulo di temporanei senza pool) e picco memoria di `PHImageManager`:
  [autorelease pool per il memory management](https://ruslandzhafarov.medium.com/using-autorelease-pool-for-efficient-memory-management-d0cfa7e51698)
  · [PHImageManager memory spike (Apple Forums)](https://developer.apple.com/forums/thread/730134)
- **Limiti di memoria / jetsam** (il foreground scatta ben prima della RAM totale):
  [jetsam per-process limit (Apple Forums)](https://developer.apple.com/forums/thread/688973)
