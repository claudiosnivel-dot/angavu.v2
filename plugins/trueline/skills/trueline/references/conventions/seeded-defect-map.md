# Seeded Defect Map — S1..S8

**Sorgente:** `10-EVALUATION` §2 (tabella difetti seminati) + `eval/harness/expected/registry.json` + `07-CONVENTIONS-THREATMODEL` §4 (pattern vietati), §5/`named-standards.md` §3.4 (standard RLS R1..R9), §6/`threat-model.md` §6.3 (superfici enumerate).  
**Uso:** il gate di valutazione (`10` §3, `eval/harness/`) verifica che ogni difetto seminato corrisponda a un pattern vietato / provvedimento RLS / superficie enumerata; questo file è l'artifact di mappatura che il gate può consultare.

---

## Mappatura S1..S8

### S1 — Chiave hardcoded nel sorgente

| Campo | Valore |
|---|---|
| `category` | `secret` |
| `source_oracle` | gitleaks (autoritativo sui segreti, `03` §6) |
| `owasp` | A07:2025 · A02:2025 |
| `cwe` | CWE-798 |
| `expected_fix_state` | `verified` |
| **Pattern vietato** | `forbidden-patterns.md` §4.1 — chiave / segreto come string literal assegnato a `key` / `secret` / `token`; **service_role key** hardcoded o usata lato client |
| **RLS R#** | R7 (service_role confinata server-side) — overlap |
| **Superficie** | `threat-model.md` §6.3 — Config da env / Edge Function; fiducia: input inline → untrusted → CRITICAL |
| **Anchor** | `eval/reference-app/src/lib/config.ts`, marker `SEED:S1` |

---

### S2 — Segreto nella git history (working tree pulito)

| Campo | Valore |
|---|---|
| `category` | `secret` |
| `source_oracle` | gitleaks (scan history, `03` §5.2) |
| `owasp` | A07:2025 |
| `cwe` | CWE-798 |
| `expected_fix_state` | `mitigated-residual` (non `verified`: la riscrittura della history è distruttiva, gate umano `L-COL-024`) |
| **Pattern vietato** | `forbidden-patterns.md` §4.1 — chiave / segreto come string literal; il pattern è ora solo nella history |
| **RLS R#** | nessuno diretto (il segreto non è più nel working tree) |
| **Superficie** | `threat-model.md` §6.3 — Config da env; fiducia: segreto storico nella history git |
| **Anchor** | `eval/reference-app/src/legacy/credentials.ts` (history), `history_path: src/legacy/credentials.ts` |

---

### S3 — Tabella `public` senza RLS

| Campo | Valore |
|---|---|
| `category` | `rls` |
| `source_oracle` | rls-check (statico su DDL migration) |
| `owasp` | A01:2025 |
| `cwe` | CWE-285 |
| `expected_fix_state` | `verified` |
| **Pattern vietato** | nessuna regola Semgrep diretta (il checker RLS è l'oracolo pertinente) |
| **RLS R#** | **R1** — RLS abilitato su ogni tabella `public`/user-facing `[statico]` |
| **Superficie** | `threat-model.md` §6.3 — Tabella RLS-governata; fiducia default: untrusted (via anon); OWASP: A01:2025 |
| **Anchor** | `eval/reference-app/supabase/migrations/0001_init.sql`, marker `SEED:S3`, tabella `public.audit_logs` |

---

### S4 — Policy `USING (true)` (isolamento finto)

| Campo | Valore |
|---|---|
| `category` | `rls` |
| `source_oracle` | rls-check (statico su DDL migration) |
| `owasp` | A01:2025 |
| `cwe` | CWE-285 |
| `expected_fix_state` | `verified` |
| **Pattern vietato** | nessuna regola Semgrep diretta |
| **RLS R#** | **R3** — niente `USING (true)` / `WITH CHECK (true)` su tabelle user-facing `[statico]` |
| **Superficie** | `threat-model.md` §6.3 — Tabella RLS-governata; fiducia default: untrusted (via anon); OWASP: A01:2025 |
| **Anchor** | `eval/reference-app/supabase/migrations/0001_init.sql`, marker `SEED:S4`, tabella `public.documents`, policy `documents_read_all` |

---

### S5 — Multi-tenant senza `auth.uid()`

| Campo | Valore |
|---|---|
| `category` | `rls` |
| `source_oracle` | rls-check `[DB-test]` (verifica comportamentale per-tenant) |
| `owasp` | A01:2025 |
| `cwe` | CWE-285 |
| `expected_fix_state` | `verified` (con DB di test attivo); degrada a checker statico `[statico]` senza DB di test, dichiarato |
| **Pattern vietato** | nessuna regola Semgrep diretta (richiede ragionamento su logica multi-tenant) |
| **RLS R#** | **R4** — le policy vincolano per identità/tenant (`auth.uid() = user_id` / derivazione `tenant_id`) `[DB-test]` |
| **Superficie** | `threat-model.md` §6.3 — Tabella RLS-governata; fiducia default: untrusted (via anon); OWASP: A01:2025 |
| **Anchor** | `eval/reference-app/supabase/migrations/0001_init.sql`, marker `SEED:S5`, tabella `public.invoices`, policy `invoices_visible_when_not_draft` |

---

### S6 — SQL concatenato (detection-only)

| Campo | Valore |
|---|---|
| `category` | `injection` |
| `source_oracle` | semgrep (ruleset curato M4) |
| `owasp` | A05:2025 |
| `cwe` | CWE-89 |
| `expected_fix_state` | `detection-only` (trovata, spiegata, prioritizzata; non auto-fixata nel set verificato; in REMEDIATE la skill può proporre fix senza elevare la categoria, `L-COL-023`) |
| **Pattern vietato** | `forbidden-patterns.md` §4.2 — SQL per concatenazione / template con input: `` pg.query(`SELECT … ${x}`) `` → query parametrizzate (`$1`) |
| **RLS R#** | nessuno diretto (injection, non controllo di accesso) |
| **Superficie** | `threat-model.md` §6.3 — Edge Function / route handler; input: body / query / params; fiducia: untrusted; OWASP: A05:2025; controllo: Semgrep §4.2 |
| **Anchor** | `eval/reference-app/src/db.ts`, marker `SEED:S6` |

---

### S7 — Route mutante senza authz (detection-only)

| Campo | Valore |
|---|---|
| `category` | `authz` |
| `source_oracle` | semgrep (ruleset curato M4) |
| `owasp` | A01:2025 |
| `cwe` | CWE-862 |
| `expected_fix_state` | `detection-only` (trovata, spiegata, prioritizzata; nessun falso via libera, `10` §3 criterio 3) |
| **Pattern vietato** | `forbidden-patterns.md` §4.3 — handler che scrive senza check identità/ruolo; mutation con client service_role senza authz applicativa |
| **RLS R#** | R7 (service_role confinata server-side, con authz applicativa esplicita) — overlap; R7 è `[statico]` + `[DB-test]` |
| **Superficie** | `threat-model.md` §6.3 — Edge Function / route handler; input: body / JWT; fiducia: untrusted → semi; OWASP: A01:2025; controllo: Semgrep §4.3, authz |
| **Anchor** | `eval/reference-app/src/routes/bookings.ts`, marker `SEED:S7` |

---

### S8 — Export/funzione morta introdotta

| Campo | Valore |
|---|---|
| `category` | `dead-code` |
| `source_oracle` | knip |
| `owasp` | nessuno (igiene) |
| `cwe` | nessuno |
| `expected_fix_state` | `verified` (rimozione via gate umano; knip riesieguito non segnala più il morto) |
| **Pattern vietato** | nessuna regola Semgrep (knip è l'oracolo del dead-code; le rimozioni non sono mai automatiche, `L-COL-021`) |
| **RLS R#** | nessuno |
| **Superficie** | nessuna superficie del threat model (il dead-code è igiene, non una categoria di rischio OWASP); il checkpoint blocca per **delta** (nuovo morto) non per severità |
| **Anchor** | `eval/reference-app/src/legacy/unused.ts`, marker `SEED:S8`, simbolo `formatLegacyBookingLabel` |

---

## Sintesi della copertura per oracolo

| Oracolo | Difetti coperti | Note |
|---|---|---|
| gitleaks | S1, S2 | autoritativo sui segreti; dedup semgrep-secret per stesso path |
| rls-check | S3, S4, S5 | S3/S4 `[statico]`; S5 `[DB-test]` (degrada senza DB) |
| semgrep | S6, S7 | detection-only nel set v1; M4 implementa le regole curate (§4.2/§4.3) |
| knip | S8 | dead-code; rimozione sempre gate-umano (`L-COL-021`) |

## Categorie detection-only vs verificate-a-zero

| Categoria | Difetti | Fix_state target |
|---|---|---|
| `secret` | S1, S2 | S1 → `verified`; S2 → `mitigated-residual` |
| `rls` | S3, S4, S5 | tutti → `verified` |
| `dead-code` | S8 | `verified` |
| `injection` | S6 | `detection-only` |
| `authz` | S7 | `detection-only` |
