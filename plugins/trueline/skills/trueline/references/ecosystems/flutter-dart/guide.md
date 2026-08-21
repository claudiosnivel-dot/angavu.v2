# ecosystems/flutter-dart/guide.md — Trueline · ecosistema flutter-dart (Dart/Flutter su Supabase)

> Pack di rilevamento eco-F4 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (verified_set vuoto). Authz-surface = **route-authz**
> (chiamate Supabase mutanti senza verifica identità), semgrep best-effort (Dart
> sperimentale). floor: `[secret, dependency-vuln, authz]`.

---

## Profilo dell'ecosistema

- **Linguaggio**: Dart — Flutter SDK, applicazioni mobile/web/desktop con backend Supabase.
- **Backend**: Supabase — client `supabase_flutter` (Dart), operazioni via `supabase.from(<table>).insert/update/delete`.
- **Marker di detect**: `pubspec.yaml` (presente in ogni progetto Dart/Flutter; fallback `lang_any`).
- **Lockfile osv**: `pubspec.lock` (generato da `pub get`; contiene nome, versione e hash di ogni dipendenza).
- **Tool dead-code (dichiarato, F5)**: `dart analyze` / `dart fix` — analisi statica nativa; rimozioni mai automatiche (`L-COL-021`).
- **Test runner**: `flutter test` / `dart test` (fuori scope harness JS; fixture usa Dart test package).

---

## Oracle set — batteria detection (fase 1)

| Controllo | Categoria finding | Oracolo | Wrapper | Note |
|---|---|---|---|---|
| secret | `secret` | gitleaks (working-tree) | `scripts/oracles/run_gitleaks.mjs` | Language-agnostic; shared con supabase-jsts/postgres-jsts |
| dependency-vuln | `dependency-vuln` | osv-scanner su `pubspec.lock` | `scripts/oracles/run_osv.mjs` | Lockfile Pub; ecosistema osv = "Pub" |
| authz | `authz` (authz-surface) | Semgrep + ruleset Dart (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Semgrep Dart = sperimentale; best-effort (L-COL-006) |
| injection | `injection` | Semgrep + ruleset del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Idem, best-effort |
| dead-code | `dead-code` | `dart analyze` (dichiarato, F5) | — | Non esercitato nella fase F4 (strumento fuori sandbox) |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza.
Nessun finding non equivale a "sicuro" (`L-COL-006`). `verified_set=[]` (fase F4).

---

## authz-surface: route-authz Supabase (non RLS-al-DB)

In un'app Flutter/Dart, l'isolamento per identità vive nell'applicazione:
ogni funzione che esegue una scrittura Supabase deve verificare
`supabase.auth.currentUser` prima di agire. Senza verifica, chiunque
richiami la funzione può mutare i dati di qualunque tenant (CWE-862, A01:2025).

### Pattern difettoso rilevato (SEED:FD-S3)

```dart
// DIFETTO — scrittura Supabase senza verifica identità (CWE-862, A01:2025)
// SEED:FD-S3
Future<void> createPost(Map<String, dynamic> data) async {
  await supabase.from('posts').insert(data);
}
```

### Pattern sicuro (contrasto — NON flaggato)

```dart
// SICURO — verifica identità prima della scrittura
Future<void> createPostSafe(Map<String, dynamic> data) async {
  final user = supabase.auth.currentUser;
  if (user == null) throw Exception('Unauthorized');
  await supabase.from('posts').insert({...data, 'user_id': user.id});
}
```

### Auth-check riconosciuti dal ruleset (esclusione pattern-not-inside)

- `supabase.auth.currentUser` — accesso al profilo utente autenticato (null se non autenticato)

---

## Sink Supabase rilevati dal ruleset route-authz

| Operazione | Pattern mutante rilevato |
|---|---|
| Inserimento | `supabase.from(<table>).insert(...)` |
| Aggiornamento | `supabase.from(<table>).update(...)` |
| Cancellazione | `supabase.from(<table>).delete()` |

Operazioni di sola lettura (`select()`) e handler senza sink mutante: **nessun finding** (0 FP per design).

---

## Dipendenza vulnerabile (SEED:FD-S2)

Il lockfile della fixture (`pubspec.lock`) pinna `archive@3.3.0`, che ha advisories OSV:

- **GHSA-9v85-q87q-g4vg** (CVSS 7.8) — path traversal / zip-slip in `archive < 3.3.1`
- **GHSA-r285-q736-9v95** (CVSS 7.8) — vulnerabilità correlata in `archive < 3.3.1`

Rilevata da `osv-scanner --lockfile pubspec.lock:pubspec.lock`.
Stato-fix: `detection-only` (un bump del pacchetto pub è operazione human-gated).

---

## Secret hardcoded (SEED:FD-S1)

La fixture `lib/config.dart` contiene una chiave in stile `sk_live_...` hardcoded
nell'identificatore `_supabaseServiceKey`. Rilevata da gitleaks (regola
`trueline-stripe-like-key`). Il contrasto usa `Platform.environment['SUPABASE_SERVICE_KEY']`
(env-read, gitleaks-clean).

---

## Preflight specifico

- `pubspec.lock` presente — assente → osv-scanner non può girare, degrada dichiarato.
- Semgrep Dart sperimentale — assente o parser limitato → authz/injection best-effort,
  degrada dichiarato (mai un falso verde; `L-COL-006`).
- Nessun DB live richiesto (flutter-dart non ha controlli RLS a runtime in fase F4).
