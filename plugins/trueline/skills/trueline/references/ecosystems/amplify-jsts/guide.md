# Guida ecosistema amplify-jsts

## Identità

| Campo        | Valore                          |
|--------------|---------------------------------|
| `id`         | `amplify-jsts`                  |
| `version`    | `1.0.0`                         |
| `languages`  | `js`, `ts`                      |
| `backend`    | `amplify` (AWS AppSync / Amplify Gen1) |
| `floor`      | `secret`, `dependency-vuln`, `authz` |
| `verified_set` | `secret`, `dead-code`, `authz` |

## Rilevamento

Trueline attiva questo pack se il progetto contiene **almeno uno** tra:

- `schema.graphql` (file SDL AppSync)
- `amplify/` (directory Amplify CLI Gen1)

in combinazione con `package.json` (`lang_any`).

## Oracoli del floor

### secret — `gitleaks` (shared)

Scansione delle credenziali committate (working-tree + history). Rileva chiavi AWS,
token di servizio, private key PEM nel working tree e nei commit precedenti.

### dependency-vuln — `osv`

Scansione del lockfile (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) via
osv-scanner. Cerca advisory nella banca dati OSV (CVE, GHSA). Richiede
`lockfileVersion 3` per compatibilità con osv-scanner.

### authz — `appsync_auth_check` (authz-surface)

Oracolo dichiarativo **statico** che analizza i file `schema.graphql` raccogliendo
i tipi annotati con `@model`. Per ogni tipo, verifica la direttiva
`@auth(rules: [...])` cercando una rule `{ allow: public }`.

**Control ID:** `APPSYNC001_PUBLIC_AUTH`
**Severity:** HIGH (FLOOR, deterministico)
**CWE:** CWE-862 (Missing Authorization)
**OWASP:** A01:2025 (Broken Access Control)
**match_path:** `<TypeName>@auth`

L'oracolo emette un finding per ogni tipo `@model` con `allow: public` nella
definizione `@auth`. Scan path: `.` e `amplify/` (ricorsivo).

#### Scoping onesto (L-COL-006)

`authz-verified` = `appsync_auth_check` STATICO ri-eseguito pulito: lo schema
`schema.graphql` non contiene più `allow: public` dopo la remediation
(sostituito con `allow: owner`). NON invarianza d'isolamento a runtime —
l'istanza AppSync non è disponibile nel sandbox. Analogo dichiarativo della
prova statica Firestore (regole `if true` → owner-scoped).

### dead-code — `knip`

Rileva export non referenziati, file inutilizzati, entrypoint orfani.
Configurato via `knip.json` nella root del progetto.

### injection — `semgrep` (bonus, non-floor)

Bonus non-floor. Ruleset: `ruleset/amplify-jsts-injection.yml`.

## ⚠ Gen1 vs Gen2: NOTA IMPORTANTE

Il floor `authz` SDL `@auth` copre **solo Amplify Gen1**:

```graphql
# Gen1 — COPERTO dal floor
type Post @model @auth(rules: [{ allow: public }]) { ... }
```

La sintassi **Amplify Gen2** (`a.allow.publicApiKey()` in TypeScript) è una
API completamente diversa e **non è coperta dal floor** di questo pack:

```typescript
// Gen2 (TypeScript) — FUORI dal floor, detection-only via code-review/semgrep semantico
const schema = a.schema({
  Post: a.model({ ... }).authorization((allow) => [allow.publicApiKey()]),
});
```

Se il progetto usa Amplify Gen2, la copertura `authz` resta **detection-only**.
Dichiarare esplicitamente nel report di fase.

## Fixture di riferimento

`eval/ecosystems/amplify-jsts/reference-app/`

| File                | Seed    | Categoria        | Stato atteso     |
|---------------------|---------|------------------|------------------|
| `serviceAccount.json` | AM-S1 | secret           | verified         |
| `package-lock.json`   | AM-S2 | dependency-vuln  | detection-only   |
| `schema.graphql`      | AM-S3 | authz            | verified         |
| `src/dead.ts`         | AM-S4 | dead-code        | verified         |

## Fix della remediation (engine, non dati)

Il fix `fixAppsyncS3(dir, finding)` (nel provider deterministico EVAL-ONLY
`eval/harness/fix_provider.eval.mjs`, non spedito nel `.skill`) sostituisce
`allow: public` con `allow: owner` nella rule colpita del `schema.graphql`.
Signature: `fix-appsync-owner-scope:<TypeName>`.

*(Wiring engine: orchestratore SERIALE, BIT-invarianza — non parte di questi dati.)*

## Ledger

- L-COL-006: scoping onesto authz (prova statica, non runtime)
- L-COL-024: provisioning oracle = ENGINE integrator; inner .git = ORCHESTRATORE
- L-COL-029: oracoli nuovi (additivo)
- L-COL-030: verified set fase 2
