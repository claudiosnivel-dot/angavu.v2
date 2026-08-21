# ecosystems/dotnet-cs/guide.md — Trueline · ecosistema dotnet-cs (C# su ASP.NET)

> Pack di rilevamento eco-F4 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (`verified_set` vuoto). Authz-surface = **route-authz**
> (controller action mutanti senza `[Authorize]`), via semgrep best-effort.

---

## Profilo dell'ecosistema

- **Linguaggio**: C# — .NET 6/8, ASP.NET Core Web API.
- **Backend**: ASP.NET App — controller REST, minimal API, Razor Pages con endpoint mutanti.
- **Marker di rilevamento**: `global.json` (pin SDK .NET, presente nella maggior parte dei progetti .NET
  strutturati) e/o `app.csproj` (file progetto concreto). Il detect usa `lang_any` con match
  presence-only (nessun glob): la fixture contiene entrambi i file.
- **Schema dichiarato**: progetto ASP.NET Core standard, `packages.lock.json` abilitato via
  `RestorePackagesWithLockFile=true` nel `.csproj` (necessario per osv-scanner NuGet).
- **Lock file**: `packages.lock.json` (NuGet) — osv-scanner lo riconosce automaticamente come
  ecosistema NuGet e legge il campo `resolved` per ogni pacchetto.

---

## Oracle set — batteria detection (fase 1)

| Controllo chkp | Categoria finding | Oracolo | Wrapper | Note |
|---|---|---|---|---|
| 2 — sicurezza | `authz` (`authz-surface`) | Semgrep + ruleset route-authz del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Rileva action mutanti ([HttpPost/Put/Delete/Patch]) senza `[Authorize]` sul metodo o classe |
| 2 — sicurezza | `injection` | Semgrep + ruleset del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | SQL string-concat, interpolazione input in query |
| 2 — sicurezza | `secret` | gitleaks — working tree | `scripts/oracles/run_gitleaks.mjs` | `--redact` obbligatorio; shared con altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su `packages.lock.json` | `scripts/oracles/run_osv.mjs` | NuGet: osv-scanner rileva automaticamente il formato |
| 1 — dead-code | `dead-code` | Roslyn analyzer (F5 opz.) | — | Dichiarato, non verificato in fase 1 |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti, non ne
certifica l'assenza. Nessun finding nei finding di detection non equivale a "sicuro" (`L-COL-006`).

**Semgrep (authz/injection):** best-effort — semgrep assente nel sandbox degrada onesto (non è
un fallimento del pack; il gate dichiara il gap come `L-COL-006`).

---

## authz-surface: route-authz (controller ASP.NET)

In ASP.NET Core, l'isolamento per identità/ruolo vive **nell'applicazione**: ogni action method
di un controller che accetta scritture (POST, PUT, DELETE, PATCH) deve essere protetto da
`[Authorize]` o da un meccanismo equivalente (policy, middleware di auth).

### Pattern difettoso rilevato (SEED:CS-S3)

```csharp
// DIFETTO — action mutante senza [Authorize] (CWE-862, A01:2025)
[HttpPost]
public IActionResult Create([FromBody] ItemRequest req)
{
    // Nessun controllo di autorizzazione: chiunque può POST.
    return Ok(new { created = true });
}
```

### Pattern sicuro (contrasto — NON flaggato)

```csharp
// SICURO — stessa azione con [Authorize]
[Authorize]
[HttpPost("secure")]
public IActionResult CreateSecure([FromBody] ItemRequest req)
{
    return Ok(new { created = true });
}
```

### Auth-check riconosciuti dal ruleset (esclusioni `pattern-not`)

- Attributo `[Authorize]` sul metodo
- Attributo `[Authorize]` sulla classe controller

---

## Differenza rispetto ad altri pack

| Aspetto | dotnet-cs | postgres-jsts |
|---|---|---|
| Linguaggio | C# / ASP.NET Core | JavaScript / TypeScript (Node.js, Express) |
| authz-surface | `[Authorize]` su controller (semgrep, best-effort) | `req.user`/`verifyToken` in handler (semgrep) |
| floor | `secret`, `dependency-vuln`, `authz` | `secret`, `dependency-vuln`, `authz` |
| verified_set | `[]` (tier detection, fase 1) | `[]` (tier detection, fase 1) |
| Lock file | `packages.lock.json` (NuGet) | `package-lock.json` (npm) |
| Segnale detect | `global.json` + `app.csproj` (lang_any-only) | `package.json` (lang_any-only) |

---

## Preflight specifico

- `packages.lock.json` presente — richiede `RestorePackagesWithLockFile=true` nel `.csproj` e
  `dotnet restore` eseguito; assente → osv-scanner non può girare, degradato e dichiarato.
- `global.json` o `app.csproj` presenti per il classify (detect marker).
- Nessun DB live richiesto (dotnet-cs non ha controlli RLS a runtime).
- Semgrep (authz) richiede docker per il criterio 2 del gate; assente → il gate degrada
  dichiarato (L-COL-006), come postgres-jsts.
