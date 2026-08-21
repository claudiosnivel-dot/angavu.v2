# ecosystems/pocketbase-jsts/guide.md — Trueline · ecosistema pocketbase-jsts (JS/TS su PocketBase)

> Pack di rilevamento eco-F2 — tier **verified** (verified_set: secret, dead-code, authz).
> Coverage dichiarata; authz-surface = **authz** (PocketBase collection rules via
> `pocketbase_rules_check` STATICO su `pb_schema.json`).

---

## Profilo dell'ecosistema

- **Linguaggio**: JavaScript / TypeScript — PocketBase JS SDK (`pocketbase`), backend Node.js.
- **Backend**: PocketBase — database open-source self-hosted con API REST autogenerata, autenticazione
  integrata e regole di accesso dichiarative per collection.
- **Client tipici**: `pocketbase` (SDK JS/TS), `pocketbase-js-sdk`, accesso diretto all'API REST PocketBase.
- **Schema dichiarato**: le regole di accesso sono definite in `pb_schema.json` — uno schema JSON
  esportato dalla dashboard PocketBase che contiene per ogni collection i campi
  `listRule`, `viewRule`, `createRule`, `updateRule`, `deleteRule`.
  Nessuna migration SQL. Segnale di rilevamento forte: presenza di `pb_schema.json`.
- **Test runner tipici**: vitest, jest, mocha.

---

## Oracle set — batteria (verified_set: secret, dead-code, authz)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| 2 — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` |
| 2 — sicurezza | `authz` (`authz-surface`) | `pocketbase_rules_check` STATICO su `pb_schema.json` | Rileva `listRule:""`, `viewRule:""` etc. vuote (accesso pubblico) |
| 2 — sicurezza | `injection` | semgrep JS/TS + ruleset del pack (`ruleset/`) | Command injection via `child_process`; non-floor |
| 3 — qualita' | `dead-code` | knip | Esportazioni non referenziate; verified |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Verified set:** `secret`, `dead-code`, `authz` — promozione via loop deterministico con
oracoli rieseguiti (L-COL-002). authz-verified = `pocketbase_rules_check` STATICO
ri-eseguito pulito (NON invarianza runtime: PocketBase non disponibile nel sandbox, L-COL-006).

---

## authz-surface: PocketBase Collection Rules (non route-authz)

In questo ecosistema l'isolamento per identita'/tenant e' delegato alle **Collection Rules** di
PocketBase — regole dichiarative valutate dal backend PocketBase prima di ogni operazione sulle
collection. L'applicazione JS/TS NON implementa authz nel codice applicativo: il controllo e'
centralizzato nel file `pb_schema.json`.

`pocketbase_rules_check` e' un oracolo **STATICO** che legge `pb_schema.json` (array di collection
o oggetto `{collections:[...]}`) e verifica i campi di regola per ogni collection.

### ⚠ Trappola critica: null vs stringa vuota

| Valore del rule field | Significato PocketBase | Verdetto oracolo |
|---|---|---|
| `""` (stringa vuota) | **PUBBLICO** — chiunque (anche non autenticato) | **POCKETBASE001_PUBLIC_RULE** (HIGH, FLOOR) |
| `null` | **LOCKED** — solo admin | **NESSUN finding** (SICURO) |
| `"@request.auth.id != \"\""` | **Autenticato** — solo utenti loggati | **NESSUN finding** (regola valida) |

**ATTENZIONE**: un oracolo che tratta `null` come "valore mancante -> pubblico" e' **sbagliato**.
`null` e' esplicitamente LOCKED/admin-only in PocketBase — il comportamento opposto di `""`.
Il test critico `viewRule:null -> 0 finding` e' OBBLIGATORIO.

### Pattern SICURO riconosciuto (PocketBase Collection Rules)

```json
{
  "name": "user_items",
  "listRule": "@request.auth.id != \"\"",
  "viewRule": "@request.auth.id != \"\"",
  "createRule": "@request.auth.id != \"\"",
  "updateRule": "@request.auth.id != \"\"",
  "deleteRule": "@request.auth.id != \"\""
}
```

### Pattern SICURO (LOCKED = null):

```json
{
  "name": "private_data",
  "listRule": null,
  "viewRule": null,
  "createRule": null,
  "updateRule": null,
  "deleteRule": null
}
```

Nessun finding: `null` = admin-only, accesso massimamente ristretto.

### Pattern DIFETTOSO rilevato (POCKETBASE001_PUBLIC_RULE):

```json
{
  "name": "posts",
  "listRule": "",
  "viewRule": ""
}
```

`""` (stringa vuota) su qualsiasi rule field = accesso pubblico incondizionato.
`pocketbase_rules_check` emette POCKETBASE001_PUBLIC_RULE per ogni rule field vuoto.

---

## Differenza rispetto agli altri pack

| Aspetto | firebase-jsts | firebase-py | pocketbase-jsts |
|---|---|---|---|
| Linguaggio | JS/TS | Python | JS/TS |
| Backend | Firebase (Firestore) | Firebase (Firestore) | PocketBase |
| authz-surface | Firestore Security Rules (`.rules`) | Firestore Security Rules (`.rules`) | PocketBase Collection Rules (`pb_schema.json`) |
| Authz rule "public" | `allow read: if true;` | `allow read: if true;` | `"listRule": ""` (stringa vuota) |
| Authz rule "locked" | nessun blocco match | nessun blocco match | `"listRule": null` |
| Oracolo authz | `firestore_rules_check` | `firestore_rules_check` | `pocketbase_rules_check` |
| Segnale detect forte | `firebase.json` / `firestore.rules` (files_any) | `firestore.rules` (files_any) | `pb_schema.json` (files_any) |
| dead-code tool | knip | vulture | knip |
| verified_set | `[secret, dead-code, authz]` | `[secret, dead-code, authz]` | `[secret, dead-code, authz]` |

---

## Preflight specifico

- Lockfile presente (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) — assente → osv-scanner non
  puo' girare, degradato e dichiarato.
- File `pb_schema.json` presente nella root del repo — assente → `pocketbase_rules_check` non ha
  schema da analizzare; finding = 0 (non significa authz ok).
- **Nessun DB live richiesto**: `pocketbase_rules_check` e' completamente statico — analizza il
  file JSON testuali, non interroga PocketBase.
- **Collisione zero**: il segnale `pb_schema.json` e' distinto da `firebase.json`/`firestore.rules`
  (firebase-jsts) e da `appwrite.json` (appwrite-jsts). Nessun overlap nei `files_any`.
