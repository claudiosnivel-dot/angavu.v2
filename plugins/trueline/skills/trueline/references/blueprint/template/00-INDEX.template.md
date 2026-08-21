# 00-INDEX — Blueprint di {{project_name}}

> Template dell'INDICE di blueprint (11 §4): mappa dei moduli, piano di build,
> decision ledger e manifest. Generato da BOOTSTRAP nel formato-utente.
> Placeholder `{{snake_case}}` → input dell'utente.

| | |
|---|---|
| **Progetto** | {{project_name}} |
| **Ecosistema** | {{ecosystem}} (v1: JS/TS + Supabase) |
| **Obiettivo** | {{project_objective}} |
| **Schema task** | `11-BLUEPRINT-ENGINE` §3 (`L-COL-019`) |

---

## 1. Mappa dei moduli

| File | Macrotask | Contenuto |
|---|---|---|
| `{{module_file}}` | `{{macrotask_name}}` | {{macrotask_summary}} |
<!-- una riga per macrotask -->

## 1bis. Contratto di altitudine (opzionale — abilita `arch_check` in BUILD)

Dichiara gli **strati** dell'architettura e le dipendenze **vietate** fra strati.
Se presente, `validate_blueprint` ne valida la forma e in BUILD `arch_check`
verifica le regole contro il grafo import reale (madge) come **gate assoluto** —
con vacuity guard obbligatorio (`atomic-task-schema.md`). Omettilo se non vuoi il
gate di altitudine. Selettori glob repo-relative; `mode` opzionale (default
`transitive`); `allow` = eccezioni accettate e audite (mai silenziose).

```yaml
architecture:
  layers:
    {{layer_name}}: "{{layer_glob}}"       # es. ui: "src/ui/**"
  forbidden:
    - { from: {{from_layer}}, to: {{to_layer}} }   # es. { from: ui, to: data }
  # allow:
  #   - { from: ui, to: data, module: "src/ui/Legacy.tsx", note: "TICKET-123" }
```

## 2. Piano di build (ordine dei macrotask)

Ordine derivato dal DAG dei task (`depends_on`):

```
{{build_plan_dag}}
```

I macrotask senza dipendenze aperte possono partire per primi; ogni macrotask si
chiude al suo confine col checkpoint (`01` §4) prima del commit atomico
(`L-COL-024`).

## 3. Aggancio alla sicurezza (`07`)

I macrotask che toccano dati/auth — {{security_relevant_macrotasks}} — portano la
baseline di sicurezza richiesta da `11` §5.2 p.9 (RLS isolation per tenant,
nessun segreto nel sorgente) per l'ecosistema v1 (Supabase).

## 4. Decision ledger

| ID | Decisione | Stato |
|---|---|---|
| {{decision_id}} | {{decision_summary}} | {{decision_status}} |
<!-- le decisioni si modificano SOLO con emendamento esplicito registrato qui -->

## 5. Fonti di verità

- **Piano**: questo blueprint (`00-INDEX` + moduli numerati).
- **Stato vivo**: `{{session_state_path}}` (`SESSION-STATE`, 11 §4 — fonte di
  verità del progetto-utente, distinta dalla SESSION-STATE di Trueline stesso).
- **Baseline / budget**: `{{baseline_budget_path}}`.

## 6. Self-check del blueprint

- **Strutturale**: `validate_blueprint.mjs` su questa dir — atteso exit 0 (11 §5.1).
- **Semantico**: `self-check-checklist.md` punti 6–10 (11 §5.2).
