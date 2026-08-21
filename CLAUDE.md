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
- Prossimo passo: **Trueline BOOTSTRAP** su `docs/FEASIBILITY-iOS.md` → `blueprint/`.
