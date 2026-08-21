# modes/bootstrap.md — Trueline · modalità BOOTSTRAP

> Caricato **solo** quando il dispatch del corpo `SKILL.md` risolve a BOOTSTRAP
> (`02` §6). Dal nulla al **piano**: nessun codice prodotto (`01` §3.1).

---

## Quando

Repo vuoto o quasi (nessun sorgente sostanziale, niente blueprint, niente
`SESSION-STATE.md`). Nei casi ambigui il corpo **chiede conferma** prima di
costruire alcunché (`01` §2, `L-COL-005`).

---

## Reference e script caricati in BOOTSTRAP (`02` §6)

**Reference (livello 3, on demand):**

| File | Perché |
|---|---|
| `references/blueprint/atomic-task-schema.md` | schema obbligatorio dei task atomici (`L-COL-019`) |
| `references/blueprint/self-check-checklist.md` | checklist semantica punti 6–10 (`11` §5.2) |
| `references/blueprint/template/` | suite parametrica (00-INDEX, VISION, moduli, SESSION-STATE, task) |
| `references/conventions/named-standards.md` | vocabolario OWASP/ASVS/CWE + standard RLS per scrivere le `security_notes` dei task |
| `references/ecosystems/supabase-jsts/guide.md` | specifiche dell'ecosistema attivo (risolto da `scripts/ecosystem/resolve.mjs`; esempio v1: supabase-jsts) |

Non si caricano in BOOTSTRAP: `references/oracles/` (ruleset, soglie),
`references/conventions/forbidden-patterns.md` e `threat-model.md` in pieno,
`references/finding-model.md`. La batteria oracolare non è necessaria
per pianificare.

**Script usati:**

- `scripts/blueprint/validate_blueprint.mjs` — self-check **strutturale**
  deterministico; la skill lo esegue dopo la generazione del blueprint e
  **non avanza** finché non esce pulito (`11` §5.3).

---

## Pipeline (`01` §3.1)

### 1. Raccolta intento

Obiettivo del progetto, ecosistema (v1: JS/TS su Supabase), vincoli noti
(performance, privacy, timeline, integrazioni).

**Regola:** input dell'utente, non invenzione dell'LLM. Se un vincolo non è
dichiarato non va inventato.

### 2. Generazione blueprint

Suite di file in stile-utente dai template di `references/blueprint/template/`:

- `00-INDEX.md` — mappa, piano di build, decision ledger, manifest.
- `VISION-AND-CONSTRAINTS.md` — perché, per chi, non-goals, vincoli.
- `SESSION-STATE.md` (istanza iniziale) — fonte di verità dello stato vivo.
- Moduli numerati `01-…`, `02-…` — scomposti in macrotask; ogni macrotask
  contiene task atomici secondo lo schema di `references/blueprint/atomic-task-schema.md`.

Ogni **task atomico** porta **obbligatoriamente** (`L-COL-019`):

- `definition_of_done` — "il lavoro c'è" (artefatti prodotti, osservabili).
- `acceptance_criteria` — "fa la cosa giusta" (asserzioni comportamentali testabili).
- `target_tests` — i criteri resi eseguibili (file + quali AC coprono).

Un blueprint con anche un solo task privo di questi tre campi è invalido e
`validate_blueprint` lo rifiuta.

### 3. Self-check strutturale (script)

Eseguire `scripts/blueprint/validate_blueprint.mjs`. Controlli meccanici:

1. campi obbligatori presenti e non vuoti su ogni task atomico,
2. ogni `acceptance_criteria` coperto da ≥1 `target_tests` (nessun criterio orfano),
3. DAG `depends_on` senza cicli e senza riferimenti a ID inesistenti,
4. ID task univoci e non riusati,
5. ogni task atomico dichiara un `macrotask` esistente.

**Se rosso → blueprint rifiutato.** Correggere e ri-eseguire; non si avanza
alla checklist semantica.

### 4. Self-check semantico (checklist guidata)

Applicare `references/blueprint/self-check-checklist.md` (punti 6–10) su ogni
task atomico, solo dopo che lo strutturale è verde:

6. **Misurabilità** — ogni criterio è osservabile/testabile, non un aggettivo.
7. **Atomicità** — ogni task è costruibile e verificabile entro un ciclo.
8. **Copertura** — i macrotask insieme coprono l'obiettivo senza salti impliciti.
9. **Baseline di sicurezza** — ogni task che tocca dati/auth cita RLS/segreti per nome (non "gestione sicura" generico). Vedi §5 di `07-CONVENTIONS-THREATMODEL` e il catalogo di `references/conventions/named-standards.md` §3.4.
10. **Niente task fantasma** — nessuna unità senza criteri reali.

Un rilievo va presentato all'utente (human-in-the-loop, `L-COL-005`). Il
blueprint si chiude solo dopo la conferma.

### 5. Enumerazione threat model per le `security_notes`

Per i task che toccano dati/auth, la skill esegue la procedura di
`references/conventions/threat-model.md` §6.2 in forma ridotta:

1. identifica la superficie (edge function, tabella RLS-governata, storage, ecc.),
2. identifica l'input e il livello di fiducia (`untrusted` / `semi` / `trusted`),
3. mappa alle categorie OWASP 2025 applicabili (mappa in `named-standards.md` §3.1),
4. scrive `security_notes` che citano RLS / segreti per nome.

**Confine `L-COL-002`:** il threat model produce *scope*, non verdetti. Una
superficie è "sicura" se i controlli oracolari la validano — mai perché il
threat model lo dichiari.

### 6. Emissione dei 3 prompt di lifecycle

BOOTSTRAP emette i template da `assets/prompts/` parametrizzati sul blueprint
(`L-COL-022`, `12-LIFECYCLE-PROMPTS`):

- `project-start.md` — orienta l'agente al blueprint, alle decisioni bloccate,
  al piano di macrotask e alle invarianti per l'intero progetto.
- `session-start.md` — apre ogni sessione: legge `SESSION-STATE`, seleziona il
  macrotask corrente, ripete i task con i loro `acceptance_criteria` e
  `target_tests`, prepara il branch.
- `session-end.md` — chiude ogni sessione: verifica che il checkpoint sia girato,
  aggiorna `SESSION-STATE`, registra lo stato git e il deploy-coupling.

Questi prompt sono **artefatti di output**, non runtime della skill (`L-COL-022`).
Con la skill, è BUILD a eseguire la disciplina che i prompt descrivono. Senza la
skill (portabilità cross-tool) li incolla l'utente.

### 7. Istanzia `SESSION-STATE`

Fotografia dello stato iniziale: blueprint pronto, nessun macrotask costruito,
baseline vuota, `main_deploy_coupled: unknown`.

---

## Disciplina BOOTSTRAP

- **Oracle-as-judge per il piano** (`L-COL-002`): la qualità semantica non è
  oracolabile; si rende affidabile con template + checklist, non con l'opinione
  dell'LLM. Lo script strutturale è l'unico oracolo di questa fase.
- **Human-in-the-loop** (`L-COL-005`): rilievi semantici → proposta all'utente,
  mai applicati in silenzio.
- **Nessun codice prodotto** in questa fase. BOOTSTRAP pianifica; BUILD costruisce.
- **Niente inventato** (`L-COL-006`): obiettivo, vincoli e macrotask vengono
  dall'utente; la skill struttura, non scrive intento al posto suo.

---

## Uscita

Blueprint + `SESSION-STATE` presenti → alla sessione successiva il dispatch
sceglie **BUILD** (confidenza alta, `01` §2).
