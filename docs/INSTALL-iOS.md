# Installare Angavu su un iPhone (modalità sviluppatore)

> Come ottenere un `.ipa` firmato in **development** e installarlo su un iPhone
> fisico. Onestà (manifesto Angavu): un binario iOS installabile può nascere solo
> su un Mac / runner macOS **con firma Apple**. Non esiste scorciatoia da Linux.

Ci sono due strade. Scegli in base a cosa hai.

---

## Strada A — La più semplice (Mac + Xcode, niente CI, niente secret)

Se hai un Mac, questa è la via più rapida per un solo sviluppatore:

1. Genera il progetto Xcode: `make app` (richiede `xcodegen`), poi apri
   `App/Angavu.xcodeproj`.
2. Collega l'iPhone via cavo. In **Signing & Capabilities** del target `Angavu`
   seleziona il tuo **Team** (basta un Apple ID; il team personale *free* funziona
   per l'installazione su device, con certificato che scade dopo 7 giorni).
3. In alto scegli il tuo iPhone come destinazione e premi **Run** (▶). Xcode firma
   e installa da solo.
4. Sull'iPhone: **Impostazioni → Privacy e sicurezza → Modalità sviluppatore → ON**,
   riavvia, conferma. (iOS 16+.)

Non serve nessun `.ipa` "a mano": Xcode fa tutto. Usa la **Strada B** solo se vuoi
un `.ipa` prodotto dalla CI (es. non hai un Mac a portata, o vuoi un artefatto
ripetibile da scaricare).

---

## Strada B — `.ipa` dalla CI (workflow `Release iOS`)

Il workflow [`.github/workflows/release-ios.yml`](../.github/workflows/release-ios.yml)
builda un `.ipa` **development** sul runner macOS e lo pubblica come artefatto
scaricabile. Gira solo on-demand e solo se aggiungi i secret di firma.

> **Nota Apple Developer.** Per procurarti *come file* un certificato di sviluppo
> (`.p12`) e un provisioning profile serve in pratica l'**Apple Developer Program**
> (99 $/anno — già previsto dal progetto). Con il solo team personale free è più
> pratico usare la **Strada A**.

### 1) Procurati i 3 pezzi da Apple

Su [developer.apple.com](https://developer.apple.com/account) → Certificates,
Identifiers & Profiles:

1. **App ID**: registra l'identifier `com.angavu.app` (deve combaciare con
   `App/project.yml`). In alternativa un wildcard `*` che copra il bundle id.
2. **Device**: registra l'iPhone con il suo **UDID** (lo leggi in Xcode →
   *Devices and Simulators*, o da Apple Configurator).
3. **Certificato di sviluppo** (Apple Development): crealo e installalo nel
   Portachiavi del Mac, poi **esportalo in `.p12`** (Portachiavi → tasto destro sul
   certificato → *Esporta* → formato `.p12`, imposta una password). Se non hai un
   Mac, puoi crearlo/scaricarlo dal portale e convertirlo, ma il flusso `.p12`
   passa comunque dal Portachiavi.
4. **Provisioning profile — tipo Development**: per l'App ID `com.angavu.app`,
   includendo il certificato sopra **e** il device registrato. Scaricalo
   (`.mobileprovision`).
5. **Team ID**: dalla pagina *Membership* (stringa di 10 caratteri).

### 2) Converte in base64

Cert e profilo vanno passati alla CI come base64 (su Mac/Linux):

```bash
base64 -i AngavuDevelopment.p12            # → copia l'output (BUILD_CERTIFICATE_BASE64)
base64 -i Angavu_Development.mobileprovision   # → copia l'output (BUILD_PROVISION_PROFILE_BASE64)
```

### 3) Aggiungi i GitHub Secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Valore |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | base64 del `.p12` |
| `P12_PASSWORD` | la password scelta esportando il `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | base64 del `.mobileprovision` (Development) |
| `DEVELOPMENT_TEAM` | il Team ID (10 caratteri) |
| `KEYCHAIN_PASSWORD` | una password qualsiasi per il keychain temporaneo della CI |

Nessuno di questi vive nel repo: la CI li usa a runtime e ripulisce il keychain a
fine job.

### 4) Lancia il workflow

Repo → **Actions → Release iOS (.ipa development) → Run workflow** (sul branch che
preferisci). A fine run scarica l'artefatto **`Angavu-ios-development-ipa`**:
contiene `Angavu.ipa`.

### 5) Installa l'`.ipa` sull'iPhone

Prima, sul telefono: **Impostazioni → Privacy e sicurezza → Modalità sviluppatore
→ ON**, riavvia e conferma (iOS 16+).

Poi, da un Mac, uno di questi:

- **Apple Configurator 2** (gratis su Mac App Store): collega l'iPhone, trascina
  `Angavu.ipa` sul dispositivo.
- **Xcode → Window → Devices and Simulators**: seleziona l'iPhone, sezione
  *Installed Apps* → **+** → scegli `Angavu.ipa`.
- Da terminale: `xcrun devicectl device install app --device <UDID> Angavu.ipa`.

L'app si apre solo se il device è incluso nel provisioning profile.

---

## Limiti dichiarati (onestà)

- Una build **development** è per test personali/ristretti: il profilo/certificato
  **scade** (≈1 anno con Developer Program; 7 giorni con team free) e va rigenerata.
- L'`.ipa` **non** è distribuibile sull'App Store: quello è un percorso separato
  (metodo `app-store` + TestFlight/Review), non coperto da questo workflow.
- L'installazione richiede comunque un Mac (Configurator/Xcode/devicectl) o
  strumenti equivalenti: è un vincolo della piattaforma Apple, non dell'app.
