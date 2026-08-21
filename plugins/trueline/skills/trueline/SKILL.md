---
name: trueline
description: >
  Trueline e una lifecycle skill di security review e remediation per progetti di
  coding JS/TS (JavaScript/TypeScript) su Supabase. Genera un blueprint di task
  atomici verificabili, costruisce un macrotask alla volta (build), e verifica
  ogni macrotask con oracoli deterministici (security/sicurezza, secret/segreti,
  RLS, dead-code) prima di committare — l'oracolo emette il verdetto, mai l'LLM.
  Tre modalita: bootstrap (avvia un nuovo progetto con un blueprint e task
  atomici), build (avanza il prossimo macrotask del blueprint), remediate (fai un
  audit di sicurezza e bonifica secret e RLS di un repo esistente). Trigger
  multilingue (IT/EN): security review, security audit, fai un audit, metti in
  sicurezza, harden, secure, remediate, remediation, bonifica, RLS, secret,
  segreti, blueprint, avvia progetto, start project, avanza macrotask, next
  macrotask, oracoli su un codebase Supabase, pianificazione blueprint-first.
when_to_use: >
  Usa quando l'utente chiede di, su un codebase JS/TS (JavaScript/TypeScript) su
  Supabase con un agente: (bootstrap) avviare o impostare un nuovo progetto con
  un blueprint e task atomici; (build) avanzare o costruire il prossimo macrotask
  del blueprint; (remediate) fare un audit di sicurezza e bonificare secret e RLS
  di un repo esistente. Trigger multilingue — IT: metti in sicurezza, fai un
  audit, bonifica, remediation, RLS, secret/segreti, blueprint, avvia progetto,
  avanza macrotask, oracoli; EN: security review, security audit, harden, secure,
  remediate, secrets, blueprint, start project, next macrotask.
---

# Trueline — corpo della skill (livello 2)

Disciplina **blueprint-first di build-e-verifica** per progetti JS/TS su Supabase.
La skill non giudica il codice a intuito: lancia **oracoli deterministici**, ragiona
sui fatti che producono, propone correzioni, e ne accetta una **solo dopo averla
ri-verificata** con lo stesso oracolo e una rete di test. Il verdetto e una proprieta
dell'output di un comando, mai una frase dell'LLM.

Questo corpo fa quattro cose e nient'altro: **risolve l'intento** e sceglie la
modalita, **dispatcha** caricando solo i reference della modalita attiva, tiene
visibili le **invarianti non negoziabili**, e invoca l'**hook di preflight**. Tutto il
peso (ruleset, schema, template, soglie) sta in `references/`, caricato on demand.

---

## 1. Risoluzione-intento e dispatch *(L-COL-017)*

All'invocazione la skill classifica il contesto del repo e **propone** una modalita.
La classificazione e deterministica dove puo esserlo (presenza di file). Dove il
segnale e debole, la skill **non sceglie da sola**: espone cosa ha visto e **chiede
conferma esplicita** prima di costruire o modificare alcunche *(L-COL-005)*.

| Segnale osservato nel repo | Modalita | Confidenza |
|---|---|---|
| `SESSION-STATE.md` + blueprint presenti, repo con codice | **BUILD** | alta |
| Repo vuoto o quasi (nessun sorgente sostanziale, niente blueprint) | **BOOTSTRAP** | alta |
| Codice sorgente sostanziale **senza** blueprint ne `SESSION-STATE` | **REMEDIATE** | alta |
| Blueprint presente ma `SESSION-STATE` assente, o codice + blueprint parziale | **ambiguo -> chiedi** | — |
| Conflitto fra segnali (blueprint dice fase X, lo stato del codice un'altra) | **ambiguo -> chiedi** | — |

**Regola dura.** Nei casi ambigui la skill propone la modalita piu probabile e
**attende conferma**. Protegge dal caso peggiore: far partire REMEDIATE che modifica
codice quando l'utente voleva BUILD, o viceversa.

Indizi di classificazione (euristici): presenza di `00-INDEX.md` + `SESSION-STATE.md`
nella radice del blueprint; conteggio e maturita dei sorgenti; presenza di una
directory di blueprint riconoscibile. Gli indizi alimentano la *proposta*; non
sostituiscono la conferma nei casi ambigui.

**Classificazione dell'ecosistema.** La skill rileva l'ecosistema attivo del repo
tramite `scripts/ecosystem/resolve.mjs`: ogni manifest in `references/ecosystems/`
dichiara un campo `detect` (file sentinella, es. `supabase/config.toml`) e un campo
`triggers` (parole chiave nell'intento). Il risolutore classifica il repo nel manifest
che combacia per primo (segnale forte = file sentinella; segnale debole = trigger
lessicale). Nessun manifest combacia -> ecosistema non supportato, dichiarato in
chiaro *(L-COL-006)*; mai inventato.

---

## 2. Tabella di dispatch — caricamento per modalita *(L-COL-014)*

Ogni modalita tira **solo** i reference che le servono. Questo e il cuore della
parsimonia di token: il corpo non duplica mai il contenuto di un reference, ci
rimanda. Carica **solo** la riga della modalita attiva.

| Reference (livello 3) | BOOTSTRAP | BUILD | REMEDIATE |
|---|:---:|:---:|:---:|
| `references/modes/bootstrap.md` | ● | | |
| `references/modes/build.md` | | ● | |
| `references/modes/remediate.md` | | | ● |
| `references/build-discipline.md` (disciplina di costruzione, `L-COL-031`) | | ● | ● |
| `references/blueprint/atomic-task-schema.md` | ● | ○ (consuma i criteri) | |
| `references/blueprint/self-check-checklist.md` | ● | | |
| `references/blueprint/template/` | ● | | |
| `references/oracles/semgrep-ai-ruleset/` (ruleset curato) | | ● | ● |
| `references/oracles/thresholds.md` (soglie + loop-budget) | | ● | ● |
| `references/conventions/named-standards.md` | ○ | ● | ● |
| `references/conventions/forbidden-patterns.md` | ○ | ● | ● |
| `references/conventions/threat-model.md` | ○ | ● | ● |
| `references/finding-model.md` | | ● | ● |
| `references/ecosystems/supabase-jsts/guide.md` (ecosistema attivo, risolto da `scripts/ecosystem/resolve.mjs`) | ● | ● | ● |

● = caricato · ○ = caricato parzialmente / solo la parte rilevante.

La riga "ecosistema attivo" indica il percorso references/ecosystems/\<attivo\>/guide.md risolto
a runtime da `scripts/ecosystem/resolve.mjs` in base ai `detect`/`triggers` del manifest. L'esempio
letterale in tabella usa `supabase-jsts` perche e l'ecosistema v1 incluso; ecosistemi futuri
aggiungeranno la propria cartella con lo stesso schema.

In **BUILD** lo schema del task atomico e gia "speso" nel blueprint: BUILD non
rilegge l'intero schema, **consuma i criteri di accettazione** del task come oracolo
del controllo conformita-logica *(L-COL-019)*. Gli **script** (`scripts/`) non si
"caricano": si **eseguono**; nel contesto entra solo il loro **output normalizzato**
*(L-COL-007)*.

---

## 3. Le tre modalita (sintesi; il dettaglio sta nei reference di modalita)

Macchina a stati con tre punti d'ingresso e **un solo motore di verifica** — il
**checkpoint** (§5). Il flusso converge sempre su quel gate prima di toccare `main`.

### 3.1 BOOTSTRAP — dal nulla al piano (`references/modes/bootstrap.md`)
Repo vuoto/quasi. **Non produce codice.** Raccoglie l'intento dall'utente (obiettivo,
ecosistema, vincoli), genera il **blueprint** in task atomici — ciascuno con
**definition-of-done + criteri di accettazione + target_tests** *(L-COL-019)*, schema
in `references/blueprint/atomic-task-schema.md` —, passa il **self-check** (strutturale
via `scripts/blueprint/validate_blueprint.mjs`; semantico via
`references/blueprint/self-check-checklist.md`), **emette i 3 prompt** parametrizzati
(`assets/prompts/`, `L-COL-022`), e istanzia `SESSION-STATE`.

### 3.2 BUILD — un macrotask alla volta (`references/modes/build.md`)
Blueprint + `SESSION-STATE` presenti. Seleziona il macrotask corrente (rispettando le
dipendenze), lo **costruisce sul branch di lavoro** (mai su `main`), poi esegue il
**checkpoint** (§5). Su verde: commit atomico sul branch + modello git (§6). Su rosso:
**loop di fix** (§5) / retry / stop. Promessa BUILD: **conformita alla specifica** —
fa cio che il task diceva, niente morto, niente vuln note, niente regressioni.

### 3.3 REMEDIATE — bonifica del brownfield (`references/modes/remediate.md`)
Codice esistente sostanziale, niente blueprint. Remediation piena *(L-COL-023)*, non
solo detection. Inventaria il codebase, costruisce la **baseline di caratterizzazione**
(characterization test — sul percorso critico: senza baseline non si dimostra
l'invarianza di una fix), lancia gli oracoli -> **findings strutturati**
(`references/finding-model.md`), **triage** e spiegazione (l'LLM prioritizza e traduce,
non emette verdetti), e propone **fix human-gated** verificate col loop (§5). Lavora su
branch; il merge su `main` resta un **"vai" umano**. Promessa REMEDIATE: la
conformita-logica **degrada** a *invarianza comportamentale* — "fa ancora cio che
faceva", non "e giusto". Detto in chiaro all'utente.

---

## 4. Preflight delle dipendenze — LA PRIMA AZIONE COMUNE *(03 §4 / 09 §6)*

**Prima di qualunque oracolo** — quindi come **primissimo passo** di BUILD e REMEDIATE
(e appena serve in BOOTSTRAP) — la skill esegue `scripts/preflight.mjs`. Il patto è
sempre lo stesso: **controlla le dipendenze, le installa, e ciò che non riesce a
installare te lo comunica per farlo a mano.** Nessun oracolo parte finché lo stato delle
dipendenze non è chiaro.

- **CONTROLLA** ogni tool esterno con rilevazione deterministica + confronto con la
  **versione minima pinnata**: `gitleaks` (secret) · `osv-scanner` (dependency-vuln) ·
  `semgrep` via Docker (injection/authz) · `knip` (dead-code). `rls_check`
  (`scripts/oracles/rls_check.mjs`) è **built-in**, non richiede nulla: funziona sempre.
- **INSTALLA** i mancanti/sotto-versione, **project-local per default** e **consent-gated**
  *(L-COL-005)*: `scripts/preflight.mjs --install --target=project` scarica i
  **binary-release** di gitleaks/osv-scanner (solo `node:https`, **nessun toolchain**) in
  `<progetto>/.trueline/bin/` (gitignorato) e installa `knip` come devDependency; con
  `--target=global` usa i canali di sistema (go/brew/docker). Senza consenso esplicito
  (o `--yes`) **propone e chiede**, non installa da sé. → REMEDIATE gira anche su una
  macchina senza Go/Docker/Python.
- **COMUNICA i non-installabili**: un tool senza canale disponibile sull'OS (es.
  `semgrep` senza Docker né Python) è **dichiarato non installabile**, il suo controllo
  **degrada a "non eseguito"** (mai un verde finto, `L-COL-006`), e la skill **ti passa i
  passi/comandi manuali** per installarlo tu.
- Per il **push** verifica remote + auth: assenti → **committa in locale** sul branch e lo
  **dichiara**, senza fallire in silenzio.

Il preflight non vendorizza i binari di terzi: rileva, installa (col tuo consenso),
degrada onesto. Il `.skill` bundla solo codice nostro + reference.

---

## 5. Il checkpoint e il loop di fix *(L-COL-018, L-COL-003)*

Il **checkpoint** gira al confine di **ogni macrotask** (BUILD) ed e il motore di
verifica anche dentro REMEDIATE. **Quattro controlli, ciascuno ancorato a un oracolo;
l'LLM non decide l'esito di nessuno dei quattro.** Orchestrato da
`scripts/checkpoint/run_checkpoint.mjs`.

| # | Controllo | Oracolo (fonte di verita) | Verde quando |
|---|---|---|---|
| 1 | **Dead code** | `run_deadcode` (knip/ts-prune/depcheck) | nessun **nuovo** morto introdotto; il morto pre-esistente e **segnalato**, mai cancellato in autonomia *(L-COL-021)* |
| 2 | **Sicurezza** | `run_semgrep` (+ ruleset AI curato) · `run_gitleaks` · `run_osv` · `rls_check` | nessun finding di severita ≥ soglia (`references/oracles/thresholds.md`) nelle categorie in scope |
| 3 | **Regressioni** | suite di test esistente (BUILD) / characterization (REMEDIATE) | nessun test prima verde ora rosso |
| 4 | **Conformita-logica** | `target_tests` / criteri di accettazione del task (BUILD) / invarianza characterization (REMEDIATE) | i criteri *(L-COL-019)* sono soddisfatti / il comportamento e invariato |

**Dove sta l'LLM** *(L-COL-002)*. L'**oracolo decide** — produce il fatto, e il fatto
e il verdetto. L'**LLM esegue, normalizza** (output grezzo -> finding model via
`scripts/findings/normalize.mjs`), **prioritizza, spiega e propone** patch
(`scripts/triage/triage.mjs`). Non emette mai "e sicuro", "ho sistemato", "via libera".

**Loop di fix su checkpoint rosso** *(L-COL-003)*. Quando un controllo e rosso la skill
non procede. Entra nel **loop di verifica della fix** (`scripts/loop/run_loop.mjs`):
propone una correzione **human-gated** *(L-COL-021)*, la applica, **riesegue lo stesso
oracolo** che ha trovato il problema **e riesegue i test**, e accetta solo se il finding
e azzerato **e** nulla si e rotto. Policy di retry/scarto e tetti (budget `O-COL-006`)
in `references/oracles/thresholds.md`. **Finche il checkpoint non e verde, non si
committa oltre il branch e non si tocca `main`.** Esaurito il budget -> stato
**terminale all'umano**, mai uno scarto silenzioso, mai un `verified` finto.

---

## 6. Modello git a strati *(L-COL-024, L-COL-025)*

A pubblicare su `main` e il **verdetto deterministico dell'oracolo**, mai
l'LLM-che-dice-fatto. Il gate umano governa la *sostanza* delle fix; il checkpoint
verde e l'approvazione a *pubblicare* — tranne dove pubblicare significa **deployare**.
Logica in `scripts/git/layered_git.mjs`; rilevamento deploy in
`scripts/git/detect_deploy_coupling.mjs`.

| Strato | Operazioni | Autorita |
|---|---|---|
| **Branch di lavoro** | `init`, `checkout -b`, stage, commit, push del branch | **Autonoma.** Additivo, isolato, reversibile; commit atomici per macrotask. |
| **Merge su `main`** | merge / fast-forward / PR-merge verso `main` | **Gated dal checkpoint verde.** Asimmetria per modalita (sotto). |
| **Operazioni distruttive** | `push --force`, `reset --hard` su branch pushato, rebase di storia pubblicata, delete branch | **Mai autonome.** Sempre gate umano esplicito *(L-COL-005)*. |

**Asimmetria sul merge.** **BUILD**-verde -> merge su `main` **autonomo** (il verde =
conformita alla specifica). **REMEDIATE** -> branch autonomo, ma il merge su `main`
resta un **"vai" umano**: pubblicare una bonifica mai ancorata a un intento non e
qualcosa che la skill fa da se.

**Gate di deploy** *(L-COL-025)*. Prima di **qualunque** merge autonomo su `main` la
skill rileva se `main` e accoppiato a un deploy automatico (GitHub Actions on push,
Cloudflare Pages/Workers, `vercel.json`/`netlify.toml`, hook Supabase). Mix
**fail-safe**: auto-detect -> esito in `SESSION-STATE` (`main_deploy_coupled:
true|false|unknown`) -> confermato **una volta** con l'utente; in caso di ambiguita o
mancata conferma si **assume coupled** e il merge torna **human-gated anche sul verde**.
In alternativa la skill puo ridirigere l'autonomia su un branch `staging`.

---

## 7. Invarianti non negoziabili (valgono in tutte e tre le modalita)

Il corpo le tiene visibili a **ogni** run: governano ogni azione, non si spostano mai
in un reference.

- **Oracle-as-judge, mai LLM-as-judge** *(L-COL-002)*. "Verde" = exit/output di un
  comando, **mai** un parere dell'LLM. Ogni claim traccia a un oracolo deterministico.
- **Il loop di verifica della fix e obbligatorio** *(L-COL-003)*. Nessuna fix non
  verificata e mai presentata come fatta: applica -> riesegui lo stesso oracolo ->
  riesegui i test -> accetta solo a finding azzerato e nulla rotto.
- **Nessun falso "via libera"** *(L-COL-006)*. Il framing e sempre "trovato e
  verificata la correzione di X" / "questi controlli sono passati", **mai** "la tua app
  e sicura". L'assenza di finding non e prova di sicurezza; cio che un oracolo non
  copre va **dichiarato** non coperto, non riempito con una stima.
- **Git a strati, autorita all'oracolo** *(L-COL-024)*. Autonomia sul branch; merge su
  `main` gated dal verde; distruttive mai autonome (§6).
- **Fix human-gated** *(L-COL-005)*. La skill **propone**, non applica da sola
  correzioni; nessuna azione distruttiva o irreversibile senza approvazione esplicita.
- **Dead-code mai cancellato in autonomia** *(L-COL-021)*. Il morto e **segnalato**;
  la rimozione e una fix human-gated (falsi positivi su import dinamici / magia del
  framework).
- **Privacy per architettura** *(L-COL-013)*. Gira interamente nell'ambiente
  dell'utente; il codice **non** viene mai trasmesso a terzi; nessuna telemetria.

Le invarianti convivono con il **gate di deploy** *(L-COL-025)* di §6: un merge
autonomo su `main` deploy-coupled = deploy autonomo in produzione, quindi sospeso.

---

## 8. Riferimenti (tutti caricati on demand, per modalita attiva)

- **Modalita**: `references/modes/bootstrap.md`, `references/modes/build.md`,
  `references/modes/remediate.md`.
- **Blueprint**: `references/blueprint/atomic-task-schema.md`,
  `references/blueprint/self-check-checklist.md`, `references/blueprint/template/`.
- **Oracoli/soglie**: `references/oracles/semgrep-ai-ruleset/`,
  `references/oracles/thresholds.md`.
- **Convenzioni** *(L-COL-012)*: `references/conventions/named-standards.md`,
  `references/conventions/forbidden-patterns.md`,
  `references/conventions/threat-model.md`.
- **Finding model** *(L-COL-011)*: `references/finding-model.md`.
- **Ecosistema attivo** (risolto da `scripts/ecosystem/resolve.mjs`): `references/ecosystems/supabase-jsts/guide.md` (esempio v1; il percorso effettivo e references/ecosystems/\<attivo\>/guide.md).
- **Prompt di lifecycle** (output di BOOTSTRAP, `L-COL-022`):
  `assets/prompts/project-start.md`, `assets/prompts/session-start.md`,
  `assets/prompts/session-end.md`.
- **Script** (eseguiti, output-only nel contesto, `L-COL-007`):
  `scripts/preflight.mjs`, `scripts/blueprint/validate_blueprint.mjs`,
  `scripts/checkpoint/run_checkpoint.mjs`, `scripts/findings/normalize.mjs`,
  `scripts/triage/triage.mjs`, `scripts/loop/run_loop.mjs`,
  `scripts/git/layered_git.mjs`, `scripts/git/detect_deploy_coupling.mjs`,
  `scripts/oracles/run_semgrep.mjs`, `scripts/oracles/run_gitleaks.mjs`,
  `scripts/oracles/run_osv.mjs`, `scripts/oracles/rls_check.mjs`,
  `scripts/oracles/run_deadcode.mjs`.
