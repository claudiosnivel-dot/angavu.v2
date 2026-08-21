# session-start — prompt di lifecycle (output di BOOTSTRAP)

> **Cos'è.** Prompt da incollare **all'apertura di ogni sessione di lavoro**
> (dopo la prima, che usa `project-start.md`). Legge `SESSION-STATE`, sceglie il
> macrotask corrente, ripete task/criteri/test e prepara il branch (12 §2.2).
> Artefatto di output di BOOTSTRAP, non il runtime della skill (12 §4).
>
> **Parametrizzazione (12 §3).** Placeholder `{{…}}` riempiti da BOOTSTRAP con
> input utente + blueprint generato. Niente placeholder residuo nell'emesso.

---

## ▶ Prompt da incollare

```
Riprendiamo il lavoro su **{{project_name}}** ({{ecosystem}}). Il blueprint è il
piano: si costruisce secondo i task, non si ridiscute il design.

1) RECUPERO CONTESTO — leggi PRIMA di qualunque azione:
   • {{session_state_path}}  → fonte di verità sullo stato vivo: macrotask
     fatti/in corso, baseline, budget consumato, stato git, note di carry-over.
   • {{blueprint_location}}  → il piano (00-INDEX + moduli) per il macrotask di oggi.

2) SELEZIONA IL MACROTASK CORRENTE rispettando il DAG delle dipendenze:
{{macrotask_plan_with_dependencies}}
   Scegli il primo macrotask non ancora chiuso le cui dipendenze sono già verdi.
   Non aprire un macrotask le cui dipendenze non sono soddisfatte.

3) RIPETI i task atomici del macrotask scelto. Per ciascuno enuncia, dal blueprint:
   • definition_of_done — gli artefatti osservabili che provano che il lavoro c'è;
   • acceptance_criteria — le asserzioni comportamentali (given/when/then);
   • target_tests — i test che rendono eseguibili i criteri.
   Questi target_tests sono l'ORACOLO del controllo di conformità-logica del
   checkpoint (L-COL-019, 11 §3): è contro di loro che si misura "verde", non
   contro una tua impressione.

4) PREPARA IL BRANCH DI LAVORO per questo macrotask. Lavora SU BRANCH, MAI su main.

5) PROMEMORIA: al CONFINE DEL MACROTASK gira il CHECKPOINT prima di committare.
   Il merge su main resta gated dal verde del checkpoint.

INVARIANTI NON NEGOZIABILI — tienile in testa per OGNI task (12 §5):
  • ORACLE-AS-JUDGE, MAI LLM-AS-JUDGE (L-COL-002): "verde" = esito di un oracolo
    o di un test, mai una tua frase ("è sicuro", "ho sistemato").
  • LOOP DI VERIFICA DELLA FIX OBBLIGATORIO (L-COL-003): applica → riesegui lo
    stesso oracolo → riesegui i test → accetta SOLO se sparito e nulla rotto.
  • HUMAN-IN-THE-LOOP SULLE FIX; DEAD-CODE MAI CANCELLATO IN AUTONOMIA
    (L-COL-005, L-COL-021).
  • GIT A STRATI (L-COL-024, L-COL-025): branch autonomo, merge su main gated dal
    verde, distruttive mai autonome, DEPLOY NON SUPERVISIONATO BLOCCATO.
  • NESSUN FALSO "VIA LIBERA"; COPERTURA SEMPRE DICHIARATA (L-COL-006): un
    controllo non eseguito NON è un verde.

Posizioni utili: blueprint/stato → {{blueprint_location}} / {{session_state_path}};
baseline e budget → {{baseline_budget_path}}.

Dopo aver letto {{session_state_path}}: dichiara in poche righe lo stato, il
macrotask scelto coi suoi task/criteri/test, il branch preparato, ed eventuali
blocchi. Poi attendi il mio via prima di costruire.
```

---

## Note operative (non incollare)

- **Sempre prima `SESSION-STATE`:** è l'unica fonte di verità tra sessioni; non dare per scontato lo stato a memoria.
- **Parametri (12 §3):** `{{project_name}}`, `{{ecosystem}}`, `{{blueprint_location}}`, `{{session_state_path}}`, `{{macrotask_plan_with_dependencies}}`, `{{baseline_budget_path}}`.
- **Il branch, mai main:** è la base del git a strati; il merge avviene solo sul verde del checkpoint, al confine del macrotask.
