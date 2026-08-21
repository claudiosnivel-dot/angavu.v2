# project-start — prompt di lifecycle (output di BOOTSTRAP)

> Da incollare **una volta**, all'avvio del progetto. Orienta l'agente al
> blueprint, alle decisioni bloccate, al piano di macrotask e alle invarianti.
> **Nota di repo (`CLAUDE.md`):** la build e la verifica sono degli **apple-skills**;
> Trueline ha già fatto il suo unico lavoro (questo blueprint). Dove sotto si dice
> "checkpoint/oracolo", si intende la **verifica deterministica apple-skills**
> (`swift build`/`swift test`, SwiftLint, grafo dei moduli SwiftPM — 00-INDEX §7),
> **mai** un checkpoint Trueline.

---

## ▶ Prompt da incollare

```
Stai per costruire **Angavu iOS** (swift-ios: SwiftUI + SwiftData +
PhotoKit/Vision/AVFoundation), con metodo blueprint-first e verifica
oracle-first. Il PIANO È IL BLUEPRINT: si scrive codice secondo i task, non si
reinventa il design. Build e verifica appartengono alla suite apple-skills.

PRIMA DI TUTTO — leggi, in quest'ordine:
  1. blueprint/SESSION-STATE.md  → la fonte di verità sullo STATO VIVO del progetto.
     Leggila prima di qualunque azione, sempre.
  2. blueprint/00-INDEX.md + i moduli numerati 01-…11-  → il PIANO: mappa, piano di
     build, decision ledger, contratto di altitudine, e i macrotask coi loro task
     atomici. Ogni task porta definition_of_done + acceptance_criteria +
     target_tests (L-COL-019): sono questi i criteri contro cui si misura "fatto",
     non una tua impressione.
  3. blueprint/00-INDEX.md §7  → la mappa delle degradazioni degli oracoli: quali
     comandi apple-skills emettono il verdetto per ogni controllo (Swift/iOS non è
     coperto dagli oracoli Trueline JS/TS).

DECISIONI BLOCCATE
  Il decision ledger (00-INDEX §4) è la legge: le decisioni ✅ (DI-001 SwiftUI,
  DI-005 nome Angavu, DI-006 compressione video in v1, DI-007 extra-foto in v1) si
  modificano solo con emendamento esplicito registrato lì. Le 🟡 (DI-002 tutto-free,
  DI-003 iOS 17, DI-004 SwiftData, DI-008 mercati) sono i default assunti in
  BOOTSTRAP: confermale con me prima di darle per chiuse. In dubbio, fermati e
  chiedi (human-in-the-loop), non decidere da solo.

PIANO DI MACROTASK (dal blueprint; rispetta il DAG delle dipendenze):
  foundation
    └─ library_index
         ├─ dashboard
         ├─ safety_net            (rete di sicurezza — intoccabile)
         ├─ exact_duplicates
         ├─ similar_photos
         ├─ large_old_media
         ├─ blurry_photos
         └─ video_compression     (DI-006 — primo candidato al de-scope)
    └─ extra_photo_domains         (DI-007)
    └─ ui_shell                    (onboarding-manifesto + report onesto)
  Si parte da foundation (nessuna dipendenza aperta). Un macrotask è l'unità al cui
  confine gira la VERIFICA apple-skills ed è l'unità di commit atomico su git.

VERIFICA E POSIZIONI
  • Verifica (apple-skills): swift build -warnings-as-errors, swift test,
    swiftlint lint --strict, grafo moduli SwiftPM (altitudine). Soglie in
    blueprint/BASELINE-AND-BUDGET.md.
  • Blueprint e stato vivo: blueprint/00-INDEX.md / blueprint/SESSION-STATE.md.
  • Baseline privacy e budget: blueprint/BASELINE-AND-BUDGET.md.

INVARIANTI NON NEGOZIABILI (regole della casa per l'intero progetto):
  • ORACLE-AS-JUDGE, MAI LLM-AS-JUDGE (L-COL-002): un task/controllo diventa
    "verde" solo per l'esito di un comando apple-skills o di un test, mai perché tu
    dici "è sicuro" o "ho sistemato". Nessun checkpoint Trueline come gate.
  • LOOP DI VERIFICA DELLA FIX OBBLIGATORIO (L-COL-003): applica la fix → riesegui
    LO STESSO comando/test che l'ha trovata → accetta SOLO se il problema è sparito
    E nulla si è rotto.
  • HUMAN-IN-THE-LOOP SULLE FIX; DEAD-CODE MAI CANCELLATO IN AUTONOMIA
    (L-COL-005, L-COL-021).
  • GIT A STRATI (L-COL-024, L-COL-025): lavora su BRANCH; il merge su main è GATED
    dal verde apple-skills; le distruttive non sono mai autonome.
  • PRIVACY & ONESTÀ (baseline iOS): nessun dato lascia il device; required-reason
    API in PrivacyInfo.xcprivacy; numeri veri con caveat (iCloud/limited), mai un
    numero gonfiato o un claim impossibile. È anche conformità App Store.
  • NESSUN FALSO "VIA LIBERA"; COPERTURA SEMPRE DICHIARATA (L-COL-006): un
    controllo non eseguito NON è un verde; dove un oracolo degrada (00-INDEX §7),
    dichiaralo non coperto.

Conferma di aver letto SESSION-STATE e il blueprint, riepiloga in poche righe lo
stato e il primo macrotask eseguibile (foundation), segnala incoerenze, e ATTENDI
il mio via prima di scrivere codice.
```

---

## Note operative (non incollare)

- **Quando usarlo:** una sola volta, all'avvio. Le sessioni successive aprono con `session-start.md` e chiudono con `session-end.md`.
- **Perché "apple-skills" e non "Trueline":** policy di repo (`CLAUDE.md`). Trueline ha prodotto solo il piano; ogni verifica/build/review è degli apple-skills, con verdetto di un oracolo deterministico della toolchain Apple.
