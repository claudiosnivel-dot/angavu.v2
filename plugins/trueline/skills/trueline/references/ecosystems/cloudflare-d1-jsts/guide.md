# ecosystems/cloudflare-d1-jsts/guide.md — Trueline · ecosistema cloudflare-d1-jsts (JS/TS su Cloudflare Workers + D1)

> Pack di rilevamento tier **detection** (eco-F6). Coverage dichiarata;
> verified_set vuoto (fase 1). Authz-surface = **route-authz**
> (Workers fetch handler che chiama `env.DB.prepare(SQL)` senza auth-guard).

---

## Profilo dell'ecosistema

- **Linguaggio**: JavaScript / TypeScript — Cloudflare Workers runtime (V8 isolates).
- **Backend**: cloudflare-d1 — SQLite-compatible edge database di Cloudflare, accessibile via `env.DB` nel Workers context.
- **Client DB tipico**: `env.DB.prepare(sql).bind(...).run()` / `.all()` / `.first()`.
- **Framework authz tipici**: controllo manuale `request.headers.get('Authorization')`, middleware custom, Cloudflare Access.
- **Gestione dipendenze**: npm (`package.json` + `package-lock.json`).
- **Segnale di classificazione**: presenza di `wrangler.toml` nella directory del progetto (`detect.files_any`), con `package.json` come segnale-lingua (`detect.lang_any`). **Nessuna Fase 0 richiesta**: `wrangler.toml` e' un marker di file reale che distingue i progetti D1 senza bisogno di content-detection sulle dipendenze.

---

## Oracle set — batteria detection (eco-F6)

| Controllo chkp | Categoria finding | Oracolo | Wrapper | Note |
|---|---|---|---|---|
| 2 — sicurezza | `authz` (`authz-surface`) | Semgrep + ruleset route-authz del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Rileva `env.DB.prepare(SQL + var)` senza auth-guard |
| 2 — sicurezza | `injection` | Semgrep + ruleset del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | SQL concatenazione da input utente |
| 2 — sicurezza | `secret` | gitleaks — working tree | `scripts/oracles/run_gitleaks.mjs` | `--redact` obbligatorio; shared con gli altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | `scripts/oracles/run_osv.mjs` | Lockfile: `package-lock.json` |
| 1 — dead-code | `dead-code` | knip | `scripts/oracles/run_deadcode.mjs` | non-floor (eco-F6 detection) |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack e' in tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza. Nessun finding nei finding di detection non equivale a "sicuro" (`L-COL-006`). authz/injection via semgrep = **best-effort** (semgrep assente nel sandbox -> degrada onesto; mai falso verde).

---

## authz-surface: route-authz (env.DB.prepare senza auth-guard)

In Cloudflare Workers, il database D1 e' accessibile tramite il binding `env.DB` (o il nome binding dichiarato in `wrangler.toml`). Quando un fetch handler chiama `env.DB.prepare(...)` con SQL costruito per **concatenazione** da input non validato, senza verificare prima l'identita del richiedente, qualsiasi client raggiunge l'endpoint puo' accedere o modificare i dati (CWE-862, Broken Access Control).

### Pattern difettoso rilevato (SEED:D1-S3)

```js
// src/index.js — DIFETTO
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const userId = url.searchParams.get("user_id");
    // VULNERABILE: SQL concatenato + nessun auth-guard (CWE-862)
    const stmt = env.DB.prepare("SELECT * FROM notes WHERE user_id = " + userId);
    const result = await stmt.all();
    return Response.json(result.results);
  }
};
```

### Pattern sicuro (contrasto — NON flaggato)

```js
// src/guarded.js — SICURO
export function guardedHandler(request, env) {
  // AUTH GUARD: verifica Authorization prima di qualsiasi accesso DB
  const auth = request.headers.get("Authorization");
  if (!auth || !auth.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }
  const url = new URL(request.url);
  const userId = url.searchParams.get("user_id");
  // Query parametrizzata: nessuna concatenazione SQL
  const stmt = env.DB.prepare("SELECT * FROM notes WHERE user_id = ?");
  return stmt.bind(userId).all();
}
```

### Perche' il contrasto NON viene flaggato

La regola semgrep `d1-authz-unguarded-prepare-sql-concat` usa il pattern `$ENV.DB.prepare($A + $B)`. Il contrasto usa `env.DB.prepare("... ?")` con un singolo argomento stringa letterale (nessun operatore `+`) → 0 FP.

---

## Sink D1 e pattern route-authz rilevati

| Tipo | Pattern difettoso rilevato |
|---|---|
| D1 — fetch Worker | `env.DB.prepare("SQL" + userInput)` senza auth-guard |
| D1 — query concatenata | `env.DB.prepare(var + "SQL")` o qualsiasi forma `$A + $B` |

Query con `?` placeholder (`env.DB.prepare("... WHERE id = ?").bind(userId)`) e Workers con auth-guard esplicito: **nessun finding** (0 FP per design).

---

## Dipendenze vulnerabili — lockfile

Il lockfile `package-lock.json` (lockfileVersion 3) e' il riferimento primario per osv-scanner. Il pin vulnerabile del SEED (D1-S2) e' `lodash@4.17.20`, una versione nota con advisory nel database OSV (GHSA-35jh-r3h4-6jhm / CVE-2021-23337, Command Injection via template, CVSS 7.2).

---

## Segreti — gitleaks (language-agnostic)

gitleaks rileva segreti hardcoded in qualsiasi file sorgente JS/TS (`.js`, `.ts`), TOML, `.env`, ecc. Il SEED D1-S1 usa una chiave in stile Stripe (`sk_live_...`) hardcodata in `src/config.js`. Il contrasto pulito legge le credenziali da `env.STRIPE_SECRET_KEY` (binding Cloudflare Workers) senza mai committare il valore.

---

## Preflight specifico

- `wrangler.toml` presente (marker detection) — assente → classify non riconosce il pack.
- `package-lock.json` presente — assente → osv-scanner non puo' girare, degradato e dichiarato.
- Semgrep disponibile (docker) — assente → authz/injection degradano onesto (best-effort, L-COL-006).
- knip disponibile (node_modules) — assente → dead-code degradato dichiarato (non-floor, eco-F6).
- Nessun DB live richiesto (cloudflare-d1-jsts non ha controlli RLS a runtime).

---

## Differenza rispetto a postgres-jsts e firebase-jsts

| Aspetto | postgres-jsts | firebase-jsts | cloudflare-d1-jsts |
|---|---|---|---|
| Linguaggio | JavaScript / TypeScript | JavaScript / TypeScript | JavaScript / TypeScript |
| Segnale classify | `package.json` (lang_any only) | `firebase.json`/`firestore.rules` + `package.json` | `wrangler.toml` (files_any) + `package.json` (lang_any) |
| authz-surface | route-authz (Express/Next) | Firestore Security Rules | route-authz (Workers D1: env.DB.prepare) |
| authz oracolo | semgrep (ruleset) | firestore_rules_check (statico) | semgrep (ruleset) |
| dead-code | knip | knip | knip |
| lockfile | package-lock.json / yarn.lock / pnpm-lock.yaml | package-lock.json | package-lock.json |
| verified_set | `['secret', 'dead-code']` | `['secret', 'dead-code', 'authz']` | `[]` (eco-F6 = detection) |
