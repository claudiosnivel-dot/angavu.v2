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
Al termine (~pochi minuti) scarica l'artefatto **`Angavu-unsigned-ipa`**.

> ⚠️ **IMPORTANTISSIMO — estrai lo zip prima di sideloadare.** GitHub consegna
> l'artefatto come **`Angavu-unsigned-ipa.zip`** (un contenitore). **Dentro** c'è il
> vero file da installare: **`Angavu-unsigned.ipa`**. **Estrai** lo zip e dai a
> Sideloadly/AltStore **il `.ipa` interno**, MAI lo zip esterno. Se passi lo zip (o
> lo rinomini in `.ipa`), AltStore risponde **«non è nel formato adatto»**: sta
> guardando uno zip che contiene un `.ipa`, non un `.ipa` con dentro `Payload/`.

> È generato da `.github/workflows/ipa.yml` (build `-sdk iphoneos` senza firma,
> impacchettato in `Payload/Angavu.app` → `.ipa`) e **verificato in CI** (struttura
> `Payload/`, eseguibile Mach-O, chiavi `Info.plist`, build device): se l'artefatto
> esiste, l'`.ipa` è ben formato.

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

## Se AltStore/Sideloadly dice «non è nel formato adatto»

Quasi sempre è uno di questi, in ordine di probabilità:

1. **Hai passato lo zip esterno, non l'`.ipa` interno.** L'artefatto scaricato è
   `Angavu-unsigned-ipa.zip`. **Estrailo** e sideloada `Angavu-unsigned.ipa` che
   trovi dentro. (Su iPhone: File → tocca lo zip per estrarlo; su PC: click destro →
   Estrai.) Questo è il caso n.1.
2. **Doppia compressione / rinomina.** Non rinominare uno `.zip` in `.ipa`: un `.ipa`
   valido ha `Payload/NomeApp.app/…` alla radice, non un `.ipa` annidato.
3. **Artefatto scaduto o build vecchia.** Gli artefatti durano 14 giorni; se è
   vecchio, ri-lancia **"Build unsigned IPA"** e riscarica.
4. **Dubbi sul file?** La CI ora verifica il formato dell'`.ipa` (step *"Verifica
   formato .ipa"*): se quel passo è verde, il `.ipa` interno è ben formato — il
   problema è nel modo in cui lo passi al tool, non nel file.

5. **«Encountered unknown tag html on line 1» / `kCFPropertyListOldStyleParsingError`.**
   Questo è il caso più insidioso: il file che hai dato ad AltStore **è una pagina
   HTML, non l'`.ipa`**. Succede perché la repo è **privata** e gli scaricamenti da
   GitHub (artefatti E release) funzionano **solo da loggati**: se scarichi da un
   browser non autenticato, GitHub restituisce una pagina di login/errore in HTML che
   finisce salvata come `.zip`/`.ipa`. **Verifica la dimensione**: il file giusto pesa
   **~700 KB**; se sono pochi KB è l'HTML. Rimedi:
   - **Consigliato**: scarica l'artefatto da un **computer loggato su GitHub**, estrai
     l'`.ipa`, e installalo sull'iPhone via cavo con **Sideloadly** (evita del tutto il
     download da telefono).
   - Da iPhone: apri `github.com` in **Safari**, **accedi**, poi vai al run e scarica;
     controlla che lo zip sia ~700 KB prima di darlo ad AltStore.

Se dopo l'estrazione l'errore persiste, apri il log del run e controlla lo step
*"Verifica formato .ipa"*: elenca le chiavi `Info.plist` e la struttura reale.

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

`ui_shell` è costruito: l'`.ipa` installa il **guscio reale** — onboarding col
**manifesto**, home, e la schermata **"cosa NON facciamo"**, con il tema nativo
**Aurora** (brand token ripresi dall'Android, ricostruiti per HIG).

Resta il **cablaggio dati**: le schermate del cuore-foto (duplicati, foto simili,
video, ecc.) e il **report onesto** (`HonestReportView`) devono ancora essere
collegate ai dati veri della libreria (PhotoKit → dashboard/library_index). La
logica di tutte queste feature è già completa e verificata in CI; manca la loro
resa in schermate navigabili. Quindi oggi l'`.ipa` mostra il guscio + manifesto,
non ancora la pulizia foto interattiva.
