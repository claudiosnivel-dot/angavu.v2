# 05-similar-photos — Macrotask `similar_photos`

> Foto simili: Vision feature print + computeDistance → cluster; dHash come
> fallback; "tieni la migliore". Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Trovare foto **simili** (non identiche) con similarità *semantica*:
`VNGenerateImageFeaturePrintRequest` + `computeDistance`, cluster per soglia,
con **dHash/Hamming** come fallback economico; poi "tieni la migliore" per
nitidezza/qualità volti/estetica.

## Task atomici

```yaml
- id: T-040
  title: "Feature print Vision dietro adapter e distanza semantica"
  macrotask: "similar_photos"
  depends_on: [T-011]

  objective: >
    Esporre, dietro un protocollo del Data layer, il calcolo del feature print di
    un asset (VNGenerateImageFeaturePrintRequest) e la distanza fra due feature
    print (computeDistance), così che il Domain lavori su distanze pure.

  definition_of_done:
    - "Protocollo FeaturePrinting nel Data layer (feature print + computeDistance) su Vision"
    - "Il Domain riceve distanze come valori puri, senza import di Vision"

  acceptance_criteria:
    - id: AC-040-1
      given: "un fake feature-printer con distanze note fra coppie"
      when: "il Domain interroga la distanza fra due asset"
      then: "riceve la distanza fornita dal provider, senza dipendere da Vision"
    - id: AC-040-2
      given: "il protocollo FeaturePrinting"
      when: "si ispezionano gli import del modulo AngavuDomain"
      then: "AngavuDomain non importa Vision (l'accesso è solo nel Data layer)"

  target_tests:
    - file: "Tests/AngavuDomainTests/FeatureDistanceTests.swift"
      covers: [AC-040-1, AC-040-2]

  security_notes:
    - "Vision è on-device; nessun pixel lascia il device; required-reason API dichiarate"

  out_of_scope:
    - "Clustering per soglia (T-041)"

- id: T-041
  title: "Clustering per soglia con fallback dHash"
  macrotask: "similar_photos"
  depends_on: [T-004, T-040]

  objective: >
    Raggruppare gli asset in cluster di simili quando la distanza semantica è sotto
    una soglia; se il feature print non è disponibile per un asset, usare il dHash
    (distanza di Hamming) come fallback economico. Esecuzione cancellabile.

  definition_of_done:
    - "Clustering di dominio per soglia di distanza semantica"
    - "Fallback a dHash/Hamming quando il feature print manca per un asset"
    - "Esecuzione a blocchi cancellabile (T-004)"

  acceptance_criteria:
    - id: AC-041-1
      given: "asset con distanze semantiche note e soglia fissata"
      when: "si esegue il clustering"
      then: "gli asset entro soglia finiscono nello stesso cluster, quelli oltre soglia in cluster distinti"
    - id: AC-041-2
      given: "un asset privo di feature print ma con dHash disponibile"
      when: "si esegue il clustering"
      then: "l'asset è raggruppato usando la distanza di Hamming del dHash (fallback attivo)"
    - id: AC-041-3
      given: "un clustering in corso su molti asset"
      when: "si richiede la cancellazione dopo il primo blocco"
      then: "il processo termina cancelled senza processare gli asset residui"

  target_tests:
    - file: "Tests/AngavuDomainTests/SimilarClusterTests.swift"
      covers: [AC-041-1, AC-041-2, AC-041-3]

  out_of_scope:
    - "Punteggio 'tieni la migliore' (T-042)"

- id: T-042
  title: "Punteggio qualità per 'tieni la migliore'"
  macrotask: "similar_photos"
  depends_on: [T-041]

  objective: >
    Assegnare a ogni asset di un cluster un punteggio di qualità (nitidezza via
    Core Image/vImage, qualità volti, e — solo iOS 18 — aesthetics score come
    progressive enhancement) dietro adapter, e nel Domain scegliere il best per
    punteggio.

  definition_of_done:
    - "Protocollo QualityScoring nel Data layer (nitidezza/volti/aesthetics)"
    - "Regola di dominio best-of-cluster per punteggio più alto"
    - "Percorso iOS<18: aesthetics assente -> punteggio senza quel termine, dichiarato"

  acceptance_criteria:
    - id: AC-042-1
      given: "un cluster di 3 asset con punteggi di qualità noti"
      when: "si applica la regola best-of-cluster"
      then: "è selezionato come keep l'asset col punteggio più alto, gli altri sono removable"
    - id: AC-042-2
      given: "un ambiente senza aesthetics score (iOS 17)"
      when: "si calcola il punteggio di qualità"
      then: "il punteggio usa nitidezza/volti senza il termine aesthetics, senza fallire"

  target_tests:
    - file: "Tests/AngavuDomainTests/KeepBestScoringTests.swift"
      covers: [AC-042-1, AC-042-2]

  security_notes:
    - "Scoring on-device; iOS 18 aesthetics come progressive enhancement, mai requisito"

  out_of_scope:
    - "L'eliminazione (macrotask safety_net)"

- id: T-043
  title: "Proposta di eliminazione per cluster di simili"
  macrotask: "similar_photos"
  depends_on: [T-042]

  objective: >
    Comporre, per ogni cluster di simili, una proposta di eliminazione (keep il
    best, removable il resto) come dati per la rete di sicurezza, senza mai
    eliminare in autonomia.

  definition_of_done:
    - "Struttura DeletionProposal { keep, removable[] } di dominio per cluster"
    - "La proposta non innesca alcuna eliminazione (solo dati)"

  acceptance_criteria:
    - id: AC-043-1
      given: "un cluster con best individuato e 2 removable"
      when: "si compone la DeletionProposal"
      then: "keep è il best e removable contiene esattamente i 2 restanti"
    - id: AC-043-2
      given: "un cluster con un solo asset"
      when: "si compone la DeletionProposal"
      then: "removable è vuoto (nulla da proporre in eliminazione)"

  target_tests:
    - file: "Tests/AngavuDomainTests/SimilarDeletionProposalTests.swift"
      covers: [AC-043-1, AC-043-2]

  security_notes:
    - "Nessuna eliminazione senza anteprima obbligatoria (safety_net); la proposta è reversibile"

  out_of_scope:
    - "L'anteprima e la delete di sistema (macrotask safety_net)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
