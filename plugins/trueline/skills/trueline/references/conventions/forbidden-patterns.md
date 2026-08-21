# Forbidden Patterns — Trueline conventions reference

**Modulo sorgente:** `07-CONVENTIONS-THREATMODEL` §4  
**Caricamento:** per modalità attiva (`02` §6) — pieno in BUILD e REMEDIATE.  
**Scopo:** spec del ruleset Semgrep curato (`references/oracles/semgrep-ai-ruleset/`). Ogni voce definisce l'anti-pattern vietato, la controparte sicura (bersaglio della fix), la mappatura OWASP 2025 / CWE e la severità (scala `04` §4). Tutto JS/TS + Supabase.

---

## Confine

I pattern vietati sono il **sottoinsieme staticamente rilevabile**. Ciò che richiede ragionamento (es. "questo endpoint *dovrebbe* essere admin-only?") non è una regola Semgrep: emerge dall'enumerazione del threat model (`threat-model.md`) e diventa una `security_notes` (`11`) o un finding detection-only, non un verde automatico.

Le regole YAML vere vivono in `references/oracles/semgrep-ai-ruleset/`. Questa specifica ne fissa il contenuto; le implementazioni YAML si scrivono all'implementazione del modulo M4.

---

## §4.1 Segreti inline / chiavi hardcoded — `category: secret`

Rete ridondante a gitleaks (dedup per fingerprint + categoria, `03` §6); la regola Semgrep cattura il *pattern d'uso*, non solo l'entropia.

**Sketch di struttura regola (riferimento):**

```yaml
# references/oracles/semgrep-ai-ruleset/secrets/service-role-clientside.yml
rules:
  - id: col-secret-service-role-clientside
    languages: [typescript, javascript]
    severity: ERROR                      # -> CRITICAL (04 §4)
    metadata: { category: secret, owasp: "A07:2025", cwe: "CWE-798" }
    message: >
      service_role key usata fuori da contesto server-side: bypassa RLS,
      espone l'intero DB. Usare la anon key lato client; service_role solo
      server-side con authz applicativa esplicita.
    patterns:
      - pattern-either:
          - pattern: createClient(..., process.env.SUPABASE_SERVICE_ROLE_KEY, ...)
          - pattern: createClient(..., "$SERVICE_ROLE_LITERAL", ...)
      # ...vincoli di contesto client-side nella regola reale
```

**Catalogo:**

| Vietato | Sicuro (bersaglio della fix) | OWASP 2025 / CWE | Severità |
|---|---|---|---|
| Chiave / segreto come **string literal** assegnato a `key` / `secret` / `token` / `password` / connection string | Da `process.env` / `Deno.env.get`; mai committato | A07:2025 / **CWE-798** | HIGH / CRITICAL |
| **service_role key** hardcoded o usata lato client | anon key lato client; service_role **solo** server-side | A07:2025 · A01:2025 / **CWE-798** | **CRITICAL** |
| Private key / PEM inline | secret store / env; rotazione | A04:2025 / CWE-321 | CRITICAL |

---

## §4.2 Injection — `category: injection`

| Vietato | Sicuro (bersaglio della fix) | OWASP 2025 / CWE | Severità |
|---|---|---|---|
| SQL per **concatenazione** / template con input non sanificato — es. `` pg.query(`SELECT … ${x}`) `` | Query **parametrizzate** (`$1`), tagged template con binding; mai interpolare input nell'SQL | A05:2025 / **CWE-89** | HIGH |
| `` child_process.exec(`… ${x}`) `` / invocazione shell con input controllato dall'utente | `execFile` con **array di argomenti**, flag `shell: false`; no interpolazione di stringhe nella shell | A05:2025 / **CWE-78** | HIGH |
| **PostgREST filter injection**: input interpolato in `.or("…")` / `.filter("…")` di supabase-js | `.eq()` / `.in()` tipati con valori **validati**; mai interpolare input utente in `.or()` | A05:2025 / **CWE-89** | HIGH |

---

## §4.3 Authz mancante su route mutanti — `category: authz`

Sottigliezza Supabase: **RLS è ottima difesa, ma la service_role la bypassa** — un handler con service_role deve fare authz propria.

| Vietato | Sicuro (bersaglio della fix) | OWASP 2025 / CWE | Severità |
|---|---|---|---|
| Handler che **scrive** (INSERT / UPDATE / DELETE o mutation) **senza** check identità / ruolo | Verifica `auth.getUser()` / JWT prima della mutation; derivazione esplicita dell'identità | A01:2025 / **CWE-862** | HIGH |
| Mutation con **client service_role** senza authz applicativa | Client user-scoped (RLS attiva) oppure authz esplicita derivata dal JWT | A01:2025 / **CWE-285** | HIGH |
| Edge Function che muta senza validare il JWT del chiamante | Valida il token, deriva l'identità, poi muta; no mutazione anonima | A01:2025 / CWE-306 | HIGH |

---

## §4.4 Crypto debole / confronti non timing-safe — `category: crypto`

| Vietato | Sicuro (bersaglio della fix) | OWASP 2025 / CWE | Severità |
|---|---|---|---|
| `Math.random()` per generare token / segreti / nonce | `crypto.randomUUID()` / `getRandomValues` / `randomBytes` | A04:2025 / **CWE-338** | HIGH |
| MD5 / SHA-1 per hashing di password | `bcrypt` / `scrypt` / `argon2` | A04:2025 / **CWE-327** | HIGH |
| `==` / `===` su segreti / HMAC / token (vulnerabile a timing attack) | `crypto.timingSafeEqual` | A04:2025 / **CWE-208** | MEDIUM |

---

## §4.5 Sink pericolosi — `category: injection` / `config` · `misc`

| Vietato | Sicuro (bersaglio della fix) | OWASP 2025 / CWE | Severità |
|---|---|---|---|
| `eval` / `new Function(stringa)` / `setTimeout("stringa")` | Nessuna esecuzione di stringhe; logica esplicita nelle chiamate dirette | A05:2025 / **CWE-95** | HIGH |
| Deserializzazione non sicura di input (es. `JSON.parse` su payload non fidato senza schema) | Parser sicuri, schema validato (zod / ajv) prima di consumare il payload | A08:2025 / CWE-502 | HIGH |
| `fetch(userUrl)` non validato — **SSRF**: l'URL è controllato dall'input dell'utente | Allowlist di host / schemi; no redirect ciechi; A01:2025 (SSRF assorbita) | **A01:2025** / **CWE-918** | HIGH |
| Path da input non sanificato usato per accesso a file / storage | Normalizza con `path.resolve` + confina a base dir; rifiuta `..` | A01:2025 / **CWE-22** | HIGH |
| Merge / assign di oggetti da input senza protezione (prototype pollution) — es. `Object.assign(target, userInput)` | `Object.create(null)` per oggetti-mappa; guardie esplicite su `__proto__` / `constructor` | A05:2025 / CWE-1321 | MEDIUM |

---

## Mappatura severità Semgrep → finding model

| Semgrep `severity` | `severity` finding (`04` §4) |
|---|---|
| `ERROR` | `HIGH` (o `CRITICAL` per i segreti, per policy) |
| `WARNING` | `MEDIUM` |
| `INFO` | `LOW` |
