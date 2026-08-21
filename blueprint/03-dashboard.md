# 03-dashboard — Macrotask `dashboard`

> Dashboard numeri veri con caveat iCloud, distinzione "spazio libreria" vs
> "spazio device liberato ora", banner accesso limited. Identificatori in
> inglese, prosa in italiano.

## Obiettivo del macrotask

Mostrare all'utente numeri **veri** aggregati dall'indice: totale byte per
categoria, con il **caveat iCloud** dichiarato (se "ottimizza spazio" è attivo,
eliminare libera iCloud, non subito il device) e un banner che invita ad
abilitare l'accesso completo quando è `limited`.

## Task atomici

```yaml
- id: T-020
  title: "Aggregazione numeri veri per categoria"
  macrotask: "dashboard"
  depends_on: [T-012, T-014]

  objective: >
    Aggregare dall'indice i byte totali e i conteggi per categoria (foto, video,
    screenshot, duplicati candidati) usando ByteSize, mantenendo distinta la quota
    esatta da quella stimata.

  definition_of_done:
    - "Funzione di dominio che somma le ByteSize per categoria dai record dell'indice"
    - "Il risultato distingue somma exact da somma estimated"

  acceptance_criteria:
    - id: AC-020-1
      given: "un indice con asset di byte noti in due categorie"
      when: "si calcola l'aggregato per categoria"
      then: "ogni categoria riporta la somma corretta dei byte dei suoi asset"
    - id: AC-020-2
      given: "un mix di asset con ByteSize exact ed estimated"
      when: "si calcola l'aggregato"
      then: "la quota estimated è riportata separatamente dalla quota exact, mai fusa in un unico numero 'esatto'"

  target_tests:
    - file: "Tests/AngavuDomainTests/DashboardAggregateTests.swift"
      covers: [AC-020-1, AC-020-2]

  security_notes:
    - "Numeri veri: nessun numero gonfiato; la stima resta marcata (manifesto onestà)"

  out_of_scope:
    - "Rendering SwiftUI della dashboard (macrotask ui_shell)"

- id: T-021
  title: "Caveat iCloud: spazio libreria vs spazio device liberato ora"
  macrotask: "dashboard"
  depends_on: [T-020]

  objective: >
    Distinguere, nel modello della dashboard, lo 'spazio libreria' dallo 'spazio
    device liberabile ora', in base allo stato iCloud 'ottimizza spazio', così da
    non promettere GB locali che non si liberano.

  definition_of_done:
    - "Modello di dominio che espone reclaimableLibrarySpace e reclaimableDeviceSpaceNow come valori distinti"
    - "La distinzione dipende dallo stato iCloud optimize-storage rilevato"

  acceptance_criteria:
    - id: AC-021-1
      given: "iCloud optimize-storage attivo e asset con originale in cloud"
      when: "si calcola lo spazio device liberabile ora"
      then: "è inferiore allo spazio libreria e l'output segnala il caveat iCloud"
    - id: AC-021-2
      given: "iCloud optimize-storage non attivo"
      when: "si calcola lo spazio device liberabile ora"
      then: "coincide con lo spazio libreria (nessuna quota bloccata in cloud)"

  target_tests:
    - file: "Tests/AngavuDomainTests/ICloudCaveatTests.swift"
      covers: [AC-021-1, AC-021-2]

  security_notes:
    - "Mai promettere GB locali che non si liberano: onestà sul caveat iCloud (feasibility §6)"

  out_of_scope:
    - "Testo esatto del report onesto (macrotask ui_shell)"

- id: T-022
  title: "Banner accesso limited"
  macrotask: "dashboard"
  depends_on: [T-010, T-020]

  objective: >
    Quando l'accesso è limited, esporre nel modello della dashboard un banner che
    dichiara il conteggio come parziale e invita ad abilitare l'accesso completo,
    senza spacciare il parziale per totale.

  definition_of_done:
    - "Il modello della dashboard espone uno stato di banner limited-access derivato da PhotoAccess"
    - "Il totale mostrato è marcato 'parziale' quando l'accesso è limited"

  acceptance_criteria:
    - id: AC-022-1
      given: "PhotoAccess.limited"
      when: "si costruisce il modello della dashboard"
      then: "il banner limited-access è presente e il totale è marcato parziale"
    - id: AC-022-2
      given: "PhotoAccess.full"
      when: "si costruisce il modello della dashboard"
      then: "nessun banner limited-access e il totale non è marcato parziale"

  target_tests:
    - file: "Tests/AngavuDomainTests/LimitedAccessBannerTests.swift"
      covers: [AC-022-1, AC-022-2]

  security_notes:
    - "Accesso limited dichiarato con grazia; nessun conteggio parziale spacciato per totale"

  out_of_scope:
    - "Styling del banner (macrotask ui_shell)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
