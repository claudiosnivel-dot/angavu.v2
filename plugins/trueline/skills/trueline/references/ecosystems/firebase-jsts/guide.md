# ecosystems/firebase-jsts/guide.md — Trueline · ecosistema firebase-jsts (JS/TS su Firebase)

> Pack di rilevamento SP-5 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **authz**
> (Firestore Security Rules via `firestore_rules_check` STATICO sui file `.rules`).

---

## Profilo dell'ecosistema

- **Linguaggio**: JavaScript / TypeScript — Firebase SDK client-side, Firebase Admin SDK, Cloud Functions for Firebase.
- **Backend**: Firebase — Firestore (NoSQL document DB), Firebase Authentication, Firebase Storage, Realtime Database (RTDB), Cloud Functions.
- **Client tipici**: `firebase/app`, `firebase/firestore`, `firebase-admin`, `@firebase/firestore`, `firebase-functions`.
- **Schema dichiarato**: regole di sicurezza gestite tramite file `.rules` — `firestore.rules`, `storage.rules` — e deployment via `firebase deploy --only firestore:rules`. Nessuna migration SQL. Configurazione principale in `firebase.json`.
- **Test runner tipici**: vitest, jest, mocha.

---

## Oracle set — batteria detection (fase 1)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| 2 — sicurezza | `secret` | gitleaks — working tree | `--redact` obbligatorio; shared con altri pack; **la `apiKey` pubblica Firebase NON è un secret** (vedi sotto) |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | Lockfile: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` |
| 2 — sicurezza | `authz` (`authz-surface`) | `firestore_rules_check` STATICO sui file `.rules` | Analizza `firestore.rules`; rileva pattern aperti come `allow read, write: if true;` |
| 2 — sicurezza | `injection` | semgrep JS/TS + ruleset del pack (`ruleset/`) | Command injection via `child_process` con concatenazione; `eval` di input utente |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza. Nessun finding di detection non equivale a "sicuro" (L-COL-006).

---

## authz-surface: Firestore Security Rules (non route-authz)

In questo ecosistema l'isolamento per identità/tenant è delegato a **Firestore Security Rules** — regole dichiarative che Firebase valuta lato server prima di permettere qualsiasi lettura o scrittura nel database. L'applicazione JS/TS NON implementa authz nel codice applicativo (nessun middleware Express, nessun check `req.user.id`): il controllo è centralizzato nel file `firestore.rules`.

`firestore_rules_check` è un oracolo **STATICO** che legge `firestore.rules` e verifica:

- assenza di regole permissive senza condizioni (`allow read, write: if true;`);
- presenza di almeno una condizione sull'identità dell'utente (`request.auth != null`, `request.auth.uid`);
- coerenza fra le collection dichiarate e le regole applicate (collection senza regola = accesso non definito, potenzialmente aperto o chiuso secondo il default Firebase — che è chiuso di default dal 2019, ma deve essere dichiarato esplicitamente).

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

### Differenza rispetto a Supabase/RLS

Supabase e Postgres usano Row Level Security (RLS) dichiarata in DDL SQL (`CREATE POLICY ... USING (auth.uid() = user_id)`), applicata dal motore Postgres. Firebase usa Firestore Security Rules: sintassi proprietaria, valutata dal backend Firebase, applicata a livello di documento nel NoSQL store. Il concetto di isolamento è analogo (solo l'utente X può accedere ai documenti di X), ma il meccanismo è completamente diverso — nessun SQL, nessuna migration, nessun `auth.uid()` come funzione SQL: l'identità arriva via `request.auth.uid` nel linguaggio delle regole.

---

## injection e dead-code (extra non-floor)

- **injection** (semgrep, ruleset `ruleset/firebase-jsts-injection.yml`): rileva sink di command injection in Cloud Functions JS/TS — `child_process.exec(...)` / `execSync(...)` con input concatenato — e `eval(userInput)`. Non genera finding su invocazioni di `exec` con literal statici né su query Firestore (l'SDK Firestore usa API strutturata, non SQL concatenato). Categoria: `injection`; CWE-77/CWE-95; OWASP A05:2025.
- **dead-code**: non dichiarato in questo pack (tier detection, fase 1). Candidato futuro: knip su workspaces TS.

---

## Differenza rispetto agli altri pack

| Aspetto | supabase-jsts | postgres-jsts | postgres-py | firebase-jsts |
|---|---|---|---|---|
| Linguaggio | JS/TS | JS/TS | Python | JS/TS |
| Backend | Supabase (Postgres) | Postgres diretto | Postgres diretto | Firebase (Firestore) |
| authz-surface | RLS-al-DB (`rls_check`, `auth.uid()`) | route-authz applicativo (semgrep) | RLS-al-DB (`rls_check`, `current_setting(...)`) | Firestore Security Rules (`firestore_rules_check`) |
| floor | `secret`, `dependency-vuln`, `rls` | `secret`, `dependency-vuln`, `authz` | `secret`, `dependency-vuln`, `rls` | `secret`, `dependency-vuln`, `authz` |
| verified_set | `[secret, rls, dead-code]` | `[]` (detection, fase 1) | `[]` (detection, fase 1) | `[]` (detection, fase 1) |
| Segnale detect forte | `supabase/config.toml` (files_any) | solo `package.json` (lang_any) | `pyproject.toml` / `requirements.txt` (lang_any) | `firebase.json` / `firestore.rules` (files_any) |
| dead-code tool | knip | knip | vulture | — (non dichiarato) |
| Authz language | SQL DDL | JS/TS (semgrep) | SQL DDL | Firestore Rules DSL |

> Un repo con **sia** `firebase.json` **sia** `package.json` è classificato come `firebase-jsts` grazie al segnale forte `files_any`. Un repo JS/TS senza `firebase.json` e senza `supabase/config.toml` viene classificato come `postgres-jsts`. I segnali `files_any` hanno priorità sul puro `lang_any`.

---

## Preflight specifico

- Lockfile presente (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) — assente → osv-scanner non può girare, degradato e dichiarato.
- File `firestore.rules` presente nella root del repo (o percorso dichiarato in `firebase.json`) — assente → `firestore_rules_check` non ha regole da analizzare; finding = 0 (non significa authz ok — potrebbe significare rules non ancora scritte).
- **Nessun DB live richiesto**: `firestore_rules_check` è completamente statico — analizza i file `.rules` testuali, non interroga Firestore.
- **`apiKey` pubblica Firebase NON è un secret**: la `apiKey` che appare nel blocco `firebaseConfig` lato client (`apiKey: "AIzaSy..."`) è un identificatore pubblico — per design, viene inclusa nel codice client-side e non dà accesso privilegiato. Il controllo di accesso è interamente nelle Security Rules. gitleaks potrebbe segnalare questo valore come falso positivo: aggiungere un'eccezione specifica per il pattern `firebaseConfig.apiKey` nel `.gitleaks.toml` del progetto. Il **service-account private key** (JSON scaricato dalla Firebase Console, usato da Firebase Admin SDK) è invece un secret a tutti gli effetti — gitleaks lo rileva correttamente come `google-service-account`.
