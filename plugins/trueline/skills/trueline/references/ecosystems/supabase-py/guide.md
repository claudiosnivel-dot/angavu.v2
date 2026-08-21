# ecosystems/supabase-py/guide.md — Trueline · ecosistema supabase-py (Python su Supabase)

> Pack di rilevamento SP-3 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **rls**
> (RLS-al-DB Supabase via `rls_check` STATICO sulla DDL; riconosce `auth.uid()`
> come token di isolamento dal JWT).

---

## Profilo dell'ecosistema

- **Linguaggio**: Python — FastAPI, Flask, Django (e framework minimali tipo Starlette/aiohttp).
- **Backend**: Supabase — connessione al Postgres gestito da Supabase via `supabase-py` SDK, `psycopg` / `psycopg2`, SQLAlchemy raw o ORM; autenticazione via JWT Supabase, identità letta da `auth.uid()` / `auth.jwt()` nelle policy RLS.
- **Client tipici**: `supabase.create_client(url, key)`, `psycopg2.connect(DATABASE_URL)`, `AsyncSession` / `Session` di SQLAlchemy puntate al DB Supabase.
- **Schema dichiarato**: migration SQL gestite da Supabase CLI (`supabase/migrations/`). Marker forte: `supabase/config.toml` presente nella root. Directory migration tipiche: `supabase/migrations/`, `migrations/`, `db/migrations/`.
- **Test runner tipici**: pytest (prevalente), unittest.

---

## Oracle set — batteria detection (fase 1)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| 2 — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack Postgres |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `requirements.txt`, `poetry.lock`, `Pipfile.lock` |
| 2 — sicurezza | `rls` (`authz-surface`) | `rls_check` STATICO sulla DDL | Riconosce `auth.uid()` / `auth.jwt()` per Supabase (vedi sotto) |
| 2 — sicurezza | `injection` | semgrep Python + ruleset del pack (`ruleset/`) | SQL string-concat, f-string in query, `.format(...)` non parametrizzato |
| 1 — dead-code | `dead-code` | vulture | Rileva funzioni/classi Python non raggiungibili; rimozioni mai automatiche (L-COL-021) |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `rls`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza. Nessun finding di detection non equivale a "sicuro" (L-COL-006).

---

## authz-surface: RLS-al-DB Supabase via rls_check (non route-authz)

In questo ecosistema l'isolamento per identità/tenant è delegato al **database** tramite Row Level Security (RLS) di Supabase. L'identità dell'utente è estratta dal JWT Supabase tramite le funzioni built-in `auth.uid()` e `auth.jwt()` — non serve impostare manualmente il contesto di sessione come in Postgres non-Supabase. Le policy RLS sul DB garantiscono che ogni query legga o scriva solo le righe autorizzate per l'utente autenticato.

`rls_check` è un oracolo **STATICO** configurato con `"kind": "supabase-rls"` che legge i file SQL delle migration e verifica:

- presenza di `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` sulle tabelle sensibili;
- presenza di almeno una policy `CREATE POLICY ... USING (...)` per tabella protetta;
- uso di `auth.uid()` o `auth.jwt()` (pattern Supabase) come valore di contesto nelle policy — riconosciuti come token di isolamento validi.

### Pattern DDL sicuro riconosciuto (Supabase)

```sql
-- Abilita RLS sulla tabella
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

-- Policy che usa auth.uid() di Supabase per isolamento per utente (identità dal JWT)
CREATE POLICY tenant_isolation ON bookings
  USING (user_id = auth.uid());
```

### Pattern difettoso rilevato

```sql
-- DIFETTO — RLS non abilitato o policy assente: tutti gli utenti leggono tutti i record
-- (nessun ALTER TABLE ... ENABLE ROW LEVEL SECURITY o nessuna CREATE POLICY)
```

### Differenza rispetto a Postgres non-Supabase

Postgres non-Supabase usa `current_setting('app.current_user_id', true)` per leggere il contesto di sessione impostato manualmente dall'applicazione. Supabase usa `auth.uid()` come funzione built-in che legge l'identità direttamente dal JWT. `rls_check` riconosce entrambi i pattern; per questo pack è configurato con `"kind": "supabase-rls"` (non `"postgres-rls"`).

---

## Classificazione 2-D: segnale detect e pack di destinazione

La classificazione di un repo avviene in due dimensioni: **backend** (Supabase o Postgres diretto) e **linguaggio** (Python o JS/TS).

| Segnale rilevato | Pack assegnato |
|---|---|
| `supabase/config.toml` presente **+** file Python (`pyproject.toml` / `requirements.txt` / `Pipfile` / `setup.py`) | **supabase-py** |
| `supabase/config.toml` presente **+** file JS/TS (`package.json`) | **supabase-jsts** |
| Nessun `supabase/config.toml` **+** file Python | **postgres-py** |
| Nessun `supabase/config.toml` **+** file JS/TS | **postgres-jsts** |
| `supabase/config.toml` presente **+** entrambe le lingue o nessuna lingua riconoscibile | **ambiguo** — pack proposto + conferma utente |

### Forza del segnale detect per pack

| Pack | `files_any` (segnale forte) | `lang_any` (segnale lingua) |
|---|---|---|
| **supabase-py** | `supabase/config.toml` | `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.py` |
| **supabase-jsts** | `supabase/config.toml` | `package.json` |
| **postgres-py** | *(nessuno)* | `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.py` |
| **postgres-jsts** | *(nessuno)* | `package.json` |

`supabase-py` vince su `postgres-py` perché ha il segnale forte `supabase/config.toml` (files_any) **oltre** al segnale lingua py (lang_any). `postgres-py` ha solo il segnale lingua. `supabase-py` e `supabase-jsts` condividono lo stesso files_any ma si distinguono per la lingua: Python vs JS/TS.

---

## injection e dead-code (extra non-floor)

- **injection** (semgrep, ruleset `ruleset/supabase-py-injection.yml`): rileva query Python costruite con concatenazione di stringhe (`"SELECT ... " + user_input`, f-string non parametrizzate, `.format(...)` su SQL). Non genera finding sulle query con parametri `%s` / `:param` / `?`. Fixture di riferimento: `eval/ecosystems/supabase-py/reference-app`.
- **dead-code** (vulture): analisi statica AST. Rimuovere codice morto non è mai automatico (L-COL-021); vulture produce candidati che l'utente revisiona.

---

## Differenza rispetto agli altri pack Postgres/Supabase

| Aspetto | supabase-py | supabase-jsts | postgres-py |
|---|---|---|---|
| Linguaggio | Python | JS/TS | Python |
| authz-surface | RLS-al-DB (`rls_check`, `auth.uid()`) | RLS-al-DB (`rls_check`, `auth.uid()`) | RLS-al-DB (`rls_check`, `current_setting(...)`) |
| rls_check kind | `supabase-rls` | `supabase-rls` | `postgres-rls` |
| floor | `secret`, `dependency-vuln`, `rls` | `secret`, `dependency-vuln`, `rls` | `secret`, `dependency-vuln`, `rls` |
| verified_set | `[]` (tier detection, fase 1) | `[secret, rls, dead-code]` | `[]` (tier detection, fase 1) |
| Segnale detect forte | `supabase/config.toml` (files_any) **+** py | `supabase/config.toml` (files_any) **+** js/ts | solo `pyproject.toml` / `requirements.txt` (lang_any) |
| dead-code tool | vulture | knip | vulture |

> Un repo con **sia** `supabase/config.toml` **sia** file Python e JS/TS sarebbe classificato come ambiguo (stack ibrido); Trueline propone il pack più probabile e chiede conferma all'utente.

---

## Preflight specifico

- Lockfile presente (`requirements.txt`, `poetry.lock`, `Pipfile.lock`) — assente → osv-scanner non può girare, degradato e dichiarato.
- Directory migration Supabase presente (`supabase/migrations/`) — assente → rls_check non ha DDL da analizzare, finding = 0 (non significa RLS ok).
- Nessun DB live richiesto: `rls_check` è completamente statico.
- `vulture` richiede i sorgenti Python nel working tree; non richiede l'installazione delle dipendenze applicative.
- `supabase/config.toml` è il marker Supabase: la sua presenza è condizione necessaria per assegnare questo pack (invece di `postgres-py`).
