# 02-library-index — Macrotask `library_index`

> PhotoKit: permessi, enumerazione asset, indice SwiftData incrementale,
> osservazione cambi libreria, byte reali per asset. È il tronco su cui poggia
> il cuore-foto. Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Costruire l'indice locale della libreria foto/video: gestire i permessi PhotoKit
con grazia (full/limited/denied), enumerare i `PHAsset` con metadati veri,
persisterli in **SwiftData**, mantenerli aggiornati con
`PHPhotoLibraryChangeObserver`, e ricavare i **byte reali** per asset con
degradazione dichiarata dove PhotoKit non li espone in modo pulito.

## Task atomici

```yaml
- id: T-010
  title: "Gestione permessi PhotoKit: full / limited / denied"
  macrotask: "library_index"
  depends_on: [T-001]

  objective: >
    Modellare e gestire lo stato di autorizzazione alla libreria (authorized,
    limited, denied, notDetermined) dietro un protocollo del Data layer, con la
    logica di decisione pura nel Domain, così che le feature reagiscano allo stato
    senza spacciare un accesso parziale per totale.

  definition_of_done:
    - "Protocollo PhotoLibraryAuthorizing nel Data layer che espone lo stato di autorizzazione"
    - "Enum PhotoAccess { full | limited | denied | notDetermined } nel Domain"
    - "NSPhotoLibraryUsageDescription presente e sincera in Info.plist"

  acceptance_criteria:
    - id: AC-010-1
      given: "un fake authorizer che restituisce limited"
      when: "il Domain calcola la modalità d'accesso"
      then: "risulta PhotoAccess.limited e viene marcato che il conteggio è parziale (non spacciabile per totale)"
    - id: AC-010-2
      given: "un fake authorizer che restituisce denied"
      when: "il Domain calcola la modalità d'accesso"
      then: "risulta PhotoAccess.denied e nessuna enumerazione viene tentata"

  target_tests:
    - file: "Tests/AngavuDomainTests/PhotoAccessPolicyTests.swift"
      covers: [AC-010-1, AC-010-2]

  security_notes:
    - "NSPhotoLibraryUsageDescription sincera e minima; required-reason API dichiarate in PrivacyInfo.xcprivacy (baseline privacy, 00-INDEX §3)"
    - "Accesso limited gestito senza spacciare un conteggio parziale per totale (onestà dei numeri)"

  out_of_scope:
    - "Il banner UI 'abilita accesso completo' (macrotask dashboard, T-022)"

- id: T-011
  title: "Enumerazione PHAsset e modello di dominio LibraryAsset"
  macrotask: "library_index"
  depends_on: [T-004, T-010]

  objective: >
    Enumerare i PHAsset via un adapter del Data layer e mapparli su un modello di
    dominio LibraryAsset puro (id, tipo, dimensioni pixel, data, subtype), usando
    il motore cancellabile per librerie enormi.

  definition_of_done:
    - "Adapter PhotoAssetEnumerating nel Data layer dietro protocollo"
    - "Modello LibraryAsset nel Domain senza import di Photos"
    - "Enumerazione a blocchi tramite il motore cancellabile (T-004)"

  acceptance_criteria:
    - id: AC-011-1
      given: "un fake enumerator con 3 asset noti"
      when: "il Domain costruisce i LibraryAsset dagli item enumerati"
      then: "produce 3 LibraryAsset con id/tipo/data corrispondenti agli input"
    - id: AC-011-2
      given: "un'enumerazione su molti asset con cancellazione a metà"
      when: "si cancella dopo il primo blocco"
      then: "l'enumerazione termina cancelled e non mappa gli asset dei blocchi successivi"

  target_tests:
    - file: "Tests/AngavuDomainTests/LibraryAssetMappingTests.swift"
      covers: [AC-011-1, AC-011-2]

  security_notes:
    - "L'adapter è l'unico punto che tocca Photos; il Domain resta puro (altitudine, 00-INDEX §1bis)"

  out_of_scope:
    - "Hashing per duplicati (macrotask exact_duplicates)"

- id: T-012
  title: "Indice SwiftData della libreria"
  macrotask: "library_index"
  depends_on: [T-011]

  objective: >
    Persistere i LibraryAsset in un indice SwiftData interrogabile, con upsert
    idempotente per id, così che l'app abbia un catalogo locale interrogabile
    senza rienumerare ogni volta.

  definition_of_done:
    - "Modello SwiftData AssetRecord con id univoco e campi dell'indice"
    - "Operazione di upsert idempotente per id nel Data layer"
    - "Query per tipo/dimensione/età esposte al Domain via protocollo di repository"

  acceptance_criteria:
    - id: AC-012-1
      given: "un indice SwiftData vuoto e 2 LibraryAsset"
      when: "si esegue l'upsert dei 2 asset due volte"
      then: "l'indice contiene esattamente 2 record (upsert idempotente, nessun duplicato)"
    - id: AC-012-2
      given: "un indice popolato con asset di tipo foto e video"
      when: "si interroga il repository per i soli video"
      then: "restituisce solo i record di tipo video"

  target_tests:
    - file: "Tests/AngavuDataTests/SwiftDataIndexTests.swift"
      covers: [AC-012-1, AC-012-2]

  security_notes:
    - "Indice interamente on-device; nessun dato lascia il device (zero backend, 00-INDEX §3)"

  out_of_scope:
    - "Aggiornamento incrementale sui cambi libreria (T-013)"

- id: T-013
  title: "Aggiornamento incrementale via PHPhotoLibraryChangeObserver"
  macrotask: "library_index"
  depends_on: [T-012]

  objective: >
    Mantenere l'indice SwiftData allineato ai cambi della libreria applicando i
    delta (inserimenti/rimozioni/modifiche) di PHPhotoLibraryChangeObserver, senza
    ricostruire l'intero indice.

  definition_of_done:
    - "Componente che traduce un change-set PhotoKit in delta di dominio (added/removed/changed)"
    - "Applicazione dei delta all'indice SwiftData in modo incrementale"

  acceptance_criteria:
    - id: AC-013-1
      given: "un indice con 5 asset e un delta che rimuove 1 e aggiunge 2"
      when: "si applica il delta all'indice"
      then: "l'indice risulta con 6 asset coerenti col delta, senza ricostruzione totale"
    - id: AC-013-2
      given: "un delta che modifica i metadati di un asset esistente"
      when: "si applica il delta"
      then: "il record esistente è aggiornato in place, mantenendo lo stesso id"

  target_tests:
    - file: "Tests/AngavuDomainTests/IncrementalIndexDeltaTests.swift"
      covers: [AC-013-1, AC-013-2]

  out_of_scope:
    - "UI di refresh (macrotask dashboard)"

- id: T-014
  title: "Byte reali per asset con degradazione dichiarata"
  macrotask: "library_index"
  depends_on: [T-011]

  objective: >
    Ricavare la dimensione in byte reale per asset tramite PHAssetResource; dove
    il dato esatto non è disponibile, marcare esplicitamente il valore come stima,
    senza mai spacciare una stima per esatta.

  definition_of_done:
    - "Adapter che estrae la dimensione da PHAssetResource nel Data layer"
    - "Modello ByteSize { exact(bytes) | estimated(bytes) } nel Domain"
    - "Percorso di degradazione: risorsa senza dimensione esatta -> estimated marcato"

  acceptance_criteria:
    - id: AC-014-1
      given: "una risorsa con dimensione esatta disponibile"
      when: "il Domain calcola la ByteSize"
      then: "risulta ByteSize.exact con il valore della risorsa"
    - id: AC-014-2
      given: "una risorsa priva di dimensione esatta"
      when: "il Domain calcola la ByteSize"
      then: "risulta ByteSize.estimated marcata come stima, mai spacciata per exact"

  target_tests:
    - file: "Tests/AngavuDomainTests/ByteSizeTests.swift"
      covers: [AC-014-1, AC-014-2]

  security_notes:
    - "Numeri veri: nessuna stima spacciata per esatta (manifesto onestà, feasibility §6)"

  out_of_scope:
    - "Aggregazione totale e caveat iCloud (macrotask dashboard)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
