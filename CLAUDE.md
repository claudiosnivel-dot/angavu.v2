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

## Attivazione e trust

I plugin `angavu-local` (trueline + apple-skills) si attivano da
`.claude/settings.json` **appena la cartella è fidata**. Il trust vive nella
config utente locale (`~/.claude.json`), non nel repo: sulla macchina locale è
permanente dopo che accetti una volta il dialog di trust; in un ambiente
remoto/web il container è effimero, quindi il trust può richiedere di essere
riconcesso a ogni nuova sessione. Il lato repo è già versionato e permanente:
nessuna installazione manuale dei plugin.

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
- **Confine Apple = CI GitHub Actions** (`.github/workflows/ci.yml`, runner
  `macos-15`): a ogni push gira `make build`/`test`/`lint` + build dell'app iOS.
  È qui che l'oracolo Swift emette verde/rosso (L-COL-002), senza possedere un Mac.
- **BUILD verificati (CI Apple verde)**: `foundation`, `library_index`,
  `safety_net`, `dashboard`. `dashboard` chiuso al run #6 (`success`): T-020
  (aggregazione per categoria, exact/estimated separati), T-021 (caveat iCloud,
  riusa `DeletedAssetSize`), T-022 (banner limited). Package a 3 moduli
  (AngavuDomain puro / AngavuData / AngavuFeatures) + app SwiftUI `App/` iOS 17.0;
  oracolo di altitudine (import `domain→data` rompe la build), gate
  `-warnings-as-errors`.
- Prossimo passo: **BUILD** del macrotask `exact_duplicates` (SHA-256 sui candidati
  per dimensione; elimina via `safety_net`), rispettando il DAG.

## Lifecycle di sessione (vincolante)

- **Inizio sessione**: eseguire `blueprint/prompts/session-start.md` (recupero
  contesto da `SESSION-STATE`, scelta macrotask sul DAG, ripetizione
  task/criteri/test, branch pronto).
- **Fine sessione — automatica sul verde**: **ogni volta che il macrotask della
  sessione è verde** (oracolo Apple in CI = run `success` su build+test+lint),
  eseguire `blueprint/prompts/session-end.md` e chiudere: marcare il macrotask
  `done` in `SESSION-STATE.md`, registrare il commit e l'esito del gate, indicare
  il prossimo macrotask. Regola confermata dall'utente (2026-08-21) per tutte le
  sessioni future. NB: è una convenzione di repo letta da ogni sessione, non un
  hook dell'harness (non esiste un evento harness "macrotask verde").
