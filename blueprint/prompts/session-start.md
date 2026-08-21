# session-start — prompt di lifecycle (output di BOOTSTRAP)

> Da incollare **all'apertura di ogni sessione di lavoro** (dopo la prima, che usa
> `project-start.md`). Legge `SESSION-STATE`, sceglie il macrotask corrente,
> ripete task/criteri/test, prepara il branch. **Verifica = apple-skills** (00-INDEX §7).

---

## ▶ Prompt da incollare

```
Riprendiamo il lavoro su **Angavu iOS** (swift-ios). Il blueprint è il piano: si
costruisce secondo i task, non si ridiscute il design. Build e verifica sono degli
apple-skills.

1) RECUPERO CONTESTO — leggi PRIMA di qualunque azione:
   • blueprint/SESSION-STATE.md  → stato vivo: macrotask fatti/in corso, baseline,
     budget consumato, stato git, note di carry-over.
   • blueprint/00-INDEX.md + il modulo del macrotask di oggi (01-…11-).

2) SELEZIONA IL MACROTASK CORRENTE rispettando il DAG delle dipendenze:
   foundation → library_index → { dashboard, safety_net, exact_duplicates,
   similar_photos, large_old_media, blurry_photos, video_compression };
   extra_photo_domains e ui_shell come da 00-INDEX §2.
   Scegli il primo macrotask non ancora chiuso le cui dipendenze sono già verdi.
   Non aprire un macrotask le cui dipendenze non sono soddisfatte.

3) RIPETI i task atomici del macrotask scelto. Per ciascuno enuncia, dal blueprint:
   • definition_of_done — gli artefatti osservabili che provano che il lavoro c'è;
   • acceptance_criteria — le asserzioni comportamentali (given/when/then);
   • target_tests — i test (swift test) che rendono eseguibili i criteri.
   Questi target_tests sono l'ORACOLO del controllo di conformità-logica
   (L-COL-019): è contro di loro che si misura "verde", non contro un'impressione.

4) PREPARA IL BRANCH DI LAVORO per questo macrotask. Lavora SU BRANCH, MAI su main.

5) PROMEMORIA: al CONFINE DEL MACROTASK gira la VERIFICA apple-skills
   (swift build -warnings-as-errors, swift test, swiftlint lint --strict, grafo
   moduli SwiftPM per l'altitudine). Il merge su main resta gated dal loro verde.

INVARIANTI NON NEGOZIABILI — per OGNI task:
  • ORACLE-AS-JUDGE, MAI LLM-AS-JUDGE (L-COL-002): "verde" = esito di un comando
    apple-skills o di un test, mai una tua frase.
  • LOOP DI VERIFICA DELLA FIX OBBLIGATORIO (L-COL-003): applica → riesegui lo
    stesso comando/test → accetta SOLO se sparito e nulla rotto.
  • HUMAN-IN-THE-LOOP SULLE FIX; DEAD-CODE MAI CANCELLATO IN AUTONOMIA
    (L-COL-005, L-COL-021).
  • GIT A STRATI (L-COL-024, L-COL-025): branch autonomo, merge su main gated dal
    verde, distruttive mai autonome.
  • PRIVACY & ONESTÀ (baseline iOS): niente dati fuori dal device; required-reason
    API dichiarate; numeri veri con caveat.
  • NESSUN FALSO "VIA LIBERA"; COPERTURA SEMPRE DICHIARATA (L-COL-006).

Posizioni utili: blueprint/00-INDEX.md, blueprint/SESSION-STATE.md,
blueprint/BASELINE-AND-BUDGET.md.

Dopo aver letto SESSION-STATE: dichiara in poche righe lo stato, il macrotask
scelto coi suoi task/criteri/test, il branch preparato, ed eventuali blocchi. Poi
attendi il mio via prima di costruire.
```

---

## Note operative (non incollare)

- **Sempre prima `SESSION-STATE`:** unica fonte di verità tra sessioni; non dare per scontato lo stato a memoria.
- **Il branch, mai main:** base del git a strati; il merge avviene solo sul verde della verifica apple-skills, al confine del macrotask.
