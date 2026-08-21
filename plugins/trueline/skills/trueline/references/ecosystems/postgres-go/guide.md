# ecosystems/postgres-go/guide.md — Trueline · ecosistema postgres-go (Go su Postgres)

> Pack di rilevamento Eco-F4 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **route-authz**
> (handler HTTP mutanti senza identity/role check), **non** RLS-al-DB.

---

## Profilo dell'ecosistema

- **Linguaggio**: Go — `net/http` standard library, Gorilla Mux, Chi, Gin, Echo.
- **Backend**: Postgres non-Supabase — connessione diretta via `database/sql` + driver `lib/pq` o `jackc/pgx`; query parametrizzate con `$1, $2, ...`.
- **Client tipici**: `db.Exec(...)`, `db.Query(...)`, `db.QueryRow(...)`, `pgx.Pool.Exec(...)`.
- **Schema dichiarato**: migration SQL gestite dall'app (non Supabase CLI). Nessun `supabase/config.toml`.
- **Dead-code**: `x/tools/deadcode` (dichiarato, non verificato nel tier detection).

---

## Oracle set — batteria detection (fase 1)

| Controllo chkp | Categoria finding | Oracolo | Wrapper | Note |
|---|---|---|---|---|
| 2 — sicurezza | `authz` (`authz-surface`) | Semgrep + ruleset route-authz del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Rileva handler HTTP mutanti (POST/PUT/DELETE/PATCH) senza identity/role check |
| 2 — sicurezza | `injection` | Semgrep + ruleset del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Concatenazione SQL senza parametro, `fmt.Sprintf` in query |
| 2 — sicurezza | `secret` | gitleaks — working tree | `scripts/oracles/run_gitleaks.mjs` | `--redact` obbligatorio; shared con gli altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | `scripts/oracles/run_osv.mjs` | Lockfile: `go.mod`, `go.sum` |
| 1 — dead-code | `dead-code` | `x/tools/deadcode` | (F5, non verificato qui) | Dichiara il tool; verifica demandata a F5/gate F6 |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza. Nessun finding nei finding di detection non equivale a "sicuro" (`L-COL-006`).

---

## authz-surface: route-authz (non RLS-al-DB)

In questo ecosistema **non esiste RLS a livello di database** (non è Supabase). L'isolamento per identità/tenant vive **nell'applicazione**: ogni handler HTTP che esegue una scrittura sul DB deve verificare l'identità del chiamante prima di agire.

### Pattern difettoso rilevato (SEED:GO-S3)

```go
// DIFETTO — handler HTTP mutante senza identity check (CWE-862, A01:2025)
func createBookingHandler(w http.ResponseWriter, r *http.Request) {
    // Scrittura sul DB senza alcun controllo di identità/ruolo
    db.Exec("INSERT INTO bookings (user_id, slot) VALUES ($1, $2)", 1, "2025-01-01")
    fmt.Fprintln(w, `{"ok": true}`)
}
```

### Pattern sicuro (contrasto — NON flaggato)

```go
// SICURO — verifica identità prima della scrittura
func createBookingSecureHandler(w http.ResponseWriter, r *http.Request) {
    token := r.Header.Get("Authorization")
    if token == "" {
        http.Error(w, "unauthorized", http.StatusUnauthorized)
        return
    }
    db.Exec("INSERT INTO bookings (user_id, slot) VALUES ($1, $2)", 1, "2025-01-01")
    fmt.Fprintln(w, `{"ok": true}`)
}
```

### Auth-check riconosciuti dal ruleset (esclusioni pattern-not-inside)

- `r.Header.Get("Authorization")`
- `r.Context().Value(...)` per user context middleware
- Middleware `requireAuth` / `AuthMiddleware` applicato alla rotta

---

## Sink DB rilevati dal ruleset route-authz

| Client | Pattern mutante rilevato |
|---|---|
| `database/sql` | `db.Exec("INSERT ...")`, `db.Exec("UPDATE ...")`, `db.Exec("DELETE ...")` senza auth check |
| `database/sql` | `db.ExecContext(ctx, "INSERT ...")`, `db.ExecContext(ctx, "UPDATE ...")`, `db.ExecContext(ctx, "DELETE ...")` senza auth check |
| `pgx` | `pool.Exec(ctx, "INSERT ...")`, `pool.Exec(ctx, "UPDATE ...")`, `pool.Exec(ctx, "DELETE ...")` senza auth check |

Handler GET e handler senza sink di scrittura: **nessun finding** (0 FP per design).

---

## SEED dependency-vuln

Il lock pin vulnerabile del pack è `github.com/dgrijalva/jwt-go@v3.2.0+incompatible`
(**CVE-2020-26160** / GHSA-w73w-5m7g-f7qc): il campo `aud` non viene validato,
consentendo bypass dei controlli di audience sui token JWT. osv-scanner emette il
finding su `go.mod`.

---

## Differenza rispetto a postgres-jsts

| Aspetto | postgres-jsts | postgres-go |
|---|---|---|
| Linguaggio | JS/TS (Node.js, Express) | Go (`net/http`, stdlib) |
| authz-surface | route-authz (semgrep TS) | route-authz (semgrep Go) |
| Detect marker | `package.json` | `go.mod` |
| Lockfile osv | `package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` | `go.mod` / `go.sum` |
| Dead-code tool | `knip` | `x/tools/deadcode` (dichiarato) |
| verified_set | `[secret, dead-code]` (SP-7) | `[]` (tier detection, F4) |

---

## Preflight specifico

- `go.mod` presente — assente → classify non combacia (lang_any mancante).
- Lockfile (`go.mod` / `go.sum`) — assente → osv-scanner non può girare, degradato e dichiarato.
- Semgrep disponibile (docker) — assente → authz/injection best-effort deferred a F5/gate F6.
- Nessun DB live richiesto (postgres-go non ha controlli RLS a runtime nel tier detection).
