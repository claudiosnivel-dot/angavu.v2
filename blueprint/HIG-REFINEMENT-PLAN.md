# HIG-REFINEMENT-PLAN — Angavu iOS

> **Output di una sessione di PROGETTAZIONE** (design/piano, 2026-08-23), non di
> build. Piano di rifinitura HIG del **guscio UI già completo (8/8 schermate)**,
> derivato da un audit di sola-lettura delle view SwiftUI (`apple-skills:ios`
> ui-review + `apple-skills:design` typography/game-feel). Ogni task è **atomico**,
> eseguibile a cadenza in una sessione di BUILD, e **chiuso al confine CI**
> (`swift build -warnings-as-errors` + `swift test` + `swiftlint --strict` + build
> app iOS verdi, runner `macos-15`).
>
> **Nessuna logica nuova nel Domain/Data.** Il lavoro vive in `AngavuFeatures`
> (layer di presentazione puro + View guardate `#if canImport(SwiftUI)`) e in
> `App/`. Dove un task introduce una **decisione presentabile** (es. formattazione
> hero, label di stima per VoiceOver), questa va nel layer di presentazione PURO con
> `target_tests` in `AngavuFeaturesTests` (oracolo su Linux). Le View restano
> **compilate** dai due job CI ma **senza test di rendering** (resa a runtime non
> coperta, L-COL-006).

---

## 0. Come leggere questo piano

- **Severità**: 🔴 critico · 🟠 alto · 🟡 medio · 🟢 basso (rifinitura).
- **Trasversale vs locale**: i rilievi dell'audit si ripetono su più schermate.
  Ogni task raccoglie **tutti i siti** dello stesso difetto → una fix, molte
  schermate, un solo confine CI.
- **Ordine consigliato**: R-00 (bug) → R-01…R-04 (alti, coerenza sistemica) →
  R-05…R-09 (medi) → R-10…R-11 (bassi). Ogni task è indipendente: si può prendere
  in qualsiasi ordine rispettando il proprio confine CI.
- **`file:line`**: riferimenti allo stato al commit `ee3b6d8`. Verificare le righe
  prima di editare (potrebbero slittare tra un task e l'altro).

---

## R-00 — [BUG, non solo HIG] Persistenza dell'onboarding · 🟠

**Problema.** `App/ContentView.swift:14` dichiara `didFinishOnboarding` come
`@State`: si azzera a **ogni cold-launch**, quindi l'onboarding-manifesto ricompare
a ogni avvio dell'app. È un difetto funzionale, non solo estetico.

- Siti: `App/ContentView.swift:14`, `:18-24`.

**Definition of done.** `didFinishOnboarding` persistito con
`@AppStorage("didFinishOnboarding")`; l'onboarding compare **una sola volta** per
installazione. (Opzionale: una voce di debug/menu per riproporlo.)

**Copertura.** La transizione è View-level (compilata in CI). Se si estrae la
decisione «mostrare onboarding?» in una funzione pura, coprirla con 1 target_test.

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-01 — Cifra-hero che scala con Dynamic Type · 🟠 · trasversale

**Problema.** Il numero più importante di ogni schermata usa una dimensione
**fissa** `.font(.system(size: 44, weight: .bold, design: .rounded))`, che **non
scala** col Dynamic Type e si tronca alle accessibility sizes. Incoerenza anche su
`monospacedDigit` (presente sulle righe, assente su alcune cifre-hero).

- Siti: `DashboardView.swift:118`, `CategoryReviewView.swift:123`,
  `HonestReportView.swift:93`/`:100`, `CompressionView+Sections.swift:76`.
- Correlato: `HonestReportView.swift:92`/`:100`/`:148` mancano `monospacedDigit`.

**Definition of done.**
- Un unico helper di presentazione — es. `AuroraType.heroNumber` — basato su un
  **text style semantico** (`.largeTitle`/`.title`, `design: .rounded`,
  `.weight(.bold)`, `.monospacedDigit()`), riusato da tutte le cifre-hero.
- Le cifre-hero scalano con Dynamic Type (cap ragionevole se serve, es.
  `.dynamicTypeSize(... .accessibility3)`), niente `size:` fisso.
- Aggiungere `.contentTransition(.numericText())` dove la cifra cambia a runtime
  (il numero non "teletrasporta"). Gated su Reduce Motion (vedi R-06).

**Copertura.** L'helper è puro → 1 target_test che ne verifica text style e
`monospacedDigit`. Rese compilate in CI.

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-02 — Titolo unico per schermata (niente doppioni) · 🟠 · trasversale

**Problema.** Ogni schermata monta un `navigationTitle(...)` in **large title**
*più* un header in-body a gradiente con lo **stesso testo** → la scritta appare
**due volte**.

- Siti: `HomeView.swift:51`+`:61-63` ("Angavu"),
  `DashboardView.swift:47`+`:58-60` ("Numeri veri"),
  `CategoryReviewView.swift:59`+`:75-77` (`category.title`),
  `CompressionView.swift:65`+`:80-82` ("Comprimi video"),
  `HonestReportView.swift:45`+`:56-58` ("Report onesto"),
  `NonGoalsView.swift:32-34`+`:40-42` (`presentation.title`).

**Definition of done.** Per ogni schermata **una sola** intestazione visibile.
Convenzione consigliata: tenere l'**hero in-body** (wordmark/titolo a gradiente,
identità del brand) e portare la nav bar a `.navigationBarTitleDisplayMode(.inline)`
(titolo inline discreto o vuoto). Applicare la **stessa** convenzione ovunque per
coerenza.

**Copertura.** Solo View (compilata in CI). Verifica visiva a runtime dichiarata
non coperta.

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-03 — Raggruppamento VoiceOver di righe e card · 🟡 · trasversale

**Problema.** Righe categoria e card di stato espongono 3-4 elementi VoiceOver
separati (titolo, conteggio, byte, "stima"), invece di un elemento unico leggibile.
Manca il trait `isHeader` sui titoli di sezione/stato.

- Siti: `DashboardView.swift:306-332` (row), `HonestReportView.swift:207-226`
  (row), `CategoryReviewView.swift:300-317` (row, legge l'**id grezzo**),
  `NonGoalsView.swift:59-61`, `HomeView.swift:76-106` (statusCard),
  `CompressionView+Sections.swift:55-61`/`:295-318` (row che legge il
  `localIdentifier`).

**Definition of done.**
- `.accessibilityElement(children: .combine)` su ogni riga/card, con
  `accessibilityLabel`/`accessibilityValue` **umani** (mai il `localIdentifier`
  grezzo: es. «Elemento, da eliminare» / «Video, 128 MB»).
- `.accessibilityAddTraits(.isHeader)` sui titoli di stato/sezione.
- Icone puramente decorative marcate `.accessibilityHidden(true)` (dove non già).

**Copertura.** View (compilata in CI). Se si estraggono le stringhe-label nel layer
puro, coprirle con target_tests (es. label per disposizione keep/removable).

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-04 — Etichette e tap target dei bottoni d'azione · 🟡 · trasversale

**Problema.** Bottoni `.borderless` in coda di riga («Fondi», «Rimuovi») non dicono
**quale** elemento a VoiceOver e rischiano tap target < 44pt. Le righe-candidato
compressione sono `Button` che avvolgono l'id grezzo.

- Siti: `ExtraPhotoDomainsView.swift:120-124` («Fondi»), `:150-155` («Rimuovi»),
  `CompressionView+Sections.swift:55-61`/`:295-318` (row-button).

**Definition of done.**
- `accessibilityLabel` specifica per azione+oggetto («Fondi Mario Rossi»,
  «Rimuovi calendario Spam»); `accessibilityHint` dove l'azione non è ovvia
  («Stima il risparmio»).
- Tap target ≥ 44pt garantito (`.frame(minHeight: 44)` / `.contentShape(Rectangle())`).
- Valutare `swipeActions` per l'azione distruttiva in lista (più idiomatico del
  bottone in coda), mantenendo comunque la conferma human-gated.

**Copertura.** View (compilata in CI).

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-05 — Stati vuoto/errore uniformi su `ContentUnavailableView` · 🟡 · trasversale

**Problema.** Empty-state ed error-state sono card custom disomogenee (a volte un
semplice `Text().secondary`, a volte una card con «Riprova»): manca l'idioma iOS 17
`ContentUnavailableView` (icona + titolo + descrizione + azione).

- Siti: `DashboardView.swift:278-302` (errore) / `:169-187` (vuoto),
  `CategoryReviewView.swift:169-187` (vuoto),
  `CompressionView+Sections.swift:249-266` (`noVideosCard`),
  `ExtraPhotoDomainsView.swift:94-95`/`:130-131` (empty `Text` nudo).

**Definition of done.** Empty/error uniformati su `ContentUnavailableView` (con
`actions:` per il retry dove c'è). Messaggi **onesti** (un errore d'indice resta uno
stato esplicito, mai una lista vuota spacciata per «pulito»: invariante già presente
in `CategoryReviewSource`, da preservare).

**Copertura.** View (compilata in CI). Le decisioni di quale stato mostrare sono già
nel layer di presentazione puro (coperte dai target_tests esistenti).

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-06 — Micro-interazioni & haptics sui momenti-firma · 🟡 · trasversale

**Problema.** I momenti che l'utente "sente" non danno feedback: fine scansione,
apertura anteprima e **conferma d'eliminazione** (spot haptic per eccellenza),
fine/fallimento compressione, avanzamento onboarding, esito fusione/rimozione. Le
transizioni di fase (idle→ready→failed, onboarding→home) sono **tagli netti**.

- Siti: `HomeView.swift:39-55`/`:44` (fine scan), `CategoryReviewView.swift:61-66`/
  `:206` (anteprima/conferma), `CompressionView.swift:66-71` (done/failed),
  `OnboardingManifestoView.swift:81-92` (continue), `ExtraPhotoDomainsView.swift:168-172`
  (outcome), `HonestReportView.swift:72-85` e `App/ContentView.swift:18-24`
  (transizioni di fase).

**Definition of done.** (Utility mono-utente → canale **haptics**, non suoni.)
- `.sensoryFeedback` con **vocabolario per rarità** (`.impact` leggero =
  conferma/avanzamento; `.warning` = apertura anteprima distruttiva; `.success` =
  eliminazione/compressione completata; `.error` = fallimento). **Un solo owner**
  per evento (nessun doppio-buzz).
- Transizioni di fase animate con `withAnimation` + `.transition(.opacity)` /
  `.move`. **Tutte gated su Reduce Motion** con equivalente statico (parità
  informativa).
- **Toggle haptics** utente (Core Haptics/sensory feedback non hanno un setting di
  sistema globale) — collocabile in `ThemeSettings`/Impostazioni.

**Copertura.** View (compilata in CI). Il vocabolario evento→feedback, se estratto
in un enum puro, va coperto con 1 target_test (mappa non vacua, un evento = un
livello).

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-07 — `ProgressView` sempre etichettata + avanzamento determinato · 🟡

**Problema.** Spinner nudi `ProgressView().progressViewStyle(.circular)` senza
label negli stati idle/loading; un caso in cui esiste una frazione d'avanzamento
ma si mostra un indeterminato.

- Siti: `HonestReportView.swift:76`, `HomeView.swift:99-100`, `DashboardView.swift:78`,
  `CompressionView.swift:100-101`, `ExtraPhotoDomainsView.swift:84-88`/`:194-199`.
- Determinabile: `CompressionView+Sections.swift:147-170` (`workingCard`) se il
  view-model espone `fraction` dell'export.

**Definition of done.** Ogni `ProgressView` ha una label testuale onesta
(«Calcolo del report…», «Analisi in corso», «Lettura di contatti e calendari…»).
Dove esiste una frazione reale, `ProgressView(value:)` determinato con
`accessibilityValue` percentuale.

**Copertura.** View (compilata in CI).

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-08 — Layout categoria adattivo a Dynamic Type grande · 🟡

**Problema.** Le righe «titolo … valore» sono `HStack` con `Spacer()` e titolo
senza `lineLimit`: alle accessibility sizes i due lati si comprimono o troncano.

- Siti: `DashboardView.swift:310-329` (row), analoghi in
  `HonestReportView.swift:207-226`, righe categoria di `CategoryReviewView`.

**Definition of done.** Righe chiave avvolte in
`ViewThatFits(in: .horizontal) { HStack{…}; VStack(alignment:.leading){…} }` (o
branch su `dynamicTypeSize.isAccessibilitySize`), con `lineLimit`/`allowsTightening`
sensati. Nessun testo tagliato ad AX5.

**Copertura.** View (compilata in CI). Verifica visiva a runtime a XXL/AX dichiarata
non coperta.

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-09 — Parsimonia di gradiente/glow e contrasto testo-su-accento · 🟡

**Problema.** (1) `HonestReportView` usa `AuroraBrand.gradient` **due volte** sulla
stessa vista (header + cifra-hero), ai limiti della regola di parsimonia.
(2) `HomeView.swift:50` applica `AuroraBrand.glow.ignoresSafeArea()` come `.background`
dell'intera view: da verificare che resti **bagliore in testa** e non un fondo intero.
(3) `.foregroundStyle(.white)` hardcoded su CTA a gradiente: da **verificare il
contrasto ≥ 4.5:1** sui tre stop (l'estremo fucsia/azzurro chiaro è il rischio).

- Siti: `HonestReportView.swift:58`+`:94/:101`, `HomeView.swift:50`,
  `OnboardingManifestoView.swift:87-88` (+ CTA analoghe in Home/Dashboard/Compression,
  già valutate accettabili su gradiente medio-scuro).

**Definition of done.**
- **Un solo** uso del gradiente per schermata (la cifra-hero vince; header a
  `.primary`).
- Glow confermato top-anchored che sfuma a `.clear` (eventualmente confinato con
  `frame(height:)`/`alignment: .top`), mai fondo pieno.
- Contrasto del testo sulle CTA a gradiente verificato ≥ 4.5:1 su tutti gli stop;
  se non passa, aggiustare lo stop o lo stile del testo.

**Copertura.** View (compilata in CI). Il contrasto va verificato con Accessibility
Inspector / calcolo manuale sui tre esadecimali (documentare l'esito).

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-10 — Accessibilità di stima e simboli · 🟢

**Problema.** Il prefisso `"~ "` è letto da VoiceOver come "tilde"; la marca-stima
non è chiara vocalmente. Il wordmark del brand non ha trait header.

- Siti: `HonestReportView.swift:99`/`:217`, `OnboardingManifestoView.swift:45`
  (wordmark), `DashboardView` (marca «stima»).

**Definition of done.** `accessibilityLabel` esplicita per i valori stimati
(«stima, 128 MB») invece del `~` letto male; `.accessibilityAddTraits(.isHeader)`
sul wordmark. SF Symbols coerenti per peso/scale.

**Copertura.** View (compilata in CI); stringhe-label pure coperte da target_test se
estratte.

**Gate CI.** build+test+lint+app iOS verdi.

---

## R-11 — Rifiniture minori · 🟢

- `HonestReportView.swift:72-85` — transizione idle→ready→failed animata (coperto in
  parte da R-06).
- `ThemeSettings.swift:54-61` — `Picker` con `.labelsHidden()` ridondante col header
  di sezione: semplificabile (nessun impatto funzionale).
- `ExtraPhotoDomainsView.swift:201-213` — durante `Task` di fusione/rimozione,
  disabilitare la riga + spinner in coda finché non risolve (feedback d'avanzamento).

**Gate CI.** build+test+lint+app iOS verdi (raggruppabili in un unico task di pulizia).

---

## Riepilogo priorità

| Task | Titolo | Sev | Schermate toccate |
|---|---|---|---|
| R-00 | Persistenza onboarding (`@AppStorage`) | 🟠 | ContentView |
| R-01 | Cifra-hero scalabile (Dynamic Type + monospacedDigit) | 🟠 | Dashboard, CategoryReview, HonestReport, Compression |
| R-02 | Titolo unico per schermata | 🟠 | Home, Dashboard, CategoryReview, Compression, HonestReport, NonGoals |
| R-03 | Raggruppamento VoiceOver righe/card | 🟡 | Dashboard, HonestReport, CategoryReview, NonGoals, Home, Compression |
| R-04 | Label + tap target ≥44pt dei bottoni | 🟡 | ExtraPhotoDomains, Compression |
| R-05 | Stati vuoto/errore su `ContentUnavailableView` | 🟡 | Dashboard, CategoryReview, Compression, ExtraPhotoDomains |
| R-06 | Micro-interazioni & haptics (Reduce Motion + toggle) | 🟡 | Home, CategoryReview, Compression, Onboarding, ExtraPhotoDomains, HonestReport, ContentView |
| R-07 | `ProgressView` etichettata + determinata | 🟡 | HonestReport, Home, Dashboard, Compression, ExtraPhotoDomains |
| R-08 | Layout categoria adattivo (ViewThatFits) | 🟡 | Dashboard, HonestReport, CategoryReview |
| R-09 | Parsimonia gradiente/glow + contrasto | 🟡 | HonestReport, Home, Onboarding |
| R-10 | Accessibilità stima/simboli | 🟢 | HonestReport, Onboarding, Dashboard |
| R-11 | Rifiniture minori | 🟢 | HonestReport, ThemeSettings, ExtraPhotoDomains |

**Cadenza suggerita**: 1-2 task per sessione di BUILD, ognuno chiuso al proprio
confine CI, aggiornando `SESSION-STATE.md` sul verde. Nessun task tocca Domain/Data;
l'altitudine resta invariata.
