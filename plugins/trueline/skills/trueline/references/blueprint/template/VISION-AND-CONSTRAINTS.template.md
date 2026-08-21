# VISION & CONSTRAINTS — {{project_name}}

> Template della VISIONE e dei VINCOLI di blueprint (11 §4). Generato da
> BOOTSTRAP nel formato-utente. Cattura il *perché*, il *per chi*, i *non-goals*
> e i *vincoli* — input dell'utente, non invenzione dell'LLM (stessa regola di
> 11 §4 e 01 §3.1).
>
> Placeholder in forma `{{snake_case}}` → riempiti con gli input dell'utente.
> Prosa in italiano, identificatori/nomi-file in inglese.

| | |
|---|---|
| **Progetto** | {{project_name}} |
| **Ecosistema** | {{ecosystem}} (v1: JS/TS + Supabase) |
| **Owner / stakeholder** | {{project_owner}} |

---

## 1. Perché esiste (problema)

{{problem_statement}}

## 2. Per chi (utenti)

{{target_users}}

## 3. Obiettivo (cosa significa "fatto")

{{project_objective}}

Il blueprint scompone questo obiettivo in macrotask; i `target_tests` dei task
atomici (`11` §3) ne diventano l'oracolo del checkpoint (`01` §4). "Fatto" =
oracoli verdi sul confine di ogni macrotask, **non** una dichiarazione dell'LLM
(`L-COL-002`, `L-COL-006`).

## 4. Non-goals (cosa NON facciamo)

> Argine allo scope creep. Ogni voce qui è una cosa che il progetto
> deliberatamente NON affronta in questa versione.

- {{non_goal_1}}
- {{non_goal_2}}

## 5. Vincoli

| Tipo | Vincolo |
|---|---|
| Ecosistema | {{ecosystem}} (v1: JS/TS + Supabase) |
| Sicurezza | RLS per-tenant obbligatoria su dati multi-tenant; nessun segreto nel sorgente (`07`) |
| Git | branch a strati; merge su `main` gated dal verde; deploy non supervisionato bloccato (`L-COL-024`, `L-COL-025`) |
| {{constraint_type}} | {{constraint_detail}} |

## 6. Parity gate (promessa forte)

Conformità alla specifica = i `target_tests` dei task del macrotask passano al
checkpoint. Per il brownfield (REMEDIATE) la conformità-logica degrada a
**invarianza** via characterization test (`06`): asimmetria onesta.

## 7. Baseline & budget

- **Baseline di sicurezza**: `{{baseline_budget_path}}` (findings noti, soglie).
- **Budget**: `{{baseline_budget_path}}` (limiti di spesa/tempo per ciclo).

## 8. Fonti di verità

- **Piano**: il blueprint (`00-INDEX` + moduli numerati).
- **Stato vivo**: `{{session_state_path}}` (`SESSION-STATE`, fonte di verità del
  progetto-utente — distinta dalla SESSION-STATE di Trueline stesso).
