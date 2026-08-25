# POST-DEVICE-UX-PLAN — Angavu iOS

> **Output di una sessione di PROGETTAZIONE** (design/piano, 2026-08-25), non di
> build. Nasce dal **primo test dell'`.ipa` su iPhone reale** (128 GB, ~25k asset,
> iCloud "Ottimizza spazio dispositivo" attivo): la scansione e la navigazione
> funzionano, ma il device-test ha scoperto una serie di difetti **funzionali, di
> onestà e di UX** che il confine CI headless non può cogliere (nessuna libreria
> reale, nessun iCloud, nessun rendering). Questo piano li raccoglie, blocca le
> decisioni di prodotto già prese con l'utente, e li ordina in task **atomici**,
> ciascuno **chiuso al confine CI** (`swift build -warnings-as-errors` + `swift
> test` + `swiftlint --strict` + build app iOS, runner `macos-15`).
>
> **Confine di verifica onesto (L-COL-006).** Molti di questi difetti sono
> **device-only** (residenza iCloud, lettura AVAsset, rendering miniature). La regola
> resta: la **logica pura** (dominio: tetti, caveat, selezione, dedup) si copre con
> `target_tests` (oracolo su Linux/CI); gli **adapter PhotoKit/AVFoundation** e le
> **View** restano "compilati in CI, runtime sul device dichiarato NON coperto" e si
> validano sul telefono dell'utente. Nessun verde dichiarato a memoria (L-COL-002).
>
> **Altitudine invariata.** Il Domain resta puro (nessun import PhotoKit/AVFoundation/
> SwiftUI). Le nuove capacità di piattaforma entrano SOLO dietro i port del Data;
> la presentazione vive in `AngavuFeatures` + `App/`.

---

## 0. Come leggere questo piano

- **Severità**: 🔴 critico (onestà/manifesto) · 🟠 alto (funzionale/fiducia) · 🟡 medio · 🟢 basso.
- **Fasi**: P0 → A → B → D → C (ordine consigliato, concordato con l'utente).
  Ogni fase è un piccolo macrotask; i task dentro sono atomici e chiudibili in una
  sessione di BUILD.
- **`file:line`**: riferimenti allo stato al commit `0a0852e`. Verificare le righe
  prima di editare (slittano tra un task e l'altro).
- **Manifesto** (VISION §): offline, on-device, **numeri veri mai gonfiati**, rete
  di sicurezza (mai eliminare alla cieca), no ads. Ogni task è misurato contro questo.

---

## 1. Evidenza dal device-test (2026-08-25)

Dispositivo utente: iPhone **128 GB**, 81,76 usati / **46,24 liberi**; iCloud
"Ottimizza spazio dispositivo" ATTIVO. Impostazioni iOS → **Foto occupa 7,99 GB sul
telefono**. Libreria: Foto 22.508 (32,15 GB libreria), Video 2503 (106,85 GB
libreria), Screenshot ~180 (~208 MB).

| # | Difetto osservato | Evidenza |
|---|---|---|
| P0 | **"139,21 GB liberabili sul telefono ora"** su un telefono da 128 GB con Foto che occupa 7,99 GB reali → **~17× di sovrastima**, fisicamente impossibile | screenshot dashboard vs Impostazioni iOS |
| A | **Nessuna miniatura**: righe = `localIdentifier` grezzo (`8A4EB40…1/L0/001`). Non sai cosa elimini | screenshot Screenshot/Comprimi video |
| A | **Screenshot tutto-o-niente**: nessuna selezione per-elemento, CTA "Elimina 175 elementi" | screenshot Screenshot |
| B | **Video: "Non riesco a leggere durata/bitrate"** → nessuna stima, nessun batch | screenshot Comprimi video |
| C | **Manca "Foto simili"** (e duplicati/sfocate/grandi-vecchi): solo categoria Screenshot cablata | screenshot dashboard |
| D | **Rianalisi da capo** rientrando in una categoria già vista, **e** al ritorno da background→foreground | riferito dall'utente |
| D/UX | **Rotella indeterminata** invece di barra di avanzamento durante il calcolo | riferito dall'utente |

---

## 2. Decisioni bloccate (con l'utente, 2026-08-25)

1. **"139 GB" → residenza reale (opzione #1/#3), in cima a tutto (P0).** Numero
   device onesto via residenza per-asset (API pubbliche) + tetto di realtà; il
   risultato è cachato (tira dentro la fondazione della fase D).
2. **Selezione: "Per categoria".** Screenshot e grandi/vecchi → tutto preselezionato
   (opt-out, deselezioni ciò che tieni). Duplicati/simili → preselezionata solo "la
   peggiore", la migliore protetta.
3. **Cache SOPRA la view.** Store `@Observable` a livello app/ambiente (non `@State`
   di view): sopravvive a navigazione e background→foreground.
4. **Video: durata da `PHAsset.duration`** (metadato locale, nessun download) +
   bitrate medio dai byte veri. Niente più dipendenza dall'`AVAsset` (che fallisce
   sugli originali in iCloud).
5. **Niente API private** (es. `PHAssetResource.locallyAvailable` via KVC): rischio
   App Store. Solo API pubbliche.

---

## 3. Criteri di accettazione dell'onestà (derivati dal device dell'utente)

Valgono come oracolo di dominio per la fase P0:

- `deviceReclaimableNow ≤ librarySpace` (già nel contratto, ma la SOMMA lo violava).
- `deviceReclaimableNow ≤ spazioLiberoDevice` e `≤ capacitàDevice` (tetto di realtà).
- Con residenza indeterminata → **caveat, non un numero fabbricato**.
- Sul dispositivo di test: il device-now deve atterrare **nell'ordine di ~8 GB**
  (Foto-sul-telefono reale), non 139 GB. "139 GB" resta come **"Spazio in libreria
  (include iCloud)"**, etichettato e separato.

---

## FASE P0 — Numeri device onesti + fondazione cache · 🔴

Causa radice: `Sources/AngavuData/DeviceStorageInspecting.swift:39-41` —
`deviceResidentBytes` restituisce `libraryBytes` (assume tutto residente). La somma
diventa l'intera libreria (139 GB).

### P0-1 — Store dei risultati a livello app (fondazione cache) · 🟠
- **Output**: un `@Observable` `AnalysisResultsStore` (in `AngavuFeatures`), iniettato
  via environment da `App/` (posseduto sopra le view, non in `@State`). Chiavi per:
  figure dashboard, review per categoria, residenza. API `value(for:)` / `set(_:for:)`
  / `invalidate(...)` / `invalidateAll()`.
- **DoD**: navigazione avanti-indietro e background→foreground **non** ricalcolano;
  un `invalidate` forza il ricalcolo. Invalidazione agganciata a: eliminazione
  eseguita + `LibraryChangeObserver` (T-013) quando la libreria cambia.
- **target_tests**: store puro (set/get/invalidate, TTL/versione se serve) in
  `AngavuFeaturesTests` — logica pura, gira ovunque.
- **Copertura**: il comportamento SwiftUI (sopravvivenza a background) è View-level →
  compilato, runtime dichiarato non coperto; validato sul device.

### P0-2 — Residenza per-asset reale dietro il port · 🟠 · device-only
- **Output**: `SystemDeviceStorageInspector.deviceResidentBytes` non restituisce più
  `libraryBytes` cieco. Residenza via **API pubbliche async** (`PHAssetResourceManager`
  /`PHImageManager` con `isNetworkAccessAllowed=false`: se l'originale non è servibile
  senza rete → non residente → 0 byte device per quell'asset). Risultato cachato in
  P0-1 (costoso su 25k → una volta sola).
- **DoD**: la somma dei device-resident bytes sul device di test è nell'ordine di ~8 GB,
  non 139. Mai > libreria per-asset.
- **Copertura**: adapter Apple-only → **compilato in CI, runtime NON coperto**,
  validato sul telefono. Nuovo eventuale port async dichiarato onesto.

### P0-3 — Tetto di realtà + caveat nel calcolo (dominio puro) · 🔴
- **Output**: `ReclaimableSpaceCalculator` (T-021) riceve anche **capacità/spazio libero
  device** (nuovo port `DeviceCapacityReading` nel Data, impl. via
  `URLResourceValues.volumeAvailableCapacityForImportantUsage` — API pubblica). Il
  device-now = `min(residente, liberoDevice, capacità)`. Se residenza indeterminata →
  stato **caveat** (nessun numero).
- **DoD**: impossibile per costruzione stampare `device_now > libreria` o `> device`.
- **target_tests** (dominio, oracolo): `device_now ≤ libreria`; `device_now ≤ libero`;
  `device_now ≤ capacità`; residenza indeterminata → caveat, non numero; caso del
  device utente (residente ~8, libreria 139, capacità 128) → mostra ~8 + caveat.

### P0-4 — Presentazione onesta (Dashboard + Report) · 🟠
- **Output**: la hero "liberabili sul telefono ora" mostra il device-now onesto;
  "139 GB" ricompare come **"Spazio in libreria (include iCloud)"**, riga separata ed
  etichettata; caveat iCloud sempre visibile quando presente.
- **Copertura**: decisione presentabile (label/formato) nel layer puro con target_test;
  View compilata, resa non coperta.
- **Gate CI**: build+test+lint+app iOS verdi.

---

## FASE A — Fiducia visiva (base condivisa) · 🟠

"Mai alla cieca" (manifesto). Riusata da B e C.

### A-1 — Miniature reali (async, cache) · device-only
- **Output**: port `AssetThumbnailProviding` (Data) impl. via `PHCachingImageManager`
  (async, `isNetworkAccessAllowed=false`; placeholder + glifo "in iCloud" onesto per i
  non-residenti). View mostra l'anteprima nelle righe (lista) e — per C — in griglia.
- **Copertura**: adapter Apple-only compilato/non-coperto; caching e cancellazione allo
  scroll gestiti (perf).

### A-2 — Selezione per-elemento · 🟠
- **Output**: stato di selezione (`Set<String>` di id) nella review, toggle per riga,
  "seleziona tutto/niente", CTA "Elimina N selezionati". Alimenta il percorso subset
  **già esistente** nel dominio (`CategoryReviewViewModel.presentDeletionPreview(of:)`).
- **Default**: per categoria (decisione #2).
- **target_tests**: la logica di selezione/derivazione preselezione per categoria è
  pura → oracolo. Il gate anteprima (T-050) resta invariato (mai eliminare senza preview).

### A-3 — Etichette umane al posto del `localIdentifier` · 🟡
- **Output**: riga mostra data + tipo (dall'indice: `creationDate`, `kind`, subtype) —
  es. "Screenshot · 14 mar 2024" — non l'id grezzo. L'id resta accessibilità/debug.
- **target_tests**: formattazione etichetta nel layer puro.

---

## FASE B — Video davvero utile (dove ci sono i 106 GB) · 🟠

### B-1 — Fix lettura spec senza AVAsset/iCloud · 🔴 (bug visibile)
- **Output**: `AVFoundationVideoSpecProvider` non dipende più da `requestAVAsset`
  (fallisce sugli originali in iCloud). Durata da `PHAsset.duration` (locale); bitrate
  medio = `byteReali*8/durata` (byte veri dall'indice). `nil` solo se durata assente.
- **DoD**: sul device di test le stime compaiono anche per i video in iCloud; il box
  "non riesco a leggere" scompare nel caso comune.
- **Copertura**: adapter Apple-only compilato/non-coperto; la matematica bitrate/stima
  è già dominio testato (T-080).

### B-2 — Flusso batch di compressione · 🟠
- **Output**: stima su tutti (o top-N per dimensione) → selezione video → comprimi i
  selezionati con **progresso + annulla**; opt-in e rete di sicurezza (originale
  recuperabile) invariati; miniature video (riusa A-1) + durata/dimensione mostrate.
- **target_tests**: orchestrazione batch (coda, cancellazione, esiti per-item) nel layer
  puro dove possibile; export reale device-only.

---

## FASE D — Analizza una volta + progresso determinato · 🟡

(La fondazione store è già in P0-1; qui si estende alle categorie e al progresso.)

### D-1 — Detection lazy per-categoria + cache
- **Output**: ogni categoria calcola alla prima apertura e **cacha** il risultato nello
  store (P0-1); rientri istantanei; "Ri-analizza" manuale (pull-to-refresh);
  invalidazione automatica su eliminazione + `LibraryChangeObserver`.
- **DoD**: nessun ricalcolo su navigazione/background; onestà: badge "dati aggiornati X
  fa" e mai un numero stantìo spacciato per fresco.

### D-2 — Progresso determinato
- **Output**: il calcolo emette `AnalysisProgress` (X/N) → barra determinata al posto
  della rotella, riusando il motore `ChunkedAnalysis`/`AnalysisProgress` già esistente.
- **target_tests**: mappatura stato→presentazione (determinato vs indeterminato) nel
  layer puro.

---

## FASE C — Sblocco categorie foto (32 GB di foto) · 🟠

Dipende da D (troppo costoso senza cache/progresso).

### C-1 — Cablare le sorgenti reali delle categorie
- **Output**: `CleanupCategory` estesa oltre `.screenshots`: duplicati esatti (T-030/31/32),
  foto simili (T-040…43), sfocate (T-070/71), video grandi/vecchi (T-060/61/62). Il
  **motore è già verde**; qui si aggancia `CategoryReviewSource` alle sorgenti reali +
  griglia di confronto visivo (riusa A-1) + "tieni la migliore" preselezionata
  (decisione #2).
- **target_tests**: la mappa categoria→sorgente e la preselezione sono pure → oracolo;
  detector reali (Vision/SHA-256/CoreImage) device-only, già dichiarati non coperti.

---

## FASE E — Primo avvio "Shazam" (rifà l'esperienza di scansione) · 🟠 UX

Rimuove il passaggio ridondante "idle → tap Analizza → attesa → tap Vedi i numeri
veri" e lo trasforma in **un solo tap magico** che porta al risultato. Idea utente
(2026-08-25). Prevalentemente View-level (`AngavuFeatures` + `App/`); la macchina a
stati `ScanState` esiste già (idle/requestingPermission/scanning/completed/failed).

### E-1 — Un solo tasto centrale + progresso unico
- **Output**: la Home apre con un **tasto gigante centrale** (stile Shazam). Al tap:
  richiesta permesso → scansione, con **una sola barra di avanzamento**. Nessuno stato
  "idle" separato con bottone da modulo.
- **DoD**: dall'apertura al risultato con un solo tap; il progresso copre in modo
  onesto le 3 fasi (permesso indeterminato → enumerazione/mappatura determinate).

### E-2 — Animazioni gated (battito + riempimento "acqua") · device-only rendering
- **Output**: il tasto scende gradualmente; durante lo scan fa un **battito cardiaco**
  (fase permesso, indeterminata) e poi si riempie come un **livello d'acqua** (fase
  determinata: la frazione reale `AnalysisProgress` guida il fill + cambio colore).
- **Disciplina**: TUTTE le animazioni **gated su Reduce Motion** (equivalente statico:
  barra semplice, nessun particellare) — coerente con R-06. SwiftUI puro (Canvas/
  TimelineView + Shape animabile), zero dipendenze, offline.
- **Skill**: `apple-skills:design` (game-feel: haptics/celebrations) in fase di build.

### E-4 — Carosello "leggi mentre aspetti" (metà superiore) · 🟠
- **Output**: mentre lo scan è in corso e il tasto è sceso in basso, la **metà
  superiore** ospita un **carosello scrollabile lateralmente** (`TabView .page` o
  `ScrollView` orizzontale con paging) — manifesto Angavu + curiosità sullo spazio.
  Trasforma l'attesa in mini-onboarding.
- **Contenuto come DATI** (coerente con `ManifestContent`, T-100): un
  `ScanCarouselContent` nel Domain puro (slide: `id`, titolo, corpo, `symbol`),
  testabile; niente stringhe sparse nella View.
- **Onestà**: le curiosità sono **approssimative e dichiarate tali** ("circa", "può"),
  mai numeri esatti inventati (manifesto: numeri veri). Fact-check leggero in fase di
  build.
- **Slide iniziali proposte** (rivedibili):
  1. *Tutto sul tuo telefono* — niente cloud/server, i dati non escono.
  2. *Zero pubblicità, zero tracciamento* — Pro a pagamento unico, opzionale.
  3. *Numeri veri, coi caveat* — se un dato è stimato, lo dichiariamo.
  4. *Rete di sicurezza* — niente sparisce senza conferma e anteprima.
  5. Un minuto di 4K@60 può pesare **oltre 400 MB**.
  6. **HEVC** comprime un video fino a **~50%** vs H.264, a parità di qualità.
  7. Uno **screenshot PNG** spesso pesa più di una foto compressa.
  8. Due copie **identiche** = doppio spazio, zero valore in più.
  9. Le **Live Photo** = foto + breve video → pesano di più.
  10. **1 GB** ≈ 500–1000 foto compresse, o pochi minuti di 4K.
  11. Le **raffiche (burst)** creano decine di scatti quasi identici in un secondo.
  12. **HEIC** pesa circa metà di un vecchio JPEG, a parità di qualità.
  13. Una **panoramica** può pesare quanto 5–10 foto normali.
  14. I video **slo-mo** girano a 120/240 fps: molti più fotogrammi = più spazio.
  15. Con **Ottimizza iCloud** gli originali stanno nel cloud: "sul telefono" ≠ "in libreria" (noi le distinguiamo).
  16. Eliminare non è per sempre: gli elementi restano in **"Eliminati di recente"** ~30 giorni.
  17. **ProRAW/ProRes** (iPhone Pro): una foto ProRAW può superare i 25 MB, un minuto di ProRes 4K vari GB.
  18. I **duplicati** nascono da condivisioni, salvataggi e backup: la stessa immagine, molte volte.
  19. La foto **più pesante** non è la più bella: spesso è solo la meno compressa.
  20. **Cancellare 10 video 4K** può liberare più spazio di 5.000 foto.
  21. Lo **screenshot** è utile una volta, poi dimenticato: la cartella cresce in silenzio.
  22. Piccoli gesti, grande effetto: qualche minuto di pulizia può valere gigabyte.
  (Slide 1–4 = manifesto; 5–22 = curiosità, tutte "circa/può", da fact-check leggero in build.)
- **Accessibilità/HIG**: swipe manuale di default (i caroselli auto-avanzanti sono
  ostili a VoiceOver e a Reduce Motion); page indicator; ogni slide un elemento
  VoiceOver. Eventuale auto-avanzamento LENTO solo opzionale e **gated su Reduce
  Motion**.
- **Copertura**: contenuto e ordinamento nel Domain puro con target_test; layout
  carosello View-level (compilato, resa non coperta).
- **Opzione futura**: sulla schermata di successo (E-3) una curiosità
  **personalizzata** coi numeri veri appena calcolati ("Hai 2503 video: ~X GB").

### E-3 — Schermata di successo (coriandoli) → dashboard · 🟠
- **Output**: a **successo vero** una piccola schermata celebrativa (coriandoli gated
  + haptic `.success` già esistente) col **conteggio reale**, e un tasto "È ora di fare
  pulizia!" → dashboard.
- **Onestà (manifesto)**: niente festa se accesso **negato/limitato** o scansione
  **fallita** → ramo onesto (messaggio esplicito, "Apri Impostazioni"), mai coriandoli
  su un mezzo successo. Il conteggio parziale (limited) resta dichiarato tale.
- **Copertura**: la decisione "quale esito → quale schermata (festa vs onesto)" va nel
  layer di presentazione PURO (estende `HomeScanPresentation`) con target_test; le
  animazioni restano View-level (compilate, resa non coperta, L-COL-006).

> **Priorità**: alta per la prima impressione, ma **dopo P0** (l'onestà dei numeri è
> più urgente della delight del primo avvio). Relativamente indipendente dalle altre
> fasi (tocca la Home/scan, non il percorso di lettura dashboard).

---

## 4. Note trasversali

- **Rete di sicurezza sempre**: ogni eliminazione passa dal gate anteprima
  (`DeletionFlow`, T-050); mai un bypass, mai una selezione che elimina senza preview.
- **Onestà dei numeri**: preferire "non mostrare" a "mostrare un numero inventato"
  (residenza indeterminata, spec video assente, dati stantii).
- **Perf/altitudine**: le letture pesanti restano off-main (già fatto in `8a383b0`);
  i nuovi adapter async non toccano il main; il Domain resta puro.
- **Ordine**: P0 (🔴 onestà) → A (fiducia) → B (video, GB) → D (cache/progresso) → C
  (categorie). A-1 (miniature) è infrastruttura riusata da B-2 e C-1. **Fase E** (primo
  avvio "Shazam") è indipendente e va inserita **dopo P0**, presto (prima impressione) —
  posizione esatta a scelta dell'utente.

## 5. Fuori scope (per ora)

- Persistenza dei risultati tra riavvii (SwiftData): valutata dopo la cache in memoria.
- Domini extra-foto (contatti/calendari) a scala molto grande: rivisti solo se emergono
  freeze come sul percorso foto.
- Monetizzazione Pro (pagamento unico): differita come da manifesto/stato.
