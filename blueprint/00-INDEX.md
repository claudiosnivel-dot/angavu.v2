# 00-INDEX — Blueprint di Angavu iOS

> Indice del blueprint tecnico (mappa dei moduli, piano di build, decision ledger,
> contratto di altitudine). Generato da **Trueline BOOTSTRAP** su
> [`docs/FEASIBILITY-iOS.md`](../docs/FEASIBILITY-iOS.md). **Policy di repo**
> (`CLAUDE.md`): Trueline disegna **solo il piano**; **tutta la build e tutta la
> verifica** appartengono alla suite **apple-skills**. Schema dei task:
> `references/blueprint/atomic-task-schema.md` (`L-COL-019`).

| | |
|---|---|
| **Progetto** | Angavu iOS — cleaner onesto per la libreria foto/video |
| **Ecosistema** | **swift-ios** (SwiftUI + SwiftData + PhotoKit/Vision/AVFoundation) — **non** coperto dagli oracoli Trueline JS/TS: vedi §7 (mappa delle degradazioni) |
| **Obiettivo** | Portare la *promessa* di Angavu (offline, no ads, numeri veri, rete di sicurezza, no backend) sul sottoinsieme che iOS permette davvero, fatto meglio dei competitor |
| **Owner** | claudiosnivel-dot (solo dev, ~3 h/settimana) |

---

## 1. Mappa dei moduli

| File | Macrotask | Contenuto |
|---|---|---|
| `01-foundation.md` | `foundation` | Scaffold multi-modulo (SwiftPM + app Xcode), oracoli deterministici della toolchain Apple, Domain puro + motore d'analisi cancellabile, privacy manifest e usage-description, target iOS 17 |
| `02-library-index.md` | `library_index` | PhotoKit: permessi (full/limited/denied), enumerazione `PHAsset`, indice **SwiftData** incrementale, osservazione cambi libreria, **byte reali** per asset |
| `03-dashboard.md` | `dashboard` | Dashboard numeri veri con **caveat iCloud**, distinzione "spazio libreria" vs "spazio device liberato ora", banner accesso `limited` |
| `04-exact-duplicates.md` | `exact_duplicates` | Duplicati esatti: SHA-256 sui candidati raggruppati per dimensione, cluster nel Domain puro |
| `05-similar-photos.md` | `similar_photos` | Foto simili: `VNGenerateImageFeaturePrintRequest` + `computeDistance` → cluster; dHash come fallback; "**tieni la migliore**" |
| `06-safety-net.md` | `safety_net` | Rete di sicurezza: **anteprima obbligatoria** prima di eliminare, `deleteAssets` → "Eliminati di recente" (recupero di sistema ~30 gg) |
| `07-large-old-media.md` | `large_old_media` | Video grandi/vecchi ordinati per dimensione/età; screenshot e screen recording in blocco |
| `08-blurry-photos.md` | `blurry_photos` | Foto sfocate: punteggio nitidezza (Core Image/vImage) + aesthetics score (iOS 18, progressive enhancement) |
| `09-video-compression.md` | `video_compression` | Compressione video **HEVC** on-device (`AVAssetExportSession`), opt-in, metadati (data/luogo) preservati. `DI-006`: primo candidato al de-scope |
| `10-extra-photo-domains.md` | `extra_photo_domains` | Contatti duplicati (`Contacts`), calendari-spam (`EventKit`). `DI-007`: dominio extra-foto |
| `11-ui-shell.md` | `ui_shell` | Onboarding-manifesto, schermata "cosa **NON** facciamo", report onesto |
| `12-wiring.md` | `wiring` | **Aggiunto con `DI-009`**: cablaggio dati — composition root, flusso di scansione, schermate cuore-foto/dashboard/report/extra-foto guidate dai dati veri, eliminazione via `safety_net` |

## 1bis. Contratto di altitudine (abilita l'oracolo di altitudine in BUILD)

Strati architetturali (spirito del blueprint Android: il **Domain non dipende
dalla piattaforma**) e dipendenze **vietate** fra strati. `validate_blueprint`
ne valida la forma; in BUILD l'oracolo di altitudine (grafo dei moduli SwiftPM,
§7) verifica le regole `forbidden` come **gate assoluto**. La regola-killer è
`domain → data`: la logica di cluster/scelta/eliminazione **non** importa
PhotoKit/Vision/AVFoundation, così è testabile senza device.

```yaml
architecture:
  layers:
    domain:  "Sources/AngavuDomain/**"
    data:    "Sources/AngavuData/**"
    feature: "Sources/AngavuFeatures/**"
    app:     "App/**"
  forbidden:
    - { from: domain, to: data }
    - { from: domain, to: feature }
    - { from: domain, to: app }
    - { from: data, to: feature }
    - { from: data, to: app }
    - { from: feature, to: app }
```

## 2. Piano di build (ordine dei macrotask)

Ordine derivato dal DAG dei task (`depends_on`). `foundation` non ha dipendenze
aperte e parte per primo; `library_index` è il tronco su cui poggia tutto il
cuore-foto; `safety_net` è la capacità di eliminazione condivisa che i rilevatori
consumano.

```
foundation
  └─ library_index
       ├─ dashboard
       ├─ safety_net
       ├─ exact_duplicates      (elimina via safety_net)
       ├─ similar_photos        (elimina via safety_net)
       ├─ large_old_media       (elimina via safety_net)
       ├─ blurry_photos         (elimina via safety_net)
       └─ video_compression     (DI-006 — primo de-scope)
  └─ extra_photo_domains        (DI-007 — indipendente dal cuore-foto)
  └─ ui_shell                   (onboarding + report, trasversale)
       └─ wiring                (DI-009 — cablaggio dati: integra tutto in UEE navigabile)
```

> **`wiring` (`DI-009`)** è a valle di tutto il piano di build (dipende da
> `library_index`, dai rilevatori, da `safety_net` e da `ui_shell`): non aggiunge
> logica nuova, collega quella esistente a schermate coi dati veri. Vedi `12-wiring.md`.

I macrotask senza dipendenze aperte possono partire per primi; ogni macrotask si
chiude al suo confine con la verifica **apple-skills** (build/test/lint verdi, §7)
prima del commit atomico.

## 3. Aggancio alla sicurezza & privacy (baseline iOS)

I macrotask che toccano dati sensibili — `library_index`, `safety_net`,
`extra_photo_domains` (foto, contatti, calendario) — portano la baseline
privacy iOS al posto della baseline RLS/Supabase (§7): **required-reason API**
dichiarate in `PrivacyInfo.xcprivacy`, `NS…UsageDescription` sincere e minime,
**nessun dato lascia il device** (zero rete/telemetria), eliminazioni sempre
verso la rete di sicurezza di sistema. Le `security_notes` dei task nominano
queste voci per nome.

## 4. Decision ledger

| ID | Decisione | Stato |
|---|---|---|
| `DI-001` | Tecnologia: **SwiftUI nativo** | ✅ confermato dall'utente |
| `DI-002` | v1 **tutto-free**, Pro (pagamento unico) rimandato | ✅ confermato dall'utente |
| `DI-003` | iOS minimo **17.0** (iOS 18 aesthetics come progressive enhancement) | ✅ confermato dall'utente |
| `DI-004` | Persistenza indice: **SwiftData** (vs Core Data) | ✅ confermato dall'utente |
| `DI-005` | Nome/brand su App Store: **Angavu** | ✅ confermato dall'utente |
| `DI-006` | **Compressione video in v1** (primo candidato al de-scope sotto slittamento estremo) | ✅ confermato dall'utente |
| `DI-007` | **Dominio extra-foto (contatti + calendario) in v1** | ✅ confermato dall'utente |
| `DI-008` | Mercati di lancio: Italia soft-launch → EN → ES/PT/DE | ✅ confermato dall'utente |
| `DI-009` | Aggiunto macrotask **`wiring`** (cablaggio dati) dopo il piano di build 11/11: schermate + report sui dati veri, oltre il piano originale | ✅ confermato dall'utente |

> Tutte le decisioni sono ora **bloccate** (`✅`): `DI-002/003/004/008`, assunte
> come default in BOOTSTRAP, sono state confermate dall'utente; `DI-009` aggiunge
> il macrotask `wiring` su richiesta dell'utente. Una decisione bloccata si
> modifica **solo** con emendamento esplicito registrato qui.

## 5. Fonti di verità

- **Piano**: questo blueprint (`00-INDEX` + moduli numerati `01-…11-`).
- **Stato vivo**: `blueprint/SESSION-STATE.md`.
- **Baseline / budget**: `blueprint/BASELINE-AND-BUDGET.md`.
- **Prompt di lifecycle** (artefatti di output): `blueprint/prompts/`.

## 6. Self-check del blueprint

- **Strutturale** (oracolo, deterministico):
  `node plugins/trueline/skills/trueline/scripts/blueprint/validate_blueprint.mjs blueprint`
  — atteso **exit 0** (campi obbligatori, copertura AC→test, DAG aciclico, id
  univoci, ownership macrotask, contratto di altitudine ben formato).
- **Semantico** (checklist guidata, punti 6–10):
  `references/blueprint/self-check-checklist.md` — i rilievi vanno all'utente
  (human-in-the-loop, `L-COL-005`).

## 7. Mappa delle degradazioni degli oracoli (Swift/iOS ≠ ecosistema JS/TS)

Trueline v1 copre JS/TS su Supabase; **Swift/iOS non è coperto** (come Kotlin/
Android non lo era). Per la policy di repo (`CLAUDE.md`) questo **non** è un
problema di verifica: la build e la verifica sono degli **apple-skills**, non di
Trueline. Qui si dichiara — onestamente, `L-COL-006` — la sostituzione
deterministica di ogni oracolo, così che "verde" resti un **fatto di comando**
prodotto dalla toolchain Apple, mai una frase dell'LLM né un checkpoint Trueline.

| Oracolo Trueline (JS/TS) | Stato su Swift/iOS | Sostituzione deterministica (apple-skills) |
|---|---|---|
| `run_semgrep` + ruleset injection/authz | **non applicabile** | SwiftLint + regole `apple-skills` (privacy/required-reason API, no-force-unwrap in path critici) su `swift build` pulito |
| `rls_check` (RLS Supabase) | **non applicabile** (zero backend) | Baseline privacy iOS: `PrivacyInfo.xcprivacy` con required-reason API, `NS…UsageDescription`, oracolo "nessun simbolo di rete/telemetria" |
| `run_gitleaks` (secret) | **applicabile in spirito** | Scan segreti su repo (nessun keystore/credenziale nel sorgente); Apple Developer signing fuori dal repo |
| `run_osv` (dependency-vuln) | **degradato** | Dipendenze minime (framework di sistema); SwiftPM `Package.resolved` audit manuale delle poche dipendenze |
| `run_deadcode` (knip) | **sostituito** | `swift build -warnings-as-errors` + regola SwiftLint dead-code / unused |
| Oracolo di regressione (test suite) | **sostituito** | `swift test` (Domain puro + adapter con fake) come oracolo di regressione |
| Oracolo di conformità-logica (`target_tests`) | **conservato** | `swift test` sui `target_tests` dei task; AC valutati dai test XCTest |
| Oracolo di altitudine (madge, grafo import JS) | **sostituito** | Grafo dei moduli **SwiftPM** come oracolo di altitudine: una dipendenza `domain → data` **rompe la build** (target separati, nessun import possibile) |

**Framing onesto (`L-COL-006`).** Dove un oracolo degrada a "non eseguito", il
controllo va **dichiarato non coperto**, mai riempito con un verde finto. La
suite apple-skills possiede il verdetto; questo blueprint fissa solo *quali*
comandi deterministici lo emettono.
