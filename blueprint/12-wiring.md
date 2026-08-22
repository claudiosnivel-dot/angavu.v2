# 12-wiring — Macrotask `wiring`

> **Aggiunto con `DI-009`** (dopo il piano di build 11/11). Non è nuova logica: è
> il **cablaggio dati** che collega la logica già costruita (Domain/Data) a
> schermate navigabili e al report onesto sui dati veri della libreria. Analogo
> dell'`08bis-wiring` dell'Android. Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Rendere l'app **davvero usabile** sull'iPhone: comporre gli adapter reali dietro i
port del Domain (composition root), orchestrare la scansione PhotoKit → indice, e
guidare le schermate del cuore-foto, del report onesto e dei domini extra-foto coi
**dati veri**, instradando **ogni** eliminazione dalla rete di sicurezza
(`DeletionFlow`, T-050). La logica è già verde in CI; qui la si porta in UI.

Regola di verificabilità: la logica di presentazione vive in **view-model**
testabili (`swift test` in `AngavuFeaturesTests`, con fake dietro i port); le
**View SwiftUI** sono verificate dalla compilazione dell'app in CI (job `ios-app`),
non da unit test. Altitudine invariata: il Domain non importa Data/PhotoKit.

## Task atomici

```yaml
- id: T-110
  title: "Composition root: DI degli adapter reali dietro i port + ModelContainer"
  macrotask: "wiring"
  depends_on: [T-001, T-012]

  objective: >
    Comporre in un AppEnvironment iniettabile gli adapter reali (authorizer,
    enumerator, indice SwiftData, byte resolver, rilevatori, deleter, exporter)
    dietro i port del Domain, e creare il ModelContainer per AssetRecord. I test
    sostituiscono gli adapter con fake, senza singleton nascosti.

  definition_of_done:
    - "AppEnvironment (in AngavuFeatures) che espone i servizi SOLO dietro i port del Domain"
    - "Factory di produzione che costruisce il grafo reale + ModelContainer(AssetRecord)"
    - "Nessun accesso globale: le feature ricevono i servizi per iniezione"

  acceptance_criteria:
    - id: AC-110-1
      given: "un AppEnvironment costruito con servizi fake iniettati"
      when: "una feature risolve un servizio dall'ambiente"
      then: "riceve esattamente l'istanza iniettata (nessun singleton nascosto)"
    - id: AC-110-2
      given: "un AppEnvironment"
      when: "si risolve il repository dell'indice"
      then: "è un valore conforme al port AssetIndexReading del Domain (Features dipende solo dai port)"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/AppEnvironmentTests.swift"
      covers: [AC-110-1, AC-110-2]

  security_notes:
    - "L'ambiente vive in Features/Data; il Domain resta puro (altitudine 00-INDEX §1bis)"

  out_of_scope:
    - "Le singole schermate (T-112…T-116)"

- id: T-111
  title: "Flusso di scansione: permessi → enumerazione → indice, off-main e cancellabile"
  macrotask: "wiring"
  depends_on: [T-110, T-010, T-011, T-013, T-004]

  objective: >
    Un ScanViewModel che orchestra permessi PhotoKit, enumerazione e
    indicizzazione fuori dal main con stato esplicito e stop cooperativo (motore
    T-004), senza spacciare un accesso limited per totale.

  definition_of_done:
    - "ScanViewModel con stati espliciti: idle | requestingPermission | scanning(progress) | completed | cancelled | failed"
    - "Usa PhotoAccessPolicy + enumerator + index writer; marca il conteggio parziale se limited"
    - "Cancellazione cooperativa via CancellationToken (T-004)"

  acceptance_criteria:
    - id: AC-111-1
      given: "un fake authorizer=limited e un enumerator con 3 asset noti"
      when: "la scansione completa"
      then: "l'indice contiene i 3 asset e lo stato marca il conteggio come parziale"
    - id: AC-111-2
      given: "una scansione in corso"
      when: "si richiede la cancellazione a metà"
      then: "lo stato diventa cancelled col progresso raggiunto e non indicizza il resto"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/ScanFlowTests.swift"
      covers: [AC-111-1, AC-111-2]

  security_notes:
    - "Accesso limited mai spacciato per totale (onestà dei numeri, feasibility §6)"

  out_of_scope:
    - "Il rendering della progress bar (View SwiftUI, verificata dal build app)"

- id: T-112
  title: "Dashboard reale: view-model sui numeri veri + caveat iCloud + banner limited"
  macrotask: "wiring"
  depends_on: [T-110, T-020, T-021, T-022]

  objective: >
    Un DashboardViewModel che espone le righe per categoria coi byte reali
    (exact/estimated separati), lo spazio recuperabile col caveat iCloud e il
    banner accesso limited, riusando gli aggregatori del macrotask dashboard.

  definition_of_done:
    - "DashboardViewModel che riusa DashboardAggregator + ReclaimableSpaceCalculator + DashboardBannerPolicy"
    - "Righe categoria con byte veri; quota exact separata da estimated (mai fuse)"

  acceptance_criteria:
    - id: AC-112-1
      given: "un indice con foto e video e byte noti"
      when: "si costruisce la dashboard"
      then: "le righe per categoria riportano i byte reali con exact ed estimated separati"
    - id: AC-112-2
      given: "accesso alla libreria limited"
      when: "si costruisce la dashboard"
      then: "il banner limited è presente e i totali sono marcati parziali"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/DashboardScreenTests.swift"
      covers: [AC-112-1, AC-112-2]

  out_of_scope:
    - "Il caveat iCloud a livello di eliminazione (già in dashboard/safety_net)"

- id: T-113
  title: "Schermate categorie: proposte dei rilevatori → liste, eliminazione via safety_net"
  macrotask: "wiring"
  depends_on: [T-110, T-032, T-043, T-062, T-071, T-050]

  objective: >
    Un CategoryReviewViewModel riusabile che presenta le proposte dei rilevatori
    (duplicati, foto simili, video grandi/vecchi, sfocate) come liste con
    keep/removable, e instrada OGNI eliminazione al DeletionFlow (T-050), mai in
    autonomia.

  definition_of_done:
    - "CategoryReviewViewModel che consuma una DeletionProposal/BulkDeletionProposal e produce righe (keep vs removable)"
    - "Azione elimina che apre il DeletionFlow (preview → accept → confirm) sull'insieme selezionato"

  acceptance_criteria:
    - id: AC-113-1
      given: "una proposta con keep e removable"
      when: "si richiede l'eliminazione dei removable"
      then: "il DeletionFlow passa a confirmed esattamente sull'insieme removable (mai sui keep)"
    - id: AC-113-2
      given: "nessuna selezione"
      when: "si richiede l'eliminazione"
      then: "l'azione è rifiutata (nessuna anteprima vuota)"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/CategoryReviewTests.swift"
      covers: [AC-113-1, AC-113-2]

  security_notes:
    - "Rete di sicurezza intoccabile: nessun percorso di eliminazione salta il DeletionFlow (T-050)"

  out_of_scope:
    - "L'esecuzione reale del delete (adapter SystemAssetDeleter, safety_net)"

- id: T-114
  title: "Report onesto: view-model sullo spazio recuperabile reale"
  macrotask: "wiring"
  depends_on: [T-110, T-021, T-052, T-102]

  objective: >
    Un HonestReportViewModel che alimenta HonestReportView (ui_shell) con lo
    spazio recuperabile reale — libreria vs device ora — e il caveat iCloud, dai
    dati dell'indice.

  definition_of_done:
    - "HonestReportViewModel che deriva libraryFreed, deviceReclaimableNow e iCloudCaveat dai dati veri"
    - "Nessun numero device promesso oltre il recuperabile reale"

  acceptance_criteria:
    - id: AC-114-1
      given: "asset con byte residenti sul device inferiori ai byte libreria"
      when: "si compone il report"
      then: "deviceReclaimableNow < libraryFreed e iCloudCaveat è vero"
    - id: AC-114-2
      given: "asset con byte device pari ai byte libreria"
      when: "si compone il report"
      then: "iCloudCaveat è falso"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/HonestReportViewModelTests.swift"
      covers: [AC-114-1, AC-114-2]

  out_of_scope:
    - "Il testo del manifesto (già dato in ui_shell T-100)"

- id: T-115
  title: "Domini extra-foto: view-model contatti duplicati e calendari-spam"
  macrotask: "wiring"
  depends_on: [T-110, T-090, T-091, T-092]

  objective: >
    View-model che presentano le proposte di contatti duplicati e calendari-spam
    e instradano l'applicazione confermata (gate proposed → confirmed) dei
    rispettivi flussi, senza toccare i calendari locali.

  definition_of_done:
    - "ContactsReviewViewModel e CalendarsReviewViewModel che espongono le proposte come righe confermabili"
    - "L'applicazione passa dal gate confirmed dei flussi extra-foto (T-092)"

  acceptance_criteria:
    - id: AC-115-1
      given: "un cluster di contatti duplicati"
      when: "si conferma il merge"
      then: "l'azione passa dal gate confirmed e produce il piano di merge"
    - id: AC-115-2
      given: "calendari sottoscritti sospetti accanto a calendari locali"
      when: "si conferma la rimozione"
      then: "solo le sottoscrizioni sospette entrano nel piano, mai i calendari locali"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/ExtraPhotoDomainsScreenTests.swift"
      covers: [AC-115-1, AC-115-2]

  security_notes:
    - "Mai rimuovere calendari locali; usage-description contatti/calendario sincere (T-090…092)"

  out_of_scope:
    - "L'esecuzione reale su Contacts/EventKit (adapter guardati, extra_photo_domains)"

- id: T-116
  title: "Compressione video: view-model opt-in → export → sostituzione via safety_net"
  macrotask: "wiring"
  depends_on: [T-110, T-080, T-081, T-082, T-050]

  objective: >
    Un CompressionViewModel che concatena stima (estimated) → gate opt-in →
    export (VideoExportCoordinator) → sostituzione (CompressedReplacementPlanner)
    con eliminazione dell'originale via DeletionFlow, a stato esplicito.

  definition_of_done:
    - "CompressionViewModel con stati: idle | estimated | consented | exporting | replacing | done | cancelled | failed"
    - "La sostituzione avviene solo dopo export success verificato + anteprima, via DeletionFlow"

  acceptance_criteria:
    - id: AC-116-1
      given: "un video con consenso opt-in, export success verificato e anteprima confermata"
      when: "il flusso procede alla sostituzione"
      then: "l'originale è instradato all'eliminazione via DeletionFlow e il compresso è pronto all'indice"
    - id: AC-116-2
      given: "un batch senza consenso opt-in"
      when: "si tenta l'avvio della compressione"
      then: "l'avvio è rifiutato finché il consenso non è dato"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/CompressionFlowTests.swift"
      covers: [AC-116-1, AC-116-2]

  security_notes:
    - "Nessuna perdita di dati: sostituzione solo dopo export verificato + anteprima (T-082); originale verso Eliminati di recente"

  out_of_scope:
    - "L'export reale AVFoundation (adapter guardato, video_compression)"

- id: T-117
  title: "Euristica screen-recording: iniezione delle risoluzioni schermo reali del device"
  macrotask: "wiring"
  depends_on: [T-110, T-061]

  objective: >
    Fornire all'euristica screen-recording di large_old_media (oggi con
    risoluzioni iniettate nei test) le risoluzioni schermo reali del device
    corrente, tramite un provider iniettabile.

  definition_of_done:
    - "ScreenResolutionProviding che espone le risoluzioni schermo note del device corrente"
    - "L'euristica screen-recording (T-061) consuma il provider invece di valori hardcoded"

  acceptance_criteria:
    - id: AC-117-1
      given: "un provider con la risoluzione schermo del device e un video a quella risoluzione"
      when: "l'euristica valuta il video"
      then: "è classificato come screen recording"
    - id: AC-117-2
      given: "un video a una risoluzione non corrispondente a nessuno schermo"
      when: "l'euristica lo valuta"
      then: "non è classificato come screen recording"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/ScreenResolutionProviderTests.swift"
      covers: [AC-117-1, AC-117-2]

  out_of_scope:
    - "Il rilevamento AVFoundation di metadati video avanzati"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
