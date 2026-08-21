# BASELINE & BUDGET — Angavu iOS

> Baseline di sicurezza/privacy (findings accettati e soglie) e budget di
> spesa/tempo per ciclo. Riferito da `00-INDEX`, `VISION-AND-CONSTRAINTS`,
> `SESSION-STATE`. Prosa in italiano, identificatori in inglese.

---

## 1. Baseline privacy & sicurezza (iOS)

Sostituisce la baseline RLS/Supabase (non applicabile: zero backend). L'oracolo
del verdetto è la suite **apple-skills** (00-INDEX §7), non l'LLM.

| Voce | Requisito | Oracolo (apple-skills) |
|---|---|---|
| Required-reason API | Dichiarate in `PrivacyInfo.xcprivacy` per ogni API a motivazione richiesta usata | Check privacy-manifest degli apple-skills |
| Usage description | `NS…UsageDescription` presenti, sincere e minime per ogni permesso usato | Check Info.plist / permessi |
| No-network | Nessun simbolo di rete/telemetria: zero dati fuori dal device | Oracolo "no-network symbols" degli apple-skills |
| No-secret | Nessun segreto/credenziale/signing nel sorgente | Scan segreti su repo |
| Permessi minimi | Nessun permesso dichiarato e non usato | Review permessi apple-skills |
| Rete di sicurezza | Ogni eliminazione passa da anteprima obbligatoria → Eliminati di recente | `target_tests` di `safety_net` (T-050…T-052) |

**Findings accettati (baseline iniziale):** nessuno. Ogni degradazione di oracolo
(00-INDEX §7) è **dichiarata non coperta**, mai un verde finto (`L-COL-006`).

## 2. Soglie

| Categoria | Soglia | Nota |
|---|---|---|
| Build | `swift build -warnings-as-errors` deve uscire 0 | Nessun warning tollerato sui moduli del package |
| Lint | `swiftlint lint --strict` deve uscire 0 | Include dead-code/unused e no-force-unwrap sui path critici |
| Test | `swift test` verde su tutti i `target_tests` del macrotask | Oracolo di conformità-logica e regressione |
| Altitudine | Grafo moduli SwiftPM conforme al `forbidden` (00-INDEX §1bis) | `domain → data` non deve compilare |

## 3. Budget

| Risorsa | Limite | Nota |
|---|---|---|
| Tempo dev | ~3 h/settimana | Scope rigido; de-scope dal basso (video_compression, `DI-006`) |
| Costo runtime | 0 | Zero backend, tutto on-device |
| Costo strutturale | 99 $/anno | Apple Developer Program (unico costo nuovo vs Android) |
| Dimensione app | ethos "<15 MB" | Nessun modello Core ML bundolato (Vision è di sistema) |

## 4. Regola di de-scope

Se il piano slitta, il taglio parte **dal basso** del feature set (feasibility §5):
`video_compression` (`DI-006`) è il **primo** candidato. **Intoccabili**: la rete
di sicurezza (`safety_net`) e il cuore-foto (`library_index`, `exact_duplicates`,
`similar_photos`).
