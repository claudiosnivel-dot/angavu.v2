# Finding model — schema, stati e regola di verifica

Questo documento descrive il **finding model**, il contratto unico (`L-COL-011`) fra
oracoli (`03`), loop di fix (`05`) e triage (`08`). L'LLM ragiona **su questo oggetto
strutturato**, mai sul dump nativo del tool. La definizione formale e in
[`../scripts/findings/finding.schema.json`](../scripts/findings/finding.schema.json)
(JSON Schema draft 2020-12); la documentazione narrativa di riferimento e
`04-FINDINGS-MODEL.md`.

## Schema (campi)

| Campo | Tipo | Obbligatorio | Significato |
|---|---|---|---|
| `fingerprint` | string | si | Identita stabile-per-riga = `hash(oracle, rule_id, normalized_path, match_signature)`. **Non** il numero di riga. Chiave del baseline-delta. |
| `id` | string | no | Handle leggibile locale al run (es. `F-014`); non e l'identita persistente. |
| `category` | enum | si | `secret` \| `rls` \| `dead-code` \| `injection` \| `authz` \| `crypto` \| `dependency-vuln` \| `config` \| `misc`. |
| `severity` | enum | si | `CRITICAL` \| `HIGH` \| `MEDIUM` \| `LOW`. |
| `location` | object | si | `{ file, start_line, end_line, symbol? }`. La riga e **display**; l'identita e il fingerprint. |
| `evidence` | string | si | Snippet/messaggio **redatto** (mai il valore di un segreto). |
| `source_oracle` | object | si | `{ oracle, tool_version?, rule_id }` — chi l'ha prodotto. |
| `owasp` | string | no | Codice OWASP **canonico 2025** (`L-COL-026`), pattern `A0x:2025`. |
| `owasp_source` | string | no | Codice OWASP/CWE **grezzo** come emesso dalla fonte (es. `A01:2021`, `CWE-89`), preservato per tracciabilita. Display/audit, non per il gating. |
| `cwe` | string | no | Identificatore CWE preciso (es. `CWE-89`), quando l'oracolo lo fornisce. |
| `fix_state` | enum | si | Stato del ciclo di vita della fix (vedi sotto). |
| `baseline_status` | enum | si | `new` \| `pre-existing` rispetto alla baseline. |
| `scope_relevance` | enum | no | `in-scope` \| `out-of-scope` rispetto al codice toccato dal macrotask. |
| `remediation_hint` | string | no | Suggerimento da oracolo o convenzione; **non** un verdetto dell'LLM. |
| `run_id` | string | si | Identificatore del run che l'ha prodotto. |
| `created_at` | string | no | Timestamp di creazione (ISO 8601). |
| `notes` | string \| null | no | Metadati di triage; **mai** un via libera. |

I campi **obbligatori** sono: `fingerprint`, `category`, `severity`, `location`,
`evidence`, `source_oracle`, `fix_state`, `baseline_status`, `run_id`.
Gli enum (`category`, `severity`, `fix_state`, `baseline_status`, `scope_relevance`)
sono **set chiusi**: un valore fuori enum e un finding **invalido** e viene rifiutato.

## Stati di `fix_state`

Ciclo di vita chiuso. Stato iniziale dopo `normalize` (prodotto dall'oracolo) =
**`detected`**.

| Stato | Significato |
|---|---|
| `detected` | trovato dall'oracolo, intatto. **Stato iniziale.** |
| `triaged` | prioritizzato/spiegato dall'LLM (`08`), non ancora corretto. |
| `fix-proposed` | patch proposta, in attesa del gate umano (`L-COL-005`, `L-COL-021`). |
| `fix-applied` | patch applicata sul branch (dopo il gate umano). |
| `verified` | oracolo riesieguito **pulito** **e** nessun test rotto. Unico stato comunicabile come "trovato e verificata la correzione". |
| `verification-failed` | il re-run flagga ancora o un test si e rotto → torna a `fix-proposed`/retry, o scarto. |
| `mitigated-residual` | mitigazione fatta ma residuo non azzerabile senza azione distruttiva (es. segreto ruotato, residuo in git history). **Non** e `verified`. |
| `accepted-risk` | l'umano accetta il finding; registrato, **mai** scartato in silenzio. |

Transizioni ammesse:

```
detected -> triaged -> fix-proposed -> fix-applied -> {verified | verification-failed}
verification-failed -> fix-proposed   (entro la retry policy)  | -> accepted-risk
secret (history) -> fix-applied(rotazione) -> mitigated-residual -> [opz. history rewrite, gate umano] -> verified
qualsiasi -> accepted-risk             (decisione umana esplicita)
```

## Regola: solo l'oracolo porta a `verified` (`L-COL-002`)

Il verde di un controllo e **l'output reale di un comando deterministico, mai una frase**.
Di conseguenza:

- **Solo l'oracolo** puo promuovere un finding a `verified`, e solo quando il re-run
  e **pulito** e **nessun test si rompe**. L'LLM non porta mai un finding a `verified`
  (`L-COL-002`, `L-COL-003`, `L-COL-006`).
- L'LLM puo scrivere `notes` e portare a `triaged`, puo proporre una patch
  (`fix-proposed`), ma **non** dichiara da solo che un problema e risolto.
- `mitigated-residual` e `accepted-risk` sono mostrati per quello che sono —
  mitigazioni e rischi accettati, **non** verifiche. Niente falso "via libera".

## OWASP canonico 2025

Il campo `owasp` e **sempre** in codici **2025** (`L-COL-026`). Il codice come emesso
dalla fonte (2021/CWE) resta in `owasp_source` per tracciabilita. La traduzione avviene
nell'adapter (`03` §6) sulla mappa di `07` §3.1; le regole curate emettono gia 2025.
Spiegazioni e report citano **solo** il 2025.

## Validazione

Lo script [`../scripts/findings/validate_finding.mjs`](../scripts/findings/validate_finding.mjs)
valida un finding (o un array di finding) contro lo schema. Esporta `validateFinding(value)`
e `validateMany(values)`, ed espone una CLI:

```
node validate_finding.mjs <file.json>
```

Esce con codice `0` se valido, `!= 0` se invalido (stampando gli errori).
