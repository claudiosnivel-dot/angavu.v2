# 09-video-compression — Macrotask `video_compression`

> Compressione video HEVC on-device (AVAssetExportSession), opt-in, metadati
> (data/luogo) preservati. `DI-006`: feature più a rischio tecnico, **primo
> candidato al de-scope** sotto slittamento estremo. Identificatori in inglese,
> prosa in italiano.

## Obiettivo del macrotask

Liberare **spazio vero senza cancellare** ricodificando i video in HEVC
on-device (`AVAssetExportSession`), sempre **opt-in**, preservando i metadati
(data/luogo), con esito onesto (byte prima/dopo) e stop cooperativo. Isolata: se
il piano slitta, è la prima a uscire dalla v1 (`DI-006`).

## Task atomici

```yaml
- id: T-080
  title: "Stima del risparmio e gate opt-in per la compressione"
  macrotask: "video_compression"
  depends_on: [T-060]

  objective: >
    Per un video candidato, stimare il risparmio atteso dalla ricodifica HEVC e
    modellare un gate opt-in esplicito: nessuna compressione parte senza consenso
    per quel video/batch.

  definition_of_done:
    - "Funzione di dominio che stima il risparmio (byte) dal bitrate/durata/preset"
    - "Stato CompressionOptIn che richiede consenso esplicito prima di procedere"

  acceptance_criteria:
    - id: AC-080-1
      given: "un video con bitrate e durata noti e preset HEVC"
      when: "si stima il risparmio"
      then: "la stima è marcata 'estimated' (mai spacciata per risparmio esatto garantito)"
    - id: AC-080-2
      given: "un batch di video senza consenso opt-in"
      when: "si tenta di avviare la compressione"
      then: "l'avvio è rifiutato finché il consenso opt-in non è dato"

  target_tests:
    - file: "Tests/AngavuDomainTests/CompressionOptInTests.swift"
      covers: [AC-080-1, AC-080-2]

  security_notes:
    - "Opt-in esplicito; stima marcata come stima (numeri veri, mai risparmio garantito finto)"

  out_of_scope:
    - "L'export HEVC effettivo (T-081)"

- id: T-081
  title: "Export HEVC cancellabile con metadati preservati"
  macrotask: "video_compression"
  depends_on: [T-004, T-080]

  objective: >
    Eseguire la ricodifica via un adapter su AVAssetExportSession con preset HEVC,
    cancellabile (stop cooperativo), preservando i metadati creation date e
    location, e riportando un esito esplicito success/cancelled/failed.

  definition_of_done:
    - "Adapter VideoExporting nel Data layer su AVAssetExportSession preset HEVC"
    - "I metadati creation date e location sono preservati nell'output"
    - "Export cancellabile con esito success | cancelled | failed(reason)"

  acceptance_criteria:
    - id: AC-081-1
      given: "un fake exporter che riporta success con metadati sorgente"
      when: "si esegue l'export di un video"
      then: "l'output conserva creation date e location del sorgente"
    - id: AC-081-2
      given: "un export in corso"
      when: "si richiede la cancellazione"
      then: "l'export termina con esito cancelled, senza lasciare l'operazione bloccata a 0%"
    - id: AC-081-3
      given: "un fake exporter che fallisce"
      when: "si esegue l'export"
      then: "l'esito è failed(reason) visibile e il video sorgente resta intatto"

  target_tests:
    - file: "Tests/AngavuDataTests/HEVCExportTests.swift"
      covers: [AC-081-1, AC-081-2, AC-081-3]

  security_notes:
    - "Ricodifica on-device; metadati preservati; il sorgente non è mai perso su failure"

  out_of_scope:
    - "La sostituzione dell'originale (T-082)"

- id: T-082
  title: "Sostituzione dell'originale solo dopo export verificato"
  macrotask: "video_compression"
  depends_on: [T-081, T-050]

  objective: >
    Sostituire l'originale con la versione compressa solo dopo che l'export è
    verificato integro e l'utente ha confermato via anteprima; l'originale resta
    recuperabile passando dalla rete di sicurezza.

  definition_of_done:
    - "Flusso che sostituisce l'originale solo se export success e conferma anteprima"
    - "L'eliminazione dell'originale passa dal DeletionFlow (T-050) verso Eliminati di recente"

  acceptance_criteria:
    - id: AC-082-1
      given: "un export success confermato in anteprima"
      when: "si esegue la sostituzione"
      then: "l'originale è eliminato via DeletionFlow e la versione compressa è indicizzata"
    - id: AC-082-2
      given: "un export non verificato integro"
      when: "si tenta la sostituzione"
      then: "la sostituzione è rifiutata e l'originale resta invariato"

  target_tests:
    - file: "Tests/AngavuDomainTests/CompressedReplacementTests.swift"
      covers: [AC-082-1, AC-082-2]

  security_notes:
    - "Nessuna perdita di dati: sostituzione solo dopo export verificato + anteprima; originale verso Eliminati di recente"

  out_of_scope:
    - "Rendering del flusso (macrotask ui_shell)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
