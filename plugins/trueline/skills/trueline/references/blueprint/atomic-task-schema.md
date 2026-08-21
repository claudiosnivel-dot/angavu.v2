# atomic-task-schema.md — Trueline · schema del task atomico *(L-COL-019)*

> Distillato da `11-BLUEPRINT-ENGINE` §3. Caricato in BOOTSTRAP (genera) e
> consumato parzialmente in BUILD (`acceptance_criteria` come oracolo del
> controllo 4, `02` §6). Identificatori in inglese, prosa in italiano.

Lo schema è la parte **oracolabile** del piano: lo script
`scripts/blueprint/validate_blueprint.mjs` lo verifica in modo deterministico
(campi obbligatori non vuoti, copertura AC→test, DAG aciclico, id univoci,
ownership del macrotask). La parte semantica resta alla
[`self-check-checklist.md`](./self-check-checklist.md).

## Formato di riferimento (YAML)

```yaml
- id: T-014                         # ID stabile, non riusato (univoco)
  title: "Endpoint creazione prenotazione con RLS"
  macrotask: "prenotazioni"         # ownership: non vuoto
  depends_on: [T-009, T-011]        # DAG esplicito, niente cicli, no id inesistenti

  objective: >                      # COSA deve ottenere (prosa)
    Esporre un endpoint che crea una prenotazione per l'utente autenticato,
    isolata per tenant via RLS.

  definition_of_done:               # IL LAVORO è completo quando…  (osservabile)
    - "Endpoint POST /bookings implementato"
    - "Migration con policy RLS su table bookings applicata"
    - "Input validato lato server (no fiducia nel client)"

  acceptance_criteria:              # COME si prova che fa la cosa giusta (testabile)
    - id: AC-014-1
      given: "utente autenticato del tenant A"
      when: "crea una prenotazione"
      then: "la riga è scritta con tenant_id = A"
    - id: AC-014-2
      given: "utente del tenant A"
      when: "tenta di leggere prenotazioni del tenant B"
      then: "riceve insieme vuoto (RLS blocca)"

  target_tests:                     # i criteri resi eseguibili — oracolo del controllo 4
    - file: "tests/bookings.create.test.ts"
      covers: [AC-014-1, AC-014-2]

  security_notes:                   # opzionale: aggancio al threat model (07)
    - "RLS isolation per tenant — categoria killer Supabase"

  out_of_scope:                     # opzionale: argine allo scope creep
    - "Cancellazione prenotazione (T-016)"
```

## Campi obbligatori (controllati dall'oracolo strutturale)

| Campo | Regola |
|---|---|
| `id` | presente, non vuoto, **univoco** in tutto il blueprint |
| `macrotask` | presente, non vuoto (ownership) |
| `objective` | presente, non vuoto |
| `definition_of_done` | lista non vuota, ogni voce non vuota |
| `acceptance_criteria` | lista non vuota; ogni item con `id` + `given` + `when` + `then` |
| `target_tests` | lista non vuota; ogni item nomina un `file`; ogni AC coperto da ≥1 test |
| `depends_on` | opzionale; se presente, DAG aciclico verso id esistenti |

**DoD vs acceptance_criteria** — `definition_of_done` = "il lavoro c'è"
(artefatti osservabili); `acceptance_criteria` = "e fa la cosa giusta"
(asserzioni comportamentali). Sono **questi** che il controllo conformità-logica
usa come oracolo. `target_tests` è il ponte da criterio a eseguibile.

## Provenienza del target_test — tag `covers:` (anti-tamper, BUILD `--blueprint`)

Nel **file** del `target_test`, ogni blocco che esercita un AC porta `covers: <AC-id>`
**in un commento** (`// covers: AC-1`). È la controparte *eseguibile* del campo
`covers` del blueprint: in BUILD col controllo 4 attivo (`--blueprint`), un AC valutato
non tracciato da alcun suo target_test in-scope rende il controllo 4 **rosso prima di
eseguire** (`scripts/blueprint/ac_assertion_trace_check.mjs`). Per-AC globale, ancorato
all'id, string-aware. **Questo schema e `validate_blueprint` restano invariati**: il
tag è una convenzione del file di test, non un campo del task.

## Contratto di altitudine — blocco `architecture:` (BUILD, A2b)

Il blueprint può dichiarare l'**altitudine** (gli strati architetturali e le
dipendenze vietate) in un blocco `architecture:` **globale** in `00-INDEX.md`
(non per-task: gli strati sono una proprietà del progetto). `validate_blueprint`
ne valida la forma (condizionale); in BUILD `arch_check` verifica le regole
`forbidden` contro il grafo import reale (madge), come **gate assoluto**.

```yaml
architecture:
  layers:                         # nome-strato -> selettore glob (path repo-relative)
    ui:     "src/ui/**"
    domain: "src/domain/**"
    data:   "src/data/**"
  forbidden:                      # regole direzionali; `mode` opzionale (default transitive)
    - { from: ui,     to: data }              # ui non deve RAGGIUNGERE data (anche via terzi)
    - { from: domain, to: ui, mode: direct }  # solo edge diretti domain->ui
  allow:                          # eccezioni ACCETTATE (audite, mai silenziose) — opzionale
    - { from: ui, to: data, module: "src/ui/LegacyGrid.tsx", note: "temp, TICKET-123" }
```

| Campo | Regola (validate_blueprint, se il blocco è presente) |
|---|---|
| `layers` | ≥1 strato; ogni strato con selettore glob non vuoto |
| `forbidden` | ≥1 regola; `from`/`to` = strati dichiarati; `mode` ∈ {direct, transitive} |
| `allow` | opzionale; `from`/`to` = strati dichiarati; `module` + `note` |

**Vacuity guard (`arch_check`, build-time, `L-COL-006`):** grafo vuoto, 0 regole,
o una regola il cui `from`/`to` mappa a 0 moduli reali ⇒ **non-verde dichiarato**,
mai un pass vacuo. **BUILD-only**: in REMEDIATE non c'è blueprint → non applicabile.
