# session-end — prompt di lifecycle (output di BOOTSTRAP)

> Da incollare **alla chiusura di ogni sessione di lavoro**. Verifica che la
> verifica apple-skills sia girata, riassume gli esiti, aggiorna `SESSION-STATE`
> e registra lo stato git. **Verifica = apple-skills** (00-INDEX §7).

---

## ▶ Prompt da incollare

```
Chiudiamo la sessione di lavoro su **Angavu iOS** (swift-ios). Niente nuovo
lavoro: consolida, registra, lascia tutto riprendibile. Il "fatto" si dichiara per
FATTI verificati, mai a sensazione (L-COL-006).

1) VERIFICA AL CONFINE DEL MACROTASK (apple-skills)
   Conferma che la verifica è girata al confine del macrotask e riassumine l'esito
   controllo per controllo: VERDE/ROSSO per ciascuno —
     • swift build -warnings-as-errors  (build pulita)
     • swift test                       (regressione + conformità sui target_tests)
     • swiftlint lint --strict          (stile + dead-code + no-force-unwrap)
     • grafo moduli SwiftPM             (altitudine: domain → data non compila)
     • baseline privacy                 (PrivacyInfo.xcprivacy, usage-description, no-network)
   Il verde è l'esito di un COMANDO o di un test, MAI una tua frase (L-COL-002). Se
   un controllo NON è stato eseguito o è degradato (00-INDEX §7), NON è un verde
   (L-COL-006): dichiaralo non coperto.

2) AGGIORNA blueprint/SESSION-STATE.md (fonte di verità — unico passaggio di
   contesto verso la prossima sessione):
   • Macrotask: fatti / in corso / da fare, rispetto al piano di 00-INDEX §2.
   • Baseline e budget consumato (blueprint/BASELINE-AND-BUDGET.md).
   • Per ogni task chiuso: id, output prodotto, quale comando/test ha prodotto il verde.

3) REGISTRA LO STATO GIT (git a strati — L-COL-024, L-COL-025):
   • Branch di lavoro e commit (con id del task + esito del gate).
   • Stato del merge su main: avvenuto SOLO se la verifica è verde; altrimenti
     SOSPESO. Le operazioni distruttive non sono mai autonome.
   • DEPLOY-COUPLING: distribuzione via App Store Connect (fuori dal repo); nessun
     deploy automatico su push. Mantieni main_deploy_coupled aggiornato.

4) VERIFICA-FIX RIVERIFICATA (L-COL-003)
   Per ogni fix applicata, conferma che è stata riverificata con lo STESSO
   comando/test, e che le rimozioni di dead-code sono passate dall'umano
   (L-COL-005, L-COL-021). Una fix non riverificata non è "fatta".

5) FRAMING ONESTO (L-COL-006)
   Usa "verificato X" / "questi controlli sono passati", MAI "Angavu è
   sicuro/pronto". Dichiara sempre la COPERTURA: cosa è stato verificato e cosa no.

Produci: (a) il riepilogo dei punti 1, 3 e 5; (b) il DIFF preciso che applicherai a
blueprint/SESSION-STATE.md. Applicalo solo dopo la mia conferma, così la prossima
sessione riparte dal macrotask corrente senza ricostruire contesto a memoria.
```

---

## Note operative (non incollare)

- **Perché conferma sul diff di `SESSION-STATE`:** unica fonte di verità tra sessioni; un aggiornamento ottimistico avvelena la sessione successiva.
- **Framing onesto (L-COL-006):** traccia sempre il verde al comando apple-skills che l'ha prodotto; mai un generico "task completato" o "è sicuro".
