# {{module_number}}-{{macrotask_name}} — Macrotask `{{macrotask_name}}`

> Template del MODULO di blueprint (11 §4). BOOTSTRAP lo genera nel
> **formato-utente** (markdown numerato) familiare e portabile. Un modulo =
> un macrotask: l'unità al cui confine gira il checkpoint (`L-COL-018`) e
> l'unità di commit atomico su git (`L-COL-024`).
>
> Placeholder in forma `{{snake_case}}` → riempiti con gli **input dell'utente**.
> Identificatori in inglese, prosa in italiano.

Task atomici secondo lo schema di `11-BLUEPRINT-ENGINE` §3 (`L-COL-019`).

## Obiettivo del macrotask

{{macrotask_objective_prose}}

## Task atomici

> Incolla qui un blocco `task.template.yaml` per ogni task. Tutti i task di
> questo file dichiarano `macrotask: "{{macrotask_name}}"`. Le dipendenze
> (`depends_on`) formano un DAG aciclico anche fra task di moduli diversi.

```yaml
# (uno o più task atomici — vedi task.template.yaml)
- id: {{task_id}}
  title: "{{task_title}}"
  macrotask: "{{macrotask_name}}"
  depends_on: [{{dependency_ids}}]

  objective: >
    {{objective_prose}}

  definition_of_done:
    - "{{dod_item_1}}"

  acceptance_criteria:
    - id: {{ac_id_1}}
      given: "{{ac1_given}}"
      when: "{{ac1_when}}"
      then: "{{ac1_then}}"

  target_tests:
    - file: "{{test_file_path}}"
      covers: [{{covered_ac_ids}}]

  # security_notes obbligatorie se il task tocca dati/auth (11 §5.2 p.9)
```

## Self-check

- **Strutturale** (deterministico): `validate_blueprint.mjs` su questa dir di
  blueprint — atteso exit 0 / tutti i controlli OK (11 §5.1).
- **Semantico** (checklist guidata): `self-check-checklist.md` punti 6–10 su
  ogni task; i rilievi vanno all'human-in-the-loop (11 §5.2–§5.3).
