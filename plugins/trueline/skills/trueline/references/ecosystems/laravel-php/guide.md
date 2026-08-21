# ecosystems/laravel-php/guide.md — Trueline · ecosistema laravel-php (PHP su Laravel)

> Pack di rilevamento — tier **detection** (eco-F4). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **route-authz**
> (rotte mutanti senza verifica di autenticazione/autorizzazione), tramite
> semgrep best-effort (semgrep assente nel sandbox → degrada onesto, MAI
> falso-verde; L-COL-006).

---

## Profilo dell'ecosistema

- **Linguaggio**: PHP — framework Laravel (8.x, 9.x, 10.x, 11.x).
- **Backend**: `laravel-app` — routing via `routes/api.php` e `routes/web.php`,
  ORM Eloquent, query builder `DB::table(...)`, middleware di autenticazione
  Laravel Sanctum / Passport / Gate.
- **Marker di classificazione**: `composer.json` (detect.lang_any). Passata 2
  (fallback lang_any-only): il segnale è la presenza di `composer.json` nella
  radice del progetto. Un repo con un segnale forte (es. `firebase.json`,
  `supabase/config.toml`) viene classificato dal pack corrispondente e non da
  questo fallback.
- **Lockfile dipendenze**: `composer.lock` — analizzato da osv-scanner per le
  vulnerabilità di supply chain.

---

## Oracle set — batteria detection (eco-F4)

| Controllo | Categoria | Oracolo | Note |
|---|---|---|---|
| sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared language-agnostic |
| sicurezza | `dependency-vuln` | osv-scanner su `composer.lock` | Lockfile Packagist/Composer |
| sicurezza | `authz` (`authz-surface`) | Semgrep + `ruleset/` | Route mutante senza auth check; best-effort |
| sicurezza | `injection` | Semgrep + `ruleset/` | SQL injection, query non parametrizzata; best-effort |
| igiene | `dead-code` | Psalm | Dichiarato; non-floor; F5 opzionale |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza
di difetti, non ne certifica l'assenza. Nessun finding non equivale a "sicuro"
(`L-COL-006`).

---

## authz-surface: route-authz (best-effort semgrep PHP)

In Laravel, l'autenticazione si applica tramite:
1. **Middleware di rotta**: `->middleware('auth:sanctum')` sulla definizione della
   rotta, oppure gruppo `Route::middleware('auth')->group(...)`.
2. **Guard inline**: `if (!auth()->check()) { return response()->json([...], 401); }`
   nel body del controller o della closure.
3. **Policy / Gate**: `$this->authorize(...)` nei controller Resource.

### Pattern difettoso rilevato (SEED:LP-S3)

```php
// DIFETTO — rotta mutante senza verifica di autenticazione (CWE-862, A01:2025)
Route::post('/api/bookings', function (Request $request) {
    // Nessun controllo di auth: chiunque può scrivere.
    DB::table('bookings')->insert([
        'tenant_id'     => $request->tenant_id,
        'customer_name' => $request->customer_name,
        'slot'          => $request->slot,
    ]);
    return response()->json(['ok' => true], 201);
});
```

### Pattern sicuro (contrasto — NON flaggato)

```php
// SICURO — verifica auth prima della scrittura
Route::post('/api/bookings/secure', function (Request $request) {
    if (!auth()->check()) {
        return response()->json(['error' => 'Unauthenticated'], 401);
    }
    DB::table('bookings')->insert([
        'tenant_id'     => auth()->id(),
        'customer_name' => $request->customer_name,
        'slot'          => $request->slot,
    ]);
    return response()->json(['ok' => true], 201);
});
```

### Auth-check riconosciuti dal ruleset (esclusioni `pattern-not-inside`)

- `auth()->check()` — guard inline
- `auth()->user()` — guard inline alternativo
- `$request->user()` — helper Laravel
- `Auth::check()` — facade statica

---

## Sink DB rilevati dal ruleset route-authz

| Client | Pattern mutante rilevato |
|---|---|
| Query Builder | `DB::table(...)->insert(...)`, `DB::table(...)->update(...)`, `DB::table(...)->delete(...)` |
| Eloquent ORM | `Model::create(...)`, `$model->save()`, `$model->update(...)`, `$model->delete()` |

Rotte `GET` e closure senza sink di scrittura: **nessun finding** (0 FP per design).

---

## Dependency-vuln (osv-scanner su composer.lock)

osv-scanner analizza il `composer.lock` nella root del progetto. Il lockfile
Packagist/Composer viene riconosciuto automaticamente per nome (`composer.lock`).

**SEED:LP-S2**: `guzzlehttp/guzzle@7.3.0` — package reale con advisory OSV
(GHSA-f3f7-f54j-rpm6: failure to strip Cookie header on host change / HTTP
downgrade). Verificato con `osv-scanner scan --lockfile composer.lock`.

Ancora del registry: `symbol = "guzzlehttp/guzzle@7.3.0"` (formato
`<name>@<version>` come emesso da normalize.mjs per la categoria dependency-vuln).

---

## Secret (gitleaks, language-agnostic)

**SEED:LP-S1**: chiave Stripe-like `sk_live_...` hardcoded in `config/services.php`.
gitleaks la rileva con la regola `stripe-access-token`.

Il contrasto nella stessa sezione usa `env('STRIPE_SECRET')` e NON deve produrre
finding (precisione: nessun falso positivo per le letture da variabile d'ambiente).

---

## Preflight specifico

- `composer.lock` presente — assente → osv-scanner non può girare, degradato e dichiarato.
- Semgrep disponibile via docker — assente → authz/injection degradati onesti (best-effort).
- Psalm non richiesto per il floor (dead-code non è nel floor): F5 opzionale.
- Nessun DB live richiesto (laravel-php non ha controlli RLS a runtime in questo tier).
