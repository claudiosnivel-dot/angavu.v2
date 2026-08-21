#!/usr/bin/env node
// run_checkpoint.mjs — ENTRYPOINT CLI del checkpoint a 4 controlli (01 §4).
//
// E' il wrapper eseguibile della macchina in checkpoint.mjs: esegue i 4 controlli
// su un projectDir, autorita' = ORACOLO (L-COL-002), e stampa su stdout un
// risultato STRUTTURATO (JSON) con stato verde/rosso/degradato PER CONTROLLO.
// NON decide nulla con l'LLM: verde/rosso e' l'output reale dei comandi.
//
//   1 DEAD CODE      -> run_deadcode (knip).  rosso se NUOVO morto (delta).
//   2 SICUREZZA      -> gitleaks (working-tree) + rls_check + osv
//                       [+ semgrep DIFFERITO M4]. rosso se finding NUOVO >=
//                       soglia (thresholds.md) nelle categorie in scope.
//   3 REGRESSIONI    -> test runner; se assente -> DEGRADATO (// TODO M3), NON verde.
//   4 CONFORMITA     -> acceptance test (BUILD) / characterization (REMEDIATE);
//                       in assenza -> DEGRADATO (// TODO M3), NON verde.
//
// *** REGOLA CRITICA — INTEGRITA DEL FIXTURE ***
// Gli oracoli del checkpoint sono di sola LETTURA (non applicano fix). Tuttavia,
// per coerenza con la disciplina di M1 (loop/verify girano su una COPIA) e per
// non dipendere mai dall'assunzione "il checkpoint non scrive", il default di
// questo entrypoint e' eseguire su una COPIA TEMPORANEA di eval/reference-app
// (eval/.tmp-verify/<id>, gitignorata, .git incluso per lo scope history), e a
// fine ESEGUIRE cleanup (rm -rf). Dopo, il fixture canonico DEVE essere
// bit-identico. Vedi verify_workspace.mjs (riuso M1.x del loop).
//
// MODALITA DI ESECUZIONE
//   default            copia eval/reference-app in temp, esegue li', cleanup.
//   --in-place <dir>   esegue DIRETTAMENTE su <dir> (il chiamante POSSIEDE la
//                      dir — es. il loop, che gia' lavora su una sua copia temp).
//                      Rifiuta in-place sul fixture canonico (guardrail), salvo
//                      --allow-canonical (sicuro: checkpoint sola-lettura, ma il
//                      guardrail resta esplicito per non normalizzare la pratica).
//
// USO
//   node run_checkpoint.mjs [projectDir] [opzioni]
//     projectDir            dir del progetto target. Default: eval/reference-app
//                           (canonica). Con --in-place e' la dir su cui operare.
//     --mode build|remediate   default: build (al confine di un macrotask).
//     --eval                EVAL-MODE: marca il run come deterministico (solo-eval).
//                           Non cambia gli oracoli; documenta il contesto nel JSON.
//     --no-osv              salta l'oracolo osv (offline / niente CVE seminate).
//     --in-place            NON copiare: opera su projectDir cosi' com'e'.
//     --allow-canonical     consenti --in-place sul fixture canonico (read-only).
//     --keep                con la copia temp, NON cancellarla a fine (debug).
//     --baseline <file>     file JSON: array di finding o di fingerprint gia' noti
//                           (baseline-delta, 04 §6). Default: baseline VUOTA
//                           (ogni finding e' "new" -> detection BUILD piena).
//
// EXIT CODE
//   0  il checkpoint e' stato ESEGUITO (l'esito di merito — verde/rosso — e' nel
//      JSON, campo .green). L'esito non si legge dall'exit code (L-COL-002).
//   1  errore di esecuzione del checkpoint (oracolo in errore, fixture mutato,
//      copia fallita): NON e' "verde". Il JSON riporta .ok=false e .error.
//   2  uso scorretto degli argomenti.
//
// Node ESM, solo built-in + checkpoint.mjs (M1.2) + verify_workspace.mjs (riuso).

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

import { runCheckpoint } from './checkpoint.mjs';
import {
  REPO_ROOT, CANONICAL_REFERENCE_APP, createVerifyWorkspace,
} from '../loop/verify_workspace.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const GO_BIN = process.platform === 'win32' ? 'C:/Users/claud/go/bin' : '/c/Users/claud/go/bin';

// runOpts deterministici (riproducibilita del gate, L-COL-002): niente Date.now.
const RUN_OPTS = { runId: 'checkpoint', createdAt: '1970-01-01T00:00:00.000Z' };

const EXIT_OK = 0; // checkpoint eseguito (esito nel JSON)
const EXIT_EXEC_ERROR = 1; // errore di esecuzione (NON e' verde)
const EXIT_USAGE = 2; // uso scorretto

// -----------------------------------------------------------------------------
// Parsing argomenti (piccolo, esplicito; nessuna dipendenza).
// -----------------------------------------------------------------------------
function parseArgs(argv) {
  const positional = [];
  const flags = { mode: 'build', eval: false, noOsv: false, inPlace: false, allowCanonical: false, keep: false, baseline: null, blueprint: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--eval') flags.eval = true;
    else if (a === '--no-osv') flags.noOsv = true;
    else if (a === '--in-place') flags.inPlace = true;
    else if (a === '--allow-canonical') flags.allowCanonical = true;
    else if (a === '--keep') flags.keep = true;
    else if (a === '--mode') flags.mode = argv[++i];
    else if (a.startsWith('--mode=')) flags.mode = a.slice('--mode='.length);
    else if (a === '--baseline') flags.baseline = argv[++i];
    else if (a.startsWith('--baseline=')) flags.baseline = a.slice('--baseline='.length);
    // --blueprint <dir>: opt-in AT-1 Fase A. Attiva il ramo AC-acceptance del
    // controllo 4 (esegue i target_test del blueprint). Assente -> null -> ramo
    // legacy INVARIATO (BIT-invarianza senza il flag).
    else if (a === '--blueprint') flags.blueprint = argv[++i];
    else if (a.startsWith('--blueprint=')) flags.blueprint = a.slice('--blueprint='.length);
    else if (a.startsWith('--')) { /* flag ignota: la ignoriamo, niente sorprese */ }
    else positional.push(a);
  }
  if (flags.mode !== 'build' && flags.mode !== 'remediate') flags.mode = 'build';
  return { positional, flags };
}

// Carica una baseline da file: accetta sia un array di fingerprint (stringhe)
// sia un array di finding (oggetti con .fingerprint). Ritorna Set<fingerprint>.
function loadBaseline(file) {
  if (!file) return new Set();
  const raw = JSON.parse(readFileSync(resolve(file), 'utf8'));
  const arr = Array.isArray(raw) ? raw : (Array.isArray(raw.findings) ? raw.findings : []);
  const fps = arr.map((x) => (typeof x === 'string' ? x : x && x.fingerprint)).filter(Boolean);
  return new Set(fps);
}

// Forma compatta e parsabile del risultato per-controllo (NIENTE rumore nativo:
// a valle si ragiona sul finding model, non sul dump del tool — L-COL-007/011).
function shapeControl(c) {
  return {
    id: c.id,
    name: c.name,
    status: c.status, // green | red | degraded | error
    green: c.green === true,
    detail: c.detail,
    // i finding che BLOCCANO il controllo (delta sopra soglia / nuovo dead-code).
    blockers: (c.blockers || []).map(shapeFinding),
    // tutti i finding visti dal controllo (inclusi i pre-esistenti segnalati).
    findings_total: Array.isArray(c.findings) ? c.findings.length : undefined,
  };
}

function shapeFinding(f) {
  return {
    fingerprint: f.fingerprint,
    category: f.category,
    severity: f.severity,
    file: f.location && f.location.file,
    start_line: f.location && f.location.start_line,
    rule_id: f.source_oracle && f.source_oracle.rule_id,
    baseline_status: f.baseline_status,
  };
}

// Snapshot deterministico dello stato del fixture canonico (git): serve a
// PROVARE, a fine run, che il checkpoint non lo ha mutato. Usa `git status
// --porcelain` (stabile) + l'HEAD: se cambiano, il fixture e' stato toccato.
function fixtureSnapshot() {
  const env = { ...process.env, PATH: `${process.env.PATH || ''}${delimiter}${GO_BIN}` };
  const opts = { cwd: CANONICAL_REFERENCE_APP, encoding: 'utf8', env };
  const status = spawnSync('git', ['status', '--porcelain'], opts);
  const head = spawnSync('git', ['rev-parse', 'HEAD'], opts);
  return {
    status: status.error ? `ERR:${status.error.message}` : (status.stdout || ''),
    head: head.error ? `ERR:${head.error.message}` : (head.stdout || '').trim(),
  };
}

function snapshotsEqual(a, b) {
  return a.status === b.status && a.head === b.head;
}

// -----------------------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------------------
function main() {
  const { positional, flags } = parseArgs(process.argv.slice(2));

  // projectDir: default = fixture canonico; risolto ad assoluto (gli oracoli
  // risolvono i path relativi contro il proprio cwd, quindi serve un assoluto).
  const projectDirArg = positional[0] || CANONICAL_REFERENCE_APP;
  const projectDir = resolve(REPO_ROOT, projectDirArg);

  let baseline;
  try {
    baseline = loadBaseline(flags.baseline);
  } catch (e) {
    emit({ ok: false, error: `baseline non leggibile: ${e.message}` });
    process.exit(EXIT_USAGE);
  }

  const isCanonical = resolve(projectDir) === CANONICAL_REFERENCE_APP;

  // --- Percorso IN-PLACE: opera direttamente su projectDir (chiamante owner) ---
  if (flags.inPlace) {
    if (isCanonical && !flags.allowCanonical) {
      emit({
        ok: false,
        error:
          'RIFIUTO: --in-place sul fixture canonico eval/reference-app senza ' +
          '--allow-canonical. Il checkpoint e\' sola-lettura, ma il guardrail ' +
          'resta esplicito: usa il default (copia temp) o --allow-canonical.',
      });
      process.exit(EXIT_EXEC_ERROR);
    }
    if (!existsSync(projectDir)) {
      emit({ ok: false, error: `projectDir assente: ${projectDir}` });
      process.exit(EXIT_EXEC_ERROR);
    }
    const report = runOn(projectDir, { ...flags, baseline, copied: false, workspace: projectDir, blueprint: flags.blueprint });
    // In-place: nessuna copia -> niente snapshot del fixture (il chiamante e'
    // owner della dir). Coerente col default sull'exit: errore di esecuzione
    // (oracolo non girato) -> exit 1 (NON verde); altrimenti 0 (esito nel JSON).
    emit(report);
    process.exit(report && report.ok === false ? EXIT_EXEC_ERROR : EXIT_OK);
  }

  // --- Percorso DEFAULT: copia temp di eval/reference-app, opera li', cleanup ---
  // Se projectDir e' diverso dal canonico ma NON --in-place, e' un errore d'uso
  // ambiguo: una dir custom va eseguita con --in-place (il chiamante la possiede).
  if (!isCanonical) {
    emit({
      ok: false,
      error:
        `projectDir custom (${projectDirArg}) senza --in-place: ambiguo. Una dir ` +
        'non canonica va eseguita con --in-place (il chiamante la possiede); il ' +
        'default (copia temp) vale solo per il fixture canonico.',
    });
    process.exit(EXIT_USAGE);
  }

  if (!existsSync(CANONICAL_REFERENCE_APP)) {
    emit({ ok: false, error: `fixture canonico assente: ${CANONICAL_REFERENCE_APP}` });
    process.exit(EXIT_EXEC_ERROR);
  }

  // Snapshot PRIMA: per provare l'integrita' del fixture a fine run.
  const before = fixtureSnapshot();

  let ws = null;
  let report;
  try {
    ws = createVerifyWorkspace({ id: `checkpoint-${RUN_OPTS.runId}`, includeGit: true });
    report = runOn(ws.dir, { ...flags, baseline, copied: true, workspace: ws.dir, blueprint: flags.blueprint });
  } catch (e) {
    report = { ok: false, error: `copia/esecuzione fallita: ${e && e.message ? e.message : e}` };
  } finally {
    // Cleanup SEMPRE (salvo --keep): il fixture canonico resta intatto.
    if (ws && !flags.keep) ws.cleanup();
  }
  if (report && typeof report === 'object') report.cleanedUp = ws ? !flags.keep : false;

  // Snapshot DOPO: il fixture DEVE essere bit-identico (git status + HEAD).
  const after = fixtureSnapshot();
  const fixtureIntact = snapshotsEqual(before, after);
  if (report && typeof report === 'object') {
    report.fixtureIntact = fixtureIntact;
    if (!fixtureIntact) {
      report.ok = false;
      report.error = (report.error ? report.error + ' | ' : '')
        + 'INTEGRITA VIOLATA: il fixture canonico e\' cambiato durante il checkpoint '
        + `(prima/dopo divergono). before.head=${before.head} after.head=${after.head}`;
    }
  }

  emit(report);
  // Errore di esecuzione o fixture mutato -> exit 1 (NON e' verde). Altrimenti 0
  // (l'esito verde/rosso e' nel JSON, .green, non nell'exit code — L-COL-002).
  process.exit(report && report.ok === false ? EXIT_EXEC_ERROR : EXIT_OK);
}

// Esegue il checkpoint su `dir` (assoluto) e ne modella il report strutturato.
function runOn(dir, { mode, eval: evalMode, noOsv, baseline, copied, workspace, blueprint }) {
  // PATH arricchito col go/bin noto (gitleaks/osv vivono li', non sul PATH).
  // checkpoint.mjs lo ri-arricchisce per ogni oracolo; lo facciamo anche qui
  // per coerenza se in futuro si invocassero tool dal processo padre.
  process.env.PATH = `${process.env.PATH || ''}${delimiter}${GO_BIN}`;

  // RETRY-SU-ERRORE-DI-MISURA (non sul verdetto). Uno stato "error" di un
  // controllo NON e' un finding: e' un oracolo che NON ha girato (es. knip che,
  // su una copia temp Windows sotto contesa di file-lock, occasionalmente non
  // emette JSON valido). Ri-eseguire la MISURA e' lecito e onesto (L-COL-006: un
  // oracolo che non gira NON e' "verde", quindi non promuoviamo nulla; al
  // massimo ripetiamo la lettura). Distinto dal retry del LOOP (O-COL-006), che
  // re-applica una FIX. Cap piccolo: un errore persistente resta error/ok:false.
  let cp = runCheckpoint(dir, { mode, baseline, runOpts: RUN_OPTS, withOsv: !noOsv, blueprintDir: blueprint });
  let attempts = 1;
  const MAX_MEASURE_ATTEMPTS = 3;
  while (cp.controls.some((c) => c.status === 'error') && attempts < MAX_MEASURE_ATTEMPTS) {
    attempts += 1;
    cp = runCheckpoint(dir, { mode, baseline, runOpts: RUN_OPTS, withOsv: !noOsv, blueprintDir: blueprint });
  }

  const controls = cp.controls.map(shapeControl);
  const anyError = controls.some((c) => c.status === 'error');

  return {
    ok: !anyError,
    schema: 'trueline.checkpoint/v1',
    mode,
    evalMode: Boolean(evalMode),
    // EVAL-MODE: nota solo-eval. Non cambia gli oracoli (autorita' = comando);
    // documenta che il gate umano dell'applicazione fix e' auto-approvato altrove
    // (loop --eval). Il checkpoint in se' non applica nulla: solo LEGGE e misura.
    evalNote: evalMode
      ? 'EVAL-MODE: run deterministico (solo-eval). Il checkpoint non applica fix; '
        + 'l\'auto-approvazione del gate umano vive nel loop (--eval), non qui.'
      : undefined,
    copied: Boolean(copied),
    workspace,
    // quante volte la MISURA e' stata ripetuta per superare un errore transitorio
    // di esecuzione di un oracolo (1 = nessun retry). Vedi nota in runOn.
    measureAttempts: attempts,
    green: cp.green === true,
    summary: cp.summary,
    degraded: cp.degraded,
    // FORWARD-DEP M3: i controlli 3/4 sono degradati in assenza di test
    // (characterization 06 / acceptance 11 §3). Degradato != verde (L-COL-006).
    forwardDeps: cp.degraded && cp.degraded.length
      ? `controlli degradati (NON verdi) in attesa dei test M3: ${cp.degraded.join(', ')} (// TODO M3)`
      : undefined,
    // POTERE DELL'ASSERZIONE (AT-1 Fase C): la sintesi risale QUI perche' shapeControl
    // tiene una whitelist di campi e scarta `power`. Senza questa riga la dichiarazione
    // non esisterebbe in nessun output emesso, e a zero candidati il controllo 4 uscirebbe
    // VERDE e MUTO (L-COL-006). undefined quando il ramo AC non ha girato -> il JSON
    // emesso resta byte-identico per ogni progetto senza --blueprint.
    assertion_power: cp.assertion_power || undefined,
    controls,
  };
}

function emit(report) {
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

const __isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (__isMain) main();

export { runOn, parseArgs, loadBaseline };
