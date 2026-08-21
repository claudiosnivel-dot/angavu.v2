# 07-large-old-media — Macrotask `large_old_media`

> Video grandi/vecchi ordinati per dimensione/età; screenshot e screen recording
> in blocco. Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Offrire liste ad alto ritorno di spazio: video **grandi e vecchi** ordinati per
dimensione/età, e **screenshot / screen recording** selezionabili in blocco,
alimentando la rete di sicurezza per l'eliminazione.

## Task atomici

```yaml
- id: T-060
  title: "Video grandi e vecchi ordinati per dimensione ed età"
  macrotask: "large_old_media"
  depends_on: [T-012, T-014]

  objective: >
    Selezionare dall'indice i video e ordinarli per dimensione (byte reali) ed età,
    esponendo una lista ordinata con soglie configurabili di 'grande' e 'vecchio'.

  definition_of_done:
    - "Query di dominio che filtra i video per soglia di dimensione ed età"
    - "Lista ordinata in modo deterministico (dimensione desc, poi età)"

  acceptance_criteria:
    - id: AC-060-1
      given: "video con dimensioni ed età note e soglie fissate"
      when: "si richiede la lista dei video grandi e vecchi"
      then: "contiene solo i video oltre entrambe le soglie, ordinati per dimensione decrescente"
    - id: AC-060-2
      given: "nessun video oltre soglia"
      when: "si richiede la lista"
      then: "la lista è vuota (nessun falso positivo)"

  target_tests:
    - file: "Tests/AngavuDomainTests/LargeOldVideoTests.swift"
      covers: [AC-060-1, AC-060-2]

  out_of_scope:
    - "La compressione (macrotask video_compression)"

- id: T-061
  title: "Screenshot e screen recording in blocco"
  macrotask: "large_old_media"
  depends_on: [T-012]

  objective: >
    Individuare gli screenshot (mediaSubtype .photoScreenshot) e le screen
    recording (euristica sui video), esponendoli come categoria selezionabile in
    blocco.

  definition_of_done:
    - "Filtro di dominio per screenshot basato sul subtype indicizzato"
    - "Euristica per screen recording documentata e applicata sui video"

  acceptance_criteria:
    - id: AC-061-1
      given: "asset con e senza il subtype screenshot"
      when: "si richiede la categoria screenshot"
      then: "contiene esattamente gli asset marcati screenshot, nessun altro"
    - id: AC-061-2
      given: "video che soddisfano l'euristica di screen recording e altri che no"
      when: "si richiede la categoria screen recording"
      then: "contiene solo i video che soddisfano l'euristica dichiarata"

  target_tests:
    - file: "Tests/AngavuDomainTests/ScreenshotCategoryTests.swift"
      covers: [AC-061-1, AC-061-2]

  out_of_scope:
    - "L'eliminazione (macrotask safety_net)"

- id: T-062
  title: "Proposta di eliminazione in blocco per large_old_media"
  macrotask: "large_old_media"
  depends_on: [T-060, T-061, T-050]

  objective: >
    Comporre una DeletionProposal in blocco dalle liste (video grandi/vecchi,
    screenshot, screen recording) selezionate dall'utente, che confluisce nel gate
    di anteprima obbligatoria della rete di sicurezza.

  definition_of_done:
    - "Composizione di una DeletionProposal dagli asset selezionati nelle liste"
    - "La proposta entra nel DeletionFlow (T-050) e non elimina in autonomia"

  acceptance_criteria:
    - id: AC-062-1
      given: "una selezione di 4 asset fra video e screenshot"
      when: "si compone la DeletionProposal in blocco"
      then: "removable contiene i 4 asset selezionati e keep è vuoto (categoria a eliminazione diretta)"
    - id: AC-062-2
      given: "la DeletionProposal in blocco"
      when: "la si passa al DeletionFlow"
      then: "il flusso richiede l'anteprima prima di consentire la conferma (gate T-050)"

  target_tests:
    - file: "Tests/AngavuDomainTests/BulkDeletionProposalTests.swift"
      covers: [AC-062-1, AC-062-2]

  security_notes:
    - "Anche l'eliminazione in blocco passa dall'anteprima obbligatoria (safety_net)"

  out_of_scope:
    - "Rendering delle liste (macrotask ui_shell)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
