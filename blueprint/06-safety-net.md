# 06-safety-net — Macrotask `safety_net`

> Rete di sicurezza: anteprima obbligatoria prima di eliminare, deleteAssets verso
> "Eliminati di recente". È la capacità di eliminazione condivisa dai rilevatori.
> Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Garantire che **nulla** venga eliminato senza un'**anteprima obbligatoria**
(gate nostro) prima della conferma di sistema, e che l'eliminazione passi da
`deleteAssets` verso "Eliminati di recente" (recupero di sistema ~30 gg): la rete
di sicurezza è di sistema, non serve ricostruire un cestino.

## Task atomici

```yaml
- id: T-050
  title: "Gate di anteprima obbligatoria prima di ogni eliminazione"
  macrotask: "safety_net"
  depends_on: [T-012]

  objective: >
    Modellare una macchina a stati di eliminazione in cui la transizione allo
    stato 'confirm' è possibile solo dopo che l'anteprima è stata mostrata e
    accettata: nessun percorso raggiunge l'eliminazione saltando l'anteprima.

  definition_of_done:
    - "Stato DeletionFlow { idle -> previewing -> confirmed -> deleting } nel Domain"
    - "Nessuna transizione verso confirmed senza passare da previewing accettato"

  acceptance_criteria:
    - id: AC-050-1
      given: "un DeletionFlow in stato idle con asset selezionati"
      when: "si tenta di passare direttamente a confirmed saltando previewing"
      then: "la transizione è rifiutata (il gate anteprima è obbligatorio)"
    - id: AC-050-2
      given: "un DeletionFlow che ha mostrato e fatto accettare l'anteprima"
      when: "si passa a confirmed"
      then: "la transizione è consentita e l'insieme da eliminare coincide con quello previewato"

  target_tests:
    - file: "Tests/AngavuDomainTests/DeletionPreviewGateTests.swift"
      covers: [AC-050-1, AC-050-2]

  security_notes:
    - "Anteprima obbligatoria: rete di sicurezza intoccabile (feasibility §5); nessuna delete silenziosa"

  out_of_scope:
    - "La chiamata deleteAssets di sistema (T-051)"

- id: T-051
  title: "Eliminazione via deleteAssets verso Eliminati di recente"
  macrotask: "safety_net"
  depends_on: [T-050]

  objective: >
    Eseguire l'eliminazione confermata tramite un adapter che chiama
    PHAssetChangeRequest.deleteAssets (un solo alert di sistema per batch), il cui
    esito manda gli asset in 'Eliminati di recente'; aggiornare l'indice di
    conseguenza.

  definition_of_done:
    - "Adapter AssetDeleting nel Data layer che incapsula deleteAssets su un batch"
    - "Un solo alert di sistema per batch (nessun loop per-asset)"
    - "All'esito success, i record eliminati sono rimossi dall'indice"

  acceptance_criteria:
    - id: AC-051-1
      given: "un batch confermato di 3 asset e un fake deleter che riporta success"
      when: "si esegue l'eliminazione del batch"
      then: "il deleter è invocato una sola volta con i 3 asset e l'indice li rimuove tutti"
    - id: AC-051-2
      given: "un fake deleter che riporta cancellazione dell'alert di sistema"
      when: "si esegue l'eliminazione del batch"
      then: "nessun record è rimosso dall'indice (l'utente ha annullato l'alert)"

  target_tests:
    - file: "Tests/AngavuDataTests/AssetDeletionTests.swift"
      covers: [AC-051-1, AC-051-2]

  security_notes:
    - "deleteAssets -> Eliminati di recente (recupero ~30 gg di sistema): rete di sicurezza fornita da iOS"
    - "Un solo alert di sistema per batch, coerente con l'anteprima nostra che lo precede"

  out_of_scope:
    - "Il testo dell'anteprima UI (macrotask ui_shell)"

- id: T-052
  title: "Riepilogo post-eliminazione onesto"
  macrotask: "safety_net"
  depends_on: [T-051, T-021]

  objective: >
    Dopo un'eliminazione, comporre un riepilogo onesto: quanti asset, byte
    libreria liberati, e byte device liberabili ora (con caveat iCloud), senza
    gonfiare i numeri.

  definition_of_done:
    - "Struttura DeletionSummary { count, libraryBytesFreed, deviceBytesReclaimableNow } di dominio"
    - "deviceBytesReclaimableNow tiene conto del caveat iCloud (T-021)"

  acceptance_criteria:
    - id: AC-052-1
      given: "un'eliminazione di 3 asset con byte noti, iCloud non attivo"
      when: "si compone il DeletionSummary"
      then: "count è 3 e libraryBytesFreed uguaglia deviceBytesReclaimableNow (somma dei byte)"
    - id: AC-052-2
      given: "un'eliminazione con iCloud optimize-storage attivo"
      when: "si compone il DeletionSummary"
      then: "deviceBytesReclaimableNow è inferiore a libraryBytesFreed e il caveat è segnalato"

  target_tests:
    - file: "Tests/AngavuDomainTests/DeletionSummaryTests.swift"
      covers: [AC-052-1, AC-052-2]

  security_notes:
    - "Numeri veri anche nel riepilogo: mai promettere spazio device che non si libera (caveat iCloud)"

  out_of_scope:
    - "Rendering del riepilogo (macrotask ui_shell)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
