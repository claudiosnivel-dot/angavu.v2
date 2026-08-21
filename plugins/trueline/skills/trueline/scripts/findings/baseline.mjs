#!/usr/bin/env node
// =============================================================================
// baseline.mjs — meccanismo del BASELINE-DELTA (03 §8, 04 §6, L-COL-018).
//
// E' la memoria del checkpoint: la differenza fra "questo difetto e' colpa del
// mio macrotask" (baseline_status=new -> BLOCCA il gate) e "questo difetto
// c'era gia' prima che toccassi nulla" (baseline_status=pre-existing ->
// SEGNALATO, non blocca). Senza questa distinzione il gate sarebbe gate
// sull'ASSOLUTO (rosso su qualsiasi debito storico) invece che sul DELTA del
// lavoro corrente — esattamente cio' che L-COL-018 vieta.
//
// La CHIAVE del delta e' il `fingerprint` (identita' stabile-per-riga: ancora
// di CONTENUTO, mai il numero di riga, 04 §6): spostare un difetto di qualche
// riga NON lo fa risultare "nuovo". Il confronto e' per fingerprint, MAI per
// riga (requisito esplicito del task).
//
// DUE FUNZIONI (API pubblica):
//   capture(projectDir, oracles[]) -> snapshot dei finding normalizzati,
//       indicizzato per fingerprint. Riusa i wrapper M0 (run_gitleaks /
//       rls_check / run_deadcode / run_osv) + normalize + validate. NON li
//       riscrive: li ORCHESTRA, come il checkpoint (L-COL-002: il verde/rosso
//       resta proprieta' dell'oracolo, non di una frase).
//   delta(current[], baseline) -> per ogni finding corrente, lo marca
//       baseline_status = new | pre-existing in base alla presenza del suo
//       fingerprint nella baseline. Ritorna una COPIA marcata + un riepilogo.
//
// *** INTEGRITA DEL FIXTURE *** (regola critica): questo modulo SOLO LEGGE gli
// oracoli; non muta mai il progetto target. Per il gate ripetibile la cattura
// va fatta su una COPIA TEMP del fixture (eval/.tmp-verify, vedi
// verify_workspace.mjs): cosi' il fixture canonico resta bit-identico.
//
// CLI:
//   node baseline.mjs capture <dir> [opzioni]
//       Esegue gli oracoli su <dir>, scrive lo snapshot (default
//       <dir>/.trueline/baseline.json) e lo stampa su stdout.
//   node baseline.mjs delta <dir> [opzioni]
//       Esegue gli oracoli su <dir> (stato CORRENTE), carica la baseline e
//       stampa i finding correnti marcati new|pre-existing.
//   opzioni:
//       --oracles <lista>   csv di oracoli (default: gitleaks,rls-check,knip,osv)
//       --baseline <file>   percorso dello snapshot (default <dir>/.trueline/baseline.json)
//       --out <file>        (capture) dove scrivere lo snapshot; "-" = solo stdout
//       --run-id <id>       run_id deterministico (default "baseline")
//       --created-at <iso>  created_at deterministico (default epoch ISO)
//       --no-osv            esclude osv (utile offline; equivale a togliere osv dalla lista)
//
// Node ESM, solo built-in + i wrapper M0 (oracoli) e normalize/validate (04).
// =============================================================================

import { spawnSync } from 'node:child_process';
import {
  existsSync, readFileSync, writeFileSync, mkdirSync,
} from 'node:fs';
import {
  resolve, dirname, join, delimiter,
} from 'node:path';
import { fileURLToPath } from 'node:url';

import { normalizeAll } from './normalize.mjs';
import { validateMany } from './validate_finding.mjs';
import { scanScopeFor, applyScanScope, scanScopeCoverage } from '../oracles/scan_scope.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
// trueline/scripts/findings -> root e' 3 livelli sopra.
const REPO_ROOT = resolve(__dirname, '..', '..', '..');
const ORACLES = resolve(__dirname, '..', 'oracles');
const RUN_GITLEAKS = resolve(ORACLES, 'run_gitleaks.mjs');
const RLS_CHECK = resolve(ORACLES, 'rls_check.mjs');
const RUN_DEADCODE = resolve(ORACLES, 'run_deadcode.mjs');
const RUN_OSV = resolve(ORACLES, 'run_osv.mjs');
// A2a/A2c — oracoli d'igiene (per catturare il baseline d'igiene delta).
const RUN_DUPCHECK = resolve(ORACLES, 'run_dupcheck.mjs');
const RUN_CYCLECHECK = resolve(ORACLES, 'run_cyclecheck.mjs');
const TWIN_CHECK = resolve(ORACLES, 'twin_check.mjs');

// go/bin (gitleaks, osv-scanner) NON e' sul PATH di default in questo ambiente.
const GO_BIN = process.platform === 'win32'
  ? 'C:/Users/claud/go/bin'
  : '/c/Users/claud/go/bin';

// Set di oracoli di default: copre il set verificato-a-zero (L-COL-010) +
// dependency-vuln. Gli alias sono quelli accettati da normalize (04).
const DEFAULT_ORACLES = ['gitleaks', 'rls-check', 'knip', 'osv'];

// Valori deterministici di default (riproducibilita' del gate, L-COL-002):
// la baseline DEVE essere ricalcolabile bit-per-bit, quindi niente Date.now().
const DEFAULT_RUN_ID = 'baseline';
const DEFAULT_CREATED_AT = '1970-01-01T00:00:00.000Z';

// Versione dello schema dello snapshot (per evoluzioni future del formato).
const BASELINE_VERSION = 1;

// =============================================================================
// Esecuzione di un oracolo come processo figlio (decide dall'output JSON, non
// dall'exit code — 03 §3). Stesso schema usato da checkpoint.mjs/loop.mjs per
// garantire path normalizzati e quindi FINGERPRINT coerenti col resto della
// macchina (la chiave del delta).
// =============================================================================
function runOracleProcess(scriptPath, args, cwd) {
  if (!existsSync(scriptPath)) {
    return { ok: false, json: null, detail: `oracolo assente: ${scriptPath}` };
  }
  const env = { ...process.env, PATH: `${process.env.PATH || ''}${delimiter}${GO_BIN}` };
  const res = spawnSync(process.execPath, [scriptPath, ...args], {
    cwd, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (res.error) return { ok: false, json: null, detail: `spawn: ${res.error.message}` };
  const raw = (res.stdout || '').trim();
  if (!raw) {
    const tail = (res.stderr || '').trim().split('\n').slice(-1)[0] || '(stderr vuoto)';
    return { ok: false, json: null, detail: `nessun JSON (exit=${res.status}): ${tail}` };
  }
  try { return { ok: true, json: JSON.parse(raw), detail: `exit=${res.status}` }; }
  catch (e) { return { ok: false, json: null, detail: `JSON invalido: ${e.message}` }; }
}

// Tabella di dispatch oracolo-canonico -> come eseguirlo sul progetto target.
// Ogni voce ritorna { script, args, scope } con cwd = projectDir (allinea i
// path normalizzati ai fingerprint del checkpoint/loop).
//   gitleaks  -> working-tree (scope BUILD; S1 vive qui). NB: la baseline NON
//                cattura lo scope `history` (S2): la history e' fuori dal delta
//                del macrotask corrente e S2 e' un caso a parte (05 §7).
//   rls-check -> DDL delle migration (S3/S4/S5).
//   knip      -> dead-code working-tree (S8).
//   osv       -> dependency-vuln dal lockfile.
function oracleInvocation(canon, projectDir, minTokens = 50) {
  switch (canon) {
    case 'jscpd':
      return { script: RUN_DUPCHECK, args: [projectDir, String(minTokens)], scope: 'working-tree', normOracle: 'jscpd' };
    case 'cycle':
      return { script: RUN_CYCLECHECK, args: [projectDir], scope: 'working-tree', normOracle: 'cycle' };
    case 'twin':
      return { script: TWIN_CHECK, args: [projectDir], scope: 'working-tree', normOracle: 'twin' };
    case 'gitleaks':
      return { script: RUN_GITLEAKS, args: [projectDir, 'working-tree'], scope: 'working-tree', normOracle: 'gitleaks' };
    case 'rls-check':
      return {
        script: RLS_CHECK,
        args: [resolve(projectDir, 'supabase', 'migrations')],
        scope: 'static-ddl',
        normOracle: 'rls-check',
      };
    case 'knip':
      return { script: RUN_DEADCODE, args: [projectDir], scope: 'working-tree', normOracle: 'knip' };
    case 'osv': {
      const lockfile = resolve(projectDir, 'package-lock.json');
      return { script: RUN_OSV, args: [lockfile], scope: 'deps', normOracle: 'osv', optional: true, guard: existsSync(lockfile) };
    }
    default:
      return null;
  }
}

// Normalizza i nomi/alias di oracolo richiesti dall'utente alla forma canonica
// usata internamente (allineata agli alias di normalize, 04).
const ORACLE_ALIASES = {
  gitleaks: 'gitleaks',
  secret: 'gitleaks',
  'rls-check': 'rls-check',
  rls_check: 'rls-check',
  rls: 'rls-check',
  knip: 'knip',
  deadcode: 'knip',
  'dead-code': 'knip',
  osv: 'osv',
  'osv-scanner': 'osv',
  // A2c — oracoli d'igiene strutturale (baseline d'igiene delta).
  jscpd: 'jscpd',
  duplication: 'jscpd',
  'dup-check': 'jscpd',
  cycle: 'cycle',
  architecture: 'cycle',
  madge: 'cycle',
  'cycle-check': 'cycle',
  twin: 'twin',
  'twin-check': 'twin',
};

function canonicalOracle(name) {
  return ORACLE_ALIASES[String(name).trim().toLowerCase()];
}

// =============================================================================
// CAPTURE — esegue gli oracoli su projectDir e produce lo snapshot.
// =============================================================================
//
// projectDir   directory del progetto target (idealmente una COPIA TEMP del
//              fixture: il capture solo legge, ma il gate ripetibile lo richiede).
// oracles      array di nomi/alias di oracolo (default DEFAULT_ORACLES).
// opts         { runId, createdAt }.
//
// Ritorna { ok, snapshot, findings, errors, detail }:
//   snapshot   oggetto serializzabile { version, project, oracles, captured_at,
//              run_id, count, fingerprints:[...], findings:{ <fp>: finding } }.
//              `fingerprints` e' l'INDICE (set di chiavi) usato dal delta;
//              `findings` mappa fingerprint -> finding normalizzato.
//   findings   l'array piatto dei finding normalizzati (dedup-ati fra oracoli).
export function capture(projectDir, oracles = DEFAULT_ORACLES, opts = {}) {
  const dir = resolve(projectDir);
  if (!existsSync(dir)) {
    return { ok: false, snapshot: null, findings: [], errors: [`progetto assente: ${dir}`], detail: 'capture fallita' };
  }
  const runOpts = {
    runId: opts.runId || DEFAULT_RUN_ID,
    createdAt: opts.createdAt || DEFAULT_CREATED_AT,
  };

  const requested = (oracles && oracles.length ? oracles : DEFAULT_ORACLES)
    .map(canonicalOracle)
    .filter(Boolean);
  // Dedup preservando l'ordine richiesto.
  const canonOracles = [...new Set(requested)];

  const errors = [];
  const usedOracles = [];
  const pairs = []; // { oracle, native } per normalizeAll (dedup fra oracoli)

  // --- SCAN-SCOPE (PLAN 2026-07-28 §3.5) --------------------------------------
  // LA SIMMETRIA COL CHECKPOINT E' IL PUNTO. La baseline e' l'insieme dei
  // fingerprint "gia' noti": se congelasse finding che il checkpoint ESCLUDE (o
  // se ne perdesse di quelli che il checkpoint TIENE) nascerebbe un DELTA
  // FANTASMA a ogni giro. La direzione pericolosa e' la seconda: un finding che
  // il checkpoint produce e la baseline non contiene risulta 'new' e BLOCCA il
  // gate, per sempre, senza che nessuno abbia introdotto niente.
  //
  // Percio' qui NON si reimplementa nulla: si chiama la STESSA scanScopeFor col
  // MEDESIMO projectDir che usa control2Security (che risolve il manifest allo
  // stesso modo, da `dir`). Stesso input, stessa funzione, stesso scope.
  //
  // `opts.manifest` e' rispettato se il chiamante l'ha gia' risolto (undefined =>
  // lo risolve scanScopeFor). Una dichiarazione di progetto ROTTA fa fallire la
  // capture: una baseline costruita ignorando in silenzio un'esclusione che il
  // progetto crede attiva sarebbe una memoria falsa (L-COL-006).
  let scope;
  try {
    scope = scanScopeFor(dir, opts.manifest ? { manifest: opts.manifest } : {});
  } catch (e) {
    return {
      ok: false, snapshot: null, findings: [], errors: [`scan-scope: ${e.message}`], detail: 'scope di scansione non risolvibile',
    };
  }
  const scopeExcluded = [];

  for (const canon of canonOracles) {
    const inv = oracleInvocation(canon, dir, Number(opts.minTokens) || 50);
    if (!inv) { errors.push(`oracolo sconosciuto: ${canon}`); continue; }
    // osv (optional): se il lockfile manca o il tool e' offline, NON falsifichiamo
    // la baseline -> lo dichiariamo degradato e proseguiamo (best-effort).
    if (inv.optional && inv.guard === false) {
      errors.push(`osv saltato (lockfile assente): ${dir}`);
      continue;
    }
    const r = runOracleProcess(inv.script, inv.args, dir);
    if (!r.ok) {
      if (inv.optional) { errors.push(`${canon} degradato: ${r.detail}`); continue; }
      errors.push(`${canon}: ${r.detail}`);
      continue;
    }
    // Lo scope vale per l'oracolo dei SEGRETI (la leva vive in
    // manifest.oracles.secret.exclude): gitleaks e' l'unico ramo filtrato, gli
    // altri oracoli passano intatti (BIT-invarianza per rls/knip/osv/igiene).
    // Il filtro sta PRIMA della normalizzazione, come nel checkpoint, cosi' i
    // fingerprint della baseline sono quelli dell'insieme davvero scansionato.
    // Guardia sul TIPO identica al checkpoint: un JSON non-array passa INTATTO a
    // normalizeAll (che lo rifiuta), non diventa "zero segreti".
    let native = r.json;
    if (inv.normOracle === 'gitleaks' && Array.isArray(native) && scope.patterns.length > 0) {
      const applied = applyScanScope(native, scope, dir);
      scopeExcluded.push(...applied.excluded);
      native = applied.kept;
    }
    pairs.push({ oracle: inv.normOracle, native });
    usedOracles.push(canon);
  }

  // normalizeAll fonde + dedup fra oracoli (gitleaks autoritativo sui segreti, 03 §6).
  let findings;
  try {
    findings = normalizeAll(pairs, runOpts);
  } catch (e) {
    return { ok: false, snapshot: null, findings: [], errors: [...errors, `normalize: ${e.message}`], detail: 'normalize fallita' };
  }

  // La baseline e' un INSIEME DI FINGERPRINT NOTI: lo stato per-finding nella
  // baseline e' sempre "pre-existing" (per definizione, e' il passato). Lo
  // forziamo nello snapshot per coerenza, anche se il delta usa solo le chiavi.
  for (const f of findings) f.baseline_status = 'pre-existing';

  // Validazione contro lo schema (04): una baseline non valida e' un bug, non
  // una feature — la rifiutiamo invece di persisterla.
  const v = validateMany(findings);
  if (!v.ok) {
    return {
      ok: false, snapshot: null, findings, errors: [...errors, `schema KO: ${v.errors.slice(0, 3).join('; ')}`], detail: 'snapshot non conforme allo schema',
    };
  }

  // Indice per fingerprint (ordinato per stabilita' del JSON: due capture
  // identiche danno byte-identico, requisito di riproducibilita').
  const sorted = [...findings].sort((a, b) => a.fingerprint.localeCompare(b.fingerprint));
  const byFp = {};
  for (const f of sorted) byFp[f.fingerprint] = f;

  const snapshot = {
    version: BASELINE_VERSION,
    project: toRepoRel(dir),
    oracles: usedOracles,
    run_id: runOpts.runId,
    captured_at: runOpts.createdAt,
    count: sorted.length,
    fingerprints: sorted.map((f) => f.fingerprint),
    findings: byFp,
  };

  // Cio' che la baseline NON ha guardato si scrive NELLO snapshot: chi legge un
  // baseline.json deve poter vedere con quale confine e' stato costruito, o due
  // baseline con lo stesso `count` sembrerebbero la stessa cosa. Il campo compare
  // SOLO se c'e' almeno un pattern dichiarato: senza dichiarazioni lo snapshot
  // resta byte-identico a quello di prima (BIT-invarianza, e la capture deve
  // restare ricalcolabile bit-per-bit).
  const scanScope = scope.patterns.length > 0 ? scanScopeCoverage(scope, scopeExcluded) : null;
  if (scanScope) snapshot.scan_scope = scanScope;

  return {
    ok: true,
    snapshot,
    findings: sorted,
    errors,
    scanScope,
    detail: `${sorted.length} finding catturati da [${usedOracles.join(', ')}]`
      + (scanScope && scanScope.excluded_total > 0
        ? `; ${scanScope.excluded_total} esclusi dallo scope di scansione` : ''),
  };
}

// =============================================================================
// DELTA — marca i finding CORRENTI rispetto alla baseline.
// =============================================================================
//
// current    array di finding normalizzati dello stato CORRENTE.
// baseline   o lo snapshot { fingerprints, ... } di capture(), o un Set/array
//            di fingerprint, o un array di finding (da cui estraiamo i fp).
//
// Confronto PER FINGERPRINT, mai per riga (04 §6):
//   - fingerprint presente in baseline -> baseline_status = 'pre-existing'
//   - fingerprint assente              -> baseline_status = 'new'
//
// Ritorna { marked, new: [...], preExisting: [...], summary } dove `marked` e'
// una COPIA dei finding correnti con baseline_status impostato (non mutiamo
// l'input). `summary` e' un riepilogo contabile.
export function delta(current, baseline) {
  const known = toFingerprintSet(baseline);
  const marked = [];
  const fresh = [];
  const pre = [];
  for (const f of current || []) {
    const status = known.has(f.fingerprint) ? 'pre-existing' : 'new';
    const copy = { ...f, baseline_status: status };
    marked.push(copy);
    if (status === 'new') fresh.push(copy); else pre.push(copy);
  }
  return {
    marked,
    new: fresh,
    preExisting: pre,
    summary: {
      total: marked.length,
      new: fresh.length,
      pre_existing: pre.length,
      baseline_size: known.size,
    },
  };
}

// Estrae un Set<fingerprint> da forme diverse di baseline.
function toFingerprintSet(baseline) {
  if (!baseline) return new Set();
  if (baseline instanceof Set) return baseline;
  if (Array.isArray(baseline)) {
    // array di stringhe (fingerprint) o di finding ({ fingerprint }).
    return new Set(baseline.map((x) => (typeof x === 'string' ? x : x && x.fingerprint)).filter(Boolean));
  }
  if (typeof baseline === 'object') {
    if (Array.isArray(baseline.fingerprints)) return new Set(baseline.fingerprints);
    if (baseline.findings && typeof baseline.findings === 'object') {
      return new Set(Object.keys(baseline.findings));
    }
  }
  return new Set();
}

// =============================================================================
// HELPER I/O baseline
// =============================================================================
function defaultBaselinePath(projectDir) {
  // .trueline/ e' gitignorato (vedi .gitignore root): artefatto di run, non sorgente.
  return resolve(projectDir, '.trueline', 'baseline.json');
}

export function writeBaseline(path, snapshot) {
  mkdirSync(dirname(path), { recursive: true });
  // JSON stabile (2 spazi, newline finale) per diff puliti e riproducibilita'.
  writeFileSync(path, `${JSON.stringify(snapshot, null, 2)}\n`, 'utf8');
}

export function readBaseline(path) {
  if (!existsSync(path)) throw new Error(`baseline assente: ${path}`);
  return JSON.parse(readFileSync(path, 'utf8'));
}

// A2c — carica il baseline d'igiene COMMITTATO di un progetto, se presente.
// Ritorna { present, set:Set<fingerprint> }. Path tracciato: <dir>/.trueline/
// hygiene-baseline.json (nel progetto utente va tracciato con negazione .gitignore;
// vedi references/modes). Assente -> { present:false, set:new Set() } (BIT-invarianza:
// il checkpoint unisce un set vuoto). Illeggibile/corrotto -> present:false (fail-safe:
// il vacuity guard del checkpoint lo tratta come "manca il baseline").
export function hygieneBaselinePath(projectDir) {
  return resolve(projectDir, '.trueline', 'hygiene-baseline.json');
}
export function loadHygieneBaseline(projectDir) {
  const p = hygieneBaselinePath(projectDir);
  if (!existsSync(p)) return { present: false, set: new Set() };
  try {
    const snap = JSON.parse(readFileSync(p, 'utf8'));
    const fps = Array.isArray(snap.fingerprints)
      ? snap.fingerprints
      : (snap.findings && typeof snap.findings === 'object' ? Object.keys(snap.findings) : []);
    return { present: true, set: new Set(fps) };
  } catch {
    return { present: false, set: new Set() };
  }
}

function toRepoRel(abs) {
  const rel = abs.startsWith(REPO_ROOT) ? abs.slice(REPO_ROOT.length + 1) : abs;
  return rel.split(/[\\/]/).join('/');
}

// =============================================================================
// CLI
// =============================================================================
function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      // flag booleane note (no valore a seguire).
      if (key === 'no-osv' || key === 'hygiene') { flags[key] = true; continue; }
      const val = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
      flags[key] = val;
    } else {
      positional.push(a);
    }
  }
  return { positional, flags };
}

function resolveOracleList(flags) {
  if (flags.hygiene) return ['jscpd', 'cycle', 'twin'];
  let list = flags.oracles
    ? String(flags.oracles).split(',').map((s) => s.trim()).filter(Boolean)
    : [...DEFAULT_ORACLES];
  if (flags['no-osv']) list = list.filter((o) => canonicalOracle(o) !== 'osv');
  return list;
}

function main(argv) {
  const { positional, flags } = parseArgs(argv);
  const [cmd, dirArg] = positional;

  if (!cmd || !dirArg || !['capture', 'delta'].includes(cmd)) {
    process.stderr.write(
      'uso:\n'
      + '  node baseline.mjs capture <dir> [--oracles g,r,k,o] [--out <file>] [--no-osv]\n'
      + '  node baseline.mjs delta   <dir> [--oracles ...] [--baseline <file>] [--no-osv]\n',
    );
    return 2;
  }

  const projectDir = resolve(process.cwd(), dirArg);
  const oracles = resolveOracleList(flags);
  const runOpts = {
    runId: flags['run-id'] || (cmd === 'delta' ? 'delta' : DEFAULT_RUN_ID),
    createdAt: flags['created-at'] || DEFAULT_CREATED_AT,
    minTokens: Number(flags['min-tokens']) || 50,
  };
  const baselinePath = flags.baseline
    ? resolve(process.cwd(), flags.baseline)
    : defaultBaselinePath(projectDir);

  if (cmd === 'capture') {
    const res = capture(projectDir, oracles, runOpts);
    if (!res.ok) {
      process.stderr.write(`[baseline capture] ERRORE: ${res.detail}\n`);
      for (const e of res.errors) process.stderr.write(`  - ${e}\n`);
      return 1;
    }
    for (const e of res.errors) process.stderr.write(`[baseline capture] avviso: ${e}\n`);
    const outFlag = flags.out;
    if (outFlag !== '-') {
      const outPath = outFlag ? resolve(process.cwd(), outFlag) : baselinePath;
      writeBaseline(outPath, res.snapshot);
      process.stderr.write(`[baseline capture] ${res.detail}; snapshot -> ${toRepoRel(outPath)}\n`);
    } else {
      process.stderr.write(`[baseline capture] ${res.detail}; (solo stdout, nessun file)\n`);
    }
    process.stdout.write(`${JSON.stringify(res.snapshot, null, 2)}\n`);
    return 0;
  }

  // cmd === 'delta'
  let baseline;
  try {
    baseline = readBaseline(baselinePath);
  } catch (e) {
    process.stderr.write(`[baseline delta] ERRORE: ${e.message}\n`);
    return 1;
  }
  const cur = capture(projectDir, oracles, runOpts);
  if (!cur.ok) {
    process.stderr.write(`[baseline delta] ERRORE cattura stato corrente: ${cur.detail}\n`);
    for (const e of cur.errors) process.stderr.write(`  - ${e}\n`);
    return 1;
  }
  for (const e of cur.errors) process.stderr.write(`[baseline delta] avviso: ${e}\n`);
  const d = delta(cur.findings, baseline);
  process.stderr.write(
    `[baseline delta] totali=${d.summary.total} new=${d.summary.new} `
    + `pre-existing=${d.summary.pre_existing} (baseline=${d.summary.baseline_size})\n`,
  );
  process.stdout.write(`${JSON.stringify(d.marked, null, 2)}\n`);
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] === __filename) {
  process.exit(main(process.argv));
}
