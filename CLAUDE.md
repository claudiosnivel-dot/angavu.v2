# CLAUDE.md — Angavu iOS

Porting onesto di [Angavu](https://github.com/claudiosnivel-dot/angavu) (cleaner
Android) su iOS. Prodotto **gemello**, non port 1:1. Manifesto: offline, no ads,
numeri veri, rete di sicurezza, Pro a pagamento unico. Vedi
[`docs/FEASIBILITY-iOS.md`](docs/FEASIBILITY-iOS.md).

## Policy della toolchain (vincolante in questo repo)

| Strumento | Uso consentito | Uso **vietato** |
|---|---|---|
| **Trueline** (`plugins/trueline/`) | **Solo BOOTSTRAP** — generare/mantenere il blueprint tecnico (`blueprint/`) | Niente BUILD, niente REMEDIATE, niente checkpoint/oracoli di Trueline come gate di verifica |
| **apple-skills** (`plugins/apple-skills/`) | **Tutta la build e tutta la verifica**: implementazione (generatori, pattern iOS/SwiftUI/SwiftData/Core ML-Vision/AVFoundation), code review iOS/Swift, UI/HIG review, testing/TDD, security (privacy manifest / required-reason API), performance, release-review e gate di rilascio | — |
| **caveman** (`.claude/skills/caveman/`) | Stile output compresso per risparmio token (`/caveman lite\|full\|ultra\|off`) | Comprime lo stile, mai la sostanza |

**In sintesi:** Trueline disegna **solo il piano** (BOOTSTRAP); la suite
**apple-skills** possiede **tutto il resto** — la build (implementazione) e ogni
controllo/review/verifica. Il verdetto di un check resta di un **oracolo
deterministico** della toolchain Apple (`swift build` / `swift test`, SwiftLint,
grafo dei moduli come oracolo di altitudine, e i tool degli `apple-skills`),
**mai** una dichiarazione dell'LLM e **mai** un checkpoint Trueline.

## Stato

- Toolchain vendorizzata e documento di fattibilità completi (scope confermato:
  `DI-005` Angavu, `DI-006` compressione video in v1, `DI-007` extra-foto in v1).
- **Trueline BOOTSTRAP completato**: `blueprint/` generato da
  `docs/FEASIBILITY-iOS.md` (11 macrotask, 36 task atomici con
  `definition_of_done`/`acceptance_criteria`/`target_tests`, contratto di
  altitudine, mappa delle degradazioni degli oracoli Swift/iOS in `00-INDEX` §7,
  3 prompt di lifecycle in `blueprint/prompts/`). Self-check **strutturale**
  verde (`validate_blueprint.mjs blueprint` → exit 0) e semantico applicato.
- Decision ledger **interamente confermato** (`DI-001…008` tutti `✅`; i default
  `DI-002/003/004/008` confermati dall'utente): nessuna decisione pendente.
- **BUILD `foundation` completato**: `Package.swift` a 3 moduli (AngavuDomain puro
  / AngavuData / AngavuFeatures) + app SwiftUI `App/` iOS 17.0, oracolo di
  altitudine (import `domain→data` rompe la build), gate `-warnings-as-errors`,
  motore d'analisi cancellabile nel Domain. `swift build`/`swift test` verdi
  (11 pass, 2 skip). `swiftlint` dichiarato non coperto nel sandbox (L-COL-006),
  da girare al confine Apple con `make lint`.
- Prossimo passo: **BUILD** del macrotask `library_index` (PhotoKit + indice
  SwiftData), rispettando il DAG.
