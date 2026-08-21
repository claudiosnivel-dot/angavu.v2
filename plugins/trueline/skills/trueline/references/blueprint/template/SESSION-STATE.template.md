# SESSION-STATE — {{project_name}}

> Template della SESSION-STATE di blueprint (11 §4): la **fonte di verità sullo
> stato vivo del progetto-UTENTE**, consumata da BUILD e aggiornata a ogni
> chiusura di sessione (`session-end.md`, 12 §2.3).
>
> NOTA: questa è un'**istanza diversa** dalla SESSION-STATE del blueprint di
> Trueline stesso. Stesso pattern, istanze distinte — da non confondere (11 §4).
>
> Placeholder in forma `{{snake_case}}` → riempiti da BOOTSTRAP e poi aggiornati
> a ogni sessione. Prosa in italiano, identificatori/nomi-file in inglese.

| | |
|---|---|
| **Progetto** | {{project_name}} |
| **Ecosistema** | {{ecosystem}} (v1: JS/TS + Supabase) |
| **Ultimo aggiornamento** | {{last_updated}} |
| **Sessione corrente** | {{current_session_id}} |

---

## 1. Stato dei macrotask

> Aggiornato a ogni `session-end`. Stati: `todo` | `in_progress` | `done`.

| Macrotask | Stato | Checkpoint | Note |
|---|---|---|---|
| {{macrotask_name}} | {{macrotask_status}} | {{checkpoint_result}} | {{macrotask_note}} |
<!-- una riga per macrotask, nell'ordine del piano di build (00-INDEX §2) -->

## 2. Macrotask corrente

- **Selezionato**: `{{current_macrotask}}` (rispetta le dipendenze del DAG).
- **Task atomici in corso**: {{current_tasks}}
- **Criteri/test di riferimento**: vedi il modulo `{{current_module_file}}` e i
  `target_tests` dei task (oracolo del controllo 4 in BUILD, 11 §6).

## 3. Stato git

> Registrato a ogni `session-end` (12 §2.3). Mai lavorare su `main`.

| Campo | Valore |
|---|---|
| Branch di lavoro | `{{work_branch}}` |
| Ultimo commit | `{{last_commit}}` |
| Stato merge su `main` | {{merge_status}} (gated dal verde del checkpoint) |
| Deploy-coupling | {{deploy_coupling_note}} (`05` §8.3) |

## 4. Baseline & budget

- **Baseline di sicurezza**: `{{baseline_budget_path}}` — findings accettati / soglie.
- **Budget consumato**: {{budget_consumed}} / {{budget_total}}.

## 5. Esiti dell'ultima sessione (framing onesto)

> Solo fatti di comando: "trovato e verificata la correzione di X", "questi
> controlli sono passati", **mai** "è sicuro" (`L-COL-006`).

- {{last_session_outcome_1}}
- {{last_session_outcome_2}}

## 6. Prossimi passi

- {{next_step_1}}
- {{next_step_2}}
