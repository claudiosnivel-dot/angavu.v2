# 08-blurry-photos — Macrotask `blurry_photos`

> Foto sfocate: punteggio nitidezza (Core Image/vImage) + aesthetics score
> (iOS 18, progressive enhancement). Identificatori in inglese, prosa in italiano.

## Obiettivo del macrotask

Segnalare le foto **sfocate** con un punteggio di nitidezza (Core Image/vImage) e,
solo su iOS 18, l'aesthetics/utility score come progressive enhancement — sempre
come **suggerimento**, mai eliminando in autonomia.

## Task atomici

```yaml
- id: T-070
  title: "Punteggio di nitidezza dietro adapter e soglia di sfocatura"
  macrotask: "blurry_photos"
  depends_on: [T-011]

  objective: >
    Esporre, dietro protocollo del Data layer, un punteggio di nitidezza per foto
    (Core Image/vImage) e nel Domain classificare come 'blurry' gli asset sotto una
    soglia configurabile.

  definition_of_done:
    - "Protocollo SharpnessScoring nel Data layer su Core Image/vImage"
    - "Classificazione di dominio blurry/non-blurry per soglia"

  acceptance_criteria:
    - id: AC-070-1
      given: "asset con punteggi di nitidezza noti e soglia fissata"
      when: "si classificano gli asset"
      then: "quelli sotto soglia risultano blurry, quelli sopra soglia no"
    - id: AC-070-2
      given: "un asset esattamente al valore di soglia"
      when: "si classifica l'asset"
      then: "l'esito segue la regola di confine dichiarata (deterministico e documentato)"

  target_tests:
    - file: "Tests/AngavuDomainTests/BlurClassificationTests.swift"
      covers: [AC-070-1, AC-070-2]

  security_notes:
    - "Scoring on-device; nessun pixel lascia il device"

  out_of_scope:
    - "L'aesthetics score iOS 18 (T-071)"

- id: T-071
  title: "Aesthetics score come progressive enhancement iOS 18"
  macrotask: "blurry_photos"
  depends_on: [T-070]

  objective: >
    Su iOS 18, combinare l'aesthetics/utility score (VNCalculateImageAestheticsScoresRequest)
    col punteggio di nitidezza; su iOS 17, degradare al solo punteggio di nitidezza,
    dichiarando l'assenza del termine estetico.

  definition_of_done:
    - "Combinazione nitidezza + aesthetics quando disponibile"
    - "Degradazione a sola nitidezza su iOS 17, marcata come tale"

  acceptance_criteria:
    - id: AC-071-1
      given: "un ambiente con aesthetics disponibile"
      when: "si calcola il punteggio combinato"
      then: "il punteggio include il termine aesthetics oltre alla nitidezza"
    - id: AC-071-2
      given: "un ambiente iOS 17 senza aesthetics"
      when: "si calcola il punteggio"
      then: "usa la sola nitidezza e l'esito è marcato 'senza aesthetics', senza fallire"

  target_tests:
    - file: "Tests/AngavuDomainTests/AestheticsEnhancementTests.swift"
      covers: [AC-071-1, AC-071-2]

  security_notes:
    - "iOS 18 aesthetics come progressive enhancement, mai requisito minimo"

  out_of_scope:
    - "L'eliminazione (macrotask safety_net)"
```

## Nota sulla taglia di riferimento (FSE-C2)

«Sfocato» è un'**euristica alla taglia di decodifica**, non una verità assoluta. La
nitidezza è la varianza del Laplaciano (`SharpnessMetric`) su una griglia 48×48
ricampionata da un originale a taglia `.sharpness` (≈64px, FSE-C1); il suo valore grezzo
è **sensibile alla risoluzione**. La soglia (`BlurThreshold.minimumSharpness` = 0.3)
dichiara perciò la scala a cui è tarata (`referenceLongestSide` = 64). FSE-C1 non ha
cambiato la risoluzione effettiva del kernel — il percorso legacy ricampionava già a
≈64px — quindi 0.3 resta valido; la scala è ora **esplicita e vincolata**, non assunta.
Se la taglia `.sharpness` cambia, la soglia va **ri-tarata e ri-dichiarata**
(oracolo `SharpnessThresholdRetuneTests`), mai ereditata a caso. La distanza semantica
del feature print è invece **invariante alla taglia** (Vision normalizza il descrittore):
`FeaturePrintScaleInvarianceTests` ne prova in CI l'invarianza **relativa** (il feature
print discrimina il contenuto più della scala: `d(A,A') < d(A,A@2x) < d(A,B)`); la parità
di clustering 224px vs full-res su **foto reali** è device-only (§7, nessuna fixture reale).

## Self-check

- **Strutturale**: `validate_blueprint.mjs blueprint` — atteso exit 0.
- **Semantico**: `self-check-checklist.md` punti 6–10 su ogni task.
