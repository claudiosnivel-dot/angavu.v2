# SESSION-STATE — Angavu iOS

> Fonte di verità sullo **stato vivo del progetto**, consumata da BUILD
> (apple-skills) e aggiornata a ogni chiusura di sessione. Distinta dalla
> SESSION-STATE interna di Trueline. Prosa in italiano, identificatori in inglese.

| | |
|---|---|
| **Progetto** | Angavu iOS |
| **Ecosistema** | swift-ios (SwiftUI + SwiftData + PhotoKit/Vision/AVFoundation) |
| **Ultimo aggiornamento** | 2026-08-21 (BOOTSTRAP) |
| **Sessione corrente** | bootstrap-0 |

---

## 1. Stato dei macrotask

> Stati: `todo` | `in_progress` | `done`. Ordine del piano di build (00-INDEX §2).
> Il checkpoint qui è la **verifica apple-skills** (swift build/test, SwiftLint,
> grafo moduli), non un checkpoint Trueline (policy di repo).

| Macrotask | Stato | Checkpoint | Note |
|---|---|---|---|
| `foundation` | todo | — | Scaffold + oracoli toolchain + Domain puro + motore cancellabile |
| `library_index` | todo | — | Dipende da foundation |
| `dashboard` | todo | — | Dipende da library_index |
| `safety_net` | todo | — | Dipende da library_index (rete di sicurezza intoccabile) |
| `exact_duplicates` | todo | — | Dipende da library_index; elimina via safety_net |
| `similar_photos` | todo | — | Dipende da library_index; elimina via safety_net |
| `large_old_media` | todo | — | Dipende da library_index; elimina via safety_net |
| `blurry_photos` | todo | — | Dipende da library_index; elimina via safety_net |
| `video_compression` | todo | — | `DI-006`: primo candidato al de-scope |
| `extra_photo_domains` | todo | — | `DI-007`: indipendente dal cuore-foto |
| `ui_shell` | todo | — | Onboarding-manifesto + report onesto, trasversale |

## 2. Macrotask corrente

- **Selezionato**: `foundation` (nessuna dipendenza aperta, radice del DAG).
- **Task atomici in corso**: nessuno (BOOTSTRAP non produce codice).
- **Criteri/test di riferimento**: vedi `01-foundation.md` e i `target_tests` dei
  task T-001…T-004 (oracolo di conformità in BUILD: `swift test`).

## 3. Stato git

> Mai lavorare su `main`. Merge gated dal verde apple-skills.

| Campo | Valore |
|---|---|
| Branch di lavoro | `claude/angavu-ios-app-wjq1jf` |
| Ultimo commit | (BOOTSTRAP: blueprint generato) |
| Stato merge su `main` | non ancora (gated dal verde della verifica apple-skills) |
| Deploy-coupling | `main_deploy_coupled: unknown` — nessun deploy automatico noto (app iOS via App Store Connect, fuori dal repo) |

## 4. Baseline & budget

- **Baseline privacy/sicurezza**: `blueprint/BASELINE-AND-BUDGET.md` — findings accettati / soglie.
- **Budget consumato**: 0 (BOOTSTRAP) / vedi `BASELINE-AND-BUDGET.md`.

## 5. Esiti dell'ultima sessione (framing onesto)

- Blueprint generato dai template Trueline, adattato all'ecosistema swift-ios.
- `validate_blueprint.mjs blueprint` è **passato** (exit 0): 36 task, tutti i 7
  controlli strutturali OK, incluso il contratto di altitudine.
- Self-check semantico (punti 6–10) applicato: nessun rilievo bloccante aperto.

## 6. Prossimi passi

- Confermare i default `🟡` del decision ledger (`DI-002/003/004/008`, 00-INDEX §4).
- Aprire la prossima sessione in modalità **BUILD** (apple-skills) sul macrotask
  `foundation` (T-001 scaffold), rispettando il DAG.
- Il dispatch alla prossima sessione (blueprint + SESSION-STATE presenti) sceglie
  BUILD con confidenza alta.
