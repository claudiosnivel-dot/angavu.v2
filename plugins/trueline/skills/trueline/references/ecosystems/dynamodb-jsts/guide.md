# ecosystems/dynamodb-jsts/guide.md — Trueline · ecosistema dynamodb-jsts (JS/TS su AWS DynamoDB)

> Pack di rilevamento eco-F6 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **authz**
> (route-authz via semgrep: PutItemCommand/UpdateItemCommand/DeleteItemCommand
> in una route mutante senza auth-guard).
>
> **Richiede Fase 0 (eco-F6):** detection via `detect.deps_any` — l'ecosistema
> non ha un file-marker unico (wrangler.toml, firebase.json, supabase/config.toml)
> e si distingue da un generico progetto JS/TS SOLO per la presenza di
> `@aws-sdk/client-dynamodb` o `aws-sdk` nel package.json.

---

## Profilo dell'ecosistema

- **Linguaggio**: JavaScript / TypeScript — Node.js + AWS SDK v3 (`@aws-sdk/client-dynamodb`) o v2 (`aws-sdk`).
- **Backend**: AWS DynamoDB — database NoSQL gestito (key-value + document), API HTTP tramite SDK AWS.
- **Client tipici**: `@aws-sdk/client-dynamodb`, `@aws-sdk/lib-dynamodb` (DynamoDBDocumentClient), `aws-sdk` (v2 legacy).
- **Schema dichiarato**: nessun file migration SQL; le tabelle DynamoDB sono create via IaC (CloudFormation, CDK, Terraform) o CLI. Nessuna `firestore.rules`, nessun `supabase/config.toml`.
- **Test runner tipici**: vitest, jest, node:test.

---

## Classificazione (Fase 0, detect.deps_any)

Il pack usa `detect.deps_any: ['@aws-sdk/client-dynamodb', 'aws-sdk']` + `detect.lang_any: ['package.json']`.

`classify()` legge il contenuto di `package.json` (dependencies + devDependencies) e, se trova uno dei nomi di deps_any, tratta il match come **segnale forte** (come un files_any presente) — elevando il manifest a passata 1 del motore di classificazione. Di conseguenza:

- un repo JS con `@aws-sdk/client-dynamodb` in deps → `dynamodb-jsts` (passata 1, segnale forte)
- un repo JS senza deps DynamoDB → `postgres-jsts` (passata 2, fallback lang_any-only)
- un repo con `@aws-sdk/client-dynamodb` AND `mongodb` → `{ambiguous}` (due segnali forti a pari merito)

---

## Oracle set — batteria detection (fase 1)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| 2 — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `package-lock.json` |
| 2 — sicurezza | `authz` (`authz-surface`) | semgrep JS/TS + ruleset `ruleset/dynamodb-jsts-authz.yml` | Rileva PutItemCommand/UpdateItemCommand/DeleteItemCommand in route mutanti senza auth; best-effort (degrada se docker assente) |
| bonus | `injection` | semgrep JS/TS + ruleset `ruleset/` | Non-floor; nessuna regola injection specifica nella fase 1 (ruleset condiviso: 0 finding injection attesi) |
| bonus | `dead-code` | knip | Non-floor, dichiarato |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza. `verified_set: []` — nessun difetto auto-fixato in questa fase (L-COL-006).

---

## authz-surface: route-authz DynamoDB (semgrep)

In questo ecosistema l'isolamento per identità/tenant deve essere implementato nel **codice applicativo** (middleware Express, guard JWT, controllo `req.user`): AWS DynamoDB non ha un meccanismo di Row-Level Security analogo a Postgres RLS o Firestore Security Rules. Ogni operazione DynamoDB che avviene in una route mutante (POST/PUT/DELETE/PATCH) senza un check d'identità preventivo è una surface di Broken Access Control (CWE-862, A01:2025).

Il ruleset `dynamodb-jsts-authz.yml` usa semgrep JS/TS per rilevare:
- **Sink**: `client.send(new PutItemCommand(...))`, `client.send(new UpdateItemCommand(...))`, `client.send(new DeleteItemCommand(...))`
- **Contesto**: dentro un handler `$ROUTER.post|put|delete|patch(...)` (arrow function o function expression)
- **Esclusione**: handler che verificano identità con `verifyToken(req)`, `req.user`, `requireAuth(req)` prima del sink

### Pattern DIFETTOSO rilevato (DYNAMO-S3)

```javascript
// SEED:DYNAMO-S3 — route POST senza authz (CWE-862, A01:2025)
router.post('/items', async (req, res) => {
  // Nessun check identità: chiunque può scrivere
  const { pk, sk, data } = req.body ?? {};
  await client.send(new PutItemCommand({
    TableName: 'items',
    Item: { pk: { S: pk }, sk: { S: sk }, data: { S: data } },
  }));
  res.status(201).json({ ok: true });
});
```

### Pattern SICURO (contrasto — non deve produrre finding)

```javascript
// CONTRASTO PULITO: verifyToken() prima di PutItemCommand -> 0 FP
router.post('/items/secure', async (req, res) => {
  const user = verifyToken(req);
  if (!user) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  const { pk, data } = req.body ?? {};
  await client.send(new PutItemCommand({
    TableName: 'items',
    Item: { pk: { S: pk }, owner: { S: user.id }, data: { S: data } },
  }));
  res.status(201).json({ ok: true });
});
```

---

## Differenza rispetto agli altri pack JS/TS

| Aspetto | postgres-jsts | firebase-jsts | dynamodb-jsts |
|---|---|---|---|
| Linguaggio | JS/TS | JS/TS | JS/TS |
| Backend | Postgres (pg/Prisma/Drizzle) | Firebase (Firestore/Admin SDK) | AWS DynamoDB (@aws-sdk/client-dynamodb) |
| authz-surface | route-authz applicativo (semgrep, pool.query INSERT) | Firestore Security Rules (`firestore_rules_check` statico) | route-authz applicativo (semgrep, PutItemCommand) |
| floor | `secret, dependency-vuln, authz` | `secret, dependency-vuln, authz` | `secret, dependency-vuln, authz` |
| verified_set | `[secret, dead-code]` | `[secret, dead-code, authz]` | `[]` (detection fase 1) |
| Segnale detect | `lang_any: [package.json]` (passata 2) | `files_any: [firebase.json, firestore.rules]` (passata 1) | `deps_any: [@aws-sdk/client-dynamodb, aws-sdk]` (passata 1, Fase 0) |
| Authz oracolo | semgrep JS/TS | firestore_rules_check (statico) | semgrep JS/TS |

> Un repo con `firebase.json` e `@aws-sdk/client-dynamodb` in deps → firebase-jsts vince (files_any forte > deps_any in passata 1 per numero di hits: 1 file vs 1 dep, pari merito → tie-break langHits → firebase-jsts). In pratica questi ecosistemi non si sovrappongono (Firebase e DynamoDB sono stack AWS distinti).

---

## Preflight specifico

- Lockfile presente (`package-lock.json`) — assente → osv-scanner non può girare, degradato e dichiarato.
- Docker disponibile con immagine `semgrep/semgrep:latest` — assente → semgrep degrada onesto (authz non verificata dal floor, gate detection esce 1).
- **Nessun DB live richiesto**: l'oracolo authz è semgrep STATICO sui sorgenti JS/TS.
- **`@aws-sdk/client-dynamodb` NON è un secret**: la presenza dell'SDK nel package.json è normale. I secret DynamoDB (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) devono arrivare da env vars/IAM role, mai hardcoded. gitleaks rileva correttamente le credenziali AWS hardcoded (pattern `AKIA...` per Access Key ID, alta entropia per Secret Access Key).
