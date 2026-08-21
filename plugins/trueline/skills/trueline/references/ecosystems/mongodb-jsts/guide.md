# ecosystems/mongodb-jsts/guide.md — Trueline · ecosistema mongodb-jsts (JS/TS su MongoDB)

> Pack di rilevamento eco-F6 — tier **detection** (Fase 0). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **authz**
> (route-authz via `semgrep` con ruleset `mongodb-jsts-authz.yml`).
> Rilevamento ecosistema via **deps_any** (Fase 0 engine): detect.deps_any
> identifica il progetto dalla dipendenza dichiarata (`mongodb` o `mongoose`),
> poiche' MongoDB non ha un file-marker univoco (come `wrangler.toml` per Cloudflare D1).

---

## Profilo dell'ecosistema

- **Linguaggio**: JavaScript / TypeScript — Node.js (Express, Fastify, Koa, Next.js API routes).
- **Backend**: MongoDB — database documentale NoSQL. Accesso via:
  - **MongoDB Node.js Driver** (`mongodb` npm): `MongoClient`, `collection.insertOne/updateOne/deleteOne/findOneAndUpdate`;
  - **Mongoose ODM** (`mongoose` npm): `Model.create()`, `document.save()`, schema-based validation.
- **Client tipici**: `mongodb`, `mongoose`, eventualmente `@mongodb-js/sasl-prepare`.
- **Schema dichiarato**: nessun file di schema fisso (a differenza di Firestore o Supabase);
  i dati sono JSON documents; gli indici e la struttura sono dichiarati via Mongoose Schema
  o gestiti direttamente nel codice applicativo.
- **Test runner tipici**: jest, vitest, mocha.

---

## Rilevamento — detect.deps_any (Fase 0)

```json
"detect": {
  "deps_any": ["mongodb", "mongoose"],
  "lang_any": ["package.json"]
}
```

Il campo `deps_any` (Fase 0, eco-F6) istruisce `classify()` a leggere `package.json`
(dependencies + devDependencies) e a trattare la presenza di `mongodb` o `mongoose`
come **segnale forte** (come un `files_any`). Questo risolve la collisione con
`postgres-jsts` (che usa solo `lang_any: ['package.json']` e cadrebbe in Pass 2):
il progetto MongoDB e' classificato in **Pass 1** e vince senza ambiguita'.

---

## Oracle set — batteria detection (fase 1)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| 2 — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` |
| 2 — sicurezza | `authz` (`authz-surface`) | semgrep + `ruleset/mongodb-jsts-authz.yml` | Route handler mutante con sink MongoDB senza auth-guard |
| 2 — sicurezza | `injection` | semgrep + `ruleset/` | Dichiarato; non nel floor |
| — | `dead-code` | knip | Dichiarato; non nel floor |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack e' in tier **detection** — rileva la presenza di difetti,
non ne certifica l'assenza. Nessun finding di detection non equivale a "sicuro" (L-COL-006).
La categoria `authz` richiede **docker** (semgrep via immagine pinnata): degrada onesto
(exit 1 dichiarato) se docker assente — mai un verde silenzioso.

---

## authz-surface: route-authz MongoDB (non authz-at-DB)

In questo ecosistema l'authz e' delegata al **codice applicativo** (middleware Express,
guard di autenticazione come `verifyToken`, `requireAuth`, `req.user` da JWT/sessione):
MongoDB non ha un meccanismo di row-level security integrato lato DB come Supabase RLS.

`mongodb-jsts-authz.yml` e' un ruleset semgrep che rileva:

- route handler **mutanti** (`router.post/.put/.delete/.patch`) che chiamano
  `collection.insertOne()`, `collection.updateOne()`, `collection.deleteOne()`,
  `collection.findOneAndUpdate()`, oppure Mongoose `document.save()` / `Model.create()`;
- **senza** una verifica d'identita'/ruolo nel corpo dell'handler
  (`req.user`, `req.session`, `verifyToken(...)`, `requireAuth(...)`, `ensureAuth(...)`).

### Pattern INSICURO rilevato (seed MG-S3)

```javascript
// VULNERABILE — insertOne senza auth check (SEED:MG-S3)
router.post('/items', async (req, res) => {
  // Nessun controllo auth: chiunque puo' inserire documenti.
  const result = await db.collection('items').insertOne(req.body);
  res.status(201).json({ ok: true, id: result.insertedId });
});
```

### Pattern SICURO riconosciuto (contrasto)

```javascript
// SICURO — verifyToken prima dell'insertOne (contrasto, nessun finding atteso)
router.post('/items/secure', async (req, res) => {
  const user = verifyToken(req);
  if (!user) {
    res.status(401).json({ ok: false, error: 'unauthorized' });
    return;
  }
  const result = await db.collection('items').insertOne({ ...req.body, owner: user.id });
  res.status(201).json({ ok: true, id: result.insertedId });
});
```

---

## Seed della fixture di riferimento

| ID | Categoria | Oracolo | Ancora |
|---|---|---|---|
| MG-S1 | `secret` | gitleaks | `src/index.js` — `sk_live_MongoDBjstsS1_...` hardcoded |
| MG-S2 | `dependency-vuln` | osv-scanner | `package-lock.json` — `lodash@4.17.20` (GHSA-35jh-r3h4-6jhm) |
| MG-S3 | `authz` | semgrep | `src/routes/items.js` — `insertOne` senza auth (SEED:MG-S3) |
