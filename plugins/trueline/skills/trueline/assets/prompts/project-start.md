# project-start — prompt di lifecycle (output di BOOTSTRAP)

> **Cos'è.** Prompt da incollare **una volta**, all'avvio del progetto, per
> orientare l'agente al blueprint, alle decisioni bloccate, al piano di macrotask
> e alle invarianti (12 §2.1). È un **artefatto di output** di BOOTSTRAP, NON il
> runtime della skill (12 §1, §4): con la skill presente è la BUILD mode a
> *eseguire* ciò che qui è descritto; senza la skill, questo prompt fa girare la
> stessa disciplina **a mano** (ponte di portabilità cross-tool, `L-COL-009`).
>
> **Parametrizzazione (12 §3).** BOOTSTRAP riempie i placeholder `{{…}}` con gli
> **input dell'utente** e con il blueprint generato, **non** con invenzioni
> dell'LLM (stessa regola di 11 §4). Niente placeholder residuo nell'emesso.

---

## ▶ Prompt da incollare

```
Stai per costruire **{{project_name}}** ({{ecosystem}}; v1: JS/TS + Supabase),
seguendo un metodo blueprint-first con verifica oracle-first. Il PIANO È IL
BLUEPRINT: da qui si scrive codice secondo i task, non si reinventa il design.

PRIMA DI TUTTO — leggi, in quest'ordine:
  1. {{session_state_path}}  → la fonte di verità sullo STATO VIVO del progetto.
     Leggila prima di qualunque azione, sempre.
  2. {{blueprint_location}}  → il PIANO: 00-INDEX (mappa, piano di build, decision
     ledger) + i moduli numerati, ognuno un macrotask coi suoi task atomici. Ogni
     task porta definition_of_done + acceptance_criteria + target_tests (L-COL-019):
     sono questi i criteri contro cui si misura "fatto", non una tua impressione.

DECISIONI BLOCCATE
  Le decisioni di design registrate nel ledger di 00-INDEX sono CHIUSE: si
  modificano solo con un emendamento esplicito registrato nel ledger, mai in
  silenzio. In dubbio, fermati e chiedi (human-in-the-loop), non decidere da solo.

PIANO DI MACROTASK (dal blueprint; rispetta il DAG delle dipendenze):
{{macrotask_plan_with_dependencies}}
  Un macrotask è l'unità al cui confine gira il CHECKPOINT ed è l'unità di commit
  atomico su git. Si parte dai macrotask senza dipendenze aperte.

ECOSISTEMA E POSIZIONI
  • Ecosistema: {{ecosystem}} (v1: JS/TS su Supabase).
  • Blueprint e stato vivo: {{blueprint_location}} / {{session_state_path}}.
  • Baseline e budget: {{baseline_budget_path}}.

INVARIANTI NON NEGOZIABILI (regole della casa per l'intero progetto — 12 §5):
  • ORACLE-AS-JUDGE, MAI LLM-AS-JUDGE (L-COL-002): un task/controllo diventa
    "verde" solo per l'esito di un ORACOLO o di un test, mai perché tu dici "è
    sicuro" o "ho sistemato". Niente auto-assoluzioni.
  • LOOP DI VERIFICA DELLA FIX OBBLIGATORIO (L-COL-003): applica la fix → riesegui
    LO STESSO oracolo che l'ha trovata → riesegui i test → accetta SOLO se il
    finding è sparito E nulla si è rotto. Mai accettare una fix non riverificata.
  • HUMAN-IN-THE-LOOP SULLE FIX; DEAD-CODE MAI CANCELLATO IN AUTONOMIA
    (L-COL-005, L-COL-021): le rimozioni e le decisioni di merito passano
    dall'umano; il dead-code si segnala, non si elimina da soli.
  • GIT A STRATI (L-COL-024, L-COL-025): lavora su BRANCH autonomo; il merge su
    main è GATED dal verde; le operazioni distruttive non sono mai autonome; il
    DEPLOY NON SUPERVISIONATO È BLOCCATO.
  • NESSUN FALSO "VIA LIBERA"; COPERTURA SEMPRE DICHIARATA (L-COL-006): un
    controllo non eseguito NON è un verde; dichiara sempre cosa è stato verificato
    e cosa no. Usa "verificato X" / "il controllo Y è passato", mai "è sicuro".

Conferma di aver letto {{session_state_path}} e il blueprint, riepiloga in poche
righe lo stato e il primo macrotask eseguibile (rispettando il DAG), segnala
incoerenze, e ATTENDI il mio via prima di scrivere codice.
```

---

## Note operative (non incollare)

- **Quando usarlo:** una sola volta, all'avvio. Le sessioni successive aprono con `session-start.md` e chiudono con `session-end.md`.
- **Parametri (12 §3):** `{{project_name}}`, `{{ecosystem}}`, `{{blueprint_location}}`, `{{session_state_path}}`, `{{macrotask_plan_with_dependencies}}`, `{{baseline_budget_path}}` — tutti da input utente / dal blueprint generato, mai inventati.
- **Perché incorpora le invarianti:** il percorso manuale non deve essere una disciplina più debole di quello con la skill (12 §1, invariante del fallback).
