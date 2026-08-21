# ecosystems/supabase-jsts/guide.md — Trueline · ecosistema v1 (JS/TS su Supabase)

> Caricato in **tutte e tre** le modalità (`02` §6). È il punto di estensione v2:
> aggiungere un ecosistema = aggiungere un file qui (`firebase.md`, `nextjs-api.md`…)
> + il suo ruleset, **senza toccare il corpo** *(O-COL-005)*.

---

## Profilo dell'ecosistema v1

- **Linguaggio**: JavaScript / TypeScript — Node.js, Deno edge runtime, browser.
- **Backend**: Supabase — Postgres + PostgREST (Data API) + GoTrue Auth + Storage + Realtime + Edge Functions (Deno).
- **Client ufficiale**: `@supabase/supabase-js` v2 — libreria isomorfica (browser + server), espone `createClient(url, key)`.
- **Schema dichiarato**: migration SQL in `supabase/migrations/**/*.sql`; anche `supabase/functions/` per le edge function.
- **Test runner tipici**: vitest (prevalente), jest, `node:test`.

---

## Oracle set v1 — batteria completa

| Controllo chkp | Categoria finding | Oracolo | Wrapper | Note v1 |
|---|---|---|---|---|
| 2 — sicurezza | `injection`, `authz`, `crypto`, `secret` | Semgrep + ruleset AI curato (`references/oracles/semgrep-ai-ruleset/`) | `scripts/oracles/run_semgrep.mjs` | vendorizzato, offline, source-side |
| 2 — sicurezza | `secret` | gitleaks — working tree **e history** | `scripts/oracles/run_gitleaks.mjs` | `--redact` obbligatorio; allowlist in `.gitleaks.toml` |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | `scripts/oracles/run_osv.mjs` | online default (solo nome+versione); `--offline` disponibile |
| 2 — sicurezza | `rls` | RLS checker custom (`scripts/oracles/rls_check.mjs`) | `scripts/oracles/rls_check.mjs` | unico oracolo costruito da noi; vendorizzato nel `.skill` |
| 1 — dead-code | `dead-code` | knip (primario) / ts-prune / depcheck (fallback) | `scripts/oracles/run_deadcode.mjs` | richiede `knip.json`; rimozioni mai automatiche (`L-COL-021`) |
| 3 — regressioni | — | suite di test del progetto (BUILD) / characterization (REMEDIATE) | `scripts/characterization/` | il test runner è rilevato da `detect_runner.mjs` |
| 4 — conformità | — | `target_tests` del task atomico (BUILD) / suite characterization (REMEDIATE) | eseguiti dal runner del progetto | `L-COL-019` |

---

## Specifiche Supabase RLS

### Il modello di sicurezza

Supabase espone le tabelle Postgres via PostgREST (Data API REST). Senza RLS,
una tabella `public` è leggibile e scrivibile da chiunque abbia la **anon key**
(che è pubblica per definizione). RLS è l'unico meccanismo che isola i dati per
utente/tenant a livello di DB.

### Standard RLS nominato (R1–R9)

Definito per intero in `references/conventions/named-standards.md` §3.4.
Riepilogo operativo:

| Regola | Requisito | Verifica |
|---|---|---|
| R1 | RLS abilitato su ogni tabella `public` / user-facing | `[statico]` rls_check |
| R2 | RLS abilitato ⇒ ≥1 policy (niente deny-all silenzioso) | `[statico]` rls_check |
| R3 | Niente `USING (true)` / `WITH CHECK (true)` su tabelle user-facing; niente `auth.uid() IS NOT NULL` come sola condizione | `[statico]` rls_check |
| R4 | Le policy vincolano per identità/tenant (`auth.uid() = user_id` / `tenant_id`) | `[DB-test]` rls_characterize |
| R5 | Clausola `TO authenticated` (o ruolo appropriato) specificata | `[statico]` rls_check |
| R6 | UPDATE policy accompagnata da SELECT policy | `[statico]` rls_check |
| R7 | service_role confinata server-side + authz applicativa esplicita | `[statico]` + `[DB-test]` |
| R8 | Funzioni `SECURITY DEFINER` fanno authz propria | `[statico]` rls_check |
| R9 | Performance: `(select auth.uid())` per cache initPlan; colonne indicizzate | `[advisory]` |

**Confine dichiarato:** il checker statico legge le migration SQL (`pgsql-ast-parser`).
Non vede lo schema modificato solo dal dashboard Supabase senza migration.
Il checker dichiara il confine — non lo riempie con stime.

**Trappola del test:** l'SQL Editor di Supabase gira come superuser e bypassa
RLS → testare RLS nell'editor dà falso verde. La verifica di R4/R7 richiede
query **attraverso il client** con auth reale su un DB di test (`06` §6.1).

### Caratterizzazione RLS a runtime

Quando esiste un **DB di test** (Supabase locale `supabase start`, migration
applicate), `scripts/characterization/rls_characterize.mjs` esercita le policy
a runtime. Senza DB di test, il controllo comportamentale RLS **degrada** al
checker statico e si **dichiara** (`06` §6.1, `L-COL-006`): mai un verde finto.

---

## Specifiche supabase-js v2

### Client e chiavi

```ts
import { createClient } from '@supabase/supabase-js'

// lato client (browser/edge): usa la anon key
const supabase = createClient(url, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)

// lato server (solo server-side, mai nel browser): usa la service_role key
const adminClient = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY)
```

**Regola:** la **anon key** è pubblica per design e sicura con RLS attivo. La
**service_role key** bypassa RLS: deve stare solo server-side e ogni handler che
la usa deve fare authz applicativa esplicita (`forbidden-patterns.md` §4.3).

### Pattern di accesso ai dati

| Pattern | Oracolo che lo copre |
|---|---|
| `.from('table').select()` — lettura user-scoped | RLS checker (policy SELECT) |
| `.from('table').insert({...})` — scrittura user-scoped | RLS checker (policy INSERT) |
| `.from('table').update({...}).eq(...)` — update | RLS checker (policy UPDATE + R6) |
| `.rpc('fn', args)` — funzione RPC | RLS checker (R8 per SECURITY DEFINER) |
| `.from('table').or("col.eq.${x}")` — **filtro interpolato** | Semgrep (forbidden-patterns §4.2 PostgREST filter injection) |
| `supabase.storage.from('bucket')` — storage | Semgrep (path traversal, §4.5) |
| `supabase.auth.getUser()` — identità del chiamante | Semgrep authz (§4.3) |

### Injection via PostgREST filter

Un pattern specifico di supabase-js: i metodi `.or(string)` / `.filter(col, op, string)` accettano stringhe grezze che PostgREST interpreta come SQL. Se l'input utente è interpolato, è injection:

```ts
// VIETATO — CWE-89, A05:2025
const { data } = await supabase.from('t').or(`col.eq.${userInput}`)

// SICURO — usa i metodi tipati
const { data } = await supabase.from('t').eq('col', validatedValue)
```

Catturato dalla regola Semgrep `col-injection-postgrest-filter` del ruleset curato.

---

## Pattern di fallimento killer (top 5 per Supabase)

1. **Tabella `public` senza RLS** — esposta a chiunque abbia la anon key via
   PostgREST. Severità: HIGH. Regola R1.
2. **Policy `USING (true)` / `WITH CHECK (true)`** — RLS abilitato ma isolamento
   finto: ogni riga è visibile/scrivibile a tutti. Severità: HIGH. Regola R3.
3. **Multi-tenant senza `auth.uid()` nella policy** — utente A legge righe del
   tenant B. Severità: HIGH. Regola R4 (richiede DB-test per verifica piena).
4. **service_role key** hardcoded o usata lato client — bypassa RLS, espone
   l'intero DB. Severità: CRITICAL. Regole R7 + `forbidden-patterns.md` §4.1.
5. **Route mutante senza authz** — handler che scrive senza verificare
   `auth.getUser()` / JWT del chiamante. Severità: HIGH. Regola R8 / §4.3.

---

## Specifiche di caratterizzazione per l'ecosistema v1

Nel percorso critico di REMEDIATE (`06` §5, `scripts/characterization/`):

| Area | Tecnica di caratterizzazione |
|---|---|
| Endpoint Express/Edge Function | `request → response` (body, status, header) |
| Handler RLS-dipendenti | access pattern: chi legge/scrive cosa (richiede DB di test) |
| Funzioni pure di validazione | golden-master `input → output` |
| Middleware auth | comportamento con token valido / scaduto / assente |
| Storage path | path-traversal boundary (input → path normalizzato) |

**Non-determinismo comune in questo ecosistema e come si stabilizza:**

- timestamp `created_at` / `updated_at` → inietta clock fisso o assertisci solo il tipo.
- UUID generati dal DB → assertisci formato UUID, non il valore.
- Edge Function con crypto → `crypto.randomUUID()` è sostituibile con mock deterministico.

---

## Preflight specifico v1

Il preflight (`scripts/preflight.*`) verifica in aggiunta:

- `supabase` CLI presente per `supabase start` (DB di test per RLS a runtime) — assente → caratterizzazione RLS degrada a statico, dichiarato.
- `knip.json` presente o proponibile — assente → la skill propone una config di default ragionevole per JS/TS+Supabase.
- Lockfile presente (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) — assente → osv-scanner non può girare, controllo degradato e dichiarato.
