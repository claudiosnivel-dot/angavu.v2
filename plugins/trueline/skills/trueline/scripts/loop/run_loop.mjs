// run_loop.mjs — orchestratore di SESSIONE del verify-fix loop (05 §2, §6).
//
// Mette insieme i pezzi su una COPIA TEMPORANEA della reference app:
//   1) crea la copia temp (verify_workspace) — il fixture canonico NON si tocca.
//   2) crea il branch di lavoro (git a strati, autonomo).
//   3) raccoglie i finding dagli ORACOLI (gitleaks wt+history, rls, knip),
//      normalizzati nel finding model (04).
//   4) per ogni finding del SET IN-SCOPE (verificato-a-zero), esegue il loop
//      per-finding (loop.mjs) col FIX PROVIDER iniettato (eval = deterministico).
//   5) RI-VALUTA il checkpoint intero (01 §4) sulla copia dopo le fix.
//   6) esercita le DECISIONI del modello git a strati (merge gated / distruttive).
//   7) cleanup della copia temp (rm -rf). Il fixture canonico resta bit-identico.
//
// Uso:
//   node run_loop.mjs [--eval] [--mode=build|remediate] [--keep]
//                     [--fixture-app=<dir>] [--blueprint=<dir>]
//     --eval        auto-approva il gate umano in modo deterministico (solo-eval).
//     --mode        modalita per l'asimmetria git/checkpoint (default remediate).
//     --keep        NON cancella la copia temp (debug). Default: cleanup sempre.
//     --fixture-app EVAL-ONLY (BD-1): reference-app SORGENTE da copiare al posto
//                   della canonica (sourceApp per createVerifyWorkspace). Con
//                   questo flag, run_loop calcola il TIDY ADVISORY (disciplina
//                   di costruzione, momento 3) e lo attacca a
//                   report.build_discipline. SENZA il flag, comportamento
//                   IDENTICO a oggi (default canonico, nessun build_discipline).
//     --blueprint   EVAL-ONLY (BD-1): dir del seeded-blueprint del fixture
//                   (riservato al driver dell'harness; registrato nel report).
//   Stampa un JSON di esito su stdout. Exit 0 sempre che la sessione giri
//   (l'esito di merito e' nel JSON; il GATE M1 e' in eval/harness).
//
// Node ESM, solo built-in + i moduli M0/M1.

import { delimiter, resolve, dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

import { normalize } from '../findings/normalize.mjs';
import { validateMany } from '../findings/validate_finding.mjs';
import { createVerifyWorkspace } from './verify_workspace.mjs';
import { tidyAdvisory } from './build_discipline.mjs';
import { runFindingLoop } from './loop.mjs';
import { runCheckpoint, loadCharacterization } from '../checkpoint/checkpoint.mjs';
import { partition } from '../characterization/partition.mjs';
import { LOOP_BUDGET, verifiedSetFrom } from '../checkpoint/thresholds.mjs';
import { generate as generateCharacterization } from '../characterization/generate.mjs';
import {
  createWorkBranch, decideMerge, requestDestructive, currentBranch, commitOnBranch,
} from '../git/layered_git.mjs';
import { classify, loadManifest } from '../ecosystem/resolve.mjs';
import { AUTHZ_ORACLES, runAuthzOracle } from '../oracles/authz_oracles.mjs';
import { scanScopeFor, applyScanScope, scanScopeCoverage } from '../oracles/scan_scope.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// --- Fix provider (L-COL-029) -------------------------------------------------
// Le TABELLE DETERMINISTICHE di fix sono EVAL-ONLY e vivono in eval/ (fuori dal
// .skill). In contesto repo/eval il provider deterministico viene caricato
// DINAMICAMENTE -> comportamento BIT-INVARIANTE per tutti i gate (identico a
// quando era importato staticamente da ./fix_provider.mjs). Nel .skill
// IMPACCHETTATO eval/ non esiste: l'import dinamico fallisce -> fallback al
// provider HUMAN-GATE (nessuna tabella spedita; la fix reale e' un LLM
// human-gated, L-COL-005). L'import e' DINAMICO di proposito: uno statico verso
// eval/ romperebbe il caricamento del modulo nel .skill (file assente).
const EVAL_PROVIDER_URL = pathToFileURL(
  resolve(__dirname, '..', '..', '..', 'eval', 'harness', 'fix_provider.eval.mjs'),
).href;

// Provider HUMAN-GATE (runtime reale): non propone alcuna patch automatica ->
// la remediation e' proposta da un LLM ed e' sempre human-gated (L-COL-005).
function humanGateFixProvider() {
  return { propose() { return null; } };
}

async function resolveFixProvider() {
  try {
    const mod = await import(EVAL_PROVIDER_URL);
    return mod.deterministicFixProvider();
  } catch (e) {
    // FAIL-CLOSED + ONESTO (L-COL-006): la fallback HUMAN-GATE vale SOLO quando il
    // provider eval e' ASSENTE (.skill impacchettato: eval/ non c'e' -> MODULE_NOT_FOUND).
    // Un errore REALE di caricamento (bug/sintassi/import rotto del provider) NON va
    // mascherato in silenzio: si rilancia (in repo i gate falliscono comunque sul loro
    // import statico; run_loop esce 2 con la causa su stderr) -> il difetto emerge.
    if (e && e.code === 'ERR_MODULE_NOT_FOUND') return humanGateFixProvider();
    console.error('[resolveFixProvider] caricamento del provider eval fallito:', e?.stack || String(e));
    throw e;
  }
}
const ORACLES = resolve(__dirname, '..', 'oracles');
const RUN_GITLEAKS = resolve(ORACLES, 'run_gitleaks.mjs');
const RLS_CHECK = resolve(ORACLES, 'rls_check.mjs');
const RUN_DEADCODE = resolve(ORACLES, 'run_deadcode.mjs');
const RUN_SEMGREP = resolve(ORACLES, 'run_semgrep.mjs');
// authz dichiarativa (A0): l'oracolo authz non e' piu' cablato qui (era
// FIRESTORE_RULES_CHECK, SP-8) — collectFindings lo risolve dal manifest via la
// sorgente unica ../oracles/authz_oracles.mjs (runAuthzOracle), default firestore.
const GO_BIN = process.platform === 'win32' ? 'C:/Users/claud/go/bin' : '/c/Users/claud/go/bin';

const RUN_OPTS = { runId: 'loop-session', createdAt: '1970-01-01T00:00:00.000Z' };

function runOracle(script, args, cwd) {
  // Task 4: antepone il bin project-local `<cwd>/.trueline/bin` al PATH, poi il
  // PATH corrente, poi GO_BIN (precedenza: project-local -> PATH -> go/bin).
  // ADDITIVO/BIT-INVARIANTE: se `.trueline/bin` non esiste, e una dir inesistente
  // in testa al PATH -> nessun effetto sulla risoluzione (comportamento odierno).
  const localBin = cwd ? join(cwd, '.trueline', 'bin') : null;
  const basePath = `${process.env.PATH || ''}${delimiter}${GO_BIN}`;
  const PATH = localBin ? `${localBin}${delimiter}${basePath}` : basePath;
  const env = { ...process.env, PATH };
  const res = spawnSync(process.execPath, [script, ...args], {
    cwd, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (res.error) return { ok: false, json: null };
  const raw = (res.stdout || '').trim();
  if (!raw) return { ok: false, json: null };
  try { return { ok: true, json: JSON.parse(raw) }; } catch { return { ok: false, json: null }; }
}

function norm(oracle, json, scope) {
  const f = normalize(oracle, json, { ...RUN_OPTS, scope });
  const v = validateMany(f);
  // Tagghiamo lo scope di provenienza su ogni finding (serve a distinguere
  // S1 working-tree da S2 history, e a scegliere il re-run corretto nel loop).
  const tagged = (v.ok ? f : []).map((x) => ({ ...x, _scope: scope }));
  return tagged;
}

// Raccoglie i finding dalla COPIA per il set verificato-a-zero (secret/rls/dead-code)
// PIU' i detection-only semgrep (injection/authz, M4): questi NON sono in-scope per
// il loop (selectInScope li esclude) ma DEVONO entrare nella BASELINE pre-fix, cosi'
// che al checkpoint finale S6/S7 (immutati dalle fix) risultino PRE-EXISTING e non
// blocchino il controllo 2 (baseline-delta, 04 §6). semgrep e' BEST-EFFORT (via
// docker): se l'oracolo non gira, i suoi finding semplicemente non entrano nella
// baseline e il checkpoint li tratterebbe come nuovi — ma quello stesso checkpoint
// dichiarerebbe semgrep DEGRADATO (oracolo assente), coerente con L-COL-006.
// out (opzionale, ADDITIVO): raccoglitore per la coverage dello scan-scope. La
// firma di ritorno resta l'ARRAY dei finding (i chiamanti storici non cambiano).
function collectFindings(dir, manifest = null, out = {}) {
  const findings = [];
  const migrations = resolve(dir, 'supabase', 'migrations');

  // --- SCAN-SCOPE (PLAN 2026-07-28 §3.5) --------------------------------------
  // Questa raccolta e' DUE cose insieme: l'input del loop E la BASELINE del
  // checkpoint finale (`new Set(all.map(f => f.fingerprint))` in main). Percio' il
  // confine dev'essere lo STESSO di control2Security, o si apre il delta fantasma:
  // un finding che il checkpoint produce e la baseline non contiene risulta 'new'
  // e blocca il gate senza che nessuno abbia introdotto niente.
  // Stessa funzione, stesso projectDir, stesso manifest attivo -> stesso scope.
  // Una dichiarazione rotta qui NON viene assorbita in silenzio: si propaga e
  // run_loop la registra come errore di sessione (report.ok=false).
  // `manifest ? {manifest} : {}`: un null ESPLICITO qui significherebbe "nessun
  // manifest" mentre il checkpoint lo risolverebbe da disco -> due scope diversi.
  // Con l'omissione entrambi cadono sulla stessa auto-risoluzione da projectDir.
  const scope = scanScopeFor(dir, manifest ? { manifest } : {});
  const scopeExcluded = [];
  // Filtra il JSON NATIVO di gitleaks prima della normalizzazione. Guardia sul
  // TIPO: un non-array passa intatto (norm lo rifiuta), non diventa "zero segreti".
  const scoped = (json) => {
    if (!Array.isArray(json) || scope.patterns.length === 0) return json;
    const applied = applyScanScope(json, scope, dir);
    scopeExcluded.push(...applied.excluded);
    return applied.kept;
  };

  const gwt = runOracle(RUN_GITLEAKS, [dir, 'working-tree'], dir);
  if (gwt.ok) findings.push(...norm('gitleaks', scoped(gwt.json), 'working-tree'));

  // Lo scope vale anche per la history: il confine "generato vs d'autore" e' una
  // proprieta' del FILE, non dello scope di scansione. Il file sotto fix resta
  // comunque intoccabile nel re-run del loop (loop.mjs, REGOLA DEL SEME).
  const gh = runOracle(RUN_GITLEAKS, [dir, 'history'], dir);
  if (gh.ok) findings.push(...norm('gitleaks', scoped(gh.json), 'history'));

  const rls = runOracle(RLS_CHECK, [migrations], dir);
  if (rls.ok) findings.push(...norm('rls-check', rls.json, 'static-ddl'));

  const dc = runOracle(RUN_DEADCODE, [dir], dir);
  if (dc.ok) findings.push(...norm('knip', dc.json, 'working-tree'));

  // authz dichiarativa (A0): esegue l'oracolo authz del MANIFEST attivo — non piu'
  // solo Firestore — cosi' la baseline pre-fix ha un finding authz su cui il loop
  // (rerunOracleFor) puo' girare anche sui 4 backend non-Firebase (chiude il buco
  // end-to-end REMEDIATE). Il binding authz-surface e' individuato per ruolo E per
  // presenza in AUTHZ_ORACLES (il guard AUTHZ_ORACLES[b.tool] scarta le authz-surface
  // NON dichiarative, es. rls_check di supabase-jsts -> resta firestore default ->
  // BIT-invariante per Supabase e per il ramo senza manifest). runAuthzOracle e' la
  // sorgente UNICA condivisa col checkpoint e con loop.mjs::rerunOracleFor (stesso
  // normalize/fingerprint, parita' verificata su hasura). Prova STATICA (L-COL-006).
  // NB: usa RUN_OPTS deterministici (gli stessi di norm()) per fingerprint stabili.
  const authzBinding = manifest && manifest.oracles
    ? Object.values(manifest.oracles).find((b) => b && b.role === 'authz-surface' && AUTHZ_ORACLES[b.tool])
    : null;
  const authzTool = authzBinding ? authzBinding.tool : 'firestore_rules_check';
  const a = runAuthzOracle(authzTool, dir, authzBinding || {}, RUN_OPTS);
  if (a.ok) findings.push(...a.findings);

  // semgrep (M4, 07 §4): pattern vietati injection/authz (S6/S7), detection-only.
  // Collezionati SOLO per la baseline pre-fix (non per il loop): cosi' il checkpoint
  // finale non li vede come NUOVI. Stesso normalize/base degli altri oracoli ->
  // fingerprint coerenti con control2Security del checkpoint.
  const sg = runOracle(RUN_SEMGREP, [dir], dir);
  if (sg.ok && sg.json && Array.isArray(sg.json.results)) {
    findings.push(...norm('semgrep', sg.json, 'working-tree'));
  }

  // Coverage dello scan-scope: presente SOLO se c'e' almeno un pattern dichiarato
  // (senza dichiarazioni non c'e' nulla da dichiarare, e la forma del report resta
  // quella di oggi — BIT-invarianza).
  out.scanScope = scope.patterns.length > 0 ? scanScopeCoverage(scope, scopeExcluded) : null;

  return findings;
}

// A2c/F3 — DEBITO STRUTTURALE per l'audit REMEDIATE. control1Hygiene GIA' computa
// dup/cycle/twin (F1) quando il manifest li dichiara, ma run_loop scarta i
// control.findings nel serializzare report.checkpoint. Qui li RIUSA (nessun re-run):
// estrae la fetta d'igiene del controllo 1 per report.structural_debt (detection-only,
// non-bloccante, mai auto-fixata — L-COL-030). dead-code (knip) NON e' debito
// strutturale (ha il suo gate delta). [] se il controllo 1 o i finding sono assenti.
const HYGIENE_ORACLES = new Set(['jscpd', 'cycle', 'twin']);
export function extractStructuralDebt(controls) {
  const c1 = Array.isArray(controls) ? controls.find((c) => c && c.id === 1) : null;
  const findings = (c1 && Array.isArray(c1.findings)) ? c1.findings : [];
  return findings
    .filter((f) => f.source_oracle && HYGIENE_ORACLES.has(f.source_oracle.oracle))
    .map((f) => ({
      fingerprint: f.fingerprint,
      category: f.category,
      severity: f.severity,
      oracle: f.source_oracle.oracle,
      location: f.location,
      evidence: f.evidence,
      baseline_status: f.baseline_status,
    }));
}

const baseName = (p) => String(p).replace(/\\/g, '/').split('/').pop();

// Esegue il recomputer (run.mjs) sulla copia e ritorna Map id->observed corrente.
function recomputeObserved(dir, runnerPath) {
  const res = spawnSync(process.execPath, [runnerPath], {
    cwd: dir, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (res.status !== 0) return null;
  const lines = (res.stdout || '').trim().split(/\r?\n/).filter(Boolean);
  if (lines.length === 0) return null;
  try {
    const parsed = JSON.parse(lines[lines.length - 1]);
    return new Map((parsed.assertions || []).map((a) => [a.id, a.observed]));
  } catch { return null; }
}

// RE-BASELINE post-fix (06 §4): dopo che il loop ha applicato fix VERIFIED che
// cambiano LEGITTIMAMENTE le assertion IMPACTED (es. fixare S5 -> invoices),
// aggiorna la baseline.json SOLO per le assertion impacted (unione delle partition
// su tutti i finding verified), lasciando INVARIATE le GUARD. Cosi' il checkpoint
// finale "puro" (senza finding) confronta: GUARD vs baseline ORIGINALE (cattura
// regressioni), IMPACTED vs post-fix (re-baselined). Ritorna l'elenco di id
// re-baselined (o [] se non applicabile). NON tocca git (lo fa il chiamante).
function rebaselineImpacted(dir, verifiedFindings) {
  const charz = loadCharacterization(dir);
  if (!charz) return { rebaselined: [], reason: 'nessuna characterization' };
  const baselinePath = join(dir, 'test', 'characterization', 'baseline.json');
  let baselineObj;
  try { baselineObj = JSON.parse(readFileSync(baselinePath, 'utf8')); }
  catch { return { rebaselined: [], reason: 'baseline.json illeggibile' }; }
  const assertions = baselineObj.assertions || [];

  // Unione degli id IMPACTED su tutti i finding verified (la fix li cambia per
  // disegno). I finding non-verified (es. S2 mitigated-residual) NON re-baseline.
  const impactedIds = new Set();
  for (const f of verifiedFindings) {
    // partition() richiede category + location: usiamo il record del finding.
    const part = partition(f, assertions);
    for (const id of part.impacted) impactedIds.add(id);
  }
  if (impactedIds.size === 0) return { rebaselined: [], reason: 'nessuna assertion impacted' };

  const current = recomputeObserved(dir, charz.runnerPath);
  if (!current) return { rebaselined: [], reason: 'recompute post-fix fallito' };

  const rebaselined = [];
  for (const a of assertions) {
    if (impactedIds.has(a.id) && current.has(a.id)) {
      a.observed = current.get(a.id); // re-baseline all'observed post-fix.
      rebaselined.push(a.id);
    }
  }
  writeFileSync(baselinePath, JSON.stringify(baselineObj, null, 2) + '\n');
  return { rebaselined, reason: null };
}

// Selettore del set IN-SCOPE per il loop (set verificato-a-zero, L-COL-010 +
// set seminato verificato-a-zero del prompt: S1, S2, S3, S4, S5, S8).
//
//   SECRET:
//     - S1 = secret in WORKING-TREE su config.ts        -> verified atteso
//     - S2 = secret SOLO in HISTORY su credentials.ts    -> mitigated-residual
//     Nota: S1 riappare anche nella history (stesso file config.ts in scope
//     history); lo IGNORIAMO la' (e' gia' coperto dal re-run working-tree).
//   RLS: S3/S4/S5 (tutti i finding rls).
//   DEAD-CODE: S8 = il FILE morto seminato src/legacy/unused.ts. Altro
//     dead-code incidentale (es. db.ts, legato a S6 detection-only) NON e' nel
//     set seminato in-scope di M1: e' baseline/pre-existing (resta nel report,
//     non entra nel loop di M1). // TODO M3+: remediation piena del residuo.
function selectInScope(findings, manifest = null) {
  const result = [];
  const fpSeen = new Set();
  const push = (f) => { if (!fpSeen.has(f.fingerprint)) { fpSeen.add(f.fingerprint); result.push(f); } };

  // Set IN-SCOPE per il loop = verified_set del manifest attivo (SP-0). SENZA
  // manifest, verifiedSetFrom ritorna il DEFAULT v1 {secret, rls, dead-code}:
  // stesso comportamento del cablato. Le categorie fuori dal verified_set NON
  // entrano nel loop (mai auto-promosse a verificata-a-zero, L-COL-010).
  const inScope = verifiedSetFrom(manifest);

  for (const f of findings) {
    if (!inScope.has(f.category)) continue;

    if (f.category === 'rls') { push(f); continue; }

    if (f.category === 'dead-code') {
      // Solo il file morto seminato S8 (unused.ts).
      if (baseName(f.location.file) === 'unused.ts') push(f);
      continue;
    }

    if (f.category === 'authz') {
      // SP-8: la regola Firestore vulnerabile FB-S3 vive in firestore.rules.
      // Guardia su 'authz' nel verified_set del manifest (filtro in cima al loop):
      // senza manifest authz NON e' nel set -> mai ammessa (BIT-invariante).
      if (baseName(f.location.file) === 'firestore.rules') push(f);
      continue;
    }

    if (f.category === 'secret') {
      const bn = baseName(f.location.file);
      // S1: working-tree su config.ts.
      if (bn === 'config.ts' && f._scope === 'working-tree') { push(f); continue; }
      // S2: history su credentials.ts (file assente dal working tree).
      if (bn === 'credentials.ts' && f._scope === 'history') { push(f); continue; }
      // config.ts in scope history = S1 gia' coperto -> ignora.
    }
  }
  return result;
}

async function main() {
  const argv = process.argv.slice(2);
  const evalMode = argv.includes('--eval');
  const keep = argv.includes('--keep');
  // --characterize (M3): genera la suite di characterization (06) nella COPIA
  // PRIMA del loop, cosi' i controlli 3/4 del checkpoint hanno un oracolo reale
  // (test) e diventano verdi (non piu' degradati). Senza il flag, comportamento
  // M1 invariato (3/4 degradati): cio' preserva il gate M1.
  const characterize = argv.includes('--characterize');
  const dbUrlArg = (argv.find((a) => a.startsWith('--db-url=')) || '').split('=').slice(1).join('=');
  const dbUrl = dbUrlArg ? dbUrlArg : null;
  const modeArg = (argv.find((a) => a.startsWith('--mode=')) || '').split('=')[1];
  const mode = modeArg === 'build' ? 'build' : 'remediate';

  // BD-1 EVAL-ONLY (ADDITIVO): --fixture-app=<dir> sostituisce la reference-app
  // sorgente copiata (sourceApp), e abilita il tidy advisory. --blueprint=<dir>
  // registra la dir del seeded-blueprint del fixture (riservata all'harness).
  // SENZA questi flag, fixtureApp/blueprintDir restano null e ogni path sotto
  // resta BIT-INVARIANTE (sourceApp default = canonica, nessun build_discipline).
  const fixtureAppArg = (argv.find((a) => a.startsWith('--fixture-app=')) || '').split('=').slice(1).join('=');
  const fixtureApp = fixtureAppArg ? fixtureAppArg : null;
  const blueprintArg = (argv.find((a) => a.startsWith('--blueprint=')) || '').split('=').slice(1).join('=');
  const blueprintDir = blueprintArg ? blueprintArg : null;

  // createVerifyWorkspace riceve sourceApp SOLO quando --fixture-app e' passato:
  // altrimenti l'opzione e' assente -> default canonico (path BIT-invariante).
  const wsOpts = { id: `loop-${RUN_OPTS.runId}` };
  if (fixtureApp) wsOpts.sourceApp = fixtureApp;
  const ws = createVerifyWorkspace(wsOpts);
  const report = {
    mode, evalMode, workspace: ws.dir, fixtureMutated: false, findings: [], checkpoint: null, git: {},
  };

  try {
    // (2) branch di lavoro autonomo (convenzione 05 §8.1).
    const branchName = `trueline/${mode}/loop-session`;
    createWorkBranch(ws.dir, branchName);
    report.git.branch = currentBranch(ws.dir);

    // (2.5) CHARACTERIZATION (M3, opt-in via --characterize): genera la suite che
    //   CATTURA il comportamento corrente del percorso critico (06) nella COPIA,
    //   PRIMA di raccogliere i finding. Cosi':
    //     - i file di test generati entrano nella BASELINE (pre-existing): non
    //       contano come dead-code NUOVO al controllo 1 (04 §6, L-COL-021);
    //     - i controlli 3/4 del checkpoint hanno un oracolo reale (npm test) e
    //       diventano VERDI (non piu' degradati M3).
    //   La copertura ONESTA (injection/authz -> M4; RLS runtime degradato) viene
    //   riportata in report.coverage (criterio 3 onesto, L-COL-006).
    if (characterize) {
      const charz = generateCharacterization(ws.dir, { dbUrl });
      report.characterization = {
        ok: charz.ok,
        suiteDir: charz.suiteDir,
        runner: charz.runner,
        testScript: charz.testScript,
        files: charz.files,
        assertions: (charz.assertions || []).map((a) => ({
          id: a.id, kind: a.kind, target: a.target, file: a.file,
        })),
      };
      report.coverage = charz.coverage;
      // COMMIT della suite sul branch di lavoro PRIMA del loop. Senza questo, il
      // revert pre-patch del loop (reset --hard + clean -fd, 05 §3) cancellerebbe
      // i file di test non committati, facendo ricadere i controlli 3/4 in
      // degradato. Committandola, ogni revert torna a uno SHA che la INCLUDE.
      commitOnBranch(ws.dir, 'test(characterization): baseline comportamento corrente (M3)');
    }

    // (3) raccogli i finding dalla copia.
    //   Risolvi l'ecosistema attivo (classify -> manifest) e passalo a
    //   selectInScope: il set IN-SCOPE per il loop e' il verified_set del
    //   manifest. Nessun manifest combacia -> null -> default v1 (SP-0).
    const activeId = classify(ws.dir);
    const manifest = activeId ? loadManifest(activeId) : null;
    report.ecosystem = activeId;
    const scanScopeOut = {};
    const all = collectFindings(ws.dir, manifest, scanScopeOut);

    // BUILD-DISCIPLINE (BD-1, EVAL-ONLY): col fixture-app la copia E' l'artefatto
    // POST-COSTRUZIONE da GIUDICARE, non un repo da bonificare. Quindi:
    //   - NIENTE loop di remediation (inScope vuoto): la disciplina COSTRUISCE e
    //     poi l'oracolo GIUDICA — non si auto-fixa il difetto di costruzione
    //     (altrimenti l'orfano nuovo verrebbe rimosso e control1 non lo vedrebbe).
    //   - BASELINE VUOTA: il checkpoint deve trattare i difetti del fixture come
    //     NUOVI (introdotti dalla costruzione) -> l'orfano dead-code della fixture
    //     `orphan-injecting` rende control1 ROSSO (gate §7.3b); la fixture
    //     `overcomplicated-correct` (zero dead-code/secret) resta VERDE.
    // SENZA --fixture-app (fixtureApp null) i due valori sono calcolati ESATTAMENTE
    // come prima (selectInScope + baseline da `all`) -> path BIT-invariante.
    const inScope = fixtureApp ? [] : selectInScope(all, manifest);

    // BASELINE (04 §6): fingerprint di TUTTO cio' che e' pre-esistente PRIMA
    // delle fix. Il checkpoint finale gate-a sui finding NUOVI (delta): il
    // dead-code incidentale di db.ts (residuo S6, fuori dal set seminato M1) e'
    // pre-existing -> NON blocca il controllo 1 (resta segnalato, non cancellato
    // in autonomia, L-COL-021). // TODO M3+: remediation piena del residuo.
    // Col fixture-app la baseline e' VUOTA (vedi sopra): i difetti del fixture
    // sono NUOVI per definizione (costruzione da giudicare).
    const baseline = fixtureApp ? new Set() : new Set(all.map((f) => f.fingerprint));
    report.baselineSize = baseline.size;

    // (4) loop per-finding sul set in-scope.
    const provider = await resolveFixProvider();
    const budget = { startedAt: Date.now(), deadlineMs: Date.now() + LOOP_BUDGET.GLOBAL_WALL_CLOCK_MS };
    for (const finding of inScope) {
      const res = runFindingLoop(finding, { dir: ws.dir, fixProvider: provider, evalMode, runOpts: RUN_OPTS, budget });
      report.findings.push(res);
    }

    // (4.5) RE-BASELINE post-fix delle assertion IMPACTED (06 §4 — il nodo):
    //   le fix VERIFIED hanno cambiato LEGITTIMAMENTE il comportamento delle
    //   assertion sulla stessa regione/tabella (es. S4/S5 -> documents/invoices).
    //   Aggiorniamo la baseline SOLO per quelle (le GUARD restano congelate al
    //   comportamento originale), poi committiamo: cosi' il checkpoint finale
    //   "puro" (senza finding) trova GUARD invarianti e IMPACTED re-baselined ->
    //   controlli 3/4 VERDI. Senza --characterize questo step e' no-op.
    if (characterize) {
      const verifiedFindings = inScope.filter((f) => {
        const r = report.findings.find((x) => x.fingerprint === f.fingerprint);
        return r && r.fix_state === 'verified';
      });
      const rb = rebaselineImpacted(ws.dir, verifiedFindings);
      report.rebaseline = rb;
      if (rb.rebaselined.length > 0) {
        commitOnBranch(ws.dir, 'test(characterization): re-baseline IMPACTED post-fix (06 §4)');
      }
    }

    // (5) RI-VALUTA il checkpoint intero sulla copia (dopo le fix applicate),
    //     col baseline-delta: gate-a sui finding NUOVI sopra soglia (04 §6). Con
    //     characterization presente i controlli 3/4 usano l'invarianza (06 §4):
    //     GUARD invarianti (vs baseline originale), IMPACTED gia' re-baselined.
    const cp = runCheckpoint(ws.dir, { mode, runOpts: RUN_OPTS, withOsv: false, baseline, blueprintDir });
    report.checkpoint = {
      green: cp.green, summary: cp.summary, degraded: cp.degraded,
      controls: cp.controls.map((c) => ({ id: c.id, name: c.name, status: c.status, green: c.green, detail: c.detail })),
    };
    // POTERE DELL'ASSERZIONE (AT-1 Fase C): la proiezione dei controlli qui sopra tiene
    // 5 campi e scarta `power`, come shapeControl. La sintesi risale percio' accanto a
    // `degraded`, o la dichiarazione non arriverebbe al report del loop. Campo assente
    // quando il ramo AC non ha girato -> shape del report INVARIATA (come scan_scope).
    if (cp.assertion_power) report.checkpoint.assertion_power = cp.assertion_power;

    // SCAN-SCOPE nel REPORT REMEDIATE (PLAN §3.5 / §3.4): cio' che NON e' stato
    // scansionato si dichiara, con pattern, PROVENIENZA, `reason` di progetto e
    // numero di finding soppressi. E' l'unica cosa che rende legittima la leva 3:
    // un'esclusione riscritta nero su bianco a ogni giro non e' un bypass; una
    // taciuta lo sarebbe (L-COL-006). Non scansionare qualcosa NON e' un verde.
    // Sorgente preferita: la coverage del CHECKPOINT (lo stato finale, post-fix);
    // fallback alla raccolta pre-fix se il controllo 2 non ha eseguito gitleaks.
    // Assente => nessuna dichiarazione => nessun campo (BIT-invarianza della shape).
    const scanScopeCov = (cp && cp.scan_scope) || scanScopeOut.scanScope || null;
    if (scanScopeCov) {
      if (!report.coverage) report.coverage = { characterized: [], declared_uncovered: [] };
      report.coverage.scan_scope = scanScopeCov;
    }

    // A2c/F3 — debito strutturale (report REMEDIATE) dai finding d'igiene GIA'
    // calcolati dal controllo 1 (nessun re-run). Guardia sul manifest -> BIT-invariante
    // per i pack senza dup/cycle. report.findings (loop) resta invariato.
    const declaresHygiene = Boolean(manifest && manifest.oracles
      && (manifest.oracles.duplication || manifest.oracles.architecture));
    if (declaresHygiene) {
      report.structural_debt = extractStructuralDebt(cp.controls);
      if (!report.coverage) report.coverage = { characterized: [], declared_uncovered: [] };
      if (Array.isArray(report.coverage.declared_uncovered)) {
        report.coverage.declared_uncovered.push({
          what: 'duplicazione verbatim >=min_tokens; cicli import JS/TS; directory clone-and-rename (twin)',
          why: 'igiene strutturale detection-only (L-COL-030): rilevata e riportata, MAI auto-fixata; i simboli RINOMINATI e le duplicazioni sotto min_tokens non sono coperti',
        });
      }
    }

    // (5.5) TIDY ADVISORY (BD-1, momento 3 — solo con --fixture-app, EVAL-ONLY).
    //   La disciplina di costruzione EMETTE un segnale ISPEZIONABILE di
    //   complessita di scrittura sui sorgenti del fixture (copia ws.dir).
    //   *** ADVISORY, MAI GATE (L-COL-006): tidyAdvisory NON e' negli input di
    //   runCheckpoint (calcolato DOPO il checkpoint, attaccato SOLO al report)
    //   -> il flag complexity_flag puo' essere true MENTRE cp.green e' true
    //   (sotto-test §7.2a). *** SENZA --fixture-app questo blocco non esiste:
    //   nessun report.build_discipline -> shape BIT-invariante.
    if (fixtureApp) {
      report.build_discipline = tidyAdvisory(ws.dir, { runOpts: RUN_OPTS });
      if (blueprintDir) report.build_discipline.blueprint_dir = blueprintDir;
    }

    // (6) DECISIONI del modello git a strati (esercitate, non eseguite su remote).
    //     a) merge gated dal checkpoint + deploy-coupling, per i tre casi.
    report.git.merge = {
      // BUILD verde + non-coupled (utente conferma) -> autonomo.
      build_noncoupled: decideMerge({ dir: ws.dir, mode: 'build', checkpointGreen: true, confirmedCoupled: false }),
      // BUILD verde + coupled (o unknown non confermato) -> sospeso.
      build_coupled: decideMerge({ dir: ws.dir, mode: 'build', checkpointGreen: true, confirmedCoupled: true }),
      build_unknown_unconfirmed: decideMerge({ dir: ws.dir, mode: 'build', checkpointGreen: true, confirmedCoupled: null }),
      // REMEDIATE -> sempre human-gated.
      remediate: decideMerge({ dir: ws.dir, mode: 'remediate', checkpointGreen: true, confirmedCoupled: false }),
    };
    //     b) operazione distruttiva -> sempre bloccata in autonomia.
    report.git.destructive = requestDestructive('history rewrite');

    report.ok = true;
  } catch (e) {
    report.ok = false;
    report.error = String(e && e.message ? e.message : e);
  } finally {
    // (7) cleanup SEMPRE (salvo --keep): il fixture canonico resta intatto.
    if (!keep) ws.cleanup();
    report.cleanedUp = !keep;
  }

  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
  process.exit(0);
}

const __isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (__isMain) main().catch((e) => { console.error(e?.stack || String(e)); process.exit(2); });

export { collectFindings, selectInScope };
