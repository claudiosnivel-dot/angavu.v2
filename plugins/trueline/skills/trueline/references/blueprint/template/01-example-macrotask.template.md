# 01-auth — Macrotask `auth` (modulo di ESEMPIO)

> Template di un MODULO NUMERATO di blueprint, **già istanziato come esempio**
> (11 §4). Mostra come si presenta un modulo reale: un macrotask (`auth`) con i
> suoi task atomici in YAML secondo lo schema `11-BLUEPRINT-ENGINE` §3
> (`L-COL-019`). BOOTSTRAP genera moduli come questo nel **formato-utente**.
>
> A differenza di `blueprint-module.template.md` / `task.template.yaml` (scheletri
> pieni di placeholder), questo modulo è **concreto e già valido**: copiato in
> una dir di blueprint, `validate_blueprint.mjs` esce PULITO (exit 0). I soli
> placeholder `{{snake_case}}` rimasti sono in campi di *prosa* legati al dominio
> (es. il nome progetto) e non incidono sulla validazione strutturale.
>
> Un modulo = un macrotask: l'unità al cui confine gira il checkpoint
> (`L-COL-018`) e l'unità di commit atomico su git (`L-COL-024`).
> Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Fornire a {{project_name}} l'autenticazione di base e l'isolamento per-tenant dei
dati: registrazione/login degli utenti e una tabella `profiles` protetta da Row
Level Security, su cui poggiano i macrotask successivi.

## Task atomici

```yaml
- id: T-001
  title: "Tabella profiles con RLS per-tenant"
  macrotask: "auth"
  depends_on: []

  objective: >
    Creare la tabella `profiles` con una migration che abilita Row Level Security
    e definisce policy che isolano le righe per l'utente autenticato (auth.uid()),
    così che ogni utente veda e modifichi solo il proprio profilo.

  definition_of_done:
    - "Migration che crea la tabella profiles con colonne id, user_id, display_name, created_at"
    - "ENABLE ROW LEVEL SECURITY applicato sulla tabella profiles"
    - "Policy di SELECT/INSERT/UPDATE che vincolano user_id ad auth.uid() (no USING (true))"

  acceptance_criteria:
    - id: AC-001-1
      given: "la migration è applicata sul DB di test"
      when: "si interroga il catalogo pg per la tabella profiles"
      then: "row level security risulta abilitata (relrowsecurity = true)"
    - id: AC-001-2
      given: "due utenti distinti con un profilo ciascuno"
      when: "l'utente A interroga profiles"
      then: "riceve solo la propria riga, mai quella dell'utente B (RLS isola)"

  target_tests:
    - file: "tests/profiles.schema.test.ts"
      covers: [AC-001-1, AC-001-2]

  security_notes:
    - "RLS isolation per utente/tenant — categoria killer Supabase (07 §5)"
    - "Nessuna policy USING (true): isolamento reale, non finto"

  out_of_scope:
    - "Profili pubblici/condivisi (eventuale macrotask successivo)"

- id: T-002
  title: "Endpoint POST /signup con validazione server-side"
  macrotask: "auth"
  depends_on: [T-001]

  objective: >
    Esporre un endpoint di registrazione che crea l'utente e il relativo profilo,
    validando l'input lato server e senza mai fidarsi del client per i campi di
    identità.

  definition_of_done:
    - "Endpoint POST /signup implementato"
    - "Input (email, password) validato lato server prima di ogni scrittura"
    - "Profilo creato con user_id derivato dalla sessione/identità server, mai dal client"

  acceptance_criteria:
    - id: AC-002-1
      given: "payload di signup valido"
      when: "si chiama POST /signup"
      then: "l'utente è creato e una riga profiles è scritta con user_id dalla sessione"
    - id: AC-002-2
      given: "payload con email malformata o password troppo corta"
      when: "si chiama POST /signup"
      then: "riceve 400, nessun utente e nessun profilo creati"

  target_tests:
    - file: "tests/auth.signup.test.ts"
      covers: [AC-002-1]
    - file: "tests/auth.validation.test.ts"
      covers: [AC-002-2]

  security_notes:
    - "Validazione server-side: nessuna fiducia nel client (07 §4.3)"
    - "Nessun segreto hardcoded; chiavi Supabase via env/secret store (07 §4.1)"

  out_of_scope:
    - "Login social/OAuth (eventuale macrotask successivo)"
```

## Self-check

- **Strutturale** (deterministico): `validate_blueprint.mjs` su questa dir di
  blueprint — atteso exit 0 / tutti i 5 controlli OK (11 §5.1).
- **Semantico** (checklist guidata): `self-check-checklist.md` punti 6–10 su
  ogni task; i rilievi vanno all'human-in-the-loop (11 §5.2–§5.3).
