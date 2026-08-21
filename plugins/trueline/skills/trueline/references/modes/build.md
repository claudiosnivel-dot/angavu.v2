# modes/build.md — Trueline · modalità BUILD

> Caricato **solo** quando il dispatch risolve a BUILD (`02` §6). Un macrotask
> alla volta, ancorato al checkpoint a 4 controlli (`01` §3.2, §4).

---

## Quando

`SESSION-STATE.md` + blueprint presenti, repo con codice. È il loop di
costruzione. La promessa: *conformità alla specifica* — il codice fa ciò che il
task atomico diceva, niente morto, niente vuln note, niente regressioni
(`01` §3.2, VISION §6).

---

## Reference e script caricati in BUILD (`02` §6)

**Reference (livello 3, on demand):**

| File | Perché |
|---|---|
| `references/build-discipline.md` | disciplina di *costruzione* (i 3 momenti + fix root-cause + confine oracle-as-judge) — guida la scrittura, non giudica (`L-COL-031`) |
| `references/oracles/thresholds.md` | soglie di severità per il controllo 2 e budget del loop |
| `references/oracles/semgrep-ai-ruleset/` | ruleset Semgrep curato (vendorizzato, offline) |
| `references/conventions/named-standards.md` | vocabolario OWASP 2025 / ASVS / CWE + standard RLS |
| `references/conventions/forbidden-patterns.md` | catalogo dei pattern vietati (spec del ruleset) |
| `references/conventions/threat-model.md` | procedura di enumerazione adversariale per puntare gli oracoli |
| `references/finding-model.md` | schema dei finding: contratto tra oracoli, loop e triage (`04`) |
| `references/ecosystems/supabase-jsts/guide.md` | specifiche dell'ecosistema attivo (risolto da `scripts/ecosystem/resolve.mjs`; esempio v1: supabase-jsts) |

Lo schema del task (`references/blueprint/atomic-task-schema.md`) non si ri-carica
in pieno in BUILD: i `acceptance_criteria` + `target_tests` del task corrente
**sono già nel blueprint** e vengono letti da lì. Sono l'oracolo del controllo 4.

**Script usati:**

| Script | Funzione |
|---|---|
| `scripts/checkpoint/run_checkpoint.mjs` | orchestra i 4 controlli, emette verde/rosso |
| `scripts/checkpoint/checkpoint.mjs` | logica di gating per controllo e per categoria |
| `scripts/checkpoint/thresholds.mjs` | loader delle soglie di `references/oracles/thresholds.md` |
| `scripts/oracles/run_semgrep.mjs` | Semgrep + ruleset curato |
| `scripts/oracles/run_gitleaks.mjs` | segreti in working tree e diff |
| `scripts/oracles/run_osv.mjs` | CVE nelle dipendenze (lockfile) |
| `scripts/oracles/rls_check.mjs` | RLS checker custom su migration DDL |
| `scripts/oracles/run_deadcode.mjs` | knip (primario) / ts-prune / depcheck |
| `scripts/oracles/run_dupcheck.mjs` | jscpd — duplicazione verbatim (controllo 1, se dichiarato) |
| `scripts/oracles/run_cyclecheck.mjs` | madge — cicli di import (controllo 1, JS/TS, se dichiarato) |
| `scripts/oracles/twin_check.mjs` | twinning per-entità — **segnale** detection-only (mai gate) |
| `scripts/findings/normalize.mjs` | output nativo degli oracoli → finding model |
| `scripts/findings/baseline.mjs` | baseline-delta (sicurezza) + **baseline d'igiene** committato per dup/cycle; `--hygiene` = refresh |
| `scripts/findings/prioritize.mjs` | ordina i finding per il loop |
| `scripts/findings/explain.mjs` | spiegazione in linguaggio semplice (triage) |
| `scripts/findings/fp_policy.mjs` | policy conservativa falsi positivi (`L-COL-028`) |
| `scripts/triage/triage.mjs` | orchestra prioritizzazione + spiegazione |
| `scripts/loop/run_loop.mjs` | loop di verifica della fix (per finding rossi) |
| `scripts/loop/loop.mjs` | macchina a stati del loop per-finding |
| `scripts/git/detect_deploy_coupling.mjs` | rileva deploy-coupling prima del merge autonomo |
| `scripts/git/layered_git.mjs` | modello git a strati (branch, merge, distruttive) |

---

## Pipeline (`01` §3.2)

### 0. Preflight delle dipendenze (prima di tutto, `01` §4)

**Primissima azione, prima del checkpoint (che gira gli oracoli).**
`scripts/preflight.mjs` **controlla** le dipendenze (`gitleaks`/`osv-scanner`/
`semgrep`/`knip`; `rls_check` è built-in), **le installa project-local** —
`--install --target=project`, consent-gated → `<progetto>/.trueline/bin/`
(gitignorato) — e **ti comunica i non-installabili** con i passi/comandi manuali
(il controllo dipendente degrada a *not-run*, mai un verde finto, `L-COL-006`).

### 1. Seleziona il macrotask corrente

Da `SESSION-STATE` + blueprint, rispettando le dipendenze del DAG
(`depends_on`). Il macrotask con tutte le dipendenze verdi è il candidato.

### 2. Costruisce i task atomici

Sul **branch di lavoro** (`trueline/build/<macrotask>`). Mai direttamente su
`main`. La costruzione consuma i `definition_of_done` + `acceptance_criteria`
del task come specifica da soddisfare, non come checklist a posteriori.

La **disciplina di costruzione** (`references/build-discipline.md`, `L-COL-031`)
governa il *come* si scrive ogni task atomico, in **tre momenti** — guidano la
scrittura, **non** giudicano (l'oracolo resta il giudice, `L-COL-002`):

1. **Gate delle assunzioni** *(Think Before Coding)*: prima di scrivere, enumera
   le assunzioni, presenta le interpretazioni se più d'una, **fermati** se
   ambiguo, e riconcilia contro gli `acceptance_criteria`. **Floor
   deterministico:** un `then` con un token vago bannato ("funziona bene",
   "robusto", "sicuro", "performante", "user-friendly") o senza osservabile è
   flaggato da `scripts/blueprint/ac_observability_check.mjs` → ritorno al
   blueprint (`11` §5.2). L'ambiguità più profonda resta advisory
   (`self-check-checklist.md` §6), mai gate (`L-COL-006`).
2. **Test-first che *traduce* l'AC**: scrive prima il `target_test` che fallisce,
   poi il codice. Le **asserzioni** del test **derivano dagli `acceptance_criteria`
   (given/when/then) del blueprint** e tracciano ad essi; l'LLM fa scaffold/wiring,
   **non inventa** il comportamento asserito. Un test che diverge dal suo AC è un
   difetto-blueprint (`L-COL-019`).
3. **Scrittura minima e chirurgica** *(Simplicity First + Surgical Changes)*: il
   diff più piccolo che fa passare il test; niente astrazioni speculative; ogni
   riga traccia al task; **non lascia orfani nuovi** (allineato a `L-COL-021`,
   nessuna cancellazione autonoma). A chiusura, una **passata di tidy advisory**
   registra una nota ispezionabile `{advisory:true, complexity_flag:...}` **fuori**
   dagli input del checkpoint — mai un verdetto.

Se un task tocca **codice pre-esistente non testato** (legacy senza copertura),
la skill genera prima la caratterizzazione della porzione toccata
(`scripts/characterization/`, `06-CHARACTERIZATION-TESTS` §9) prima di
procedere.

### 3. Checkpoint al confine del macrotask

Gira `scripts/checkpoint/run_checkpoint.mjs`. I quattro controlli, autorità =
oracolo (`01` §4):

| # | Controllo | Oracolo (fonte di verità) | Verde quando |
|---|---|---|---|
| 1 | Igiene strutturale | dead-code (`run_deadcode`/knip) + dup/cycle (`run_dupcheck`/`run_cyclecheck`, se il pack li dichiara) + twin (segnale) | nessun **nuovo** difetto d'igiene introdotto (delta); dup/cycle gatano sul delta vs **baseline d'igiene committato**; il pre-esistente è segnalato, non cancellato in autonomia (`L-COL-021`) |
| 2 | Sicurezza | Semgrep + gitleaks + osv + RLS checker | nessun finding nuovo ≥ soglia nelle categorie in scope (`references/oracles/thresholds.md`) |
| 3 | Regressioni | suite di test esistente | nessun test prima verde ora rosso |
| 4 | Conformità-logica | i `target_tests` del task atomico corrente | i criteri di accettazione (`L-COL-019`) sono soddisfatti |

L'LLM **non** decide l'esito di nessuno dei quattro. Verde/rosso è una proprietà
dell'output degli strumenti, non una frase.

> **Coverage del controllo 1 (`L-COL-006`).** Duplicazione = verbatim ≥ `min_tokens`
> token (jscpd); i cloni **rinominati** (clone-and-rename per-entità) NON sono coperti dal
> gate → `twin_check` li **segnala** (detection-only, mai gate). Cicli = solo pack **JS/TS**
> (madge); per le altre lingue i cicli sono dichiarati non-coperti. L'efficienza/altitudine
> non è gate-abile (Rice); l'altitudine come *contratto dichiarato* è dominio di `arch_check`
> (A2b), non del controllo 1. dup/cycle **gatano in BUILD**, sono **report-only in REMEDIATE**.
> Il baseline d'igiene assorbe il debito pre-esistente (**refresh:** `baseline.mjs capture
> <dir> --hygiene`, ricalcolo → ratchet); un oracolo d'igiene dichiarato ma **non eseguito**,
> o un baseline d'igiene **assente** in BUILD, **NON** è verde (guard, come `arch_check`).

### 4. Verde → commit + modello git

Su checkpoint verde:

1. **Commit atomico** sul branch: messaggio che cita gli ID dei task e l'esito
   del checkpoint (storia revertabile per task).
2. **Rilevamento deploy-coupling** (`scripts/git/detect_deploy_coupling.mjs`,
   `L-COL-025`): l'esito è registrato in `SESSION-STATE` e confermato una volta
   con l'utente.
3. Se `main` **non** è deploy-coupled → merge autonomo su `main` (autorità =
   checkpoint verde).
4. Se `main` è deploy-coupled → merge **sospeso**, torna human-gated; in
   alternativa la skill redirige l'autonomia su un branch `staging`.

### 4. Rosso → loop di fix

Entra in `scripts/loop/run_loop.mjs` (`05-VERIFY-FIX-LOOP`):

```
per ogni finding fixabile, in ordine di triage (prioritize.mjs):
  proponi patch → gate umano (L-COL-005) → applica sul branch
  → riesegui lo stesso oracolo + riesegui i test
  → se pulito + verde: finding → verified (solo l'oracolo, L-COL-002)
  → se ancora rosso: retry ≤ 2 (O-COL-006) con patch materialmente diversa,
    poi terminale → umano (accepted-risk / fix manuale)
quando tutti i finding fixabili sono chiusi:
  ri-valuta il checkpoint intero (run_checkpoint.mjs)
  verde → commit + modello git (sopra)
  rosso (una fix ne ha introdotto uno nuovo) → rientra nel loop
```

**Budget:** `MAX_RETRIES_PER_FINDING = 2` (3 tentativi totali per finding) +
`GLOBAL_WALL_CLOCK_MS` come da `references/oracles/thresholds.md` §5.
Budget esaurito → stato terminale presentato all'umano; mai scarto silenzioso,
mai `verified` (`L-COL-006`).

**Falsi positivi:** `scripts/findings/fp_policy.mjs` applica la policy
conservativa (`L-COL-028`): l'LLM può segnalare un sospetto-FP con evidenza
concreta e abbassarne la priorità, ma non può sopprimerlo né cambiarne la
severità. Il FP confermato si codifica nell'allowlist che l'oracolo legge
(`.gitleaks.toml`, ignore di knip, `# nosemgrep`) — la soppressione è
dell'oracolo, non dell'LLM.

**Dead-code:** le rimozioni non sono mai automatiche (`L-COL-021`). La skill
propone; l'umano approva.

### 5. Aggiorna `SESSION-STATE`

Macrotask fatti/in corso, baseline aggiornata, budget consumato. Prossimo
macrotask secondo il DAG.

---

## Disciplina BUILD

**Disciplina di SCRITTURA** (`references/build-discipline.md`, `L-COL-031`) — il
*come* si scrive ogni task:

- **Gate delle assunzioni** *(Think Before Coding)*: enumera le assunzioni,
  fermati se ambiguo, riconcilia contro gli `acceptance_criteria`; floor
  deterministico `ac_observability_check.mjs` sui `then` non-osservabili.
- **Test-first che traduce l'AC**: scrivi il test che fallisce; le asserzioni
  derivano dagli `acceptance_criteria` del blueprint, non si inventano (`L-COL-019`).
- **Scrittura minima e chirurgica** *(Simplicity First + Surgical Changes)*: il
  diff più piccolo che fa passare il test; ogni riga traccia al task; **non
  introdurre orfani** (allineato a `L-COL-021`); tidy advisory ispezionabile,
  fuori dal checkpoint.
- **Fix root-cause-before-patch** *(systematic-debugging)*: nel loop RED, modella
  la causa radice prima di ri-editare; poi la patch minima.

**Questi guidano la scrittura, l'oracolo resta il giudice** (`L-COL-002`).

**Disciplina di GATE** — il *chi giudica*:

- **Oracle-as-judge** (`L-COL-002`): verde/rosso viene dall'oracolo, mai dall'LLM.
- **Acceptance tests come oracolo del controllo 4** (`L-COL-019`): è l'aggancio tra
  piano (BOOTSTRAP) e costruzione (BUILD) che impedisce all'LLM di giudicare sé stesso.
- **Git a strati** (`L-COL-024`): branch autonomo; merge su `main` gated dal
  checkpoint verde; distruttive mai autonome.
- **Deploy-coupling fail-safe** (`L-COL-025`): in caso di ambiguità o mancata
  conferma si assume `main_deploy_coupled: true` → merge human-gated.
- **Human-in-the-loop sulle fix** (`L-COL-005`): ogni patch richiede il "vai" umano
  prima dell'applicazione; anche ogni retry.
- **Preflight project-local** (`L-COL-005`): prima di scaricare i binary-release
  degli oracoli (gitleaks/osv-scanner project-local in `<project>/.trueline/bin/`)
  la skill assicura che `.trueline/` sia nel `.gitignore` del progetto, così i
  binari scaricati non finiscono nel versionato.
- **Degradazione semgrep dichiarata** (`L-COL-006`): se semgrep non è disponibile
  (né docker né python/pip/pipx) i controlli `injection`/`authz` del controllo 2
  **degradano** a *not-run*, dichiarato all'utente — mai un verde finto.

---

## Uscita

Tutti i macrotask verdi → blueprint completato. `SESSION-STATE` aggiornata.
