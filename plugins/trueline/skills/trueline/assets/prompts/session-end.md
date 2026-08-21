# session-end — prompt di lifecycle (output di BOOTSTRAP)

> **Cos'è.** Prompt da incollare **alla chiusura di ogni sessione di lavoro**.
> Verifica che il checkpoint sia girato, riassume gli esiti, aggiorna
> `SESSION-STATE` e registra lo stato git (12 §2.3). Artefatto di output di
> BOOTSTRAP, non il runtime della skill (12 §4).
>
> **Parametrizzazione (12 §3).** Placeholder `{{…}}` riempiti da BOOTSTRAP con
> input utente + blueprint generato. Niente placeholder residuo nell'emesso.

---

## ▶ Prompt da incollare

```
Chiudiamo la sessione di lavoro su **{{project_name}}** ({{ecosystem}}). Niente
nuovo lavoro: consolida, registra, lascia tutto riprendibile. Il "fatto" si
dichiara per FATTI verificati, mai a sensazione (L-COL-006).

1) CHECKPOINT AL CONFINE DEL MACROTASK
   Conferma che il CHECKPOINT è girato al confine del macrotask e riassumine
   l'esito controllo per controllo: VERDE/ROSSO per ciascun controllo, e il
   fix_state dei finding (verified / mitigated-residual / open). Ricorda: il verde
   è l'esito di un ORACOLO o di un test, MAI una tua frase (L-COL-002, oracle-as-
   judge). Se un controllo NON è stato eseguito, NON è un verde (L-COL-006).

2) AGGIORNA {{session_state_path}}  (è la fonte di verità — l'unico passaggio di
   contesto verso la prossima sessione):
   • Macrotask: fatti / in corso / da fare, rispetto al piano:
{{macrotask_plan_with_dependencies}}
   • Baseline e budget consumato (posizione: {{baseline_budget_path}}).
   • Per ogni task chiuso: id, output prodotto, esito del gate (quale oracolo/test
     ha prodotto il verde).

3) REGISTRA LO STATO GIT (git a strati — L-COL-024, L-COL-025):
   • Branch di lavoro e commit (con id del task + esito del gate).
   • Stato del merge su main: avvenuto SOLO se il checkpoint è verde; altrimenti
     SOSPESO. Le operazioni distruttive non sono mai autonome.
   • DEPLOY-COUPLING: nota se il macrotask tocca aree deploy-sensibili; il deploy
     non supervisionato resta BLOCCATO.

4) VERIFICA-FIX RIVERIFICATA (L-COL-003)
   Per ogni fix applicata in sessione, conferma che è stata riverificata con lo
   STESSO oracolo e con i test, e che le rimozioni di dead-code sono passate
   dall'umano (L-COL-005, L-COL-021). Una fix non riverificata non è "fatta".

5) FRAMING ONESTO (L-COL-006)
   Usa "trovato e verificata la correzione di X" / "questi controlli sono passati",
   MAI "{{project_name}} è sicuro/pronto". Dichiara sempre la COPERTURA: cosa è
   stato verificato e cosa no.

Produci: (a) il riepilogo dei punti 1, 3 e 5; (b) il DIFF preciso che applicherai
a {{session_state_path}}. Applicalo solo dopo la mia conferma, così la prossima
sessione riparte dal macrotask corrente senza ricostruire contesto a memoria.
```

---

## Note operative (non incollare)

- **Perché conferma sul diff di `SESSION-STATE`:** è l'unica fonte di verità tra sessioni; un aggiornamento ottimistico avvelena la sessione successiva.
- **Parametri (12 §3):** `{{project_name}}`, `{{ecosystem}}`, `{{session_state_path}}`, `{{macrotask_plan_with_dependencies}}`, `{{baseline_budget_path}}`.
- **Framing onesto (L-COL-006):** traccia sempre il verde all'oracolo che l'ha prodotto; mai un generico "task completato" o "è sicuro".
