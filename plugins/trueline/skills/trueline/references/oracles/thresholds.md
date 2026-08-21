# thresholds.md — soglie del checkpoint e budget del loop (Trueline)

| | |
|---|---|
| **Progetto** | Trueline (`COL`) |
| **Milestone** | M1 (soglie di gating) + **M5 (budget del loop PINNATO empiricamente)** |
| **Copre** | soglie di severita del controllo 2 (03 §8), baseline-delta (04 §6), loop-budget (`O-COL-006`, 05 §4) |
| **Pin numerico** | budget del loop **pinnato al parity gate M5**: `GLOBAL_WALL_CLOCK_MS` = round(p95×1.25) = 242401ms (§5). Le soglie di gating restano default di policy. |

---

## 1. Perche questo file esiste

Il checkpoint (`01` §4) e il loop (`05`) **non** decidono da soli quanto e "troppo":
leggono le soglie da qui. Tenere i numeri in un reference versionato fa due cose:
le rende ispezionabili/diff-abili (un cambio di policy e un diff, non codice
nascosto) e disaccoppia la *policy* (esiste un budget, esiste una soglia) dal
*pin numerico* (il valore esatto), che dipende dalla reference app e si calibra
al parity gate di M5.

**Le SOGLIE di gating (§2-§3) sono default di policy ragionati** (non un pin
empirico: sono scelte di rischio, non misure). **Il BUDGET del loop (§5) e' ora
PINNATO EMPIRICAMENTE al parity gate M5** (§5.1).

---

## 2. Soglie di gating per categoria (03 §7)

Ogni categoria ha una regola di gating propria. La regola e **autorita dell'oracolo**:
l'LLM non decide l'esito (L-COL-002). Verde = nessun finding NUOVO che supera la
soglia della categoria (baseline-delta, §4).

### 2.1 `secret` — segreti in chiaro

| Chiave | Valore | Regola |
|---|---|---|
| `SECRET_GATE` | `always-block` | **Blocca sempre**, indipendentemente dalla severita. Qualsiasi secret NUOVO in working-tree blocca il checkpoint (BUILD e REMEDIATE). Oracolo: gitleaks working-tree. |

Motivazione: un segreto esposto non ha una "severita accettabile"; la severita
OWASP e inapplicabile (`04` §4). La regola e chiusa: zero tolleranza.

### 2.2 `rls` — Row-Level Security mancante o permissiva

| Chiave | Valore | Regola |
|---|---|---|
| `RLS_GATE_BUILD` | `block-if-touched` | In BUILD blocca se la tabella carente di RLS e **toccata dalla migration in esame** (gate per triage). Oracolo: rls_check su DDL. |
| `RLS_GATE_REMEDIATE` | `always-block` | In REMEDIATE blocca sempre se presente. La fase di fix non puo' lasciare RLS mancante. |
| `RLS_SEVERITY_FLOOR` | `HIGH` | Un finding rls con severity < HIGH (es. `MEDIUM`) **non** blocca il gate; e' segnalato nel report. In M1 rls_check emette solo `CRITICAL`/`HIGH`. |

Motivazione: RLS mancante su una tabella toccata e un rischio critico di data-leak
(S3/S4/S5 del set verificato-a-zero, L-COL-010). Il triage per tabella toccata
evita falsi positivi su tabelle di sistema gia' note.

### 2.3 `injection` / `authz` / `crypto` — categorie di iniezione e autenticazione

| Chiave | Valore | Regola |
|---|---|---|
| `INJECT_AUTHZ_CRYPTO_GATE` | `block-if-new-and-high` | Blocca se finding NUOVO **e** `severity >= HIGH`. Finding MEDIUM/LOW non bloccano (segnalati). |
| `INJECT_AUTHZ_CRYPTO_SEVERITY_FLOOR` | `HIGH` | Coincide con `GATE_SEVERITY` globale. |

Oracolo: semgrep (ruleset AI curato) — **DIFFERITO a M4** (07 §4). In M1 queste
categorie sono **detection-only**: trovate e spiegate, non gate-ate nel checkpoint.
La regola di gating qui documentata entra in vigore quando il corrispondente
oracolo e integrato (M4).

### 2.4 `dependency-vuln` — vulnerabilita nelle dipendenze

| Chiave | Valore | Regola |
|---|---|---|
| `DEPVULN_GATE` | `block-if-new-and-high` | Blocca se finding NUOVO **e** `severity >= HIGH` (CRITICAL o HIGH). |
| `DEPVULN_SEVERITY_FLOOR` | `HIGH` | MEDIUM/LOW segnalati, non bloccanti. |

Oracolo: osv-scanner su lockfile. Best-effort: se l'oracolo non e raggiungibile
(offline / lockfile assente) il controllo 2 si dichiara **degradato per osv**,
non falsamente verde.

### 2.5 `dead-code` — codice morto

Il dead-code **non** ha severita OWASP (`04` §4): il gate e per DELTA, non per severita.

| Chiave | Valore | Regola |
|---|---|---|
| `DEADCODE_GATE_ON` | `delta-only` | Blocca solo sui finding `baseline_status = new`. Il morto pre-esistente e **segnalato, non cancellato in autonomia** (`L-COL-021`). |

Oracolo: knip (via run_deadcode). Dead-code nuovo introdotto da un fix = gate rosso.
Il loop propone la rimozione; l'applicazione e sempre human-gated (`L-COL-021`).

---

## 3. Soglia globale del controllo 2 (sicurezza) — `GATE_SEVERITY`

Il controllo 2 e **verde quando nessun finding NUOVO** nelle categorie in scope ha
`severity >= GATE_SEVERITY`.

| Chiave | Default provvisorio | Note |
|---|---|---|
| `GATE_SEVERITY` | `HIGH` | Blocca su `CRITICAL` e `HIGH`. `MEDIUM`/`LOW` sono segnalati ma non bloccano il gate (restano nel report). |

Ordine di severita (decrescente): `CRITICAL > HIGH > MEDIUM > LOW`.

Le categorie del **set verificato-a-zero** (`L-COL-010`): `secret`, `rls`, `dead-code`.
Le categorie detection-only (`injection`, `authz`, `crypto`, `dependency-vuln` offline)
**non** bloccano il gate di sicurezza in BUILD prima dell'integrazione degli oracoli
corrispondenti; in REMEDIATE possono entrare nel loop ma non elevano la coverage.

---

## 4. Baseline-delta (03 §8, 04 §6)

Il gate guarda i **finding nuovi sopra soglia**, non l'assoluto. Chiave del
delta = `fingerprint` (stabile-per-riga, ancora di contenuto, mai il numero di
riga, `04` §6).

- `baseline_status = pre-existing` → gia presente nella baseline → **non** blocca
  (a meno che la modalita REMEDIATE lo prenda esplicitamente in carico).
- `baseline_status = new` → introdotto da questo macrotask/fix → **blocca** se
  `severity >= GATE_SEVERITY` (controllo 2) o se categoria `dead-code` (controllo 1).

In M1 il checkpoint accetta una baseline esplicita (insieme di fingerprint gia
noti). Baseline vuota ⇒ ogni finding e `new` (comportamento di `normalize` a
baseline vuota, `04`).

---

## 5. loop-budget — `O-COL-006` (policy chiusa in 05 §4; budget PINNATO al M5)

> La **policy** e chiusa (05 §4): esiste un cap per-finding e un budget globale,
> e come si fanno rispettare. Il **pin numerico** del tetto di tempo di parete e'
> stato **derivato empiricamente al parity gate M5** (§5.1).

| Chiave | Valore pinnato | Significato |
|---|---|---|
| `MAX_RETRIES_PER_FINDING` | `2` | Cap per-finding: 2 retry = **3 tentativi totali** (proposta iniziale + 2). Deciso in 05 §4 (chiuso). |
| `GLOBAL_WALL_CLOCK_MS` | `242401` (~242s) | Tetto di tempo di parete per **sessione** di verifica. **Pinnato M5** = round(p95×1.25), p95=193921ms su 12 campioni (§5.1). |
| `GLOBAL_TOKEN_BUDGET` | `null` (non applicato in eval) | Tetto di token per sessione. Nella skill reale lo applica il runtime LLM; in eval (fix provider deterministico, nessun token) **non si applica** e **non e' misurabile da questo banco** — dichiarato null, mai un numero finto (L-COL-006). |

Vale il **primo cap che scatta**: per-finding `MAX_RETRIES_PER_FINDING`
**oppure** budget globale (`GLOBAL_WALL_CLOCK_MS` / `GLOBAL_TOKEN_BUDGET`).
Esaurito un cap → stato **terminale** presentato all'umano (`accepted-risk` /
fix manuale / rinvio), **mai** scarto silenzioso, **mai** `verified` (05 §4).

### 5.1 Procedura di taratura e pinning — ESEGUITA al parity gate M5

Pin numerico ottenuto con la procedura empirica (M5, 10-EVALUATION §6). Riproducibile
con `eval/harness/measure_budget.mjs`:

1. Eseguito il loop end-to-end sulla reference app (gate di verifica, 10 §3) sul set
   in-scope (L-COL-010) — `run_loop --eval --mode=remediate --characterize`.
2. Misurato il tempo di parete per esecuzione (i retry non scattano: il fix provider
   deterministico azzera ogni finding in-scope al 1° tentativo; in eval non ci sono token).
3. p95 su **12 campioni** rappresentativi (≥10 richiesti): 10 dedicati (warm, via
   `measure_budget.mjs`) + 2 del gate criterio-A (1 cold 193921ms, 1 warm 161960ms).
   Campioni dedicati: min 156356 · mean 161289 · max 181640 ms. **p95 = 193921 ms**
   (conservativo per n=12; dominato dal cold-start che il gate esercita realmente).
4. Pinnato `GLOBAL_WALL_CLOCK_MS` = round(p95 × 1.25) = round(193921 × 1.25) =
   **242401 ms**. `MAX_RETRIES_PER_FINDING = 2` invariato (chiuso in 05 §4).
   `GLOBAL_TOKEN_BUDGET` = null (non misurabile in eval — vedi §5, L-COL-006).
5. Registrato in `thresholds.mjs` (`WALL_CLOCK_DERIVATION` + `LOOP_BUDGET`) e nella
   tabella §5. Il gate M5 (criterio 4) **asserisce** `GLOBAL_WALL_CLOCK_MS ===
   round(p95×margin)` con `samples ≥ 10`: il verde non puo' piu' convivere col default.

Ri-tara con `measure_budget.mjs` quando cambia la reference app o le versioni degli oracoli.

---

## 6. Come leggere queste soglie da codice

Il loader unico e `trueline/scripts/checkpoint/thresholds.mjs`, che espone i
default qui sopra come oggetto JS (le tabelle di questo file ne sono la fonte di
verita leggibile). Modificare i numeri **qui** e nel loader insieme: il
disallineamento e un bug, non una feature.

Categorie rilevanti esportate dal loader:

- `GATE_SEVERITY` → soglia globale sicurezza (§3)
- `DEADCODE_GATE_ON` → policy dead-code (§2.5)
- `VERIFIED_ZERO_CATEGORIES` → set in-scope L-COL-010
- `LOOP_BUDGET.MAX_RETRIES_PER_FINDING` → cap retry per finding (§5)
- `LOOP_BUDGET.GLOBAL_WALL_CLOCK_MS` → tetto tempo di parete (§5)
- `LOOP_BUDGET.GLOBAL_TOKEN_BUDGET` → tetto token sessione (§5)

Le regole per categoria (§2) sono policy documentate, non ancora tutte codificate
come costanti separate nel loader (l'aggiunta avviene man mano che gli oracoli
corrispondenti vengono integrati: rls in M1, semgrep/injection in M4, etc.).
