# ecosystems/postgres-jsts/guide.md — Trueline · ecosistema postgres-jsts (JS/TS su Postgres non-Supabase)

> Pack di rilevamento SP-1 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **route-authz**
> (rotte mutanti senza identity/role check), **non** RLS-al-DB.

---

## Profilo dell'ecosistema

- **Linguaggio**: JavaScript / TypeScript — Node.js, Next.js API routes, Express.
- **Backend**: Postgres non-Supabase — connessione diretta via client `pg` (node-postgres), Prisma, Drizzle ORM; Next.js API routes (`pages/api/` o `app/` route handlers).
- **Client tipici**: `pg` (pool/client), `prisma/$MODEL.create|update|delete|upsert`, Drizzle `db.insert|update|delete`.
- **Schema dichiarato**: migration SQL gestite dall'app (non Supabase CLI). Nessun `supabase/config.toml`.
- **Test runner tipici**: vitest (prevalente), jest, `node:test`.

---

## Oracle set — batteria detection (fase 1)

| Controllo chkp | Categoria finding | Oracolo | Wrapper | Note |
|---|---|---|---|---|
| 2 — sicurezza | `authz` (`authz-surface`) | Semgrep + ruleset route-authz del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Rileva handler mutanti (POST/PUT/DELETE/PATCH) senza identity/role check |
| 2 — sicurezza | `injection` | Semgrep + ruleset del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | SQL string-concat, query non parametrizzata |
| 2 — sicurezza | `crypto` | Semgrep + ruleset del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Algoritmi deboli, chiavi hardcoded |
| 2 — sicurezza | `secret` | gitleaks — working tree | `scripts/oracles/run_gitleaks.mjs` | `--redact` obbligatorio; shared con supabase-jsts |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | `scripts/oracles/run_osv.mjs` | Lockfile: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` |
| 1 — dead-code | `dead-code` | knip | `scripts/oracles/run_deadcode.mjs` | Richiede `knip.json`; rimozioni mai automatiche (`L-COL-021`) |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza. Nessun finding nei finding di detection non equivale a "sicuro" (`L-COL-006`).

---

## authz-surface: route-authz (non RLS-al-DB)

In questo ecosistema **non esiste RLS a livello di database** (non è Supabase). L'isolamento per identità/tenant vive **nell'applicazione**: ogni handler di rotta che esegue una scrittura sul DB deve verificare l'identità del chiamante prima di agire.

### Pattern difettoso rilevato (SEED:PG-S3)

```ts
// DIFETTO — handler mutante senza identity check (CWE-862, A01:2025)
router.post('/bookings', async (req, res) => {
  await pool.query('INSERT INTO bookings ...'); // scrittura senza auth
  res.json({ ok: true });
});
```

### Pattern sicuro (contrasto — NON flaggato)

```ts
// SICURO — verifica identità prima della scrittura
router.post('/bookings', async (req, res) => {
  if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
  await pool.query('INSERT INTO bookings ...'); // scrittura dopo auth check
  res.json({ ok: true });
});
```

### Auth-check riconosciuti dal ruleset (esclusioni pattern-not-inside)

- `req.user` / `req.session?.userId`
- `getServerSession(...)` (NextAuth / Auth.js)
- Middleware `requireAuth` / `ensureAuth` applicato alla rotta
- `verifyToken(...)` / `verifyJwt(...)`

---

## Sink DB rilevati dal ruleset route-authz

| Client | Pattern mutante rilevato |
|---|---|
| `pg` (node-postgres) | `pool.query('INSERT …')`, `pool.query('UPDATE …')`, `pool.query('DELETE …')`, `client.query(...)` con SQL mutante |
| Prisma | `prisma.$MODEL.create(...)`, `prisma.$MODEL.update(...)`, `prisma.$MODEL.delete(...)`, `prisma.$MODEL.upsert(...)` |
| Drizzle | `db.insert(...)`, `db.update(...)`, `db.delete(...)` |

Rotte `GET` e handler senza sink di scrittura: **nessun finding** (0 FP per design).

---

## Differenza rispetto a supabase-jsts

| Aspetto | supabase-jsts | postgres-jsts |
|---|---|---|
| authz-surface | RLS-al-DB (`rls_check`) | route-authz applicativo (semgrep `ruleset/`) |
| floor | `secret`, `dependency-vuln`, `rls` | `secret`, `dependency-vuln`, `authz` |
| verified_set | `[secret, rls, dead-code]` | `[]` (tier detection, fase 1) |
| Segnale detect forte | `supabase/config.toml` (files_any) | solo `package.json` (lang_any) |
| Precedenza classify | prioritario (segnale forte) | fallback (lang-only, dopo files_any) |

> Un repo con **sia** `supabase/config.toml` **sia** `package.json` viene classificato
> come `supabase-jsts` (precedenza file-signal-forte — `classify()` in `resolve.mjs`).

---

## Preflight specifico

- `knip.json` presente o proponibile — assente → la skill propone config default per JS/TS.
- Lockfile presente (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) — assente → osv-scanner non può girare, degradato e dichiarato.
- Nessun DB live richiesto (postgres-jsts non ha controlli RLS a runtime).
