# Self-check del blueprint — parte semantica (11 §5.2)

> **Cos'è.** La rete *semantica* del self-check sul blueprint. La parte
> strutturale è già un oracolo deterministico
> (`trueline/scripts/blueprint/validate_blueprint.mjs`, 11 §5.1): campi
> obbligatori, copertura criteri→test, DAG, id univoci, appartenenza al
> macrotask. Quello che **non** è oracolabile — se un criterio ben formato è
> anche *sensato* — resta qui: una checklist **guidata dall'LLM ma vincolata**.
>
> **Quando.** Dopo che `validate_blueprint` esce PULITO (strutturale verde) e
> prima che il blueprint si chiuda per BUILD. Strutturale rosso → blueprint
> rifiutato, si corregge e si ri-valida; non si passa alla semantica (11 §5.3).
>
> **Come si applica.** Per OGNI task atomico del blueprint, rispondi ai 5 punti
> qui sotto con un esito esplicito: `OK` oppure `RILIEVO: <cosa correggere>`.
> Un rilievo **non** è un blocco automatico: è materiale per
> l'**human-in-the-loop** (`L-COL-005`). La skill propone le revisioni
> all'utente; il blueprint si chiude solo dopo la conferma (11 §5.3).
>
> **Disciplina (L-COL-002 / L-COL-006).** Questa checklist NON è un
> LLM-as-judge che dichiara "il piano è buono": è un setaccio vincolato che
> *solleva rilievi*. Nessun punto può essere marcato OK "a sensazione"; se non
> sai indicare *cosa* si osserva, è un rilievo, non un OK.

---

## La checklist (punti 6–10)

Numerazione in continuità con i 5 controlli strutturali (1–5) di `validate_blueprint`.

### 6. Misurabilità

Ogni `acceptance_criteria` è **osservabile/testabile**: dice *cosa* si osserva,
non solo che "va bene".

- **Falliscono da soli**: "funziona bene", "robusto", "sicuro", "performante",
  "user-friendly" — aggettivi senza un fatto misurabile dietro.
- **Passa**: un criterio con un osservabile concreto (uno status code, una riga
  scritta con un certo valore, un insieme vuoto, un errore atteso, un campo del
  catalogo a un valore noto).
- Domanda-guida: *quale comando/test fa diventare questo criterio verde o rosso?*
  Se non sai rispondere, è un rilievo.

### 7. Atomicità

Nessun **mega-task**: ogni task è costruibile **e** verificabile entro un solo
ciclo, con i suoi criteri esprimibili come poche asserzioni testabili (11 §2).

- **Rilievo** se: un singolo task impacchetta più capacità indipendenti (es.
  "schema + endpoint + UI + deploy"), oppure ha così tanti criteri da non stare
  in un ciclo.
- **Azione**: proporre lo **split** in task più piccoli, ciascuno con il proprio
  `definition_of_done` + `acceptance_criteria` + `target_tests`.

### 8. Copertura

I macrotask **insieme** coprono l'obiettivo del progetto: nessun salto
"…e poi succede la magia".

- **Rilievo** se: tra due task c'è un gap implicito (un artefatto consumato da un
  task ma prodotto da nessuno), oppure l'obiettivo dichiarato nella VISION non è
  raggiungibile dalla somma dei macrotask presenti.
- **Azione**: nominare il task mancante o la dipendenza implicita da rendere
  esplicita nel DAG (`depends_on`).

### 9. Baseline di sicurezza

Ogni task che **tocca dati o auth** nomina la considerazione di sicurezza
pertinente — aggancio al threat model (`07`). Per l'ecosistema v1
(JS/TS + Supabase) è il punto a più alto rischio.

- **Atteso**: i task su tabelle/route mutanti/lettura per-tenant portano
  `security_notes` che nominano **RLS** (isolamento per tenant, niente
  `USING (true)`) e/o **segreti** (nessun secret hardcoded; chiavi via env/secret
  store), pertinenti alle categorie killer di `07`.
- **Rilievo** se: un task tocca dati/auth ma non dice nulla di RLS/segreti, o li
  nomina in modo generico ("gestione sicura") senza il *cosa*.
- **Azione**: aggiungere/precisare `security_notes` con l'aggancio a `07`.

### 10. Niente task fantasma

Nessuna unità di lavoro **senza criteri**.

- Ridondante con il controllo strutturale (1) — tenuta apposta come **rete
  semantica**: cattura il caso in cui un "task" è in realtà solo un titolo o una
  nota, anche se per qualche motivo è sfuggito allo script.
- **Rilievo** se: compare un elemento che *sembra* un task (ha un titolo, è nel
  piano) ma non porta `acceptance_criteria` reali e testabili.

---

## Esito (11 §5.3)

- **Strutturale rosso** (`validate_blueprint` exit ≠ 0) → blueprint **rifiutato**;
  correggi e ri-valida. Non si avanza a questa checklist.
- **Semantico con rilievi** → la skill **propone le revisioni all'utente**
  (human-in-the-loop, `L-COL-005`); il blueprint si chiude solo dopo la conferma.
- **Tutto OK** (strutturale verde + nessun rilievo non risolto) → il blueprint è
  pronto per BUILD; i `target_tests` dei task diventano l'oracolo del
  controllo conformità-logica del checkpoint (`01` §4, 11 §6).

> **Framing onesto.** Anche con la checklist tutta-OK, l'esito è "il piano ha
> superato i controlli strutturali e non presenta rilievi semantici", **non**
> "il piano è giusto". La correttezza dell'intento resta una scelta umana
> (`L-COL-006`).
