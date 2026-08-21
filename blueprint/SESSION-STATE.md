# SESSION-STATE — Angavu iOS

> Fonte di verità sullo **stato vivo del progetto**, consumata da BUILD
> (apple-skills) e aggiornata a ogni chiusura di sessione. Distinta dalla
> SESSION-STATE interna di Trueline. Prosa in italiano, identificatori in inglese.

| | |
|---|---|
| **Progetto** | Angavu iOS |
| **Ecosistema** | swift-ios (SwiftUI + SwiftData + PhotoKit/Vision/AVFoundation) |
| **Ultimo aggiornamento** | 2026-08-21 (BUILD foundation) |
| **Sessione corrente** | build-1 |

---

## 1. Stato dei macrotask

> Stati: `todo` | `in_progress` | `done`. Ordine del piano di build (00-INDEX §2).
> Il checkpoint qui è la **verifica apple-skills** (swift build/test, SwiftLint,
> grafo moduli), non un checkpoint Trueline (policy di repo).

| Macrotask | Stato | Checkpoint | Note |
|---|---|---|---|
| `foundation` | done | swift build/test verdi (build-1) | T-001…T-004 chiusi; lint SwiftLint dichiarato non coperto qui (§7) |
| `library_index` | todo | — | Dipende da foundation (ora verde): prossimo macrotask |
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

- **Chiuso**: `foundation` — scaffold multi-modulo, oracolo di altitudine,
  gate warnings-as-errors, motore d'analisi cancellabile.
- **Prossimo**: `library_index` (dipendenza `foundation` ora verde).
- **Esito oracoli (build-1)**: `swift build -warnings-as-errors` exit 0;
  `swift test` 13 test → 11 pass, 2 skip, 0 fail; grafo di altitudine conforme,
  import proibito `domain→data` rompe la build.
- **Non coperto qui (L-COL-006)**: `swiftlint lint/analyze` — binario non
  ottenibile nel sandbox Linux (proxy GitHub scoped al solo repo target). La
  config `.swiftlint.yml` e i test esistono; l'oracolo gira al confine su
  toolchain Apple (`make lint`).

## 3. Stato git

> Mai lavorare su `main`. Merge gated dal verde apple-skills.

| Campo | Valore |
|---|---|
| Branch di lavoro | `claude/angavu-ios-app-wjq1jf` |
| Ultimo commit | BUILD foundation (scaffold + oracoli + motore cancellabile) |
| Stato merge su `main` | non ancora (gated dal verde della verifica apple-skills; lint da girare su toolchain Apple) |
| Deploy-coupling | `main_deploy_coupled: unknown` — nessun deploy automatico noto (app iOS via App Store Connect, fuori dal repo) |

## 4. Baseline & budget

- **Baseline privacy/sicurezza**: `blueprint/BASELINE-AND-BUDGET.md` — findings accettati / soglie.
- **Budget consumato**: 0 (BOOTSTRAP) / vedi `BASELINE-AND-BUDGET.md`.

## 5. Esiti dell'ultima sessione (framing onesto)

- **BUILD `foundation` completato** (build-1). Scaffold `Package.swift` a 3 moduli
  (AngavuDomain puro / AngavuData / AngavuFeatures) + app SwiftUI `App/` iOS 17.0.
- Oracoli eseguiti localmente (Swift 6.1.2 Linux, host): `swift build
  -warnings-as-errors` exit 0; `swift test` 11 pass / 2 skip / 0 fail.
- Altitudine imposta dal grafo: import `domain→data` produce errore di build
  (dipendenza circolare) — verificato da `AltitudeGraphTests`.
- **Non coperto qui**: `swiftlint` non installabile nel sandbox (proxy GitHub
  scoped). Dichiarato apertamente (L-COL-006); config + test pronti per il confine
  Apple. Nessun verde finto.
- Nota toolchain: build/test girano su Swift Linux perché i moduli di
  `foundation` sono piattaforma-puri; PhotoKit/Vision/AVFoundation entrano dai
  macrotask successivi e richiederanno la toolchain Apple.

## 6. Prossimi passi

- Decision ledger **interamente confermato**: nessuna decisione pendente.
- **Prossimo macrotask**: `library_index` (PhotoKit: permessi, enumerazione
  `PHAsset`, indice SwiftData incrementale, byte reali). Richiede toolchain Apple
  per gli oracoli (framework di device).
- Al primo confine su macOS/CI: girare `make lint` (SwiftLint + analyze) per
  chiudere l'oracolo T-003 oggi dichiarato non coperto, poi valutare il merge.
