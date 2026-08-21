# 01-foundation — Macrotask `foundation`

> Scaffold multi-modulo, oracoli deterministici della toolchain Apple, Domain
> puro e motore d'analisi cancellabile, baseline privacy. **Nessun codice
> prodotto in BOOTSTRAP**: qui si definiscono i task che BUILD (apple-skills)
> costruirà. Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Dare ad Angavu iOS le fondamenta: una struttura a moduli con **altitudine
imposta** (Domain puro senza PhotoKit/Vision/AVFoundation), gli oracoli
deterministici che rendono "verde" un fatto di comando (`swift build`/`swift
test`/SwiftLint/grafo moduli), il manifesto privacy, e il motore d'analisi
**cancellabile** (stop cooperativo, off-main, progresso onesto) che i rilevatori
riuseranno.

## Task atomici

```yaml
- id: T-001
  title: "Scaffold multi-modulo SwiftPM + app Xcode con target iOS 17"
  macrotask: "foundation"
  depends_on: []

  objective: >
    Creare la struttura a moduli (SwiftPM package con target AngavuDomain,
    AngavuData, AngavuFeatures e l'app Xcode App/) con deployment target iOS 17.0,
    così che swift build e swift test girino come oracoli deterministici.

  definition_of_done:
    - "Package.swift con target AngavuDomain, AngavuData, AngavuFeatures e relativi test target"
    - "Cartella App/ con app SwiftUI @main e deployment target iOS 17.0"
    - "swift build esce senza errori sui moduli SwiftPM"

  acceptance_criteria:
    - id: AC-001-1
      given: "il package SwiftPM appena scaffoldato"
      when: "si esegue swift build"
      then: "la build esce con codice 0 e produce i moduli AngavuDomain/AngavuData/AngavuFeatures"
    - id: AC-001-2
      given: "il target dell'app e i moduli"
      when: "si ispeziona il deployment target dichiarato"
      then: "risulta iOS 17.0 su tutti i target (nessun target sotto 17.0)"

  target_tests:
    - file: "Tests/AngavuFoundationTests/PackageStructureTests.swift"
      covers: [AC-001-1, AC-001-2]

  out_of_scope:
    - "Schermate reali (macrotask ui_shell)"
    - "Integrazione PhotoKit (macrotask library_index)"

- id: T-002
  title: "Oracolo di altitudine: grafo moduli con domain->data vietato"
  macrotask: "foundation"
  depends_on: [T-001]

  objective: >
    Rendere la regola-killer domain->data un fatto di build: AngavuDomain non
    dichiara alcuna dipendenza verso AngavuData/AngavuFeatures/App nel Package.swift,
    così un import proibito non compila (oracolo di altitudine, 00-INDEX §7).

  definition_of_done:
    - "AngavuDomain senza dipendenze verso AngavuData/AngavuFeatures nel manifest SwiftPM"
    - "Uno script/oracolo che estrae il grafo delle dipendenze dei target SwiftPM"
    - "Il grafo conferma le direzioni consentite dal contratto di altitudine (00-INDEX §1bis)"

  acceptance_criteria:
    - id: AC-002-1
      given: "il grafo dei moduli SwiftPM del package"
      when: "si verifica la dipendenza di AngavuDomain"
      then: "AngavuDomain non raggiunge AngavuData/AngavuFeatures/App (grafo conforme al forbidden)"
    - id: AC-002-2
      given: "un file di prova che da AngavuDomain importa AngavuData"
      when: "si esegue swift build"
      then: "la build fallisce (l'altitudine è imposta dal grafo, non da una convenzione)"

  target_tests:
    - file: "Tests/AngavuFoundationTests/AltitudeGraphTests.swift"
      covers: [AC-002-1, AC-002-2]

  security_notes:
    - "Altitudine come invariante di architettura: il Domain puro non tocca dati/piattaforma, riducendo la superficie sensibile"

  out_of_scope:
    - "Regole SwiftLint (T-003)"

- id: T-003
  title: "SwiftLint come oracolo di stile e dead-code + gate warnings-as-errors"
  macrotask: "foundation"
  depends_on: [T-001]

  objective: >
    Configurare SwiftLint (regole di stile, dead-code/unused, no-force-unwrap sui
    path critici) e la build con warnings-as-errors, come sostituzione
    deterministica degli oracoli semgrep/knip (00-INDEX §7).

  definition_of_done:
    - "File .swiftlint.yml con regole abilitate incluse unused_declaration e no force-unwrap sui moduli Domain/Data"
    - "swift build configurato con -warnings-as-errors sui moduli del package"
    - "swiftlint lint esce con codice 0 sul sorgente di scaffold"

  acceptance_criteria:
    - id: AC-003-1
      given: "il sorgente di scaffold e la config .swiftlint.yml"
      when: "si esegue swiftlint lint --strict"
      then: "esce con codice 0 (nessuna violazione) sul codice iniziale"
    - id: AC-003-2
      given: "un file con una dichiarazione non usata introdotto ad arte"
      when: "si esegue swiftlint lint --strict"
      then: "la regola dead-code segnala la violazione con esito diverso da 0"

  target_tests:
    - file: "Tests/AngavuFoundationTests/LintOracleTests.swift"
      covers: [AC-003-1, AC-003-2]

  out_of_scope:
    - "Regole di sicurezza App Store (macrotask ui_shell/report)"

- id: T-004
  title: "Motore d'analisi cancellabile nel Domain (stop cooperativo, progresso onesto)"
  macrotask: "foundation"
  depends_on: [T-001, T-002]

  objective: >
    Definire nel Domain puro l'astrazione del motore d'analisi a blocchi,
    cancellabile con stop cooperativo, che riporta progresso monotòno e un esito
    esplicito (completed/cancelled/failed), riusando le lezioni field-fix Android
    (niente eterno 0%, dieta low-RAM, fuori dal main).

  definition_of_done:
    - "Protocollo/tipo CancellableAnalysis nel modulo AngavuDomain, senza import di PhotoKit/Vision"
    - "Elaborazione a blocchi con checkpoint di cancellazione fra un blocco e l'altro"
    - "Esito modellato come enum esplicito: completed | cancelled | failed(reason)"

  acceptance_criteria:
    - id: AC-004-1
      given: "un'analisi in corso su una sequenza di elementi"
      when: "si richiede la cancellazione dopo il primo blocco"
      then: "l'analisi termina con esito cancelled entro il blocco successivo, senza processare gli elementi restanti"
    - id: AC-004-2
      given: "un'analisi che avanza su N blocchi"
      when: "si osservano gli aggiornamenti di progresso"
      then: "il progresso è monotòno non decrescente e raggiunge il totale solo a esito completed"
    - id: AC-004-3
      given: "un blocco che solleva un errore durante l'elaborazione"
      when: "il motore lo intercetta"
      then: "l'esito è failed(reason) visibile, mai un progresso bloccato a 0% all'infinito"

  target_tests:
    - file: "Tests/AngavuDomainTests/CancellableAnalysisTests.swift"
      covers: [AC-004-1, AC-004-2, AC-004-3]

  out_of_scope:
    - "L'uso concreto del motore su PhotoKit (macrotask library_index e rilevatori)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
