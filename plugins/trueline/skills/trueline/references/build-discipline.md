# references/build-discipline.md — Trueline · disciplina di costruzione

> Reference di livello 3, caricato **on demand** solo per la modalità attiva
> (`02` §6). In **BUILD** valgono tutti i momenti; in **REMEDIATE** il
> sottoinsieme che ha senso (momenti 1+3 + la disciplina di fix — §5).
>
> **Cos'è.** La disciplina di *scrittura* (writing/reasoning) per lo step di
> costruzione: come l'agente ragiona prima di scrivere, come traduce il criterio
> di accettazione in un test, e come scrive il diff minimo. Riequilibra la metà
> **BUILD** di `L-COL-015` (lifecycle, non solo verificatore).
>
> **Cosa NON è.** Non è un oracolo e non emette verdetti. Migliora *come* si
> scrive; il **checkpoint a 4 controlli** (`01` §4) resta l'unico giudice
> (`L-COL-002`). "Codice pulito/elegante" non è oracolabile e **non si rivendica**
> come verificato (`L-COL-006`).

---

## 1. I tre strati (impilati, non in competizione)

| Strato | Governa | Giudica? |
|---|---|---|
| Disciplina di scrittura | *come* si scrive ogni task (assunzioni esplicite, codice minimo, diff chirurgico) | mai |
| Spina di processo | *il flusso* (intento → design → piano → test-first → debug) | mai |
| Il verdetto — **oracoli Trueline** | pulito/sicuro/conforme al confine del macrotask | **solo qui** |

La disciplina sta nella corsia permessa all'LLM — **ragionare, decomporre,
tradurre, scrivere** — mai in quella vietata: **emettere verdetti**.

---

## 2. I tre momenti della costruzione (BUILD)

Per **ogni** task atomico, dentro lo step 2 di `build.md`:

### Momento 1 — Gate delle assunzioni *(Think Before Coding)*

Prima di scrivere una riga:

- **enumera le assunzioni** che il task richiede (input, contratti, formati,
  side-effect attesi);
- se ci sono **più interpretazioni**, presentale tutte e **fermati** finché
  l'ambiguità non è risolta — non scegliere in silenzio;
- **riconcilia** le assunzioni contro gli `acceptance_criteria` (given/when/then)
  del task: se un criterio non vincola un'assunzione che stai per fare, è un
  segnale di ambiguità.

**Floor deterministico.** Quando un `acceptance_criteria.then` è strutturalmente
non-osservabile — contiene un token vago bannato (vedi §6) o non nomina alcun
osservabile concreto — il momento 1 **non procede**: emette una nota
machine-readable

```json
{ "task_id": "...", "ac_id": "...", "reason": "...", "action": "return-to-blueprint" }
```

e il checker deterministico `scripts/blueprint/ac_observability_check.mjs`
(`05` §5.4 della spec di design) la **flagga** → ritorno al blueprint (`11`
§5.2). Questo è un **gate falsificabile**, non un parere.

**Advisory oltre il floor.** L'ambiguità semantica più profonda (un criterio ben
formato ma poco sensato) resta colta dal self-check semantico, guidato dall'LLM
ma vincolato (`references/blueprint/self-check-checklist.md` §6): **dichiarato
advisory**, *non* parte del gate (`L-COL-006`). È puro ragionamento → compatibile
con `L-COL-002`.

### Momento 2 — Test-first sull'AC: *traduci*, non scrivere il tuo giudice

Scrivi **prima** il `target_test` che fallisce, poi il codice che lo fa passare
(TDD). Ma con una **regola di provenienza** che chiude l'esposizione del
controllo 4:

- in BUILD le **asserzioni** del test d'accettazione (oracolo del controllo 4)
  **derivano dagli `acceptance_criteria` (given/when/then) scritti dal
  blueprint** e devono tracciare ad essi;
- l'LLM fa **scaffold/wiring** del file di test (boilerplate, fixture, import),
  **non inventa** il comportamento asserito;
- un `target_test` le cui asserzioni **divergono** dal suo AC è esso stesso un
  **difetto-blueprint / violazione d'integrità del controllo 4** (`L-COL-019`
  tiene il giudice di proprietà del blueprint, non dell'LLM in BUILD);
- un `target_test` la cui asserzione **non può fallire** non è un oracolo: è un
  verde senza contenuto. La **provenienza non implica il potere** — un'asserzione
  può discendere dall'AC alla lettera e restare incapace di dire di no.

**Convenzione di provenienza (meccanizzata, AT-1 Fase B).** Ogni blocco del
`target_test` che esercita un AC porta un tag `covers: <AC-id>` **in un commento**
(`// covers: AC-1`, anche di coda: `expect(...); // covers: AC-1`). In BUILD con
`--blueprint`, il controllo 4 esige che ogni AC **valutato** sia tracciato da ≥1 suo
`target_test` in-scope così taggato: un AC non tracciato rende il controllo 4 **rosso
prima di eseguire** (oracolo `scripts/blueprint/ac_assertion_trace_check.mjs`, sibling
di `validate_blueprint`). È **per-AC globale** (basta un file coprante taggato) e
**ancorato all'id** (`AC-1` ≠ `AC-10`); un tag dentro una **stringa** non conta
(string-aware). La presenza-del-tag è un **floor deterministico** (`L-COL-006`): prova
*che* il file dichiara quale AC esercita, **non** che l'asserzione sia semanticamente
fedele (quello resta advisory). Lo schema del task e `validate_blueprint` **non
cambiano**: il tag vive nel file di test, non nel blueprint.

**Potere dell'asserzione (meccanizzato, AT-1 Fase C).** Quando **tutti** i `target_test`
in scope sono verdi, il controllo 4 chiede una seconda cosa: che l'asserzione **potesse
fallire**. Il caso che il gate coglie è l'asserzione **tautologica** —
`expect(A).toEqual(B)` (o `assert.deepEqual(A, B)`) dove i due lati sono lo **stesso
oggetto**, perché il lato atteso è importato dallo stesso modulo che il codice sotto test
usa: l'uguaglianza è vera **per costruzione** e resta verde qualunque cosa accada al
valore.

**Cosa devi fare mentre scrivi il `target_test`.** Il **lato atteso** — l'argomento di
`toEqual`/`toBe`, il **secondo** di `assert.deepEqual` — dev'essere un valore **scritto
nel test**: un letterale, una fixture, un valore ricalcolato a mano. **Non** il binding
che l'implementazione importa a sua volta. Se l'AC dice *"la config espone i token di
`tokens.ts`"*, asserisci contro i **valori** attesi, non contro `tokens.ts`: altrimenti
stai asserendo `X === X` e il test resterebbe verde anche cancellando tutti i token.

**Cosa succede se non lo fai.** L'oracolo `scripts/blueprint/ac_assertion_power_check.mjs`
(fratello di `ac_assertion_trace_check`: quello verifica la *provenienza*, questo il
*potere*) neutralizza **temporaneamente** il binding esportato del lato atteso — nel
sorgente dell'albero su cui il checkpoint sta girando — e riesegue **quel solo**
`target_test`. Se resta **verde**, l'asserzione è **inerte** e il controllo 4 è **ROSSO**.
A emettere il verdetto è l'**esecuzione**, mai l'analisi
statica — lo statico si limita a *proporre* candidati, ed è volutamente sovra-inclusivo
(`L-COL-002`). Gira **dopo** che i `target_test` sono passati: su un controllo 4 già rosso
non costa nulla.

**Il ripristino, e i modi in cui può non riuscire** (`L-COL-006`: ciò che non si garantisce
si dichiara, non si tace). Nel caso normale il file torna **bit-identico**: si riscrivono i
**byte grezzi** letti prima della mutazione — mai una stringa ri-codificata — e il
ripristino è **verificato per sha256**. Un ripristino non bit-esatto è un `error`, mai un
verde. Quello che quella frase **non** promette, e che va saputo prima di far girare il gate
su un albero a cui tieni:

- **il write di ripristino può lanciare** (EBUSY, file in sola lettura, un antivirus che
  tiene aperto il file — su Windows succede). Allora il file resta **neutralizzato**, il
  controllo 4 esce `error` **nominando il file**, e da quel momento ogni ulteriore giro
  dell'oracolo **in quel processo** esce `error` senza toccare più nulla: un `error` che
  significa «ho mutato il sorgente» non deve poter diventare un verde al tentativo dopo;
- **una rete su `exit` e sui segnali** (`SIGINT`/`SIGTERM`, più `SIGBREAK` su Windows)
  tiene i byte originali dei file in volo e li riscrive all'uscita, anche anomala. È una
  rete, non una garanzia: gira solo se il processo arriva a eseguirla;
- **c'è una finestra in cui nessun handler gira.** Il `target_test` è rilanciato con
  `spawnSync` **senza timeout**: fra la mutazione e il ripristino il processo può restare
  fermo su un test appeso, e un `kill -9`, un riavvio o un crash dell'host in quell'istante
  lasciano il file **mutato sul disco** senza che `finally`, `exit` o segnali vengano mai
  eseguiti. Il file è sempre **uno solo** e sempre un `export const` ridotto alla sua forma
  inerte (`{}`, `[]`, una sentinella): `git diff` lo mostra subito e `git checkout -- <file>`
  lo annulla. Il timeout non c'è **per scelta**, non per dimenticanza: aggiungerlo
  cambierebbe anche il run normale del controllo 4.

**Quando l'oracolo non arriva lo dichiara — e non ti blocca per questo.** Due specie di
irrisolto, opposte:

- **`structural`** — l'oracolo **non può** giudicare per costruzione: binding di namespace
  (`import * as ns`, dove non esiste alcun `export const ns` da neutralizzare),
  initializer non riducibile a inerte (`= make()`), dichiarazione presente **solo in un
  commento**, binding fuori dall'app. Il progetto non ha nulla che non va: **non degrada
  mai**, si **dichiara** nella coverage col suo motivo.
- **`failure`** — l'oracolo **doveva** farcela e qualcosa è andato storto: run in errore,
  **zero test eseguiti**, runner non configurato. **Degrada sempre**, anche se è l'unico e
  anche se altri candidati sono stati aggiudicati: un oracolo che non ha girato non passa
  per verde (`L-COL-006`).

**Cosa il gate NON copre — dichiarato, non assunto** (`L-COL-006`). Un test **debole ma
non tautologico** (può fallire, ma esercita meno di quanto l'AC pretenda) resta
**scoperto**: qui non c'è mutation testing generale. La granularità è il **file**, quindi
un altro test dello stesso file che diventa rosso maschera l'inerzia → **falsi negativi
possibili**: è il verso giusto in cui sbagliare, perché un falso positivo renderebbe rosso
un progetto sano.

I falsi positivi sono **la direzione che l'oracolo si vieta**, e per questo va detto dove
resta possibile invece di promettere che non lo è. Il matcher dei candidati **non parsa**:
riconosce la forma dell'asserzione con una regex sul sorgente **mascherato dai commenti**,
ma i **letterali di stringa restano intatti** — devono, perché un'asserzione legittima può
contenere un accesso a chiave (`obj['k']`). Quindi un'asserzione **citata dentro una
stringa** (un template di messaggio, una tabella di esempi, un test che genera codice)
resta visibile al matcher; se **entrambi** i lati sono anche binding importati veri e la
forma dell'export è neutralizzabile, l'oracolo muta un modulo e può dichiarare **INERTE** un
test sano. È una congiunzione stretta — mai osservata sulle fixture né sulla misura del
30/07/2026 — ma è un percorso **noto**, non un'ipotesi, e nessun `error` lo copre: si
presenterebbe come un controllo 4 rosso. Se ti succede, il `detail` nomina file, riga e
binding: verifica quella riga prima di riscrivere il test.

Per le mutazioni **comportamentali** la rete non è questa ed esiste già: è il **controllo 3**
(regressioni sull'intera suite), dove una mutazione che cambia davvero il comportamento rompe
i test che lo esercitano altrove.

### Momento 3 — Scrittura minima e chirurgica *(Simplicity First + Surgical Changes)*

Il **diff più piccolo** che fa passare il test:

- **niente astrazioni speculative** (classi/interfacce/layer per un solo uso);
- **niente error-handling per scenari impossibili**;
- "se 200 righe potevano essere 50, riscrivi";
- **ogni riga cambiata traccia al task**; rispetta lo **stile esistente**;
- **non lasciare orfani nuovi**: scrivi stretto, *non* generare dead-code.
  Questo è **allineato** a `L-COL-021`, non coincidente: `L-COL-021` governa la
  rimozione human-gated del dead-code *rilevato*; qui si tratta di **non
  introdurne**. **Nessuna cancellazione autonoma**: ogni rimozione effettiva
  resta sul path dead-code human-gated (`L-COL-021`).

**Passata di tidy advisory** (chiusura del momento). Domanda-guida: *"troppo
complicato? ogni riga traccia al task?"*. Quando scatta, **registra una nota
ispezionabile** `{ advisory: true, complexity_flag: true, notes: [...] }`, **mai
un verdetto**. La nota sta **fuori** dagli input di `run_checkpoint` → non può
fare da gate (lo prova il sotto-test §7.2a dell'harness). È un segnale per
l'umano, non un cancello.

---

## 3. Disciplina di costruzione della fix — loop RED *(root-cause-before-patch)*

Vale nel **loop di fix a checkpoint-RED** (`build.md` §4 Rosso; `05`;
`remediate.md` §5), dove il rischio è il difetto "sporco su sporco" (entropia
monotona a ogni iterazione di patch).

Prima di ri-editare:

1. **modella l'intorno e la causa radice** del finding rosso — non la
   manifestazione superficiale;
2. poi applica la **patch minima** che attacca quella causa;
3. **riesegui lo stesso oracolo** che ha trovato il problema + riesegui i test.

*Puro ragionamento, advisory, mai gate* — il re-run dello **stesso** oracolo
emette il verdetto (`L-COL-002`). Il budget di retry resta `O-COL-006`
(`MAX_RETRIES_PER_FINDING = 2`, patch materialmente diversa).

---

## 4. Il confine oracle-as-judge (la linea che non si attraversa)

- I momenti **producono** il codice; il **checkpoint a 4 controlli giudica**
  (`01` §4). La disciplina non emette mai "è sicuro" / "ho sistemato" / "via
  libera".
- Il `verify:` di ogni passo è **un test/oracolo**, mai l'auto-giudizio dell'LLM
  — e (momento 2) il test è **vincolato all'AC del blueprint**, non scritto
  liberamente in BUILD.
- L'osservabilità degli AC ha un **floor deterministico**
  (`ac_observability_check.mjs`); l'ambiguità oltre il floor è **advisory
  dichiarata**, non gated.
- Il tidy self-check (momento 3) è **advisory con output ispezionabile** ma
  **fuori dagli input del checkpoint** → non può gating.
- **Asimmetria onesta** (`L-COL-006`): "pulito/elegante" non è oracolabile,
  quindi non si rivendica come verificato.

**Questi momenti guidano la scrittura; l'oracolo resta il giudice.**

---

## 5. Sottoinsieme attivo per modalità

| Momento | BUILD | REMEDIATE |
|---|:---:|:---:|
| 1 — Gate delle assunzioni | ● | ● |
| 2 — Test-first che traduce l'AC | ● | — (superato dalla baseline di caratterizzazione) |
| 3 — Scrittura minima e chirurgica | ● | ● |
| Disciplina di fix (root-cause-before-patch, §3) | ● | ● |

In **REMEDIATE** i momenti attivi sono **1 + 3 + la disciplina di fix**. Il
**momento 2 (test-first) è superato** dalla baseline di caratterizzazione
(`06`/`remediate.md` §5, partizione guardia/impattate): in REMEDIATE non si
scrive un test-che-fallisce-prima per una fix — la rete è la caratterizzazione
del comportamento corrente.

---

## 6. Token vaghi bannati (floor del momento 1)

Lista verbatim allineata a `references/blueprint/self-check-checklist.md` §6. Un
`acceptance_criteria.then` che li contiene (substring, case-insensitive) è
strutturalmente non-osservabile → flaggato da `ac_observability_check.mjs`:

- **funziona bene**
- **robusto**
- **sicuro**
- **performante**
- **user-friendly**

Un AC **passa** quando nomina un osservabile concreto (uno status code, una riga
scritta con un certo valore, un insieme vuoto, un errore atteso, un campo a un
valore noto). Domanda-guida: *quale comando/test fa diventare questo criterio
verde o rosso?*

---

## 7. Provenienza e attribuzione

La disciplina è **encodata nativa** in Trueline (self-contained / cross-tool,
`L-COL-009`): nessuna dipendenza da skill esterne installate.

- **Disciplina di scrittura** — *Simplicity First*, *Surgical Changes* e il
  gate-assunzioni *Think Before Coding* assorbono **solo l'additivo** delle linee
  guida **Karpathy** (analisi del repo `multica-ai/andrej-karpathy-skills`, autore
  `forrestchang`, licenza **MIT**; fonte originale: post di Andrej Karpathy). Si
  **scarta** il "loop until verified" LLM-interno e qualunque self-judge come
  gate: la notazione `Step → verify` è **ri-legata all'oracolo** Trueline.
- **Spina di processo** — il flusso intento → design → piano → test-first e la
  disciplina **systematic-debugging** (root-cause-before-patch, §3) sono
  ri-espressi **nativi** dalla pratica **superpowers**, non importati come
  dipendenza.

In tutti i casi: la disciplina **guida la scrittura**; l'**oracolo resta l'unico
giudice** (`L-COL-002`); "pulito/elegante" non è oracolabile né rivendicato
(`L-COL-006`). Ledger: `L-COL-031` (raffina `L-COL-015`/`L-COL-019`).
