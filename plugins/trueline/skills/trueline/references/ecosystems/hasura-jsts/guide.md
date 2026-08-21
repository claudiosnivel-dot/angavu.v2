# ecosystems/hasura-jsts/guide.md — Trueline · ecosistema hasura-jsts (JS/TS su Hasura)

> Pack tier **verified** (eco-F3). Coverage dichiarata; verified_set=[secret, dead-code, authz].
> Authz-surface = **authz** (Hasura metadata YAML via `hasura_metadata_check` STATICO).

---

## Profilo dell'ecosistema

- **Linguaggio**: JavaScript / TypeScript — applicazioni che usano Hasura GraphQL Engine come API layer.
- **Backend**: Hasura — motore GraphQL auto-generato su PostgreSQL/MySQL/SQL Server/MongoDB; autorizzazione dichiarativa nel file di metadata.
- **Client tipici**: SDK Apollo Client, urql, graphql-request, fetch nativo verso `/v1/graphql`.
- **Schema dichiarato**: autorizzazione gestita tramite file di metadata YAML — `metadata/tables.yaml` o file per-tabella in `metadata/databases/<db>/tables/`. Ogni tabella dichiara `select_permissions`, `insert_permissions`, `update_permissions`, `delete_permissions` con ruolo e filtro di riga.
- **Detect signal forte**: `config.yaml` (configurazione principale Hasura) + `metadata/databases/databases.yaml` (file di database Hasura, distingue da generici YAML).
- **Test runner tipici**: vitest, jest, mocha.

---

## Oracle set — batteria verified (eco-F3)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| 2 — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` |
| 2 — sicurezza | `authz` (`authz-surface`) | `hasura_metadata_check` STATICO sui file YAML metadata | Analizza `metadata/**/*.yaml`; rileva `filter: {}` su ruolo pubblico |
| 2 — sicurezza | `injection` | semgrep JS/TS + ruleset del pack (`ruleset/`) | Bonus non-floor |
| — | `dead-code` | knip | Export/import non usati nel sorgente TS/JS |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Verified_set:** `secret`, `dead-code`, `authz` — il loop+fix-provider porta questi seed a `verified` (oracolo LEGATO riesieguito PULITO su copia isolata + invarianza characterization). `dependency-vuln` e `injection` restano **detection-only**, mai auto-promossi.

---

## authz-surface: Hasura Metadata YAML (non route-authz)

In questo ecosistema l'isolamento per identità/tenant è delegato alle **Hasura Permission Rules** — regole dichiarative nel file di metadata che Hasura valuta su ogni richiesta GraphQL. L'applicazione JS/TS NON implementa authz nel codice applicativo (nessun middleware Express, nessun check manuale `req.user.id`): il controllo è centralizzato nella metadata.

`hasura_metadata_check` è un oracolo **STATICO** (dep-free, parser YAML subset) che legge i file `metadata/**/*.yaml` e verifica:

- ogni tabella ha `select_permissions`, `insert_permissions`, `update_permissions`, `delete_permissions`;
- ogni permission ha `{ role, permission: { filter, columns } }`;
- **HASURA001_PUBLIC_PERMISSION** (HIGH, FLOOR, deterministico): `role` ∈ `{anonymous, public, *}` **E** `filter: {}` (mappa vuota = nessun predicato di riga = accesso pubblico su TUTTE le righe).

### Pattern SICURO riconosciuto (Hasura permission owner-scoped)

```yaml
# metadata/tables.yaml — permission owner-scoped
- table:
    name: posts
    schema: public
  select_permissions:
    - role: user
      permission:
        columns:
          - id
          - title
          - created_at
        filter:
          author_id:
            _eq: X-Hasura-User-Id   # SAFE: solo il proprietario vede le proprie righe
```

### Pattern DIFETTOSO rilevato

```yaml
# metadata/tables.yaml — DIFETTO: permission anonima senza filtro di riga
- table:
    name: posts
    schema: public
  select_permissions:
    - role: anonymous
      permission:
        columns:
          - id
          - title
        filter: {}   # DIFETTO: filter vuoto = chiunque vede TUTTE le righe
```

### Semantica del campo `filter`

| Valore | Semantica Hasura | Hasura001 |
|---|---|---|
| `filter: {}` (mappa vuota) | Nessun predicato di riga = accesso su TUTTE le righe | **FINDING** (se role pubblico) |
| `filter: { user_id: { _eq: X-Hasura-User-Id } }` | Solo le righe il cui `user_id` = l'utente JWT | nessun finding |
| `filter:` assente | Conservativo: non affermabile (potrebbe essere null) | nessun finding |

**Scoping onesto:** l'oracolo è STATICO — analizza il testo dei file YAML, non interroga il motore Hasura ne esegue richieste GraphQL. `authz-verified` = `hasura_metadata_check` riesieguito PULITO (la permission anonima rimossa o il filtro reso owner-scoped), NON invarianza runtime (il Hasura engine non è disponibile nella CI).

### Differenza rispetto a Firestore Security Rules

Firestore usa regole testuali (`.rules`) valutate dal backend Firebase. Hasura usa metadata YAML dichiarativa valutata dal motore GraphQL. Il concetto è analogo (solo l'utente X accede ai documenti di X), ma il meccanismo è diverso: `X-Hasura-User-Id` (session variable JWT) vs `request.auth.uid` (Firebase Auth).

---

## Ruoli Hasura rilevanti

- **`anonymous`**: richieste senza JWT; il ruolo di default per accesso pubblico.
- **`public`**: convenzione alternativa per accesso senza autenticazione.
- **`*`**: wildcard (tutti i ruoli incluso anonymous).
- **`user`**, **`admin`**, ecc.: ruoli autenticati — fuori dal floor deterministico (non pubblici).

Il floor HASURA001 si attiva SOLO per i ruoli pubblici (`anonymous`, `public`, `*`) con `filter: {}`. Un ruolo `user` con `filter: {}` NON è nel floor (potrebbe essere intenzionale per dati non sensibili): l'oracolo non segnala.

---

## injection e dead-code

- **injection** (semgrep, ruleset `ruleset/hasura-jsts-injection.yml`): bonus non-floor. Rileva pattern di injection JS/TS tipici del lato applicativo (GraphQL subscription injection, command injection in server-side functions).
- **dead-code** (knip): verified_set. Esporta mai referenziate nel progetto JS/TS.

---

## Differenza rispetto agli altri pack

| Aspetto | firebase-jsts | appwrite-jsts | pocketbase-jsts | hasura-jsts |
|---|---|---|---|---|
| Backend | Firebase (Firestore) | Appwrite | PocketBase | Hasura GraphQL |
| authz-surface | Firestore Security Rules (`.rules`) | `appwrite.json` (`$permissions`) | `pb_schema.json` (`listRule: ""`) | Metadata YAML (`filter: {}`) |
| Oracolo authz | `firestore_rules_check` | `appwrite_perms_check` | `pocketbase_rules_check` | `hasura_metadata_check` |
| Control ID floor | FIRESTORE001 | APPWRITE001 | POCKETBASE001 | **HASURA001** |
| match_path formato | `/databases/.../collection/{id}` | `collectionId#permission(any)` | `collection.listRule` | `table.select.anonymous` |
| Detect signal forte | `firebase.json` / `firestore.rules` | `appwrite.json` | `pb_schema.json` | `config.yaml` + `metadata/databases/databases.yaml` |
| Parser | Tokenizer `.rules` custom | JSON.parse | JSON.parse | YAML subset dep-free |

---

## Preflight specifico

- Lockfile presente (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) — assente → osv-scanner non può girare, degradato e dichiarato.
- Directory `metadata/` presente con almeno un file `*.yaml` — assente → `hasura_metadata_check` non trova file; finding = 0 (non significa authz ok, potrebbe significare metadata non ancora scritta).
- **Nessun DB live richiesto**: `hasura_metadata_check` è completamente statico — analizza i file YAML testuali, non interroga PostgreSQL ne il Hasura engine.
- **File non-metadata nella dir `.`**: il walker skippа `node_modules/`, `.git/` e i file JSON noti (package-lock.json, tsconfig.json, knip.json) per evitare parse_warnings inutili.
