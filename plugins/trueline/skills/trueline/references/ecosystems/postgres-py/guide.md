# ecosystems/postgres-py/guide.md — Trueline · ecosistema postgres-py (Python su Postgres non-Supabase)

> Pack di rilevamento SP-2 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **rls**
> (RLS-al-DB via `rls_check` STATICO sulla DDL).

---

## Profilo dell'ecosistema

- **Linguaggio**: Python — FastAPI, Flask, Django (e framework minimali tipo Starlette/aiohttp).
- **Backend**: Postgres non-Supabase — connessione diretta via `psycopg` / `psycopg2`, SQLAlchemy Core o ORM, asyncpg; migrazioni gestite con Alembic o script SQL propri.
- **Client tipici**: `psycopg2.connect(...)`, `AsyncSession` / `Session` di SQLAlchemy, `asyncpg.connect(...)`, modelli Django con `DATABASES["default"]["ENGINE"] = "django.db.backends.postgresql"`.
- **Schema dichiarato**: migration SQL gestite dall'app (non Supabase CLI). Nessun `supabase/config.toml`. Directory tipiche: `migrations/`, `db/migrations/`, `alembic/versions/`.
- **Test runner tipici**: pytest (prevalente), unittest.

---

## Oracle set — batteria detection (fase 1)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| 2 — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack Postgres |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `requirements.txt`, `poetry.lock`, `Pipfile.lock` |
| 2 — sicurezza | `rls` (`authz-surface`) | `rls_check` STATICO sulla DDL | Riconosce `current_setting(...)` per Postgres NON-Supabase (vedi sotto) |
| 2 — sicurezza | `injection` | semgrep Python + ruleset del pack (`ruleset/`) | SQL string-concat, f-string in query, `.format(...)` non parametrizzato |
| 1 — dead-code | `dead-code` | vulture | Rileva funzioni/classi Python non raggiungibili; rimozioni mai automatiche (L-COL-021) |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `rls`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza. Nessun finding di detection non equivale a "sicuro" (L-COL-006).

---

## authz-surface: RLS-al-DB via rls_check (non route-authz)

In questo ecosistema l'isolamento per identità/tenant è delegato al **database** tramite Row Level Security (RLS) di Postgres. L'applicazione Python deve impostare il contesto di sessione (es. `current_setting`) prima di ogni operazione, e le policy RLS sul DB garantiscono che ogni query legga o scriva solo le righe autorizzate.

`rls_check` è un oracolo **STATICO** che legge i file SQL delle migration e verifica:

- presenza di `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` sulle tabelle sensibili;
- presenza di almeno una policy `CREATE POLICY ... USING (...)` per tabella protetta;
- uso di `current_setting('app.current_user_id', true)` o pattern equivalenti (Postgres non-Supabase) come valore di contesto nelle policy.

### Pattern DDL sicuro riconosciuto (Postgres non-Supabase)

```sql
-- Abilita RLS sulla tabella
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

-- Policy che usa current_setting per isolamento per utente
CREATE POLICY tenant_isolation ON bookings
  USING (user_id = current_setting('app.current_user_id', true)::uuid);
```

### Pattern difettoso rilevato

```sql
-- DIFETTO — RLS non abilitato o policy assente: tutti gli utenti leggono tutti i record
-- (nessun ALTER TABLE ... ENABLE ROW LEVEL SECURITY o nessuna CREATE POLICY)
```

### Differenza rispetto a Supabase

Supabase usa `auth.uid()` come funzione built-in per leggere l'identità dal JWT. In Postgres non-Supabase quella funzione non esiste: il contesto si passa via `SET LOCAL app.current_user_id = '...'` + `current_setting(...)`. `rls_check` riconosce entrambi i pattern; per questo pack è configurato con `"kind": "postgres-rls"` (non `"supabase-rls"`).

---

## injection e dead-code (extra non-floor)

- **injection** (semgrep, ruleset non ancora finalizzato — arriva in T2.2): rileva query Python costruite con concatenazione di stringhe (`"SELECT ... " + user_input`, f-string non parametrizzate, `.format(...)` su SQL). Non genera finding sulle query con parametri `%s` / `:param` / `?`.
- **dead-code** (vulture): analisi statica AST. Rimuovere codice morto non è mai automatico (L-COL-021); vulture produce candidati che l'utente revisiona.

---

## Differenza rispetto agli altri pack Postgres

| Aspetto | supabase-jsts | postgres-jsts | postgres-py |
|---|---|---|---|
| Linguaggio | JS/TS | JS/TS | Python |
| authz-surface | RLS-al-DB (`rls_check`, `auth.uid()`) | route-authz applicativo (semgrep) | RLS-al-DB (`rls_check`, `current_setting(...)`) |
| floor | `secret`, `dependency-vuln`, `rls` | `secret`, `dependency-vuln`, `authz` | `secret`, `dependency-vuln`, `rls` |
| verified_set | `[secret, rls, dead-code]` | `[]` (tier detection, fase 1) | `[]` (tier detection, fase 1) |
| Segnale detect forte | `supabase/config.toml` (files_any) | solo `package.json` (lang_any) | `pyproject.toml` / `requirements.txt` (lang_any) |
| dead-code tool | knip | knip | vulture |

> Un repo con **sia** `pyproject.toml` **sia** `supabase/config.toml` non esisterebbe in pratica (stack ibrido); se capitasse, `supabase-jsts` vincerebbe per segnale forte (files_any con dir-marker `supabase/`). Un repo Python puro senza `supabase/` viene classificato come `postgres-py`.

---

## Preflight specifico

- Lockfile presente (`requirements.txt`, `poetry.lock`, `Pipfile.lock`) — assente → osv-scanner non può girare, degradato e dichiarato.
- Directory migration SQL presente (`migrations/`, `db/migrations/`) — assente → rls_check non ha DDL da analizzare, finding = 0 (non significa RLS ok).
- Nessun DB live richiesto: `rls_check` è completamente statico.
- `vulture` richiede i sorgenti Python nel working tree; non richiede l'installazione delle dipendenze applicative.
