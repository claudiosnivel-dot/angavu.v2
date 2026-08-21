# ecosystems/firebase-py/guide.md — Trueline · ecosistema firebase-py (Python su Firebase)

> Pack di rilevamento eco-F1 — tier **verified** (fase eco-expansion). Coverage dichiarata;
> verified_set = `[secret, dead-code, authz]`. Authz-surface = **authz**
> (Firestore Security Rules via `firestore_rules_check` STATICO sui file `.rules`).
> Incrocio `supabase-py` (lingua/tie-break Python) × `firebase-jsts` (backend/authz Firestore).

---

## Profilo dell'ecosistema

- **Linguaggio**: Python — Firebase Admin SDK, applicazioni server-side che leggono/scrivono su Firestore tramite `firebase-admin`.
- **Backend**: Firebase — Firestore (NoSQL document DB), Firebase Authentication, Firebase Storage, Cloud Functions.
- **Client tipici**: `firebase-admin`, `google-cloud-firestore`, `google-auth`.
- **Schema dichiarato**: regole di sicurezza gestite tramite file `.rules` — `firestore.rules` — e deployment via `firebase deploy --only firestore:rules`. Nessuna migration SQL. Configurazione principale in `firebase.json`.
- **Test runner tipici**: pytest, unittest.
- **Lockfile**: `requirements.txt` (pip), `poetry.lock` (Poetry), `Pipfile.lock` (Pipenv).

---

## Tie-break lingua con firebase-jsts

Firebase-py e firebase-jsts condividono gli stessi `files_any` (`firebase.json`, `firestore.rules`). La classificazione viene disambiguata dal **tie-break lingua** (SP-3 T2.1):

- Un repo con `firebase.json` (o `firestore.rules`) **e** `requirements.txt` (o `pyproject.toml`/`Pipfile`/`setup.py`), **senza** `package.json` → classificato `firebase-py`.
- Un repo con `firebase.json` **e** `package.json`, **senza** file Python → classificato `firebase-jsts`.
- Presenza di **entrambi** (`package.json` + `requirements.txt`) → `{ambiguous, candidates:[firebase-jsts, firebase-py]}` (conferma umana).

---

## Oracle set — batteria verified (eco-F1)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| floor — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack; il `serviceAccount.json` è un secret critico (chiave privata PEM) |
| floor — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `requirements.txt`, `poetry.lock`, `Pipfile.lock` |
| floor — sicurezza | `authz` (`authz-surface`) | `firestore_rules_check` STATICO sui file `.rules` | Analizza `firestore.rules`; rileva pattern aperti come `allow read, write: if true;` |
| bonus — sicurezza | `injection` | semgrep Python + ruleset del pack (`ruleset/`) | SQL injection Python via `.execute()` con f-string/%-format/concat; non-floor |
| verified — igiene | `dead-code` | vulture (Python) | Simboli Python non utilizzati (funzioni, classi, attributi); `python -m vulture`; non-floor ma nel verified_set |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Verified set (categorie con loop di fix automatico verificato):** `secret`, `dead-code`, `authz`.

---

## authz-surface: Firestore Security Rules (non route-authz)

In questo ecosistema l'isolamento per identità/tenant è delegato a **Firestore Security Rules** — regole dichiarative che Firebase valuta lato server prima di permettere qualsiasi lettura o scrittura nel database. L'applicazione Python NON implementa authz nel codice applicativo (nessun middleware Flask/FastAPI dedicato, nessun check `current_user.id`): il controllo è centralizzato nel file `firestore.rules`.

`firestore_rules_check` è un oracolo **STATICO** che legge `firestore.rules` e verifica:

- assenza di regole permissive senza condizioni (`allow read, write: if true;`);
- presenza di almeno una condizione sull'identità dell'utente (`request.auth != null`, `request.auth.uid`);
- coerenza fra le collection dichiarate e le regole applicate.

### Pattern SICURO riconosciuto (Firestore Security Rules)

```javascript
// firestore.rules — isolamento per proprietario del documento
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /bookings/{bookingId} {
      // SAFE: solo il proprietario del documento può leggere o scrivere
      allow read, write: if request.auth != null
                         && request.auth.uid == resource.data.ownerId;
    }
  }
}
```

### Pattern DIFETTOSO rilevato

```javascript
// firestore.rules — DIFETTO: regola aperta senza condizione di autenticazione
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      // DIFETTO — chiunque (anche utente non autenticato) può leggere e scrivere qualsiasi documento
      allow read, write: if true;
    }
  }
}
```

### Scoping onesto (L-COL-006)

**authz-verified** in firebase-py = `firestore_rules_check` STATICO ri-eseguito pulito (la regola testuale non concede più `if true`, passa a owner-scoped). NON invarianza d'isolamento a runtime (l'emulatore Firestore non è disponibile). Analogo dichiarativo del trasferimento RLS `USING(true)` → predicato reale, provato dall'oracolo statico.

---

## secret: service account Firebase Admin

La chiave più critica in un'app Firebase Python lato server è il **service account JSON** scaricato dalla Firebase Console e passato a `firebase_admin.initialize_app(credentials.Certificate(serviceAccount))`. Questo file contiene una **private key RSA** (blocco `-----BEGIN PRIVATE KEY-----`) che dà accesso completo al progetto Firebase — scrittura Firestore, invio notifiche, accesso Admin SDK.

`gitleaks` rileva correttamente questo pattern tramite la regola `google-service-account`. Il fix consiste nel **neutralizzare il valore** di `private_key` in `serviceAccount.json` e leggere la chiave reale da una variabile d'ambiente o da un secret manager (es. `FIREBASE_PRIVATE_KEY`).

**Nota:** La `apiKey` pubblica Firebase (stile `AIzaSy...`) che appare nel blocco `firebaseConfig` lato client **NON è un secret** — è un identificatore pubblico per design. Il controllo di accesso è interamente nelle Security Rules. gitleaks potrebbe segnalare questo valore come falso positivo: aggiungere un'eccezione per il pattern `firebaseConfig.apiKey` nel `.gitleaks.toml`.

---

## dead-code: vulture (Python)

`vulture` analizza l'AST Python e identifica simboli mai referenziati — funzioni, classi, attributi, variabili. Il fix rimuove il simbolo dal file sorgente. La signature del fix include il simbolo rimosso, garantendo che ogni simbolo distinto produca una patch materialmente diversa.

---

## injection e dependency-vuln (extra non-floor)

- **injection** (semgrep, ruleset `ruleset/firebase-py-injection.yml`): rileva SQL injection Python via `.execute()` con f-string, `%-format`, concatenazione, `.format()`. Bonus, non-floor.
- **dependency-vuln** (osv-scanner su `requirements.txt`): rileva dipendenze con vulnerabilità note. Floor, non-verified (bump di versione richiede intervento umano).

---

## Differenza rispetto agli altri pack

| Aspetto | firebase-jsts | firebase-py |
|---|---|---|
| Linguaggio | JS/TS | Python |
| Backend | Firebase (Firestore) | Firebase (Firestore) |
| authz-surface | `firestore_rules_check` | `firestore_rules_check` (identico) |
| floor | `secret`, `dependency-vuln`, `authz` | `secret`, `dependency-vuln`, `authz` (identico) |
| verified_set | `[secret, dead-code, authz]` | `[secret, dead-code, authz]` (identico) |
| Segnale detect | `firebase.json`/`firestore.rules` + `package.json` | `firebase.json`/`firestore.rules` + `requirements.txt`/`pyproject.toml` |
| dead-code tool | knip (JS/TS) | vulture (Python) |
| Lockfile | `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` | `requirements.txt`, `poetry.lock`, `Pipfile.lock` |

> Un repo con `firebase.json` e **solo** `requirements.txt` (no `package.json`) viene classificato come `firebase-py`. Un repo con `firebase.json` e **solo** `package.json` (no file Python) viene classificato come `firebase-jsts`. La presenza di entrambi produce `{ambiguous}`.
