# 04-exact-duplicates — Macrotask `exact_duplicates`

> Duplicati esatti: SHA-256 sui candidati raggruppati per dimensione, cluster nel
> Domain puro. Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Trovare i duplicati **esatti**: raggruppare gli asset per dimensione (candidati),
calcolare SHA-256 dei dati immagine solo sui candidati, e formare cluster di
identici nel Domain puro — stessa logica dell'Android, applicata via PhotoKit.

## Task atomici

```yaml
- id: T-030
  title: "Raggruppamento candidati per dimensione"
  macrotask: "exact_duplicates"
  depends_on: [T-012]

  objective: >
    Ridurre il costo dell'hashing raggruppando gli asset dell'indice per
    dimensione in byte: solo i gruppi con più di un asset sono candidati a
    duplicato esatto.

  definition_of_done:
    - "Funzione di dominio che raggruppa i record per dimensione byte"
    - "Solo i gruppi con cardinalità > 1 sono restituiti come candidati"

  acceptance_criteria:
    - id: AC-030-1
      given: "asset con dimensioni [100, 100, 200, 300, 300, 300]"
      when: "si calcolano i gruppi candidati per dimensione"
      then: "si ottengono i gruppi di dimensione 100 (x2) e 300 (x3), escluso 200 (singolo)"
    - id: AC-030-2
      given: "asset tutti di dimensione distinta"
      when: "si calcolano i gruppi candidati"
      then: "l'insieme dei candidati è vuoto (nessun hashing da fare)"

  target_tests:
    - file: "Tests/AngavuDomainTests/SizeCandidateGroupingTests.swift"
      covers: [AC-030-1, AC-030-2]

  out_of_scope:
    - "Il calcolo effettivo dello SHA-256 (T-031)"

- id: T-031
  title: "Hashing SHA-256 dei candidati e cluster di identici"
  macrotask: "exact_duplicates"
  depends_on: [T-004, T-030]

  objective: >
    Calcolare lo SHA-256 dei dati immagine solo sugli asset candidati (via adapter
    di lettura dati nel Data layer) e formare cluster di asset con hash identico,
    usando il motore cancellabile per librerie enormi.

  definition_of_done:
    - "Adapter di lettura byte dell'asset nel Data layer dietro protocollo"
    - "Clustering di dominio che raggruppa per SHA-256 identico"
    - "Esecuzione a blocchi cancellabile (T-004)"

  acceptance_criteria:
    - id: AC-031-1
      given: "un gruppo candidato con due asset dai byte identici e uno diverso"
      when: "si calcolano gli hash e si formano i cluster"
      then: "i due asset identici finiscono nello stesso cluster, il terzo resta escluso"
    - id: AC-031-2
      given: "un hashing in corso su molti candidati"
      when: "si richiede la cancellazione dopo il primo blocco"
      then: "il processo termina cancelled senza hashare i candidati residui"

  target_tests:
    - file: "Tests/AngavuDomainTests/ExactDuplicateClusterTests.swift"
      covers: [AC-031-1, AC-031-2]

  security_notes:
    - "Lettura byte solo on-device; nessun dato immagine lascia il device"

  out_of_scope:
    - "La selezione del keep e l'eliminazione (T-032 + macrotask safety_net)"

- id: T-032
  title: "Selezione keep-one per cluster di duplicati esatti"
  macrotask: "exact_duplicates"
  depends_on: [T-031]

  objective: >
    Per ogni cluster di duplicati esatti, selezionare deterministicamente l'asset
    da tenere (keep) e marcare gli altri come rimovibili, senza mai eliminare:
    la scelta è dati per la rete di sicurezza (macrotask safety_net).

  definition_of_done:
    - "Regola di dominio che per ogni cluster designa un keep e marca i restanti removable"
    - "La regola è deterministica (a parità di input, stesso keep)"

  acceptance_criteria:
    - id: AC-032-1
      given: "un cluster di 3 duplicati esatti"
      when: "si applica la regola keep-one"
      then: "esattamente 1 asset è keep e 2 sono removable"
    - id: AC-032-2
      given: "lo stesso cluster valutato due volte"
      when: "si applica la regola keep-one"
      then: "il keep selezionato è identico nelle due valutazioni (deterministico)"

  target_tests:
    - file: "Tests/AngavuDomainTests/KeepOneSelectionTests.swift"
      covers: [AC-032-1, AC-032-2]

  security_notes:
    - "Nessuna eliminazione qui: la selezione è solo proposta; l'eliminazione passa dall'anteprima obbligatoria (safety_net)"

  out_of_scope:
    - "L'eliminazione effettiva (macrotask safety_net)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
