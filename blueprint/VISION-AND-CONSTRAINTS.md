# VISION & CONSTRAINTS — Angavu iOS

> Il *perché*, il *per chi*, i *non-goals* e i *vincoli*. Input dell'utente
> (`docs/FEASIBILITY-iOS.md`), non invenzione dell'LLM. Generato da BOOTSTRAP.
> Prosa in italiano, identificatori/nomi-file in inglese.

| | |
|---|---|
| **Progetto** | Angavu iOS |
| **Ecosistema** | swift-ios (SwiftUI + SwiftData + PhotoKit/Vision/AVFoundation) |
| **Owner / stakeholder** | claudiosnivel-dot (solo dev, ~3 h/settimana) |

---

## 1. Perché esiste (problema)

La categoria "cleaner" su iOS è **peggiore** che su Android: abbonamenti
predatori (5–10 $ a *settimana*), "128 GB di junk trovati!" falsi, rilevamento
foto-simili rozzo. Angavu Android nasce contro le truffe della categoria; su iOS
lo stesso manifesto — *offline, no ads, numeri veri, rete di sicurezza, Pro a
pagamento unico* — è ancora più dirompente, perché lì **nessuno lo rispetta**.
La strategia non è portare l'app, è portare **la promessa**, sul sottoinsieme che
iOS permette davvero, fatto meglio di chiunque.

## 2. Per chi (utenti)

Utenti iOS con libreria foto/video piena che vogliono liberare spazio **senza**
essere truffati: numeri veri, nessuna scare tactic, nessun abbonamento, nessun
dato inviato a server. Include librerie enormi (20k+ asset) e utenti con iCloud
"ottimizza spazio" attivo (caveat dichiarato, §6 del feasibility).

## 3. Obiettivo (cosa significa "fatto")

Un'app iOS nativa che indicizza la libreria foto/video (PhotoKit → SwiftData),
mostra **byte reali** con il caveat iCloud, trova duplicati esatti e foto simili
(Vision semantico), suggerisce cosa eliminare senza mai farlo da sola, elimina
solo dietro **anteprima obbligatoria** verso la rete di sicurezza di sistema,
comprime video HEVC on-device, gestisce contatti/calendario, e apre con un
onboarding-manifesto che dichiara apertamente **cosa non fa**.

"Fatto" = oracoli **apple-skills** verdi al confine di ogni macrotask (`swift
build`/`swift test`/SwiftLint/grafo moduli), **non** una dichiarazione dell'LLM
(`L-COL-002`, `L-COL-006`).

## 4. Non-goals (cosa NON facciamo)

> Argine allo scope creep. Il manifesto Android portato su iOS (feasibility §7).

- **Pulizia "cache di sistema / file temporanei / junk di altre app"** — impossibile nel sandbox iOS. Non si simula, si **dichiara**.
- **Media "cartella WhatsApp/Telegram" o cartelle extra via SAF** — le cartelle di altre app non sono accessibili; nessun equivalente del SAF Android.
- **RAM/CPU/battery booster** — placebo, come nell'Android.
- **"Antivirus"** — non fattibile in solo + budget zero.
- **Ads, notifiche promo, scare tactics, numeri gonfiati** — mai.
- **Backend / sync cloud** — zero server, tutto on-device.
- **IAP / Angavu Pro in v1** (`DI-002`) — si lancia tutto-free; il Pro arriva dopo, *aggiungendo sopra*, mai togliendo.
- **Vault cifrato, widget, App Intents/Shortcuts, versioni iPad/macOS dedicate** — v2+.

## 5. Vincoli

| Tipo | Vincolo |
|---|---|
| Ecosistema | Swift + SwiftUI nativo; **zero backend**; Domain puro senza dipendenze di piattaforma |
| iOS minimo | **iOS 17.0** (`DI-003`); iOS 18 aesthetics come *progressive enhancement* |
| Permessi | `NSPhotoLibraryUsageDescription`; e solo se le feature entrano: `NSContactsUsageDescription`, `NSCalendarsFullAccessUsageDescription`. **Niente permesso non usato** |
| Privacy | Nessun dato lascia il device; **PrivacyInfo.xcprivacy** con required-reason API dichiarate; nessun tracking/telemetria |
| Dimensione app | Snella: Vision è di sistema, **nessun modello Core ML bundolato** (ethos "<15 MB" dell'Android) |
| Sicurezza | Nessun segreto nel sorgente; credenziali/signing Apple fuori dal repo |
| Git | Branch a strati; merge su `main` gated dal **verde apple-skills**; deploy non supervisionato bloccato (`L-COL-024`, `L-COL-025`) |
| Tempo | ~3 h/settimana. Scope rigido: **rete di sicurezza e cuore-foto intoccabili**; il de-scope parte dalle leve più a rischio (compressione video, `DI-006`) |
| Budget | 99 $/anno Apple Developer Program (unico costo nuovo vs Android); nessun costo di runtime |
| App Store | Categoria sorvegliata (Guideline 2.3.x): niente claim su boost/velocità/virus, permessi minimi, scheda onesta |

## 6. Parity gate (promessa forte)

Conformità alla specifica = i `target_tests` dei task del macrotask passano alla
verifica **apple-skills** (`swift test`). La logica del Domain (cluster, "tieni la
migliore", policy di eliminazione) è **pura** e testabile senza device; gli
adapter di piattaforma (PhotoKit/Vision/AVFoundation) sono verificati dietro
protocolli con fake. Il grafo dei moduli SwiftPM è l'oracolo di altitudine: una
dipendenza `domain → data` **non compila**.

## 7. Baseline & budget

- **Baseline privacy/sicurezza**: `blueprint/BASELINE-AND-BUDGET.md` (required-reason API, usage-description, no-network).
- **Budget**: `blueprint/BASELINE-AND-BUDGET.md` (limiti di tempo/ciclo, ~3 h/settimana).

## 8. Fonti di verità

- **Piano**: il blueprint (`00-INDEX` + moduli numerati).
- **Stato vivo**: `blueprint/SESSION-STATE.md`.
