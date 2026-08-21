# Angavu iOS — Documento di Fattibilità e Strategia

> Nome di lavoro: **Angavu** (iOS). Documento strategico d'ingresso — l'analogo
> di `reportangavu.md` per l'Android. Non è ancora il blueprint: è l'input da cui
> Trueline **BOOTSTRAP** genererà il blueprint tecnico (task atomici + oracoli).
> Fonte: il repo Android [`angavu`](https://github.com/claudiosnivel-dot/angavu)
> (README, `blueprint/VISION-AND-CONSTRAINTS.md`, `blueprint/00-INDEX.md`) e la
> conoscenza delle API Apple. Dove il salto a iOS cambia una decisione, è
> registrata nel decision ledger (§9), da confermare.

| | |
|---|---|
| **Progetto** | Angavu iOS — cleaner onesto per la libreria foto/video |
| **Relazione con l'Android** | Prodotto **gemello**, non port 1:1 |
| **Piattaforma** | iOS nativo, **SwiftUI** (deciso `DI-001`) |
| **Owner** | claudiosnivel-dot (solo dev, ~3 h/settimana) |
| **Backend** | Zero. Tutto on-device, come l'Android |

---

## 1. La tesi

Il cleaner Android di Angavu nasce contro una categoria piena di truffe
(numeri gonfiati, scare tactics, ads dopo il pagamento). **Su iOS la categoria è
peggiore**: abbonamenti predatori (5–10 $ a *settimana*), "128 GB di junk
trovati!" falsi, rilevamento foto-simili rozzo, e purghe periodiche di Apple.

Lo stesso manifesto di Angavu — *offline, no ads, numeri veri, rete di sicurezza,
Pro a pagamento unico* — è ancora più dirompente su iOS, perché lì nessuno lo
rispetta. La strategia non è portare l'app: è portare **la promessa**, sul
sottoinsieme che iOS permette davvero, fatto meglio di chiunque.

## 2. La realtà della piattaforma iOS

iOS ha un sandbox molto più rigido di Android. Un'app **non** può:

- accedere a file, cache o storage di **altre app** (il "junk di sistema" non
  esiste come concetto accessibile — chi promette di pulirlo mente);
- vedere un file system generale come lo `SAF` di Android su cartelle arbitrarie;
- mettere file qualsiasi in un "cestino di sistema" applicativo.

Un'app **può**, con permesso dell'utente, operare su tre domini utili:

| Dominio | Framework | Cosa consente |
|---|---|---|
| **Libreria foto/video** | PhotoKit (`Photos`, `PhotosUI`) | Enumerare asset con metadati veri, analizzarne i pixel on-device, eliminarli (con conferma di sistema, verso "Eliminati di recente") |
| **Contatti** | `Contacts` | Duplicati, contatti incompleti, merge |
| **Calendario** | `EventKit` | Eventi vecchi, calendari-spam sottoscritti |

Più due leve di **recupero spazio reale** senza cancellare nulla:

| Leva | Framework | Effetto |
|---|---|---|
| **Compressione video** | `AVFoundation` (`AVAssetExportSession`, HEVC) | Ricodifica on-device → megabyte veri liberati |
| **Analisi & suggerimento** | Vision, Core Image | Trova cosa vale la pena eliminare, non elimina da solo |

## 3. Mappa feature-per-feature: Android → iOS

Legenda: 🟢 portabile · 🟡 sostituibile con equivalente iOS · 🔴 impossibile su iOS.

| Feature Android (macrotask) | iOS | Come, su iOS |
|---|---|---|
| Scansione **MediaStore** di tutto lo storage (`media_index`) | 🟡 | Solo libreria foto/video via **PhotoKit** (`PHAsset`), non tutto il file system |
| Indice **Room** incrementale | 🟢 | Indice locale in **SwiftData**/Core Data, aggiornato via `PHPhotoLibraryChangeObserver` |
| **Duplicati esatti** SHA-256 (`duplicates`) | 🟢 | Hash dei dati immagine (SHA-256) sui candidati per dimensione — stessa logica |
| **Foto simili** dHash/Hamming (`similar_photos`) | 🟢➕ | **Migliorabile**: `VNGenerateImageFeaturePrintRequest` + `computeDistance` → similarità *semantica*, superiore al dHash. dHash resta fallback economico |
| "**Tieni la migliore**" | 🟢➕ | Punteggio per nitidezza (Core Image/vImage), qualità volti e (iOS 18+) `VNCalculateImageAestheticsScoresRequest` |
| **Video grandi e vecchi** (`junk_large`) | 🟢 | `PHAsset` video ordinati per dimensione/età |
| **Screenshot / screen recording** | 🟢 | `mediaSubtype .photoScreenshot`; screen recording via euristica |
| **Cestino di sistema** recuperabile (`trash`) | 🟡 | Non serve costruirlo: `deleteAssets` manda in **"Eliminati di recente"** (recupero ~30 gg, fornito da iOS). La rete di sicurezza è di sistema |
| **Anteprima obbligatoria** prima di eliminare | 🟢 | Gate identico nostro, prima della conferma di sistema |
| **Junk sicuro / cache app / file temporanei** | 🔴 | Impossibile: nessun accesso fuori dal sandbox. **Da dichiarare apertamente** |
| Media **WhatsApp/Telegram** via cartella | 🔴 | Le cartelle di altre app non sono accessibili. (I media *salvati nella libreria foto* sì, ma non "la cartella di WhatsApp") |
| **Cartelle extra via SAF** | 🔴 | Nessun equivalente per lo storage di sistema. Solo document picker per-file, non bulk |
| **"Esplora file"** filtrabile (`field_fixes_4`) | 🟡 | Solo sulla libreria foto/video: lista filtrabile per tipo/fonte/dimensione/età |
| **Dashboard numeri veri** (`dashboard`) | 🟢 | Byte reali per asset, con il caveat iCloud dichiarato (§6) |
| **Onboarding col manifesto / "cosa non facciamo"** (`ui_shell`) | 🟢 | Identico, e su iOS ancora più forte come segnale di fiducia |
| Lezioni field-fix (onda parallela, low-RAM, no-crash `Failed`, stop cooperativo) | 🟢 | Si trasferiscono **concettualmente** all'analisi di librerie enormi via PhotoKit |

**Leve nuove, native iOS** (non esistono nell'Android, aggiungono valore):

| Feature | Framework | Nota |
|---|---|---|
| **Compressione video** HEVC | AVFoundation | Spazio vero senza cancellare. I competitor la mettono dietro paywall |
| **Foto sfocate / duplicati di scatto** | Vision, Core Image | Vision aesthetics/utility score (iOS 18+) |
| **Contatti duplicati** | Contacts | Dominio extra-foto, utile e legittimo |
| **Calendari-spam** | EventKit | Rimozione sottoscrizioni indesiderate |

## 4. Dove i competitor falliscono → i differenziatori di Angavu

| Debolezza diffusa su iOS | Mossa di Angavu |
|---|---|
| Numeri gonfiati / "junk" inventato | **Byte reali**; onestà sul caveat iCloud; mai un numero finto |
| "Puliamo la cache di sistema!" (falso) | **Dire la verità**: su iOS non è toccabile. L'onestà *è* il marketing e *è* conformità App Store |
| Foto simili con dHash rozzo | **Vision feature print** (similarità semantica) + dHash come fallback |
| "Tieni la migliore" arbitraria | Scelta per **nitidezza + qualità volti + estetica** |
| Abbonamento settimanale predatorio | **Pro a pagamento unico** (non-consumable StoreKit 2), come `D-002` Android |
| Ads, scare tactics, notifiche promo | Nessuna. Come i non-goals Android |
| Dati inviati a server | **Zero backend**, tutto on-device: segnale di privacy forte |

Due differenziatori **tecnici** che gli altri non hanno: rilevamento *semantico*
(Vision) e **onestà radicale** sui limiti della piattaforma.

## 5. Feature set proposto — v1 iOS (massimo fattibile)

Ordinato per valore/rischio. Il taglio se il piano slitta parte **dal basso**;
il cuore foto e la rete di sicurezza sono **intoccabili** (come il cestino
nell'Android).

1. **Indice libreria** (PhotoKit → SwiftData) + **dashboard numeri veri** con caveat iCloud
2. **Duplicati esatti** (SHA-256 sui candidati per dimensione)
3. **Foto simili** (Vision feature print → cluster → "tieni la migliore")
4. **Rete di sicurezza**: anteprima obbligatoria + eliminazione verso "Eliminati di recente"
5. **Video grandi / vecchi** + **screenshot / screen recording** in blocco
6. **Foto sfocate** (nitidezza / aesthetics score)
7. **Compressione video** HEVC on-device — **in v1** (`DI-006`); la feature più a rischio tecnico, quindi primo candidato al de-scope solo sotto slittamento estremo
8. **Contatti duplicati** e **calendari-spam** — **in v1** (`DI-007`, dominio extra-foto)
9. **Onboarding-manifesto** + schermata "cosa NON facciamo" + report onesto

**Fuori dalla v1 (non-goal, §7):** Pro/IAP, iCloud sync, vault cifrato, widget,
Shortcuts/App Intents, macOS/iPadOS dedicati.

## 6. Rischi tecnici e mitigazioni

| Rischio | Perché | Mitigazione |
|---|---|---|
| **iCloud "ottimizza spazio"** | Se attivo, l'originale è in cloud: eliminare libera iCloud, non subito il device | Dichiararlo nel report onesto; distinguere "spazio libreria" da "spazio device liberato ora"; mai promettere GB locali che non si liberano |
| **Byte reali per asset** | Il size esatto non è esposto in modo pulito da PhotoKit | Validare la strada `PHAssetResource` in BOOTSTRAP; se degradata, dichiarare stima e marcarla, mai spacciare stima per esatto |
| **Accesso limitato alla libreria** (iOS 14+) | L'utente può concedere solo alcune foto | Gestire `limited` con grazia: banner "abilita accesso completo per un conteggio reale"; mai un numero parziale spacciato per totale |
| **Librerie enormi** (20k+ asset) | Hashing + Vision sono costosi | Riuso delle lezioni Android: analisi a blocchi, fuori dal main, progress onesto, **stop cooperativo**, dieta low-RAM, esito `Failed` visibile mai eterno "0%" |
| **Compressione video** | Ricodifica lunga, qualità/spazio da bilanciare, rischio perdita metadati | In v1 (`DI-006`), ma isolata e opt-in; `AVAssetExportSession` con preset HEVC; conservare data/luogo; **primo candidato al de-scope** solo sotto slittamento estremo |
| **Review App Store (categoria sorvegliata)** | Guideline 2.3.x: niente claim ingannevoli, niente scare tactics | L'onestà è nativa: nessun claim falso, permessi minimi, `NSPhotoLibraryUsageDescription` sincera. Rischio basso proprio grazie al manifesto |
| **Eliminazione** | Ogni delete apre un alert di sistema (non silenziabile) | È coerente con la rete di sicurezza: un solo alert copre un batch; l'anteprima nostra precede l'alert |

## 7. Non-goals (il manifesto, portato su iOS)

- **Pulizia "cache di sistema / file temporanei / junk di altre app"** — impossibile su iOS. Non si simula, si dichiara.
- **RAM/CPU/battery booster** — placebo, come nell'Android.
- **"Antivirus"** — non fattibile in solo + budget zero.
- **Ads, notifiche promo, scare tactics, numeri gonfiati** — mai.
- **Backend / sync cloud** — zero server, tutto on-device.
- **IAP / Angavu Pro** — fuori dalla v1 (`DI-002`): si lancia tutto-free, il Pro arriva dopo *aggiungendo sopra*, mai togliendo.
- **Vault cifrato, widget, App Intents/Shortcuts, versioni iPad/macOS dedicate** — v2+.

## 8. Vincoli

| Tipo | Vincolo |
|---|---|
| Ecosistema | Swift + SwiftUI nativo; **zero backend** |
| iOS minimo | **iOS 17.0** proposto (`DI-003`) — copre la stragrande maggioranza dei device 2026 e semplifica Vision/SwiftData; iOS 18 aesthetics come *progressive enhancement* |
| Permessi | `NSPhotoLibraryUsageDescription` (foto), e solo se le feature entrano: `NSContactsUsageDescription`, `NSCalendarsUsageDescription`. Niente permesso non usato |
| Privacy | Nessun dato lascia il device; **PrivacyInfo.xcprivacy** con required-reason API dichiarate; nessun tracking |
| Dimensione app | Snella: Vision è di sistema, **nessun modello Core ML bundolato** → app piccola, coerente con l'ethos "<15 MB" dell'Android |
| Sicurezza | Nessun segreto nel sorgente; keystore/credenziali fuori dal repo |
| Tempo | ~3 h/settimana. Scope rigido: rete di sicurezza e cuore foto intoccabili; se il piano slitta, il de-scope parte dalle leve più a rischio (compressione video) |
| Budget | 99 $/anno Apple Developer Program (ricorrente, **unico costo nuovo** vs Android). Nessun costo di runtime |
| App Store policy | Categoria sorvegliata: niente claim su boost/velocità/virus, permessi minimi, scheda onesta |

> **Nota budget.** A differenza dei 25 $ una-tantum di Google Play, Apple chiede
> 99 $/anno. È l'unica voce di costo strutturalmente nuova del progetto iOS.

## 9. Decision ledger (da confermare)

| ID | Decisione | Stato |
|---|---|---|
| `DI-001` | Tecnologia: **SwiftUI nativo** (no cross-platform: la logica riusabile Android è minima, il grosso è API di piattaforma) | ✅ confermato dall'utente |
| `DI-002` | v1 **tutto-free**, Pro (pagamento unico) rimandato — come `D-002` Android | 🟡 proposto |
| `DI-003` | iOS minimo **17.0** | 🟡 proposto |
| `DI-004` | Persistenza indice: **SwiftData** (vs Core Data) | 🟡 proposto |
| `DI-005` | Nome/brand su App Store: **Angavu** | ✅ confermato dall'utente |
| `DI-006` | **Compressione video in v1** (feature più a rischio tecnico: primo candidato al de-scope solo sotto slittamento estremo) | ✅ confermato dall'utente |
| `DI-007` | **Dominio extra-foto (contatti + calendario) in v1** | ✅ confermato dall'utente |
| `DI-008` | Mercati di lancio: Italia soft-launch → EN → ES/PT/DE (come Android)? | 🟡 proposto |

## 10. Architettura proposta (bozza)

Multi-modulo per altitudine, sullo spirito del blueprint Android (il dominio non
dipende dalla piattaforma):

```
App (SwiftUI)               UI, navigazione, onboarding-manifesto
  └─ Feature/*              schermate: Duplicati, Foto simili, Video, Esplora, Cestino
       └─ Domain            modelli e regole pure (cluster, "tieni la migliore", policy di eliminazione)  ← nessuna dipendenza da PhotoKit
            └─ Data         PhotoKit (PHAsset), SwiftData (indice), Vision/CoreImage (analisi), AVFoundation (compressione)
```

- **Domain puro**: la logica di clustering/scelta/eliminazione non importa
  PhotoKit → testabile senza device, e altitudine imposta come nell'Android
  (una dipendenza proibita rompe la build).
- **Data**: adapter attorno a PhotoKit, Vision, AVFoundation; l'indice in
  SwiftData con osservazione dei cambi libreria.
- **Analisi** come pipeline cancellabile (stop cooperativo) fuori dal main.

## 11. Prossimi passi

1. Decisioni di scope chiuse (`DI-005` Angavu, `DI-006` compressione video in v1,
   `DI-007` extra-foto in v1). Restano da confermare solo le proposte `DI-002/003/004/008`,
   che il BOOTSTRAP può assumere come default e registrare.
2. **Trueline BOOTSTRAP** (prossima sessione) su questo documento → blueprint tecnico (`blueprint/`):
   macrotask, task atomici con `definition_of_done` / `acceptance_criteria` /
   `target_tests`, e la mappa delle degradazioni degli oracoli (Kotlin/Android
   non era coperto; **Swift/iOS nemmeno** — si dichiareranno le sostituzioni
   deterministiche della toolchain Apple: `swift build`/`test`, SwiftLint,
   grafo dei moduli come oracolo di altitudine). **Policy di repo** (`CLAUDE.md`):
   Trueline è usato **solo per BOOTSTRAP**; **tutta la build e tutta la verifica**
   (implementazione, review, testing, security, release gate) sono affidate alla
   suite **apple-skills**.
3. Scaffold del progetto Xcode/SwiftUI e primo macrotask (foundation).
