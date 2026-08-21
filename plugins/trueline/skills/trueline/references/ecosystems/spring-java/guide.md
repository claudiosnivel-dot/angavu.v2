# ecosystems/spring-java/guide.md — Trueline · ecosistema spring-java (Java/Spring Boot)

> Pack di rilevamento F4 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **route-authz**
> (endpoint mutanti senza @PreAuthorize/@Secured), via semgrep (best-effort,
> assente nel sandbox → degrada onesto, mai falso-verde).

---

## Profilo dell'ecosistema

- **Linguaggio**: Java — Spring Boot, Spring MVC, Spring Security.
- **Backend**: applicazione Spring Boot con endpoint REST (@RestController,
  @RequestMapping, @PostMapping, @PutMapping, @DeleteMapping, @PatchMapping).
- **Build tool tipico**: Maven (pom.xml) o Gradle (build.gradle).
- **Marker di classificazione (detect.lang_any)**: `pom.xml`.
- **Schema dichiarato**: gestito dall'app (Liquibase / Flyway / DDL manuale);
  nessuna dipendenza da Supabase CLI.

---

## Oracle set — batteria detection (fase 1)

| Categoria | Oracolo | Wrapper | Note |
|---|---|---|---|
| `secret` | gitleaks — working tree | `scripts/oracles/run_gitleaks.mjs` | `--redact` obbligatorio; shared con supabase-jsts/postgres-jsts |
| `dependency-vuln` | osv-scanner su `pom.xml` | `scripts/oracles/run_osv.mjs` | Lockfile Maven; osv riconosce `pom.xml` come Maven |
| `authz` (`authz-surface`) | Semgrep + ruleset route-authz del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Best-effort (semgrep assente nel sandbox → degrada onesto) |
| `injection` | Semgrep + ruleset del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Best-effort |
| `dead-code` | PMD (dichiarato, non nel floor) | — | F5/F6 opzionale |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti,
non ne certifica l'assenza. Nessun finding nei finding di detection non equivale a
"sicuro" (`L-COL-006`).

**Gap dichiarato (L-COL-006):** authz/injection (semgrep) e dead-code (PMD) NON
esercitati nel sandbox (semgrep + PMD assenti) → best-effort/deferred al gate finale
F6 su macchina con semgrep. secret e dependency-vuln (gitleaks + osv) sono hard.

---

## authz-surface: route-authz (non RLS-al-DB)

In questo ecosistema **non esiste RLS a livello di database** nativo. L'isolamento
per identità/ruolo vive **nel controller applicativo**: ogni endpoint di tipo mutante
(@PostMapping, @PutMapping, @DeleteMapping, @PatchMapping) deve verificare l'identità
del chiamante tramite `@PreAuthorize` o `@Secured` prima di eseguire la scrittura.

### Pattern difettoso rilevato (SEED:SJ-S3)

```java
// DIFETTO — endpoint mutante senza @PreAuthorize (CWE-862, A01:2025)
@PostMapping("/bookings")
public ResponseEntity<?> createBooking(@RequestBody Map<String, Object> body) {
    // Nessun controllo di auth: chiunque può creare prenotazioni
    bookingService.save(body);
    return ResponseEntity.status(201).body(Map.of("ok", true));
}
```

### Pattern sicuro (contrasto — NON flaggato)

```java
// SICURO — endpoint protetto da @PreAuthorize (verifica identità PRIMA della scrittura)
@PostMapping("/bookings/secure")
@PreAuthorize("isAuthenticated()")
public ResponseEntity<?> createBookingSecure(
        @RequestBody Map<String, Object> body,
        Authentication auth) {
    bookingService.save(body, auth.getName());
    return ResponseEntity.status(201).body(Map.of("ok", true));
}
```

### Auth-check riconosciuti dal ruleset (exclusioni pattern-not)

- `@PreAuthorize("isAuthenticated()")` — richiede utente autenticato
- `@PreAuthorize("hasRole('ADMIN')")` / `@PreAuthorize("hasAuthority('...')")` — role check
- `@Secured("ROLE_USER")` / `@Secured({"ROLE_ADMIN", "ROLE_USER"})` — annotation legacy

---

## Sink DB / mutante rilevati dal ruleset route-authz

| Metodo HTTP | Annotation Spring MVC | Bersaglio semgrep |
|---|---|---|
| POST | `@PostMapping(...)` | sì |
| PUT | `@PutMapping(...)` | sì |
| DELETE | `@DeleteMapping(...)` | sì |
| PATCH | `@PatchMapping(...)` | sì |
| GET | `@GetMapping(...)` | **no** (lettura) |

---

## Preflight specifico

- `pom.xml` presente — assente → la classify non scatta (lang_any fallback).
- osv-scanner sul lockfile `pom.xml`: osv-scanner riconosce Maven da `pom.xml`.
- Nessun DB live richiesto (spring-java non ha controlli RLS a runtime in fase 1).
- semgrep (Docker): necessario per il criterio 2 authz del conformance gate; assente nel
  sandbox → degrada onesto (il gate riporta `semgrep NON disponibile`, non un falso verde).
