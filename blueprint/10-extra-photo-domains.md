# 10-extra-photo-domains — Macrotask `extra_photo_domains`

> Contatti duplicati (Contacts), calendari-spam (EventKit). `DI-007`: dominio
> extra-foto in v1. Indipendente dal cuore-foto. Identificatori in inglese, prosa
> in italiano.

## Obiettivo del macrotask

Estendere l'onestà di Angavu a due domini extra-foto legittimi: **contatti
duplicati** (merge suggerito, mai automatico) e **calendari-spam** (sottoscrizioni
indesiderate), ciascuno con permesso dedicato e dichiarato, e nessuna azione
distruttiva senza conferma.

## Task atomici

```yaml
- id: T-090
  title: "Rilevamento contatti duplicati dietro adapter Contacts"
  macrotask: "extra_photo_domains"
  depends_on: [T-001]

  objective: >
    Enumerare i contatti via adapter su Contacts e nel Domain individuare i
    duplicati (per nome normalizzato + numero/email condivisi), proponendo cluster
    di merge senza fondere in autonomia.

  definition_of_done:
    - "Protocollo ContactsProviding nel Data layer su Contacts"
    - "Regola di dominio che raggruppa i contatti duplicati in cluster di merge"
    - "NSContactsUsageDescription presente e sincera"

  acceptance_criteria:
    - id: AC-090-1
      given: "contatti con due voci stesso nome e stesso numero e una distinta"
      when: "si calcolano i cluster di duplicati"
      then: "le due voci coincidenti formano un cluster, la terza resta fuori"
    - id: AC-090-2
      given: "un cluster di contatti duplicati"
      when: "si genera la proposta di merge"
      then: "la proposta è dati (nessun contatto fuso automaticamente)"

  target_tests:
    - file: "Tests/AngavuDomainTests/DuplicateContactsTests.swift"
      covers: [AC-090-1, AC-090-2]

  security_notes:
    - "NSContactsUsageDescription sincera; required-reason API dichiarate; nessun contatto lascia il device"
    - "Merge mai automatico: azione distruttiva human-gated"

  out_of_scope:
    - "Calendari-spam (T-091)"

- id: T-091
  title: "Rilevamento calendari-spam dietro adapter EventKit"
  macrotask: "extra_photo_domains"
  depends_on: [T-001]

  objective: >
    Enumerare i calendari sottoscritti via adapter su EventKit e nel Domain marcare
    quelli 'spam' (sottoscritti, non locali, con euristica di sospetto), proponendo
    la rimozione della sottoscrizione senza rimuovere in autonomia.

  definition_of_done:
    - "Protocollo CalendarsProviding nel Data layer su EventKit"
    - "Regola di dominio che marca i calendari sottoscritti sospetti"
    - "NSCalendarsFullAccessUsageDescription presente e sincera"

  acceptance_criteria:
    - id: AC-091-1
      given: "calendari locali e calendari sottoscritti che soddisfano l'euristica spam"
      when: "si calcola la lista dei calendari-spam"
      then: "contiene solo i sottoscritti sospetti, mai i calendari locali dell'utente"
    - id: AC-091-2
      given: "un calendario-spam individuato"
      when: "si genera la proposta di rimozione"
      then: "la proposta è dati (nessuna sottoscrizione rimossa automaticamente)"

  target_tests:
    - file: "Tests/AngavuDomainTests/SpamCalendarsTests.swift"
      covers: [AC-091-1, AC-091-2]

  security_notes:
    - "NSCalendarsFullAccessUsageDescription sincera; required-reason API dichiarate; nessun dato calendario lascia il device"
    - "Rimozione sottoscrizione mai automatica: azione distruttiva human-gated"

  out_of_scope:
    - "L'applicazione di merge/rimozione confermati (T-092)"

- id: T-092
  title: "Applicazione confermata di merge contatti e rimozione calendari"
  macrotask: "extra_photo_domains"
  depends_on: [T-090, T-091]

  objective: >
    Applicare le azioni extra-foto (merge contatti, rimozione sottoscrizione
    calendario) solo dopo conferma esplicita dell'utente, con esito onesto e
    reversibilità dove la piattaforma la consente.

  definition_of_done:
    - "Flusso di conferma esplicita prima di ogni merge/rimozione"
    - "Esito riportato per ogni azione (applicata | annullata | fallita)"

  acceptance_criteria:
    - id: AC-092-1
      given: "una proposta di merge contatti senza conferma"
      when: "si tenta di applicarla"
      then: "l'applicazione è rifiutata finché la conferma non è data"
    - id: AC-092-2
      given: "una proposta di rimozione calendario confermata, con adapter che riporta success"
      when: "si applica l'azione"
      then: "la sottoscrizione è rimossa e l'esito è 'applicata'"

  target_tests:
    - file: "Tests/AngavuDomainTests/ExtraDomainApplyTests.swift"
      covers: [AC-092-1, AC-092-2]

  security_notes:
    - "Ogni azione distruttiva è human-gated con conferma esplicita (L-COL-005)"

  out_of_scope:
    - "Rendering delle schermate (macrotask ui_shell)"
```

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
