# 11-ui-shell — Macrotask `ui_shell`

> Onboarding-manifesto, schermata "cosa NON facciamo", report onesto. Trasversale.
> Identificatori in inglese, prosa in italiano.

> **📌 PROMEMORIA DESIGN (da fare all'avvio di questo macrotask).** Il design
> visivo (palette, tema, bottoni, effetti) **non** è ancora stato fatto e **non**
> va portato 1:1 dall'Android (Material 3): iOS segue Apple **HIG**. Passi:
> 1. **Inventario brand token** dal repo Android
>    (`app/src/main/kotlin/app/angavu/ui/theme/Color.kt` e `Theme.kt`): estrarre
>    SOLO i colori d'**identità di brand** (accent, eventuale logo/icona), lasciando
>    lo scaffolding Material.
> 2. **Ricostruire nativo** con la skill **`apple-skills:design`** (SF Symbols,
>    tipografia SF Pro, Dynamic Type, dark mode, Liquid Glass, animazioni/feedback).
>    Il *carattere/brand* si porta; il *linguaggio visivo* è nativo iOS.
> Il repo Android è clonabile via `add_repo claudiosnivel-dot/angavu`.

## Obiettivo del macrotask

Dare all'app la sua voce: un **onboarding-manifesto** che spiega la promessa, una
schermata **"cosa NON facciamo"** che dichiara apertamente i limiti della
piattaforma (segnale di fiducia e conformità App Store), e un **report onesto**
che presenta i numeri veri con i caveat.

## Task atomici

```yaml
- id: T-100
  title: "Contenuto del manifesto e della schermata 'cosa NON facciamo' come dati"
  macrotask: "ui_shell"
  depends_on: [T-001]

  objective: >
    Modellare come dati di dominio il contenuto dell'onboarding-manifesto e della
    schermata dei non-goals (voci del manifesto e limiti dichiarati), così che sia
    testabile e coerente col VISION-AND-CONSTRAINTS §4.

  definition_of_done:
    - "Struttura ManifestContent di dominio con le voci del manifesto e i non-goals"
    - "Ogni non-goal dichiarato corrisponde a una voce del VISION-AND-CONSTRAINTS §4"

  acceptance_criteria:
    - id: AC-100-1
      given: "il ManifestContent generato"
      when: "si elencano i non-goals"
      then: "include almeno 'niente cache di sistema', 'no ads', 'zero backend' come voci esplicite"
    - id: AC-100-2
      given: "il ManifestContent"
      when: "si verifica ogni voce di non-goal"
      then: "nessuna voce promette capacità impossibili nel sandbox iOS (coerenza col manifesto)"

  target_tests:
    - file: "Tests/AngavuDomainTests/ManifestContentTests.swift"
      covers: [AC-100-1, AC-100-2]

  security_notes:
    - "Onestà come conformità App Store (Guideline 2.3.x): nessun claim ingannevole nel contenuto"

  out_of_scope:
    - "Lo styling SwiftUI (fuori dai target_tests di dominio)"

- id: T-101
  title: "Navigazione dell'app che rispetta il gate di anteprima"
  macrotask: "ui_shell"
  depends_on: [T-050, T-100]

  objective: >
    Comporre la navigazione delle sezioni (dashboard, duplicati, simili, video,
    esplora, extra-domini) in modo che ogni percorso di eliminazione attraversi il
    DeletionFlow con anteprima obbligatoria (T-050).

  definition_of_done:
    - "Modello di navigazione che collega le sezioni al DeletionFlow condiviso"
    - "Nessuna sezione espone un'eliminazione che salta l'anteprima"

  acceptance_criteria:
    - id: AC-101-1
      given: "una sezione con asset selezionati per l'eliminazione"
      when: "si segue il percorso di navigazione fino alla conferma"
      then: "il percorso passa dallo stato previewing prima di confirmed (gate rispettato)"
    - id: AC-101-2
      given: "il grafo di navigazione delle sezioni"
      when: "si enumerano i percorsi che portano a un'eliminazione"
      then: "ognuno include lo stato previewing (nessun percorso lo salta)"

  target_tests:
    - file: "Tests/AngavuFeaturesTests/NavigationPreviewGateTests.swift"
      covers: [AC-101-1, AC-101-2]

  security_notes:
    - "La rete di sicurezza vale in ogni sezione: nessun percorso UI elimina senza anteprima"

  out_of_scope:
    - "Il testo dei singoli screen (T-100 per i contenuti)"

- id: T-102
  title: "Report onesto con numeri veri e caveat"
  macrotask: "ui_shell"
  depends_on: [T-020, T-021, T-052]

  objective: >
    Comporre il report onesto che presenta gli aggregati (numeri veri) con i caveat
    (iCloud, accesso limited, stima marcata), senza mai un numero gonfiato o un
    claim impossibile.

  definition_of_done:
    - "Struttura HonestReport di dominio che unisce aggregati e caveat"
    - "Il report marca esplicitamente stime, caveat iCloud e conteggi parziali"

  acceptance_criteria:
    - id: AC-102-1
      given: "aggregati con quota estimated e iCloud attivo"
      when: "si compone lo HonestReport"
      then: "il report riporta la stima come stima e il caveat iCloud, mai un totale 'esatto' unico"
    - id: AC-102-2
      given: "accesso limited"
      when: "si compone lo HonestReport"
      then: "il report marca i conteggi come parziali e invita all'accesso completo"

  target_tests:
    - file: "Tests/AngavuDomainTests/HonestReportTests.swift"
      covers: [AC-102-1, AC-102-2]

  security_notes:
    - "Numeri veri + caveat dichiarati: nessun claim ingannevole (manifesto + Guideline App Store)"

  out_of_scope:
    - "Il rendering grafico del report"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
