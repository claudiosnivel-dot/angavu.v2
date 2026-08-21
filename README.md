# angavu.v2 — Angavu per iOS

Porting **onesto** di [Angavu](https://github.com/claudiosnivel-dot/angavu) — il
cleaner Android — sulla piattaforma Apple. Non è un port 1:1 (il sandbox iOS
rende impossibile ~2/3 delle funzioni Android), ma un **prodotto gemello** sullo
stesso manifesto: offline, senza pubblicità, numeri veri, rete di sicurezza,
costruito sul massimo che iOS consente davvero.

## Da dove partire

| File | Ruolo |
|---|---|
| [`docs/FEASIBILITY-iOS.md`](docs/FEASIBILITY-iOS.md) | **Documento di fattibilità e strategia** — mappa feature-per-feature Android→iOS (portabile / sostituibile / impossibile), differenziatori vs competitor, feature set v1, architettura proposta, rischi, decision ledger. È l'input strategico da cui generare il blueprint tecnico. |

Lo stato dell'app Android e il suo blueprint restano nel repo
[`claudiosnivel-dot/angavu`](https://github.com/claudiosnivel-dot/angavu).

## Toolchain (vendorizzata, ispezionabile, no auto-update)

Il marketplace locale `angavu-local` (`.claude-plugin/marketplace.json`) è
registrato e abilitato per chiunque apra il repo via `.claude/settings.json`.

| Percorso | Ruolo |
|---|---|
| `plugins/trueline/` | Plugin Trueline (MIT). In **questo** repo usato **solo ed esclusivamente in modalità BOOTSTRAP** per generare il blueprint tecnico dell'app iOS — niente BUILD/REMEDIATE, niente checkpoint/oracoli di Trueline come gate di verifica. |
| `plugins/apple-skills/` | 164 skill Apple su 23 categorie (iOS, SwiftUI, SwiftData, **Core ML/Vision**, testing, security, performance, App Store), vendorizzato da [rshankras/claude-code-apple-skills](https://github.com/rshankras/claude-code-apple-skills) (MIT). In questo repo possiede **tutta la build e tutta la verifica** (implementazione, review, testing, security, release gate). |

> **Policy toolchain** (vincolante, vedi [`CLAUDE.md`](CLAUDE.md)): Trueline disegna **solo il piano** (BOOTSTRAP); la suite **apple-skills** possiede **tutto il resto** — build e ogni controllo/review/verifica. Il verdetto resta di un oracolo deterministico della toolchain Apple, mai dell'LLM.
| `.claude/skills/caveman/` | Skill di stile output ultra-compresso per risparmio token (MIT). Attivabile con `/caveman lite\|full\|ultra\|off`. Comprime lo stile, mai la sostanza. |

### Attivazione

Al primo avvio di Claude Code nella cartella (dopo il **trust**),
`.claude/settings.json` registra il marketplace e abilita i plugin. Se la
sessione era già aperta:

```shell
/reload-plugins
/plugin list
```

> **Nota sul trust.** Il trust della cartella è una decisione di sicurezza
> **lato client**, salvata nella config utente locale (`~/.claude.json`), **non**
> nel repo: per design un repo non può auto-dichiararsi fidato. Sulla tua macchina
> è **permanente** appena accetti una volta il dialog *"Do you trust the files in
> this folder?"*. In un ambiente **remoto/web** il container è effimero: il trust
> concesso può non sopravvivere a una nuova sessione (nuovo container) e va
> riconcesso. Ciò che è già versionato e permanente è il lato repo
> (`.claude/settings.json`): appena una macchina si fida della cartella, i plugin
> si attivano da soli, senza installazione manuale.

## CI — l'oracolo Apple in cloud (senza un Mac)

Gli oracoli Apple (`swift build`/`test`, SwiftLint, build dell'app iOS) girano su
un **runner macOS di GitHub Actions** (`.github/workflows/ci.yml`, `macos-15`), a
ogni push. È il "confine Apple" **senza possedere un Mac**: il verde/rosso è
l'esito reale della CI, non una dichiarazione dell'LLM (L-COL-002). Il merge su
`main` è gated da quel verde. La stessa pipeline potrà poi archiviare e caricare su
TestFlight/App Store via App Store Connect API key (secrets), sempre headless.

> **Minuti**: su repo privato i minuti macOS contano ×10 (~200/mese nel piano
> Free). Il job `ios-app` è separato e disattivabile per risparmiare.

## Stato

Fonte di verità: [`blueprint/SESSION-STATE.md`](blueprint/SESSION-STATE.md).
`foundation` chiuso (build-1); `library_index` (build-2) e `safety_net` (build-3)
implementati e `in_progress` fino al verde della CI.
