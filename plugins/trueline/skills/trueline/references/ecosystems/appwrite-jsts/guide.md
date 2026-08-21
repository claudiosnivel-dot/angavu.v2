# ecosystems/appwrite-jsts/guide.md — Trueline · ecosistema appwrite-jsts (JS/TS su Appwrite)

> Pack verified eco-F2 — tier **verified** (secret, dead-code, authz). Coverage dichiarata;
> authz-surface = **authz** (permessi di collection Appwrite via `appwrite_perms_check` STATICO
> sul file `appwrite.json`). Gemello strutturale di firebase-jsts.

---

## Profilo dell'ecosistema

- **Linguaggio**: JavaScript / TypeScript — Appwrite SDK server-side (`node-appwrite`), Appwrite client SDK.
- **Backend**: Appwrite — database con collection e permessi dichiarativi, autenticazione integrata, storage, funzioni serverless.
- **Client tipici**: `node-appwrite`, `appwrite`.
- **Schema dichiarato**: configurazione delle collection e dei permessi nel file `appwrite.json` (generato da `appwrite push collections`). Nessuna migration SQL. Ogni collection dichiara `$permissions[]` (array di stringhe come `read("any")`, `create("users")`) e `documentSecurity` (bool).
- **Test runner tipici**: vitest, jest, mocha.

---

## Oracle set — batteria verified (eco-F2)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| 2 — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` |
| 2 — sicurezza | `authz` (`authz-surface`) | `appwrite_perms_check` STATICO su `appwrite.json` | Rileva `read("any")` / `write("any")` / permission pubbliche su collection Appwrite |
| 2 — sicurezza | `injection` | semgrep JS/TS + ruleset del pack (`ruleset/`) | Command injection via `child_process` con concatenazione; `eval` di input utente |
| qualità | `dead-code` | knip | Unused exports / simboli non referenziati |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Verified set:** `secret`, `dead-code`, `authz` — il loop di remediation porta queste tre categorie a stato `verified` (oracolo rieseguito pulito, L-COL-006).

---

## authz-surface: Permessi di collection Appwrite (non route-authz)

In questo ecosistema l'isolamento per identità è delegato ai **permessi dichiarativi di collection** in `appwrite.json` — array di stringhe come `"read(\"any\")"`, `"create(\"users\")"` che Appwrite valuta lato server prima di permettere qualsiasi operazione sul database. L'applicazione JS/TS NON implementa authz nel codice applicativo: il controllo è centralizzato nella configurazione della collection.

`appwrite_perms_check` è un oracolo **STATICO** che legge `appwrite.json` e verifica:

- presenza di permission con scope `"any"` nell'array `$permissions[]` di una collection (qualsiasi scope mutante o di lettura su `"any"` = accesso pubblico incondizionato);
- la property `documentSecurity` (se `false`, le permission a livello di collection valgono anche per i documenti; se `true`, ogni documento può avere permission proprie che affinano l'accesso).

### Pattern SICURO riconosciuto (Appwrite permissions)

```json
{
  "$id": "private_data",
  "name": "Private Data",
  "documentSecurity": true,
  "$permissions": ["read(\"users\")", "create(\"users\")", "update(\"users\")", "delete(\"users\")"],
  "attributes": []
}
```

Il scope `"users"` limita l'accesso agli utenti autenticati. Con `documentSecurity: true`, ogni documento può avere permission proprie che restringono ulteriormente (es. solo il creatore).

### Pattern DIFETTOSO rilevato

```json
{
  "$id": "public_posts",
  "name": "Public Posts",
  "documentSecurity": false,
  "$permissions": ["read(\"any\")", "create(\"users\")"],
  "attributes": []
}
```

Il scope `"any"` in `read("any")` concede accesso in lettura a qualsiasi visitatore (anche non autenticato). `appwrite_perms_check` emette `APPWRITE001_PUBLIC_PERMISSION` con `match_path = public_posts#read("any")`.

### Differenza rispetto agli altri pack

Supabase/Postgres usano Row Level Security (RLS) dichiarata in DDL SQL. Firebase usa Firestore Security Rules (DSL proprietario). Appwrite usa permission dichiarate come array di stringhe JSON: sintassi diversa, stessa semantica di isolamento (solo l'utente X accede ai dati di X). Nessun SQL, nessuna migration, nessun `.rules` file: il controllo è nel file `appwrite.json`.

---

## injection e dead-code (extra non-floor / verified)

- **injection** (semgrep, ruleset `ruleset/appwrite-jsts-injection.yml`): rileva sink di command injection in Cloud Functions / funzioni serverless JS/TS — `child_process.exec(...)` / `execSync(...)` con input concatenato — e `eval(userInput)`. Categoria: `injection`; CWE-77/CWE-95; OWASP A05:2025. Non-floor, bonus.
- **dead-code** (knip): unused exports / simboli mai referenziati. Categoria `dead-code`; verificato nel verified_set. Il contrasto `usedHelper` (importato e chiamato da `src/index.ts`) NON deve essere segnalato da knip (precisione).

---

## Differenza rispetto agli altri pack

| Aspetto | firebase-jsts | appwrite-jsts |
|---|---|---|
| Backend | Firebase (Firestore) | Appwrite |
| authz-surface | Firestore Security Rules (`firestore_rules_check`, file `.rules`) | Permessi collection JSON (`appwrite_perms_check`, file `appwrite.json`) |
| Formato authz | DSL regole testuale | Array di stringhe JSON (`read("any")`, `create("users")`) |
| Segnale detect forte | `firebase.json` / `firestore.rules` | `appwrite.json` |
| dead-code tool | knip | knip |
| verified_set | `[secret, dead-code, authz]` | `[secret, dead-code, authz]` |

> Un repo con **sia** `appwrite.json` **sia** `package.json` è classificato come `appwrite-jsts` grazie al segnale forte `files_any`. I segnali `files_any` hanno priorità sul puro `lang_any`.

---

## Preflight specifico

- Lockfile presente (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) — assente → osv-scanner non può girare, degradato e dichiarato.
- File `appwrite.json` presente nella root del repo (o in sottodirectory scansionata) — assente → `appwrite_perms_check` non ha collezioni da analizzare; finding = 0 (non significa authz ok).
- **Nessun DB live richiesto**: `appwrite_perms_check` è completamente statico — analizza il file `appwrite.json` testuale, non interroga Appwrite.
- **Scoping onesto (L-COL-006)**: authz-verified = `appwrite_perms_check` STATICO ri-eseguito pulito (la permission `read("any")` è rimossa / sostituita con scope ristretto) — NON invarianza d'isolamento a runtime (l'istanza Appwrite non è disponibile nel sandbox Trueline). Analogo dichiarativo al transfer Firestore `if true` → owner-scoped.
