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

## Stato

Bootstrap toolchain completato. Prossimo passo: revisione del documento di
fattibilità, poi generazione del blueprint tecnico via Trueline **BOOTSTRAP**.
