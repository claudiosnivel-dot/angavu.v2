# Installare Angavu sull'iPhone senza Mac e senza Apple Developer Program

Obiettivo: provare l'app sul **tuo** iPhone in modalità sviluppatore, **senza**
comprare un Mac e **senza** pagare i 99 $/anno dell'Apple Developer Program.

## Come funziona (il trucco: separare compilazione e firma)

Un'app iOS deve essere **firmata** per girare su un device. La firma si può fare
con un **Apple ID gratuito** (free provisioning). Il problema "serve un Mac con
Xcode" si aggira separando i due momenti:

1. **Compilazione** → la fa il **runner macOS di GitHub Actions** (il "Mac in
   cloud" che già usiamo): produce un `.ipa` **non firmato**.
2. **Firma + installazione** → le fai tu con un **tool gratuito** su un **PC
   Windows/Linux**, col tuo **Apple ID gratuito**.

Nessun Mac fisico, nessun abbonamento.

## Passo 1 — Genera l'`.ipa` non firmato (in cloud)

Su GitHub → **Actions** → workflow **"Build unsigned IPA"** → **Run workflow**.
Al termine (~pochi minuti) scarica l'artefatto **`Angavu-unsigned-ipa`**: dentro
c'è `Angavu-unsigned.ipa`.

> È generato da `.github/workflows/ipa.yml` (build `-sdk iphoneos` senza firma,
> impacchettato in `Payload/Angavu.app` → `.ipa`).

## Passo 2 — Firma e installa sull'iPhone (dal tuo PC)

Scegli **uno** di questi tool gratuiti (serve un PC + l'iPhone via cavo/WiFi):

| Tool | Gira su | Note |
|---|---|---|
| **Sideloadly** | Windows / Linux(*) / Mac | Il più semplice: apri l'`.ipa`, inserisci l'Apple ID, Install. |
| **AltStore** (con AltServer) | Windows / Mac | Ri-firma **automaticamente** ogni 7 giorni via WiFi (comodo). |
| **SideStore** | on-device (pairing una tantum) | Minimo uso del PC; rinnova sul device. |

(*) su Linux serve `libimobiledevice`/`idevicepair` per il pairing.

Passi tipici (Sideloadly):
1. Installa Sideloadly sul PC, collega l'iPhone via cavo, autorizza "Fidati".
2. Trascina `Angavu-unsigned.ipa`, inserisci il tuo **Apple ID gratuito**.
3. Premi **Start**: il tool firma con un certificato di sviluppo personale e
   installa l'app.

## Passo 3 — Abilita la Modalità Sviluppatore (iOS 16+)

Sull'iPhone: **Impostazioni → Privacy e sicurezza → Modalità sviluppatore →
ON**, poi riavvia e conferma. La prima volta, se richiesto, "Fidati" del
certificato in **Impostazioni → Generali → VPN e gestione dispositivo**.

## Limiti onesti del free provisioning (senza i 99 $)

- **Scadenza 7 giorni**: dopo una settimana l'app smette di aprirsi e va
  **rifirmata/reinstallata**. AltStore lo fa da solo via WiFi; con Sideloadly è
  manuale (ri-esegui il Passo 2).
- **Max 3 app** sideloadate per Apple ID gratuito.
- Alcuni entitlement avanzati non sono disponibili. Angavu usa PhotoKit /
  Contacts / EventKit, che **funzionano** col profilo gratuito.
- È per **test personale**, non distribuzione. Per TestFlight/App Store servono
  comunque il Developer Program (99 $) + firma in CI (lo faremo al macrotask
  `release`).

## Stato attuale dell'app

Finché il macrotask `ui_shell` non è costruito, l'`.ipa` installa la schermata
**segnaposto** ("Angavu — Fondamenta pronte"): utile per **validare tutto il
percorso di installazione** ora, non ancora l'esperienza finale.
