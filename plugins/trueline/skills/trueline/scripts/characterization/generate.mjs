// generate.mjs — GENERATORE deterministico di una suite di characterization (06).
//
// Cattura il comportamento CORRENTE del percorso critico di un progetto target e
// scrive una suite VALUE-BASED e FALSIFICABILE sotto <projectDir>/test/
// characterization/, poi cabla uno script "test" nel package.json. La suite e'
// VERDE PER COSTRUZIONE sul codice corrente (06 §3 step 4): congela cio' che il
// codice fa OGGI come un VALORE OSSERVATO (observed), vulnerabile o no. La
// remediation successiva dovra' mantenere invariato l'observed delle assertion
// GUARD (invarianza comportamentale) e potra' cambiare solo l'observed delle
// IMPACTED (partition.mjs).
//
// CONTRATTO SNAPSHOT/ASSERTION (condiviso tra i moduli). Ogni assertion porta un
// VALORE OSSERVATO, non solo pass/fail:
//   { id, kind:'endpoint'|'build-integrity'|'rls'|'pure', target, file,
//     observed:<json>, degraded?:bool }
//   - endpoint /health: observed = { status:200, body_status:'ok' } (uptime
//     ESCLUSO via stabilize: il prologo di stabilizzazione e' DERIVATO dal
//     non-determinismo realmente scansionato nel sorgente dell'endpoint).
//   - build-integrity:  observed = { typecheck_exit:0 } (nessun dist emesso).
//   - rls (runtime):    observed = { visible_rows, sees_other_tenant } per tabella.
//   - rls (degradato):  observed = { static_flagged:true }, degraded:true.
//
// La suite scrive:
//   - baseline.json = { assertions:[...con observed], coverage:{...} }, CONGELATA
//     al momento della generazione, verde-per-costruzione sul codice corrente.
//   - run.mjs       = un RECOMPUTER che RI-CALCOLA observed per ogni assertion sul
//     codice CORRENTE e stampa { assertions:[{id,observed}] } come JSON.
//   - *.characterization.test.mjs = un wrapper node:test che chiama run.mjs e
//     asserisce che current.observed deep-equals baseline.observed (`npm test`).
//
// FALSIFICABILITA: cambiare il comportamento (es. fixare S5 cosi' l'isolamento
// ritorna) cambia l'observed di quella tabella; droppare una tabella o rompere
// l'isolamento di una tabella di contrasto cambia l'observed -> il deep-equal
// fallisce. Niente assert tautologici (Array.isArray(literal)/x===x).
//
// NON-DETERMINISMO (06 §6.2): le sorgenti override-abili (uptime/clock/random)
// sono STABILIZZATE nel prologo iniettato nei test/run; cio' che non si puo'
// stabilizzare e' ESCLUSO dalle assertion e DICHIARATO in coverage. Mai un assert
// flaky.
//
// GENERICO sopra un progetto utente: niente nomi hardcoded della reference app.
// Lo scan rileva endpoint HTTP, integrita di build, e RLS (via rls_characterize).
// L'entry dell'app NON deve chiamarsi letteralmente 'createApp': si accettano
// createApp/app/default/buildServer o una istanza Express esportata.
//
// CLI:   node generate.mjs <projectDir> --db-url=<url> [--out=<dir>]
// API:   generate(projectDir, { dbUrl, outDir })
//
// Node ESM, solo built-in.

import {
  existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync, statSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { detectRunner } from './detect_runner.mjs';
import { characterizeRls } from './rls_characterize.mjs';
import { coverageDeclaration } from './coverage.mjs';
import { stabilizationPrologue } from './stabilize.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
// Path ASSOLUTO del modulo RLS della skill: viene "baked" nel run.mjs generato
// cosi' il recomputer puo' ricomporre characterizeRls con la ricetta psql senza
// duplicare logica (la skill resta dep-free; il path e' risolto a generazione).
const SKILL_RLS_CHARACTERIZE = resolve(__dirname, 'rls_characterize.mjs');

// -----------------------------------------------------------------------------
// SCAN del progetto (generico)
// -----------------------------------------------------------------------------

// Raccoglie ricorsivamente i file sorgente sotto src/ (o l'intero progetto se
// src/ assente), saltando node_modules/.git/dist.
function collectSources(projectDir) {
  const roots = ['src'].map((d) => resolve(projectDir, d)).filter(existsSync);
  const base = roots.length ? roots : [projectDir];
  const SKIP = new Set(['node_modules', '.git', 'dist', 'test', 'coverage']);
  const out = [];
  const walk = (dir) => {
    let entries;
    try { entries = readdirSync(dir); } catch { return; }
    for (const e of entries) {
      if (SKIP.has(e)) continue;
      const p = join(dir, e);
      let st;
      try { st = statSync(p); } catch { continue; }
      if (st.isDirectory()) walk(p);
      else if (/\.(ts|tsx|js|mjs|cjs)$/.test(e)) out.push(p);
    }
  };
  for (const b of base) walk(b);
  return out;
}

// Rileva endpoint HTTP (Express-like) per regex generica:
//   <router>.get|post|put|patch|delete("<path>", ...)
// Ritorna [{ method, path, file }]. GENERICO (qualunque router express).
function detectEndpoints(sources) {
  const endpoints = [];
  const re = /\.\s*(get|post|put|patch|delete)\s*\(\s*["'`]([^"'`]+)["'`]/g;
  for (const file of sources) {
    let text;
    try { text = readFileSync(file, 'utf8'); } catch { continue; }
    let m;
    while ((m = re.exec(text)) !== null) {
      endpoints.push({ method: m[1].toUpperCase(), path: m[2], file });
    }
  }
  return endpoints;
}

// Un endpoint e' "caratterizzabile in modo deterministico" se il suo handler NON
// dipende da I/O esterno (DB/rete). Euristica GENERICA: l'endpoint e' deterministico
// se il file dell'handler non importa client DB/rete noti E il path non contiene
// parametri dinamici instradati a query. Cio' che non e' deterministico viene
// ESCLUSO dalle assertion e dichiarato in coverage (06 §6.2).
function isDeterministicEndpoint(ep) {
  let text = '';
  try { text = readFileSync(ep.file, 'utf8'); } catch { /* noop */ }
  const usesDb = /supabase|createClient|\.rpc\(|\.from\(|pg\b|knex|prisma|mysql|mongodb/i.test(text);
  const dynamic = /:\w+/.test(ep.path); // path param -> probabile query DB
  return !usesDb && !dynamic;
}

// Rileva la directory di output della build (es. tsconfig.outDir 'dist').
function detectBuildOutDir(projectDir) {
  const tsPath = resolve(projectDir, 'tsconfig.json');
  if (existsSync(tsPath)) {
    try {
      const raw = readFileSync(tsPath, 'utf8')
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/(^|[^:])\/\/[^\n]*/g, '$1');
      const cfg = JSON.parse(raw);
      const out = cfg.compilerOptions && cfg.compilerOptions.outDir;
      if (out) return out.replace(/^\.\//, '').replace(/\/+$/, '');
    } catch { /* fallthrough al default */ }
  }
  return 'dist';
}

// Legge tsconfig.compilerOptions.rootDir (default 'src' se assente).
function detectTsRootDir(projectDir) {
  const tsPath = resolve(projectDir, 'tsconfig.json');
  if (!existsSync(tsPath)) return null;
  try {
    const raw = readFileSync(tsPath, 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/[^\n]*/g, '$1');
    const cfg = JSON.parse(raw);
    const rd = cfg.compilerOptions && cfg.compilerOptions.rootDir;
    if (rd) return rd.replace(/^\.\//, '').replace(/\/+$/, '');
  } catch { /* default */ }
  return 'src';
}

// Garantisce che gli artefatti di build (outDir) e node_modules siano IGNORATI da
// git nel progetto. Idempotente: append-only delle voci mancanti. GENERICO.
function ensureBuildArtifactsIgnored(projectDir, outDir) {
  const giPath = resolve(projectDir, '.gitignore');
  let current = '';
  if (existsSync(giPath)) { try { current = readFileSync(giPath, 'utf8'); } catch { current = ''; } }
  const want = [`${outDir}/`, 'node_modules/', '.trueline-charz-dist/'];
  const lines = current.split(/\r?\n/);
  const has = (entry) => lines.some((l) => l.trim() === entry || l.trim() === entry.replace(/\/$/, ''));
  const toAdd = want.filter((w) => !has(w));
  if (toAdd.length === 0) return false;
  const header = current && !current.endsWith('\n') ? '\n' : '';
  const block = `${header}# trueline characterization: artefatti di build esclusi dallo scan\n${toAdd.join('\n')}\n`;
  writeFileSync(giPath, current + block);
  return true;
}

// Rileva la presenza di un check di integrita di build (script build/typecheck).
// PREFERISCE 'typecheck' (es. tsc --noEmit) a 'build'.
function detectBuildIntegrity(pkg) {
  const s = (pkg && pkg.scripts) || {};
  if (s.typecheck) return { present: true, script: 'typecheck', emits: false };
  if (s.build) return { present: true, script: 'build', emits: true };
  return { present: false, script: null, emits: false };
}

// Rileva i nomi di variabili d'ambiente referenziate (per stabilizzare l'env).
function detectEnvRefs(sources) {
  const names = new Set();
  const reDot = /process\.env\.([A-Za-z_][A-Za-z0-9_]*)/g;
  const reIdx = /process\.env\[\s*["'`]([^"'`]+)["'`]\s*\]/g;
  for (const file of sources) {
    let t;
    try { t = readFileSync(file, 'utf8'); } catch { continue; }
    let m;
    while ((m = reDot.exec(t)) !== null) names.add(m[1]);
    while ((m = reIdx.exec(t)) !== null) names.add(m[1]);
  }
  return [...names];
}

// Rimuove i commenti (line // e block) da un sorgente, per evitare falsi segnali.
function stripComments(src) {
  return String(src || '')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}

function detectDetectionOnly(sources) {
  const cats = new Set();
  for (const file of sources) {
    let raw;
    try { raw = readFileSync(file, 'utf8'); } catch { continue; }
    const t = stripComments(raw);
    if (/["'`]\s*SELECT[\s\S]*?["'`]\s*\+/.test(t) || /\.rpc\(\s*["'`]exec_sql/.test(t)) {
      cats.add('injection');
    }
    const hasAuthCheck = /auth\.getUser\s*\(|\bgetUser\s*\(|req\.user\b|verifyJwt|verifyToken|requireAuth|authorize\s*\(|hasRole\s*\(|checkRole\s*\(|req\.auth\b|getSession\s*\(/i.test(t);
    if (/\.\s*(post|put|patch|delete)\s*\(/.test(t) && !hasAuthCheck) {
      cats.add('authz');
    }
  }
  return [...cats];
}

// -----------------------------------------------------------------------------
// GENERICITA DELL'ENTRY (C): scan dell'export che monta l'app.
// -----------------------------------------------------------------------------
// Non si richiede che l'entry si chiami letteralmente 'createApp'. Si accettano,
// in ordine di priorita': una FACTORY (createApp/buildServer/createServer/
// makeApp) come funzione esportata; un'istanza Express esportata (app/server/
// default). Ritorna { file, exportName, isFactory } oppure null se nessun entry
// importabile e' rilevato (in tal caso la copertura endpoint e' DICHIARATA
// ASSENTE — non si fabbrica un import inesistente).
function scanAppEntry(sources) {
  // Pattern di FACTORY esportate (ritornano un'app): nome -> regex di export.
  const factoryNames = ['createApp', 'buildServer', 'createServer', 'makeApp', 'buildApp', 'getApp'];
  // Pattern di ISTANZA esportata (app gia' costruita).
  const instanceNames = ['app', 'server'];

  for (const file of sources) {
    const text = safeRead(file);
    if (!text) continue;
    // 1) factory con nome noto: export function NAME / export const NAME = .
    for (const name of factoryNames) {
      const reFn = new RegExp(`export\\s+(?:async\\s+)?function\\s+${name}\\b`);
      const reConst = new RegExp(`export\\s+(?:const|let|var)\\s+${name}\\s*=`);
      if (reFn.test(text) || reConst.test(text)) {
        return { file, exportName: name, isFactory: true };
      }
    }
    // 2) factory di default: export default function (...) { ... return app }
    if (/export\s+default\s+(?:async\s+)?function/.test(text)
        && /\bexpress\s*\(/.test(text)) {
      return { file, exportName: 'default', isFactory: true };
    }
    // 3) istanza esportata: export const app = express()  -> non-factory.
    for (const name of instanceNames) {
      const reConst = new RegExp(`export\\s+(?:const|let|var)\\s+${name}\\s*=\\s*express\\s*\\(`);
      if (reConst.test(text)) {
        return { file, exportName: name, isFactory: false };
      }
    }
    // 4) default = istanza express: export default app  (app = express()).
    if (/export\s+default\s+\w+/.test(text) && /=\s*express\s*\(/.test(text)) {
      return { file, exportName: 'default', isFactory: false };
    }
  }
  return null;
}

// -----------------------------------------------------------------------------
// EMISSIONE della suite (run.mjs recomputer + wrapper node:test + baseline.json)
// -----------------------------------------------------------------------------

// Determina se il progetto e' TypeScript.
function projectIsTypeScript(pkg, projectDir) {
  if (existsSync(resolve(projectDir, 'tsconfig.json'))) return true;
  const s = (pkg && pkg.scripts) || {};
  return /tsc\b/.test(s.build || '') || /tsc\b/.test(s.typecheck || '');
}

// emitRunner — scrive run.mjs: il RECOMPUTER. Esporta recompute() -> {assertions:
// [{id, observed}]} e, come main, stampa quel JSON su stdout. Ricalcola observed
// per OGNI assertion sul codice CORRENTE:
//   - endpoint: compila TS in dir temp effimera, importa l'app via entry+export,
//     applica il PROLOGO DI STABILIZZAZIONE derivato dal sorgente, monta e
//     interroga ogni endpoint, osserva { status, body_status }.
//   - build-integrity: spawn dello script (typecheck/build), osserva
//     { typecheck_exit }. Se la build emette, ripulisce l'outDir.
//   - rls: importa characterizeRls dalla skill (path assoluto) con la ricetta
//     psql da env (TRUELINE_TEST_PSQL/dbUrl) e fotografa observed per tabella; se
//     degradata, observed = { static_flagged:true }.
function emitRunner(suiteDir, spec) {
  const {
    isTs, entrySubpath, entryExport, entryIsFactory, envRefs,
    endpoints, endpointPrologue, buildScript, buildEmits, buildOutDir,
    rlsAssertionIds, rlsTables, dbUrl,
  } = spec;

  // Mappa entrySubpath di compilazione: per TS il modulo compilato in temp.
  // NB: gli import comuni (spawnSync/rmSync/resolve/pathToFileURL) sono gia' in
  // testa al file generato; qui aggiungiamo solo cio' che manca (existsSync).
  const setupTs = `
import { existsSync } from 'node:fs';

// Compila in una dir EFFIMERA DENTRO il progetto (non os.tmpdir): cosi' i bare
// import (es. 'express') risolvono via il node_modules del progetto. La dir e'
// gitignorata e RIMOSSA dopo l'uso (lo scan di sicurezza non vede compilato).
const __charzOut = resolve(process.cwd(), '.trueline-charz-dist');
let __appLoaded = null;

function __tscEntry() {
  const cand = resolve(process.cwd(), 'node_modules', 'typescript', 'bin', 'tsc');
  return existsSync(cand) ? cand : null;
}

function __compile() {
  rmSync(__charzOut, { recursive: true, force: true });
  const entryTsc = __tscEntry();
  if (!entryTsc) throw new Error('tsc non trovato in node_modules/typescript/bin/tsc');
  const res = spawnSync(process.execPath, [entryTsc, '--project', 'tsconfig.json', '--outDir', __charzOut], {
    cwd: process.cwd(), encoding: 'utf8', shell: false, maxBuffer: 32 * 1024 * 1024,
  });
  if (res.status !== 0) {
    throw new Error('compilazione characterization fallita: ' + ((res.stdout || '') + (res.stderr || '')).slice(-400));
  }
}

async function __loadApp() {
  if (!__appLoaded) {
    __compile();
    const entry = pathToFileURL(resolve(__charzOut, ${JSON.stringify(entrySubpath)})).href;
    __appLoaded = await import(entry);
  }
  return __appLoaded;
}

function __cleanupApp() {
  try { rmSync(__charzOut, { recursive: true, force: true }); } catch { /* best-effort */ }
}
`;

  const setupJs = `
// (import comuni gia' in testa al file generato)
let __appLoaded = null;
async function __loadApp() {
  if (!__appLoaded) {
    const entry = pathToFileURL(resolve(process.cwd(), ${JSON.stringify(entrySubpath)})).href;
    __appLoaded = await import(entry);
  }
  return __appLoaded;
}
function __cleanupApp() { /* JS: nessun artefatto da pulire */ }
`;

  // Estrattore dell'app dal modulo importato: factory -> invoca; istanza -> usa.
  const appFromModule = entryIsFactory
    ? `const __mk = ${entryExport === 'default' ? 'mod.default' : `mod[${JSON.stringify(entryExport)}]`};
    const __app = (typeof __mk === 'function') ? __mk() : __mk;`
    : `const __app = ${entryExport === 'default' ? 'mod.default' : `mod[${JSON.stringify(entryExport)}]`};`;

  const hasEndpoints = endpoints.length > 0;
  const hasBuild = Boolean(buildScript);
  const hasRls = rlsAssertionIds.length > 0;

  const body = `// AUTO-GENERATO da trueline/scripts/characterization/generate.mjs
// RECOMPUTER della characterization: RI-CALCOLA observed per ogni assertion sul
// codice CORRENTE e stampa { assertions:[{id, observed}] } come JSON. Il wrapper
// node:test (vedi *.characterization.test.mjs) confronta questo output con la
// baseline.json congelata (deep-equal): un cambio di comportamento -> observed
// diverso -> test rosso. Falsificabile per costruzione.
import http from 'node:http';
import { spawnSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

${endpointPrologue}

// STABILIZZAZIONE dell'AMBIENTE: placeholder benigni per le env referenziate, per
// isolare il comportamento dal valore concreto del segreto (06 §6.2).
const __ENV_REFS = ${JSON.stringify(envRefs || [])};
function __placeholderFor(name) {
  if (/URL|URI|ENDPOINT|HOST/i.test(name)) return 'https://characterization.placeholder.local';
  if (/PORT/i.test(name)) return '0';
  return 'trueline-characterization-placeholder';
}
for (const k of __ENV_REFS) {
  if (process.env[k] === undefined || process.env[k] === '') process.env[k] = __placeholderFor(k);
}
${hasEndpoints ? (isTs ? setupTs : setupJs) : ''}
function __request(server, method, path) {
  return new Promise((resolveP, rejectP) => {
    const addr = server.address();
    const req = http.request({ host: '127.0.0.1', port: addr.port, method, path }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => resolveP({ status: res.statusCode, body: data }));
    });
    req.on('error', rejectP);
    req.end();
  });
}

const __ENDPOINTS = ${JSON.stringify(endpoints)};

// Ricalcola observed degli endpoint: { status, body_status }. body_status e' il
// campo 'status' del body JSON (se presente), un valore STABILE (uptime escluso).
async function __recomputeEndpoints() {
  const out = [];
  ${hasEndpoints ? `
  if (__ENDPOINTS.length === 0) return out;
  const mod = await __loadApp();
  ${appFromModule}
  try {
    for (const ep of __ENDPOINTS) {
      const server = __app.listen(0);
      await new Promise((r) => server.once('listening', r));
      try {
        const res = await __request(server, ep.method, ep.path);
        let parsed = null;
        try { parsed = JSON.parse(res.body); } catch { /* body non-JSON */ }
        const observed = { status: res.status };
        if (parsed && typeof parsed === 'object' && typeof parsed.status === 'string') {
          observed.body_status = parsed.status;
        }
        out.push({ id: ep.id, observed });
      } finally {
        server.close();
      }
    }
  } finally {
    __cleanupApp();
  }
  ` : ''}
  return out;
}

// Ricalcola observed di build-integrity: { typecheck_exit }.
function __recomputeBuildIntegrity() {
  ${hasBuild ? `
  const res = spawnSync('npm', ['run', ${JSON.stringify(buildScript)}, '--silent'], {
    cwd: process.cwd(), encoding: 'utf8', shell: true, maxBuffer: 32 * 1024 * 1024,
  });
  if (${JSON.stringify(Boolean(buildEmits))}) {
    try { rmSync(resolve(process.cwd(), ${JSON.stringify(buildOutDir)}), { recursive: true, force: true }); } catch { /* best-effort */ }
  }
  return [{ id: 'build-integrity:compile', observed: { typecheck_exit: res.status } }];
  ` : 'return [];'}
}

const __RLS_IDS = ${JSON.stringify(rlsAssertionIds)};

// Ricalcola observed RLS: ricompone characterizeRls (dalla skill) con la ricetta
// psql da env (TRUELINE_TEST_PSQL) o dbUrl baked. Mappa per id assertion; gli id
// assenti dallo snapshot corrente ricevono observed { missing:true } (cosi' il
// deep-equal contro la baseline FALLISCE se una tabella sparisce -> falsificabile).
async function __recomputeRls() {
  ${hasRls ? `
  const { characterizeRls } = await import(pathToFileURL(${JSON.stringify(SKILL_RLS_CHARACTERIZE)}).href);
  const dbUrl = ${JSON.stringify(dbUrl || null)};
  const snap = characterizeRls(process.cwd(), { dbUrl });
  const byId = new Map((snap.assertions || []).map((a) => [a.id, a.observed]));
  const out = [];
  for (const id of __RLS_IDS) {
    out.push({ id, observed: byId.has(id) ? byId.get(id) : { missing: true } });
  }
  return out;
  ` : 'return [];'}
}

export async function recompute() {
  const assertions = [];
  assertions.push(...(await __recomputeEndpoints()));
  assertions.push(...__recomputeBuildIntegrity());
  assertions.push(...(await __recomputeRls()));
  return { assertions };
}

const __isMain = process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (__isMain) {
  recompute()
    .then((r) => { process.stdout.write(JSON.stringify(r) + '\\n'); process.exit(0); })
    .catch((e) => { process.stderr.write('recompute KO: ' + (e && e.message ? e.message : e) + '\\n'); process.exit(1); });
}
`;
  const file = join(suiteDir, 'run.mjs');
  writeFileSync(file, body);
  return file;
}

// emitWrapper — scrive il wrapper node:test che, per ogni assertion di baseline,
// asserisce current.observed deep-equals baseline.observed sul codice CORRENTE.
// Esegue run.mjs come processo figlio (cosi' l'eventuale compilazione TS effimera
// avviene in un processo separato e non inquina il runner) e confronta.
function emitWrapper(suiteDir) {
  const body = `// AUTO-GENERATO da trueline/scripts/characterization/generate.mjs
// Wrapper node:test: \`npm test\` ESEGUE il recomputer (run.mjs) sul codice
// CORRENTE e asserisce che l'observed di OGNI assertion deep-equals la baseline
// congelata (baseline.json). Verde-per-costruzione oggi; falsificabile domani
// (un cambio di comportamento cambia l'observed e rompe il deep-equal).
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dir = dirname(fileURLToPath(import.meta.url));
const baseline = JSON.parse(readFileSync(resolve(__dir, 'baseline.json'), 'utf8'));

// Esegue run.mjs in un processo figlio e parsa il suo JSON { assertions:[...] }.
function recomputeViaChild() {
  const runner = resolve(__dir, 'run.mjs');
  const res = spawnSync(process.execPath, [runner], {
    cwd: process.cwd(), encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (res.status !== 0) {
    throw new Error('run.mjs exit=' + res.status + ': ' + ((res.stderr || res.stdout || '').slice(-400)));
  }
  // Prendi l'ULTIMA riga non vuota come JSON (eventuali log precedenti ignorati).
  const lines = (res.stdout || '').trim().split(/\\r?\\n/).filter(Boolean);
  return JSON.parse(lines[lines.length - 1]);
}

const current = recomputeViaChild();
const currentById = new Map((current.assertions || []).map((a) => [a.id, a.observed]));

for (const base of baseline.assertions) {
  test('characterization: ' + base.id + ' (observed invariante vs baseline)', () => {
    assert.ok(currentById.has(base.id),
      'assertion ' + base.id + ' assente dal recompute corrente (comportamento sparito?)');
    assert.deepEqual(currentById.get(base.id), base.observed,
      'observed di ' + base.id + ' DIVERSO dalla baseline (comportamento cambiato)');
  });
}
`;
  const file = join(suiteDir, 'characterization.test.mjs');
  writeFileSync(file, body);
  return file;
}

// Cabla lo script "test" nel package.json del progetto, in modo idempotente.
function wireTestScript(projectDir, pkg) {
  const pkgPath = resolve(projectDir, 'package.json');
  pkg.scripts = pkg.scripts || {};
  const existing = pkg.scripts.test || '';
  const placeholder = !existing || /no test specified/i.test(existing);
  const nodeTest = 'node --test "test/characterization/**/*.test.mjs"';

  if (placeholder) {
    pkg.scripts.test = nodeTest;
  } else if (!existing.includes('test/characterization')) {
    pkg.scripts.test = `${existing} && ${nodeTest}`;
  }
  writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
  return pkg.scripts.test;
}

// -----------------------------------------------------------------------------
// API principale
// -----------------------------------------------------------------------------

// generate(projectDir, { dbUrl, outDir }) -> oggetto JSON (vedi header).
export function generate(projectDir, opts = {}) {
  const root = resolve(projectDir);
  const { dbUrl = null } = opts;
  const outDir = opts.outDir ? resolve(opts.outDir) : resolve(root, 'test', 'characterization');

  if (!existsSync(root)) {
    return { ok: false, suiteDir: outDir, runner: null, assertions: [], coverage: { characterized: [], declared_uncovered: [] }, error: `projectDir assente: ${root}` };
  }

  let pkg = {};
  const pkgPath = resolve(root, 'package.json');
  if (existsSync(pkgPath)) {
    try { pkg = JSON.parse(readFileSync(pkgPath, 'utf8')); } catch { pkg = {}; }
  }

  const runnerInfo = detectRunner(root);
  const runner = 'node:test';

  const sources = collectSources(root);
  const isTs = projectIsTypeScript(pkg, root);
  const buildInfo = detectBuildIntegrity(pkg);

  const buildOutDir = detectBuildOutDir(root);
  const gitignoreTouched = ensureBuildArtifactsIgnored(root, buildOutDir);

  // Endpoint deterministici.
  const allEndpoints = detectEndpoints(sources);
  const detEndpoints = allEndpoints.filter((ep) => isDeterministicEndpoint(ep));
  const nondetEndpoints = allEndpoints.filter((ep) => !detEndpoints.includes(ep));

  // RLS (runtime se psql risolvibile, altrimenti static degradato e dichiarato).
  const rls = characterizeRls(root, { dbUrl });

  const detectionOnly = detectDetectionOnly(sources);
  const envRefs = detectEnvRefs(sources);

  mkdirSync(outDir, { recursive: true });

  // ENTRY GENERICO (C): scan dell'export che monta l'app (non solo 'createApp').
  const entry = scanAppEntry(sources);
  const rootDir = detectTsRootDir(root) || 'src';
  let entrySubpath = null;
  if (entry) {
    if (isTs) {
      const rel = relative(resolve(root, rootDir), entry.file).replace(/\\/g, '/');
      entrySubpath = rel.replace(/\.(ts|tsx)$/, '.js');
    } else {
      entrySubpath = relative(root, entry.file).replace(/\\/g, '/');
    }
  }
  const canImportApp = Boolean(entrySubpath);
  const canCompile = !isTs || existsSync(resolve(root, 'tsconfig.json'));

  // Costruisci la lista di assertion (con osservazione baseline). Gli observed
  // vengono CONGELATI ricalcolandoli sul codice corrente via run.mjs (sotto).
  const assertions = [];

  // -- endpoint --
  const endpointSpecs = [];
  let endpointPrologue = `// (nessun endpoint deterministico)`;
  const endpointsCharacterized = canImportApp && canCompile && detEndpoints.length > 0;
  if (endpointsCharacterized) {
    // PROLOGO DI STABILIZZAZIONE DERIVATO dal sorgente realmente scansionato di
    // OGNI endpoint deterministico (stabilize.stabilizationPrologue): non piu'
    // 'uptime' hardcoded, ma cio' che il codice usa davvero (uptime/clock/...).
    const endpointSources = [...new Set(detEndpoints.map((ep) => ep.file))].map((f) => safeRead(f));
    const stab = stabilizationPrologue(endpointSources);
    endpointPrologue = stab.prologue;
    for (const ep of detEndpoints) {
      const id = `endpoint:${ep.method} ${ep.path}`;
      endpointSpecs.push({ id, method: ep.method, path: ep.path });
      assertions.push({
        id, kind: 'endpoint', target: relPath(root, ep.file),
        file: 'test/characterization/run.mjs',
        // observed congelato sotto via recompute; placeholder qui.
        observed: null,
        description: `congela status/forma corrente di ${ep.method} ${ep.path} (uptime stabilizzato)`,
      });
    }
  }

  // -- build-integrity --
  if (buildInfo.present) {
    assertions.push({
      id: 'build-integrity:compile', kind: 'build-integrity', target: buildInfo.script,
      file: 'test/characterization/run.mjs', observed: null,
      description: `congela che il progetto compila/typecheck via npm run ${buildInfo.script}`,
    });
  }

  // -- rls -- (una assertion per tabella, observed dalla characterizeRls).
  const rlsAssertionIds = [];
  if (!rls.error) {
    for (const a of (rls.assertions || [])) {
      rlsAssertionIds.push(a.id);
      assertions.push({
        id: a.id, kind: 'rls', target: a.target,
        file: 'test/characterization/run.mjs',
        observed: a.observed, degraded: a.degraded === true,
        description: a.description,
      });
    }
  }

  // Copertura ONESTA.
  const coverage = coverageDeclaration({
    endpoints: endpointsCharacterized ? detEndpoints.map((e) => ({ method: e.method, path: e.path })) : [],
    pureTargets: [],
    buildIntegrity: buildInfo.present,
    rls: {
      tables: rls.tables || [],
      runtime: rls.runtime === true,
      degraded: rls.degraded === true,
      reason: rls.reason,
    },
    detectionOnlyCategories: detectionOnly,
  });

  // Endpoint NON deterministici esclusi (06 §6.2).
  for (const ep of nondetEndpoints) {
    coverage.declared_uncovered.push({
      what: `endpoint ${ep.method} ${ep.path}`,
      why: 'handler dipende da I/O esterno (DB/rete) o input dinamico: comportamento non stabilizzabile in modo deterministico — escluso dalle assertion (06 §6.2)',
    });
  }
  // GENERICITA (C): se nessun entry app importabile, DICHIARA l'assenza di
  // copertura endpoint (non si fabbrica un import inesistente).
  if (detEndpoints.length > 0 && !endpointsCharacterized) {
    coverage.declared_uncovered.push({
      what: 'endpoint HTTP del percorso critico',
      why: !canImportApp
        ? 'nessun entry app esportato rilevato (createApp/app/default/buildServer/istanza express): copertura endpoint ASSENTE, non fabbricata'
        : 'progetto TS senza tsconfig: impossibile compilare l\'app per la characterization endpoint — dichiarata assente',
    });
  }

  // Emetti run.mjs (recomputer) e il wrapper node:test.
  const files = [];
  const runnerFile = emitRunner(outDir, {
    isTs,
    entrySubpath,
    entryExport: entry ? entry.exportName : 'createApp',
    entryIsFactory: entry ? entry.isFactory : true,
    envRefs,
    endpoints: endpointSpecs,
    endpointPrologue,
    buildScript: buildInfo.present ? buildInfo.script : null,
    buildEmits: buildInfo.emits,
    buildOutDir,
    rlsAssertionIds,
    rlsTables: rls.tables || [],
    dbUrl,
  });
  files.push(runnerFile);

  // CONGELA gli observed: esegui run.mjs UNA volta sul codice corrente e usa il
  // suo output come baseline (green-by-construction: current==baseline oggi).
  const frozen = freezeObservedViaRunner(runnerFile, root);
  const frozenById = new Map((frozen.assertions || []).map((a) => [a.id, a.observed]));
  for (const a of assertions) {
    if (frozenById.has(a.id)) {
      a.observed = frozenById.get(a.id);
    } else if (a.observed === null) {
      // L'assertion non e' stata ricalcolata (es. recompute fallito per quel
      // kind): la marchiamo degradata dichiarando observed indisponibile, mai un
      // falso verde. (In pratica per endpoint/build questo non accade sul codice
      // corrente; per rls l'observed e' gia' preso dallo snapshot statico sopra.)
      a.observed = { unavailable: true };
      a.degraded = true;
    }
  }

  // Scrivi baseline.json (assertions con observed congelato + coverage).
  const baselineObj = {
    generated_by: 'trueline/scripts/characterization/generate.mjs',
    schema: 'snapshot/assertion v1 (id,kind,target,file,observed[,degraded])',
    assertions,
    coverage,
  };
  const baselinePath = join(outDir, 'baseline.json');
  writeFileSync(baselinePath, JSON.stringify(baselineObj, null, 2) + '\n');
  files.push(baselinePath);

  // Wrapper node:test.
  const wrapperFile = emitWrapper(outDir);
  files.push(wrapperFile);

  const testScript = wireTestScript(root, pkg);

  return {
    ok: true,
    suiteDir: outDir,
    runner,
    runnerDetected: runnerInfo,
    buildOutDir,
    gitignoreTouched,
    testScript,
    entry: entry ? { file: relPath(root, entry.file), exportName: entry.exportName, isFactory: entry.isFactory } : null,
    rlsRuntime: rls.runtime === true && rls.degraded !== true,
    rlsDegraded: rls.degraded === true,
    files: files.map((f) => relPath(root, f)),
    assertions: assertions.map((a) => ({ id: a.id, kind: a.kind, target: a.target, file: a.file, observed: a.observed, degraded: a.degraded === true })),
    baseline: relPath(root, baselinePath),
    coverage,
  };
}

// Esegue run.mjs come processo figlio per ottenere gli observed correnti, da
// CONGELARE come baseline (verde-per-costruzione). Ritorna { assertions:[...] }.
function freezeObservedViaRunner(runnerFile, cwd) {
  const res = spawnSync(process.execPath, [runnerFile], {
    cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (res.status !== 0) {
    // Non fabbricare observed: se il recompute fallisce, ritorna vuoto (le
    // assertion resteranno degradate/unavailable, non un falso verde).
    return { assertions: [], error: ((res.stderr || res.stdout || '').slice(-400)) };
  }
  const lines = (res.stdout || '').trim().split(/\r?\n/).filter(Boolean);
  if (lines.length === 0) return { assertions: [] };
  try { return JSON.parse(lines[lines.length - 1]); }
  catch { return { assertions: [] }; }
}

function safeRead(f) { try { return readFileSync(f, 'utf8'); } catch { return ''; } }
function relPath(root, p) { return relative(root, p).replace(/\\/g, '/'); }

// -----------------------------------------------------------------------------
// CLI
// -----------------------------------------------------------------------------
function parseArgs(argv) {
  const out = { projectDir: null, dbUrl: null, outDir: null };
  for (const a of argv) {
    if (a.startsWith('--db-url=')) out.dbUrl = a.slice('--db-url='.length) || null;
    else if (a.startsWith('--out=')) out.outDir = a.slice('--out='.length) || null;
    else if (!a.startsWith('--')) out.projectDir = a;
  }
  return out;
}

const __isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (__isMain) {
  const { projectDir, dbUrl, outDir } = parseArgs(process.argv.slice(2));
  if (!projectDir) {
    process.stderr.write('uso: node generate.mjs <projectDir> [--db-url=<url>] [--out=<dir>]\n');
    process.exit(2);
  }
  const res = generate(projectDir, { dbUrl: dbUrl === '' ? null : dbUrl, outDir });
  process.stdout.write(JSON.stringify(res, null, 2) + '\n');
  process.exit(res.ok ? 0 : 1);
}

export default generate;
