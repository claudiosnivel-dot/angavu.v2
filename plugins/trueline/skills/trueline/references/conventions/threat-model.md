# Threat Model — Trueline conventions reference

**Modulo sorgente:** `07-CONVENTIONS-THREATMODEL` §6  
**Caricamento:** per modalità attiva (`02` §6) — pieno in BUILD e REMEDIATE; parziale in BOOTSTRAP per le `security_notes`.  
**Scopo:** procedura di enumerazione adversariale che produce **scope**, non verdetti. L'unico punto dove l'LLM ragiona di sicurezza; per questo il confine è esplicito — *enumera e delimita, non assolve*.

---

## §6.1 La triade — input + livello di fiducia + categorie OWASP

Ogni run della procedura parte da tre assi:

**Input** — ogni punto in cui un dato attraversa un confine di fiducia:
- body / query / params HTTP
- header
- token auth
- payload di webhook
- config da env
- upload (file, content-type)
- **filtri forniti dal client a supabase-js** (`.or()`, `.filter()`, ecc.)
- argomenti di funzioni RPC
- subscription realtime (canali, filtri)

**Livello di fiducia** — fissa l'asticella di validazione / authz richiesta:
- *untrusted*: client / rete / anon
- *semi-trusted*: utente autenticato, altro servizio, webhook a firma verificata
- *trusted*: config server, migration, contesto service-role

**Categorie OWASP** — ogni coppia (superficie × fiducia) mappa alle categorie 2025 applicabili (`named-standards.md` §3.1), che a loro volta mappano ai **controlli oracolari** (regole di `forbidden-patterns.md`, RLS checker `named-standards.md` §3.4).

---

## §6.2 La procedura (step che la Skill esegue)

1. **Inventario delle superfici** (strutturale, deterministico dove può): Edge Functions, route / handler API, funzioni RPC, tabelle governate da RLS, confine client supabase-js, storage, realtime, webhook.
2. Per ogni superficie, **identifica gli input e il loro livello di fiducia**.
3. **Mappa** a categorie OWASP 2025 e ai **controlli concreti** che le coprono.
4. **Segnala** le superfici dove il controllo applicabile è detection-only o richiede ragionamento: diventano `security_notes` (`11`) / **percorso critico** (`06` §5), non verde automatico.

---

## §6.3 Catalogo delle superfici (Supabase/JS-TS, v1)

| Superficie | Input tipici | Fiducia default | OWASP 2025 | Controllo |
|---|---|---|---|---|
| Edge Function / route handler | body, query, header, JWT | untrusted → semi | A01:2025 · A05:2025 | Semgrep (`forbidden-patterns.md` §4.2/§4.3), authz |
| Tabella RLS-governata | filtri client, scritture | untrusted (via anon) | A01:2025 | RLS checker (`named-standards.md` §3.4 R1..R9) |
| Funzione RPC / `SECURITY DEFINER` | argomenti | semi | A01:2025 | RLS §3.4 R8, Semgrep |
| Client supabase-js (`.or()` / `.filter()`) | stringhe di filtro | untrusted | A05:2025 | Semgrep (`forbidden-patterns.md` §4.2 PostgREST filter injection) |
| Storage / upload | file, path, content-type | untrusted | A01:2025 · A05:2025 | Semgrep (`forbidden-patterns.md` §4.5), policy storage |
| Realtime subscription | canali, filtri | semi | A01:2025 | RLS §3.4 |
| Webhook in ingresso | payload, firma | untrusted finché non verificata | A07:2025 · A01:2025 | authz, verifica firma |
| Config da env | variabili | trusted (ma `secret` se inline) | A02:2025 · A07:2025 | gitleaks, Semgrep `forbidden-patterns.md` §4.1 |

---

## §6.4 Come l'output è consumato — confine `L-COL-002`

- **BOOTSTRAP** usa l'enumerazione per scrivere le `security_notes` dei task (`11` §3): ogni task che tocca dati / auth nomina la considerazione RLS / segreti pertinente.
- **BUILD / REMEDIATE** la usano per puntare la batteria oracolare alle superfici giuste e per delimitare il percorso critico (`06` §5).
- L'enumerazione è **LLM-assistita** (l'LLM legge la struttura del codice e enumera superfici / input / fiducia), ma **il verdetto su ogni superficie resta dell'oracolo**: il threat model produce **scope**, mai un via libera.

**Confine dichiarato:** il threat model è l'unico pezzo dove l'LLM ragiona di sicurezza. Una superficie è "sicura" se i controlli oracolari passano su di essa — mai perché il threat model lo dichiari. È l'unico punto dove l'LLM ragiona di sicurezza, e proprio per questo il confine è esplicito — *enumera e delimita, non assolve* (`L-COL-002`).
