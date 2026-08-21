// checkpoint.mjs — il CHECKPOINT a 4 controlli (01 §4).
//
// Gira al confine di ogni macrotask (BUILD) ed e' il motore di verifica anche
// dentro il loop di REMEDIATE. Quattro controlli, ciascuno ancorato a un
// ORACOLO deterministico. L'LLM NON decide l'esito di nessuno dei quattro
// (L-COL-002): verde/rosso e' una proprieta' dell'output del comando.
//
//   1) DEAD CODE        -> run_deadcode (knip). Verde = nessun morto NUOVO
//                          (gate per DELTA, 04 §6); il morto pre-esistente e'
//                          SEGNALATO, non cancellato in autonomia (L-COL-021).
//   2) SICUREZZA        -> gitleaks (working-tree) + rls_check + osv
//                          [+ semgrep DIFFERITO a M4]. Verde = nessun finding
//                          NUOVO con severity >= soglia (thresholds.md) nelle
//                          categorie in scope.
//   3) REGRESSIONI      -> test runner (suite esistente in BUILD / characterization
//                          in REMEDIATE). Verde = nessun test prima verde ora rosso.
//   4) CONFORMITA-LOGICA-> test di accettazione (BUILD) / invarianza
//                          characterization (REMEDIATE).
//
// FORWARD-DEP (M3): i characterization test (06) e i test di accettazione NON
// esistono ancora -> in assenza di test i controlli 3/4 si DICHIARANO DEGRADATI
// (status="degraded", // TODO M3), NON un falso verde. Un controllo degradato
// NON e' verde: il checkpoint NON e' "interamente verde" finche' 3/4 sono
// degradati. Questo e' onesto (L-COL-006: nessun falso via libera).
//
// USO BASELINE-DELTA (03 §8, 04 §6): il gate guarda i finding NUOVI sopra
// soglia, non l'assoluto. La baseline e' un insieme di fingerprint gia' noti.
//
// Node ESM, solo built-in + i wrapper M0 (oracoli) e l'adapter normalize (04).

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname, join, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

import { normalize } from '../findings/normalize.mjs';
import { loadHygieneBaseline } from '../findings/baseline.mjs';
import { validateMany } from '../findings/validate_finding.mjs';
import { partition } from '../characterization/partition.mjs';
import {
  GATE_SEVERITY, VERIFIED_ZERO_CATEGORIES, CONTROL2_GATE_CATEGORIES, severityAtLeast,
  control2CategoriesFrom,
} from './thresholds.mjs';
import { classify, loadManifest } from '../ecosystem/resolve.mjs';
import { AUTHZ_ORACLES, AUTHZ_TOOL_NAMES, runAuthzOracle } from '../oracles/authz_oracles.mjs';
import { scanScopeFor, applyScanScope, scanScopeCoverage } from '../oracles/scan_scope.mjs';
import { loadTasks } from '../blueprint/blueprint_tasks.mjs';
import { runTargetFile } from './run_file.mjs';
import { assertionTrace } from '../blueprint/ac_assertion_trace_check.mjs';
import { assertionPower } from '../blueprint/ac_assertion_power_check.mjs';
import { loadArchContract } from '../blueprint/arch_contract.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..', '..', '..');
const ORACLES = resolve(__dirname, '..', 'oracles');
const RUN_GITLEAKS = resolve(ORACLES, 'run_gitleaks.mjs');
const RLS_CHECK = resolve(ORACLES, 'rls_check.mjs');
const RUN_DEADCODE = resolve(ORACLES, 'run_deadcode.mjs');
const RUN_OSV = resolve(ORACLES, 'run_osv.mjs');
const RUN_SEMGREP = resolve(ORACLES, 'run_semgrep.mjs');
// A2a — oracoli di igiene strutturale (controllo 1 multi-oracolo).
const RUN_DUPCHECK = resolve(ORACLES, 'run_dupcheck.mjs');
const RUN_CYCLECHECK = resolve(ORACLES, 'run_cyclecheck.mjs');
const TWIN_CHECK = resolve(ORACLES, 'twin_check.mjs');
const ARCH_CHECK = resolve(ORACLES, 'arch_check.mjs');

// Oracoli DETECTION-ONLY (L-COL-030): segnalano un FATTO strutturale ma non
// gata-no MAI il verdetto. L'esclusione e' PER-ORACOLO, non per-categoria: `cycle`
// e `twin` sono entrambi category=architecture, ma solo `cycle` blocca su delta;
// `twin` (clone-and-rename per-entita') e' un segnale, mai un gate. In v1 nessun
// fix-provider deterministico spedito -> nessun oracolo di igiene oltre dead-code/
// dup/cycle gata; twin resta fuori dai blockers.
const DETECTION_ONLY_ORACLES = new Set(['twin']);

// Oracoli a GATE ASSOLUTO (A2b): un contratto DICHIARATO dall'utente (arch_check)
// blocca SEMPRE, non solo sul delta — come rls (USING(true) non si grandfather-a).
// I loro finding bypassano il filtro baseline in partitionBlockers.
const ABSOLUTE_GATE_ORACLES = new Set(['arch']);

// Tool cablati al CONTROLLO 1 (igiene strutturale). Sono guidati dallo STESSO
// manifest.oracles del controllo 2 (dopo A2a: duplication/architecture vi sono
// dichiarati), quindi il loop manifest-driven del controllo 2 li vedrebbe come
// "tool di sicurezza sconosciuti" e li declasserebbe (runTool default -> nota +
// ranFail). Sono di competenza ESCLUSIVA del controllo 1: il controllo 2 li salta
// (come gia' fa con 'knip'). `dependency-cruiser` incluso per compat storica (il
// binding architecture usa 'madge', vedi run_cyclecheck).
const CONTROL1_TOOLS = new Set(['knip', 'jscpd', 'madge', 'dependency-cruiser', 'twin']);

const GO_BIN = process.platform === 'win32'
  ? 'C:/Users/claud/go/bin'
  : '/c/Users/claud/go/bin';

// Esegue un oracolo come processo figlio e ne parsa lo stdout JSON. Decide
// dall'output (report), non dall'exit code (03 §3).
function runOracle(scriptPath, args, cwd = ROOT) {
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

function normFindings(oracle, native, opts) {
  let findings = [];
  try { findings = normalize(oracle, native, opts); }
  catch (e) { return { ok: false, findings: [], detail: `normalize(${oracle}): ${e.message}` }; }
  const v = validateMany(findings);
  if (!v.ok) return { ok: false, findings, detail: `schema KO: ${v.errors.slice(0, 2).join('; ')}` };
  return { ok: true, findings, detail: `${findings.length} finding` };
}

// Applica il baseline-delta (04 §6): marca ogni finding new/pre-existing in base
// al set di fingerprint baseline, e ritorna solo quelli che BLOCCANO (new +
// sopra soglia nelle categorie gate / categoria dead-code). baseline = Set<fingerprint>.
//
// gateCategories: l'insieme di categorie che bloccano il controllo. Il controllo 1
// (dead-code) usa deadcode=true (gate per delta, mai per severita). Il controllo 2
// (sicurezza) passa CONTROL2_GATE_CATEGORIES (secret/rls + detection-blocking
// injection/authz). Default = VERIFIED_ZERO_CATEGORIES per i chiamanti legacy.
function deltaBlockers(findings, baseline, { deadcode = false, gateCategories = VERIFIED_ZERO_CATEGORIES } = {}) {
  const out = [];
  for (const f of findings) {
    const isNew = !baseline.has(f.fingerprint);
    f.baseline_status = isNew ? 'new' : 'pre-existing';
    if (!isNew) continue; // pre-esistente: segnalato, non blocca (04 §6)
    if (deadcode) {
      // controllo 1: gate per DELTA, mai per severita.
      out.push(f);
    } else if (
      gateCategories.has(f.category)
      && severityAtLeast(f.severity, GATE_SEVERITY)
    ) {
      out.push(f);
    }
  }
  return out;
}

// =============================================================================
// CONTROLLO 1 — IGIENE STRUTTURALE (multi-oracolo, manifest-driven)
// =============================================================================
//
// Da mono-oracolo (knip/dead-code) a multi-oracolo, stesso pattern del controllo 2
// dopo A0: dead-code SEMPRE (invariato), + dup_check/cycle_check se DICHIARATI dal
// manifest (`oracles.duplication`/`oracles.architecture`), + twin_check SEMPRE
// (detection-only, ecosystem-agnostic). Tutti gata-no PER DELTA (04 §6, mai per
// severita): un difetto d'igiene PRE-ESISTENTE e' SEGNALATO, non blocca. `twin` e'
// escluso dai blockers PER-ORACOLO (DETECTION_ONLY_ORACLES), non per-categoria.
//
// BIT-invarianza: un pack senza `oracles.duplication`/`architecture` esegue solo
// dead-code + twin. twin non gata mai e su un progetto senza directory parallele
// emette twins:[] -> 0 finding -> il VERDETTO green e' identico al vecchio
// control1DeadCode (dead-code da solo, deltaBlockers per delta).

// Esclude dai blockers i finding PRE-ESISTENTI (delta, baseline) e quelli prodotti
// da un oracolo DETECTION-ONLY (twin). Annota `baseline_status` new/pre-existing
// come deltaBlockers (04 §6), cosi' i finding portano il marcatore per il report.
// baseline = Set<fingerprint>.
export function partitionBlockers(findings, baseline, detectionOnly = DETECTION_ONLY_ORACLES) {
  const out = [];
  for (const f of findings) {
    const oracle = f.source_oracle && f.source_oracle.oracle;
    const absolute = ABSOLUTE_GATE_ORACLES.has(oracle);
    const isNew = !baseline.has(f.fingerprint);
    f.baseline_status = isNew ? 'new' : 'pre-existing';
    // Eccezione audita (L-COL-028): riportata, MAI un blocker.
    if (f.fix_state === 'accepted-risk') continue;
    // Delta: i pre-esistenti non bloccano — TRANNE gli oracoli a gate ASSOLUTO (arch).
    if (!isNew && !absolute) continue;
    // Detection-only (twin; +jscpd/cycle in REMEDIATE): segnale, mai gate.
    if (detectionOnly.has(oracle)) continue;
    out.push(f);
  }
  return out;
}

// A2b — attivazione di arch_check: BUILD + blueprint con contratto + ecosistema
// graph-capable (JS/TS: il grafo import è un concetto JS/TS). Fuori da queste
// condizioni il ramo NON esiste -> controllo 1 byte-identico (BIT-invarianza).
function graphCapable(manifest) {
  const langs = (manifest && manifest.languages) || [];
  return langs.includes('js') || langs.includes('ts');
}
function archContractPresent(blueprintDir) {
  try { return blueprintDir != null && loadArchContract(blueprintDir) != null; } catch { return false; }
}

export function control1Hygiene(referenceApp, { baseline = new Set(), runOpts, manifest = null, mode = 'remediate', blueprintDir = null, hygieneBaselineMissing = false }) {
  const all = [];
  const sub = [];
  // A2b — arch_check è un GATE ASSOLUTO di floor: se degrada (contratto vacuo /
  // grafo non costruito) NON è un verde (L-COL-006), a differenza di twin
  // (detection-only) e di dup/cycle (igiene delta best-effort). Resta false per i
  // chiamanti legacy (ramo arch assente) -> BIT-invarianza.
  let archDegraded = false;
  // A2c — degrado d'igiene: un oracolo dup/cycle DICHIARATO ma NON eseguito (wrapper
  // assente / JSON non normalizzabile -> dup:degr/cycle:degr) NON e' un verde silenzioso
  // in BUILD (L-COL-006), in analogia esatta con archDegraded. Resta false per i pack
  // che non dichiarano dup/cycle (BIT-invarianza) e in REMEDIATE (dup/cycle report-only).
  let hygieneDegraded = false;

  // --- dead-code (INVARIATO: knip/vulture/... via run_deadcode) --------------
  const dc = runOracle(RUN_DEADCODE, [referenceApp], referenceApp);
  if (!dc.ok) {
    return { id: 1, name: 'dead-code', status: 'error', green: false, detail: dc.detail, findings: [], blockers: [] };
  }
  const ndc = normFindings('knip', dc.json, { ...runOpts, scope: 'working-tree' });
  if (!ndc.ok) {
    return { id: 1, name: 'dead-code', status: 'error', green: false, detail: ndc.detail, findings: [], blockers: [] };
  }
  all.push(...ndc.findings); sub.push(`dead-code:${ndc.findings.length}`);

  // --- A2a: oracoli d'igiene DICHIARATI dal manifest -------------------------
  // Un oracolo dichiarato ma NON eseguito e' DICHIARATO degradato ("dup:degr"),
  // MAI un verde silenzioso (L-COL-006). Assente dal manifest -> non eseguito
  // (BIT-invarianza per i pack che non lo dichiarano).
  const decl = manifest && manifest.oracles ? manifest.oracles : {};
  if (decl.duplication) {
    const minT = decl.duplication.min_tokens || 50;
    const r = runOracle(RUN_DUPCHECK, [referenceApp, String(minT)], referenceApp);
    if (r.ok) {
      const n = normFindings('jscpd', r.json, { ...runOpts, scope: 'working-tree' });
      if (n.ok) { all.push(...n.findings); sub.push(`dup:${n.findings.length}`); }
      else { sub.push('dup:degr'); hygieneDegraded = true; }
    } else { sub.push('dup:degr'); hygieneDegraded = true; }
  }
  if (decl.architecture) {
    const r = runOracle(RUN_CYCLECHECK, [referenceApp], referenceApp);
    if (r.ok) {
      const n = normFindings('cycle', r.json, { ...runOpts, scope: 'working-tree' });
      if (n.ok) { all.push(...n.findings); sub.push(`cycle:${n.findings.length}`); }
      else { sub.push('cycle:degr'); hygieneDegraded = true; }
    } else { sub.push('cycle:degr'); hygieneDegraded = true; }
  }

  // --- twin: SEMPRE (detection-only, ecosystem-agnostic, non gata mai) -------
  // Best-effort: se non gira lo dichiariamo (twin:degr) ma NON declassa il verde
  // (e' detection-only, non contribuisce mai al verdetto).
  const tw = runOracle(TWIN_CHECK, [referenceApp], referenceApp);
  if (tw.ok) {
    const n = normFindings('twin', tw.json, { ...runOpts, scope: 'working-tree' });
    if (n.ok) { all.push(...n.findings); sub.push(`twin:${n.findings.length}`); }
    else sub.push('twin:degr');
  } else sub.push('twin:degr');

  // --- A2b: arch_check — contratto di altitudine (GATE ASSOLUTO, BUILD-only) ---
  // Blueprint-driven (non manifest.oracles): attivo solo in BUILD con un contratto
  // `architecture:` nel blueprint e un ecosistema JS/TS. Vacuity/degradato -> exit 1
  // dell'oracolo -> runOracle ok:false -> 'arch:degr' (declassa il verde, mai un
  // verde silenzioso). In REMEDIATE / senza contratto / non-JS-TS: ramo assente.
  if (mode === 'build' && blueprintDir && graphCapable(manifest) && archContractPresent(blueprintDir)) {
    const r = runOracle(ARCH_CHECK, [referenceApp, '--blueprint', blueprintDir], referenceApp);
    if (r.ok) {
      const n = normFindings('arch', r.json, { ...runOpts, scope: 'working-tree' });
      if (n.ok) { all.push(...n.findings); sub.push(`arch:${n.findings.length}`); }
      else { sub.push('arch:degr'); archDegraded = true; }
    } else { sub.push('arch:degr'); archDegraded = true; }
  }

  // Mode-aware (A2c): in BUILD dup/cycle gata-no sul DELTA (vs baseline d'igiene
  // committato); in REMEDIATE sono REPORT-ONLY (audit del debito, non gate — come
  // twin). twin resta detection-only in entrambe. BIT-invariante per i pack senza
  // dup/cycle dichiarati (nessun finding jscpd/cycle in `all`).
  //
  // Vacuity (baseline d'igiene assente in BUILD): NON floodare blocker sul debito
  // legacy — senza baseline dup/cycle non sono distinguibili new-vs-old, quindi
  // diventano REPORT-ONLY (come in REMEDIATE) e il verde è negato dal guard
  // `hygieneMissingActive` con il messaggio di refresh (né un'ondata cieca di
  // blocker, né un verde silenzioso — L-COL-006). Il branch di detail `baseline
  // mancante` presuppone appunto blockers d'igiene soppressi (blockers.length === 0).
  // Il vacuity guard scatta SOLO se ci sono davvero finding d'igiene GATE (dup/cycle)
  // da gestire: senza baseline non si distingue new-vs-old, quindi si dichiara e si nega
  // il verde. Ma un progetto PULITO (0 dup/cycle) non ha nulla da grandfather-are -> NON
  // dev'essere rosso per un baseline che non gli serve (altrimenti OGNI build JS/TS senza
  // baseline sarebbe rosso, anche a debito zero). twin resta escluso (detection-only).
  const hasHygieneGateFindings = all.some((f) => f.source_oracle
    && (f.source_oracle.oracle === 'jscpd' || f.source_oracle.oracle === 'cycle'));
  const hygieneMissingActive = hygieneBaselineMissing && mode === 'build' && hasHygieneGateFindings;
  const detectionOnly = (mode === 'build' && !hygieneMissingActive)
    ? DETECTION_ONLY_ORACLES
    : new Set([...DETECTION_ONLY_ORACLES, 'jscpd', 'cycle']);
  const blockers = partitionBlockers(all, baseline, detectionOnly);
  // Degrado d'igiene (A2c, L-COL-006): un oracolo dup/cycle DICHIARATO ma NON eseguito
  // (dup:degr/cycle:degr) declassa il verde SOLO in BUILD, in analogia esatta con
  // archDegraded. In REMEDIATE dup/cycle sono report-only -> il degrado NON declassa
  // (preserva m5 + la BIT-invarianza dei pack che non dichiarano dup/cycle).
  const hygieneDegradedActive = hygieneDegraded && mode === 'build';
  const green = blockers.length === 0 && !archDegraded && !hygieneMissingActive && !hygieneDegradedActive;
  // Detail del ramo "NUOVO introdotto": NOMINA la/e categoria/e che bloccano (il
  // controllo 1 è multi-oracolo — dead-code/duplication/architecture). Così il
  // messaggio resta accurato e retro-compatibile: un blocker dead-code produce
  // "dead-code NUOVO" (invariante atteso da build_discipline_check), un blocker
  // dup produce "duplication NUOVO", ecc.
  const blkCats = [...new Set(blockers.map((b) => b.category))].join('/');
  return {
    id: 1, name: 'dead-code', status: green ? 'green' : 'red', green,
    detail: hygieneMissingActive && blockers.length === 0 && !archDegraded
      ? `baseline d'igiene mancante (dup/cycle attivi in BUILD) — NON verde (L-COL-006): esegui \`baseline.mjs capture <dir> --hygiene\` [${sub.join(' ')}]`
      : green
        ? `nessuna regressione d'igiene NUOVA [${sub.join(' ')}] (pre-esistenti segnalati)`
        : archDegraded && blockers.length === 0
          ? `arch degradato (contratto vacuo / non eseguito) — NON verde (L-COL-006) [${sub.join(' ')}]`
          : hygieneDegradedActive && blockers.length === 0
            ? `oracolo d'igiene dichiarato ma non eseguito (degradato) — NON verde (L-COL-006) [${sub.join(' ')}]`
            : `${blockers.length} ${blkCats || 'dead-code'} NUOVO introdotto [${sub.join(' ')}]`,
    findings: all, blockers,
  };
}

// Alias di compatibilita': i chiamanti storici importano control1DeadCode. Il
// controllo 1 e' ora multi-oracolo, ma la firma e il verdetto per i pack senza i
// nuovi oracoli restano invariati (BIT-invarianza).
export const control1DeadCode = control1Hygiene;

// =============================================================================
// CONTROLLO 2 — SICUREZZA (gitleaks working-tree + rls_check + osv)
// =============================================================================
export function control2Security(referenceApp, { baseline = new Set(), runOpts, withOsv = true, manifest = null }) {
  const migrations = resolve(referenceApp, 'supabase', 'migrations');
  const lockfile = resolve(referenceApp, 'package-lock.json');
  const all = [];
  const sub = [];
  const notes = [];
  const bindingByTool = new Map(); // tool authz -> binding del manifest (per lo scan)
  // SCAN-SCOPE (PLAN 2026-07-28 §3.5): coverage dell'esclusione, riempita dal ramo
  // gitleaks. Resta null se il ramo non gira o se non c'e' NESSUNA dichiarazione
  // (BIT-invarianza: senza dichiarazioni l'esito del checkpoint e' quello di prima,
  // campo compreso). Non e' un dettaglio cosmetico: e' la contropartita
  // dell'esclusione — cio' che non si guarda si DICHIARA (L-COL-006).
  let scanScopeCov = null;

  // --- Per-tool runner (un oracolo nominato) ---------------------------------
  // Ogni tool sa come invocare il proprio wrapper, con quale `oracle`/`scope`
  // normalizzare e se e' BEST-EFFORT (un oracolo che non gira -> DEGRADATO con
  // nota, MAI falso verde — L-COL-006/L-COL-002) o HARD (errore di sicurezza).
  // Ritorna { fatal, note } — fatal => secErr immediato; note => degradato.
  function runTool(tool) {
    // authz dichiarativa (A0): esegue l'oracolo authz del manifest e normalizza a
    // 'authz'. Se lo script c'e' ma non produce finding -> contrasto pulito (verde
    // legittimo). Se NON gira (assente/JSON rotto) -> degrado; il chiamante decide
    // se e' un floor-miss (T4). Il campo `ranFail` e' inerte finche' T4 non lo consuma.
    if (AUTHZ_TOOL_NAMES.has(tool)) {
      const b = bindingByTool.get(tool);
      const a = runAuthzOracle(tool, referenceApp, b, runOpts);
      if (!a.ran) return { note: ` (${tool}: oracolo authz non eseguito, degradato — ${a.detail})`, ranFail: true };
      if (!a.ok) return { fatal: secErr(`authz ${tool}`, a.detail) };
      all.push(...a.findings); sub.push(`${AUTHZ_ORACLES[tool].normalizeKey}:${a.findings.length}`);
      return {};
    }
    switch (tool) {
      // gitleaks working-tree (scope BUILD; S1 vive qui). cwd = referenceApp per
      // allineare i path normalizzati (e quindi i fingerprint) a collectFindings
      // del loop: e' la chiave del baseline-delta (04 §6). HARD.
      case 'gitleaks': {
        const g = runOracle(RUN_GITLEAKS, [referenceApp, 'working-tree'], referenceApp);
        if (!g.ok) return { fatal: secErr('gitleaks', g.detail) };
        // --- SCAN-SCOPE (PLAN §3.5): confine dello scope PRIMA della normalizzazione.
        // Si filtra il JSON NATIVO (il wrapper resta BIT-invariante: continua a
        // stampare l'output nativo di gitleaks) e SOLO QUI, cosi' i fingerprint che
        // arrivano al baseline-delta sono gia' quelli dell'insieme scansionato.
        //
        // SIMMETRIA (il bug piu' probabile di questo innesto): lo scope si risolve
        // con scanScopeFor(referenceApp, { manifest }) — la STESSA funzione, con lo
        // STESSO projectDir, che usano baseline.mjs::capture e run_loop::collectFindings.
        // Se i due divergessero, la baseline congelerebbe fingerprint che il
        // checkpoint non produce piu' (o, peggio, il checkpoint produrrebbe
        // fingerprint assenti dalla baseline -> 'new' -> ROSSO FANTASMA a ogni giro).
        //
        // Una dichiarazione di progetto ROTTA (JSON invalido, `reason` mancante) fa
        // LANCIARE resolveScanScope: qui diventa un ERRORE del controllo 2, non un
        // "nessuna esclusione" silenzioso. Chi l'ha scritta la crede attiva
        // (L-COL-006): ignorarla sarebbe una copertura creduta e non presente.
        // `manifest ? {manifest} : {}` e non `{manifest}`: un chiamante LEGACY passa
        // manifest=null (ramo cablato v1) e un null ESPLICITO significherebbe "nessun
        // manifest" QUI mentre baseline.mjs lo risolverebbe da disco -> due scope
        // diversi sullo stesso progetto, cioe' il delta fantasma. Con l'omissione,
        // ogni sito converge sulla stessa auto-risoluzione da projectDir.
        let scope;
        try { scope = scanScopeFor(referenceApp, manifest ? { manifest } : {}); }
        catch (e) { return { fatal: secErr('scan-scope', e.message) }; }
        // Guardia sul TIPO: applyScanScope su un non-array tornerebbe kept=[] —
        // cioe' "nessun segreto", un falso verde da input malformato. Se il JSON non
        // e' un array lo passiamo INTATTO a normalize, che lo rifiuta a voce alta.
        const applied = Array.isArray(g.json)
          ? applyScanScope(g.json, scope, referenceApp)
          : { kept: g.json, excluded: [] };
        // La coverage esce SOLO se c'e' almeno un pattern dichiarato: senza
        // dichiarazioni l'esito del checkpoint resta quello di prima, campo compreso
        // (BIT-invarianza). Con dichiarazioni esce SEMPRE, anche a excluded_total=0:
        // un pattern che non ha soppresso niente e' un'informazione, non un silenzio.
        scanScopeCov = scope.patterns.length > 0
          ? scanScopeCoverage(scope, applied.excluded)
          : null;
        const n = normFindings('gitleaks', applied.kept, { ...runOpts, scope: 'working-tree' });
        if (!n.ok) return { fatal: secErr('gitleaks normalize', n.detail) };
        all.push(...n.findings); sub.push(`gitleaks:${n.findings.length}`);
        // Nessuna esclusione e' silenziosa: se qualcosa e' stato escluso, lo si legge
        // nel detail del controllo, non solo nella coverage strutturata.
        if (applied.excluded.length > 0) sub.push(`scan-scope-escl:${applied.excluded.length}`);
        return {};
      }
      // rls_check (DDL; S3/S4/S5 vivono qui). HARD.
      case 'rls_check': {
        const r = runOracle(RLS_CHECK, [migrations], referenceApp);
        if (!r.ok) return { fatal: secErr('rls-check', r.detail) };
        const n = normFindings('rls-check', r.json, { ...runOpts, scope: 'static-ddl' });
        if (!n.ok) return { fatal: secErr('rls normalize', n.detail) };
        all.push(...n.findings); sub.push(`rls:${n.findings.length}`);
        return {};
      }
      // osv-scanner (dependency-vuln). Prende un LOCKFILE (non una dir) e richiede
      // rete. Best-effort: se l'oracolo non gira (offline/lock assente) NON
      // falsifichiamo il verde, ma lo dichiariamo degradato per osv (la fixture
      // M-1 NON ha CVE seminate, vedi run_osv §smoke). Gated da `withOsv`.
      case 'osv': {
        if (!withOsv || !existsSync(RUN_OSV) || !existsSync(lockfile)) return {}; // GATED-OFF: nessun ranFail (T4: mai floorMiss)
        const o = runOracle(RUN_OSV, [lockfile], referenceApp);
        if (!o.ok) return { note: ' (osv: non eseguibile offline, degradato)', ranFail: true };
        const n = normFindings('osv', o.json, { ...runOpts, scope: 'deps' });
        if (!n.ok) return { note: ' (osv: output non normalizzabile, degradato)', ranFail: true };
        all.push(...n.findings); sub.push(`osv:${n.findings.length}`);
        return {};
      }
      // semgrep (07 §4) — oracolo AI curato per i pattern vietati injection/authz/
      // crypto/sink (S6 injection, S7 authz). Gira VIA DOCKER (run_semgrep.mjs):
      // la SKILL resta dep-free, il container ha semgrep pinnato. BEST-EFFORT come
      // osv: se docker/l'immagine non e' disponibile NON falsifichiamo il verde,
      // ma lo dichiariamo DEGRADATO (un oracolo che non gira NON e' verde) — MAI
      // contato come pulito. Il path normalizzato (stripContainerSrc -> base
      // "eval/reference-app") coincide con gitleaks/rls: fingerprint coerenti col
      // baseline-delta.
      case 'semgrep': {
        // semgrep richiesto ma non eseguito -> ranFail (T4): declassa SOLO se semgrep
        // e' un tool di FLOOR per l'ecosistema (per supabase-jsts authz/injection NON
        // sono floor -> floorTools.has('semgrep')===false -> nessun floorMiss: m5 intatto).
        if (!existsSync(RUN_SEMGREP)) return { note: ' (semgrep: wrapper assente, degradato)', ranFail: true };
        const s = runOracle(RUN_SEMGREP, [referenceApp], referenceApp);
        if (!(s.ok && s.json && Array.isArray(s.json.results))) {
          // docker assente / immagine non pinnata / JSON non valido: DEGRADATO.
          return { note: ` (semgrep: oracolo non disponibile via docker, degradato — ${s.detail})`, ranFail: true };
        }
        const n = normFindings('semgrep', s.json, { ...runOpts, scope: 'working-tree' });
        if (!n.ok) return { note: ` (semgrep: output non normalizzabile, degradato — ${n.detail})`, ranFail: true };
        all.push(...n.findings); sub.push(`semgrep:${n.findings.length}`);
        return {};
      }
      default:
        // tool sconosciuto: lo SALTIAMO DICHIARANDO (mai falso verde). Il gate di
        // conformita (Fase D) coglie un manifest che nomina un tool senza wrapper.
        // ranFail (T4): un tool DICHIARATO ma non eseguibile e' un oracolo non-eseguito;
        // se la sua categoria e' nel FLOOR declassa il controllo 2 (L-COL-006).
        return { note: ` (${tool}: tool sconosciuto, saltato — DICHIARATO, mai falso verde)`, ranFail: true };
    }
  }

  // --- Lista degli oracoli da eseguire ---------------------------------------
  // Con `manifest`: i tool nominati dai binding `manifest.oracles`, DEDUP per tool
  // (un wrapper gira una volta sola anche se piu' categorie vi puntano, es.
  // injection/authz/crypto -> semgrep). Mappa tool->wrapper noto in runTool;
  // gateCategories derivato dal manifest. Senza `manifest` (chiamata legacy): la
  // sequenza cablata v1 (gitleaks, rls, osv, semgrep) — INVARIATA.
  let tools;
  let gateCategories;
  if (manifest && manifest.oracles) {
    const seen = new Set();
    tools = [];
    // mappa nome-tool-del-manifest -> chiave-wrapper interna.
    const toWrapper = { gitleaks: 'gitleaks', rls_check: 'rls_check', osv: 'osv', semgrep: 'semgrep' };
    for (const b of Object.values(manifest.oracles)) {
      const t = b && b.tool;
      if (!t) continue;
      // I tool del CONTROLLO 1 (dead-code/dup/cycle/twin: knip, jscpd, madge,
      // dependency-cruiser, twin) sono di competenza esclusiva del controllo 1 e
      // sono guidati dallo STESSO manifest.oracles: NON entrano nel controllo
      // sicurezza (altrimenti runTool li declasserebbe come tool ignoti). Ogni
      // altro tool noto/ignoto passa per runTool (dedup per tool).
      if (CONTROL1_TOOLS.has(t)) continue;
      // Gli oracoli authz dichiarativi (A0) hanno il tool come proprio wrapper e
      // portano un binding (scan) che runTool consuma via bindingByTool.
      const wrapper = AUTHZ_TOOL_NAMES.has(t) ? t : (toWrapper[t] || t); // ignoto: runTool lo dichiara saltato.
      if (AUTHZ_TOOL_NAMES.has(t)) bindingByTool.set(t, b);
      if (seen.has(wrapper)) continue;
      seen.add(wrapper);
      tools.push(wrapper);
    }
    gateCategories = control2CategoriesFrom(manifest);
  } else {
    tools = ['gitleaks', 'rls_check', 'osv', 'semgrep'];
    gateCategories = CONTROL2_GATE_CATEGORIES;
  }

  // --- Rete strutturale (T4): tool che servono una categoria di FLOOR ----------
  // Un oracolo la cui categoria e' nel `manifest.floor` e che e' RICHIESTO ma NON
  // parte (ranFail) declassa il controllo 2 a degraded/green:false (L-COL-006).
  // CONFINE (BIT-invarianza m5): solo i tool di FLOOR. osv gated-off ritorna {}
  // (nessun ranFail); un best-effort detection-only FUORI floor (es. semgrep per
  // supabase-jsts) degrada con nota ma NON e' in floorTools -> nessun declassamento.
  // Solo ramo manifest-driven: senza manifest floorTools resta vuoto (legacy intatto).
  const floorCats = new Set((manifest && Array.isArray(manifest.floor)) ? manifest.floor : []);
  const floorTools = new Set();
  if (manifest && manifest.oracles) {
    for (const [key, b] of Object.entries(manifest.oracles)) {
      const cats = key.split('|').map((c) => c.trim());
      if (b && b.tool && cats.some((c) => floorCats.has(c))) floorTools.add(b.tool);
    }
  }

  let floorMiss = null;
  for (const t of tools) {
    const r = runTool(t);
    if (r.fatal) return r.fatal;
    if (r.note) notes.push(r.note);
    if (r.ranFail && floorTools.has(t)) floorMiss = floorMiss || t; // primo oracolo di floor non eseguito
  }

  // gateCategories: secret/rls (verificato-a-zero) PIU' le detection-blocking
  // injection/authz (M4). Un NUOVO finding semgrep injection/authz sopra soglia
  // BLOCCA; un S6/S7 PRE-ESISTENTE (gia' in baseline) no.
  const blockers = deltaBlockers(all, baseline, { deadcode: false, gateCategories });
  const noteStr = notes.join('');
  if (floorMiss && blockers.length === 0) {
    // un oracolo di FLOOR non e' stato eseguito: NON e' verde (L-COL-006). Come i
    // controlli 3/4, degradato -> il checkpoint d'insieme non e' verde. (Se ci sono
    // blockers reali, il rosso vince: un difetto TROVATO e' piu' informativo di
    // "non eseguito" -> cade al ramo red sotto.)
    return {
      id: 2, name: 'security', status: 'degraded', green: false,
      detail: `oracolo di floor non eseguito: ${floorMiss} — controllo DEGRADATO, NON verde${noteStr}`,
      findings: all, blockers: [], scan_scope: scanScopeCov,
    };
  }
  const green = blockers.length === 0;
  return {
    id: 2, name: 'security', status: green ? 'green' : 'red', green,
    detail: green
      ? `nessun finding di sicurezza NUOVO >= ${GATE_SEVERITY} [${sub.join(' ')}]${noteStr}`
      : `${blockers.length} finding NUOVO >= ${GATE_SEVERITY} [${sub.join(' ')}]${noteStr}`,
    findings: all, blockers, scan_scope: scanScopeCov,
  };

  function secErr(where, d) {
    return {
      id: 2, name: 'security', status: 'error', green: false, detail: `${where}: ${d}`,
      findings: all, blockers: [], scan_scope: scanScopeCov,
    };
  }
}

// =============================================================================
// CHARACTERIZATION SNAPSHOT (06): baseline congelata + recompute corrente.
// =============================================================================
//
// La suite di characterization scrive:
//   test/characterization/baseline.json = { assertions:[{id,...,observed}], ... }
//   test/characterization/run.mjs       = recomputer -> { assertions:[{id,observed}] }
// L'INVARIANZA (06 §4) confronta l'observed CORRENTE (recompute) con la baseline,
// partizionando le assertion in GUARD vs IMPACTED rispetto a un finding (la fix
// puo' cambiare legittimamente le IMPACTED, mai le GUARD).

const CHARZ_REL_BASELINE = 'test/characterization/baseline.json';
const CHARZ_REL_RUNNER = 'test/characterization/run.mjs';

// deep-equal strutturale (ordine-insensibile sulle chiavi), per confrontare due
// observed JSON. Niente dipendenze: confronto ricorsivo deterministico.
function deepEqual(a, b) {
  if (a === b) return true;
  if (typeof a !== typeof b) return false;
  if (a === null || b === null) return a === b;
  if (typeof a !== 'object') return a === b;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a)) {
    if (a.length !== b.length) return false;
    return a.every((x, i) => deepEqual(x, b[i]));
  }
  const ka = Object.keys(a).sort();
  const kb = Object.keys(b).sort();
  if (ka.length !== kb.length) return false;
  if (!ka.every((k, i) => k === kb[i])) return false;
  return ka.every((k) => deepEqual(a[k], b[k]));
}

// Rileva se il progetto ha una suite di characterization VALUE-BASED (baseline +
// runner). In assenza -> null (il chiamante ricade sul comportamento degradato,
// preservando M1: un progetto senza characterization NON regredisce).
export function loadCharacterization(referenceApp) {
  const baselinePath = join(referenceApp, CHARZ_REL_BASELINE);
  const runnerPath = join(referenceApp, CHARZ_REL_RUNNER);
  if (!existsSync(baselinePath) || !existsSync(runnerPath)) return null;
  let baseline;
  try { baseline = JSON.parse(readFileSync(baselinePath, 'utf8')); } catch { return null; }
  if (!baseline || !Array.isArray(baseline.assertions)) return null;
  return { baseline, runnerPath };
}

// Esegue run.mjs (recomputer) sul codice CORRENTE e ritorna una Map id->observed.
function recomputeObserved(referenceApp, runnerPath) {
  const res = spawnSync(process.execPath, [runnerPath], {
    cwd: referenceApp, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (res.error) return { ok: false, detail: `spawn run.mjs: ${res.error.message}` };
  if (res.status !== 0) {
    return { ok: false, detail: `run.mjs exit=${res.status}: ${(res.stderr || res.stdout || '').trim().slice(-300)}` };
  }
  const lines = (res.stdout || '').trim().split(/\r?\n/).filter(Boolean);
  if (lines.length === 0) return { ok: false, detail: 'run.mjs: nessun output' };
  let parsed;
  try { parsed = JSON.parse(lines[lines.length - 1]); }
  catch (e) { return { ok: false, detail: `run.mjs JSON invalido: ${e.message}` }; }
  const map = new Map((parsed.assertions || []).map((a) => [a.id, a.observed]));
  return { ok: true, map };
}

// characterizationInvariance — il NODO 06 §4. Confronta l'observed corrente con
// la baseline, partizionato per finding:
//   - control 3 (regressioni): ogni GUARD deve deep-equal il suo observed di
//     baseline; una guard cambiata = regressione (red).
//   - control 4 (invarianza): GUARD invariante; le IMPACTED sono RI-BASELINED al
//     post-fix (la fix cambia legittimamente l'impacted). Green = guard invarianti.
// Senza finding (partitionCtx null) -> invarianza PURA: TUTTE guard.
//
// Ritorna { ok, green, detail, guard, impacted, changedGuards }.
export function characterizationInvariance(referenceApp, charz, finding) {
  const recomputed = recomputeObserved(referenceApp, charz.runnerPath);
  if (!recomputed.ok) {
    return { ok: false, green: false, detail: `recompute KO: ${recomputed.detail}` };
  }
  const assertions = charz.baseline.assertions;
  // partition() decide GUARD vs IMPACTED. Senza finding, tutte le assertion sono
  // GUARD (invarianza pura): passiamo un finding "vuoto" che non impatta nulla
  // (categoria sconosciuta, nessuna location) MA forziamo impacted=[] noi stessi.
  let guardIds; let impactedIds;
  if (finding) {
    const part = partition(finding, assertions);
    guardIds = new Set(part.guard);
    impactedIds = new Set(part.impacted);
  } else {
    guardIds = new Set(assertions.map((a) => a.id));
    impactedIds = new Set();
  }

  const changedGuards = [];
  const missingGuards = [];
  for (const a of assertions) {
    if (!guardIds.has(a.id)) continue; // impacted: re-baselined, non vincola.
    if (!recomputed.map.has(a.id)) { missingGuards.push(a.id); continue; }
    if (!deepEqual(recomputed.map.get(a.id), a.observed)) changedGuards.push(a.id);
  }

  const green = changedGuards.length === 0 && missingGuards.length === 0;
  const detail = green
    ? `invarianza OK: ${guardIds.size} guard invarianti${impactedIds.size ? `, ${impactedIds.size} impacted re-baselined` : ''}`
    : `invarianza VIOLATA: guard cambiate=[${changedGuards.join(',')}]`
      + (missingGuards.length ? ` guard mancanti=[${missingGuards.join(',')}]` : '');
  return {
    ok: true, green, detail,
    guard: [...guardIds], impacted: [...impactedIds], changedGuards, missingGuards,
  };
}

// =============================================================================
// CONTROLLO 3 — REGRESSIONI — characterization (06) o degradato (backward-compat).
// =============================================================================
//
// Con una suite di characterization VALUE-BASED presente: ogni GUARD deve restare
// invariante vs baseline (recompute observed deep-equal). Le IMPACTED dal finding
// (se passato) sono ri-baselined: non vincolano (la fix le cambia legittimamente).
// SENZA characterization: comportamento M1 invariato (degradato onesto, NON verde).
export function control3Regressions(referenceApp, { mode = 'remediate', characterization = null, finding = null } = {}) {
  const charz = characterization || loadCharacterization(referenceApp);
  if (charz) {
    const inv = characterizationInvariance(referenceApp, charz, finding);
    if (!inv.ok) {
      return { id: 3, name: 'regressions', status: 'error', green: false, detail: inv.detail };
    }
    return {
      id: 3, name: 'regressions', status: inv.green ? 'green' : 'red', green: inv.green,
      detail: `characterization (06 §4): ${inv.detail}`,
      guard: inv.guard, impacted: inv.impacted, changedGuards: inv.changedGuards,
    };
  }
  // BACKWARD-COMPAT: nessuna characterization -> M1 invariato.
  const runner = detectTestRunner(referenceApp);
  if (!runner.present) {
    return {
      id: 3, name: 'regressions', status: 'degraded', green: false,
      detail: `nessun test runner (${mode}): controllo DEGRADATO, NON verde — characterization test = M3 (06)`,
    };
  }
  const res = runTests(referenceApp, runner);
  return {
    id: 3, name: 'regressions', status: res.green ? 'green' : 'red', green: res.green,
    detail: res.detail,
  };
}

// =============================================================================
// CONTROLLO 4 — CONFORMITA-LOGICA / INVARIANZA — characterization o degradato.
// =============================================================================
//
// REMEDIATE: invarianza comportamentale (06 §4) — identica logica del controllo 3
// con la partition (GUARD invarianti, IMPACTED re-baselined). Con una suite
// presente, green = guard invarianti. SENZA characterization: M1 invariato.
export function control4Conformance(referenceApp, { mode = 'remediate', characterization = null, finding = null, blueprintDir = null, manifest = null } = {}) {
  // --- RAMO AC-ACCEPTANCE (AT-1 Fase A) ---------------------------------------
  // Si attiva SOLO in BUILD con un blueprint esplicito (blueprintDir) E un
  // run_file nel manifest (test_runner.run_file). PREEMPTA la characterization:
  // quando attivo, il controllo 4 e' il test d'accettazione AC per-task (esegue i
  // target_test del blueprint che esistono su disco, uno per uno). Senza queste
  // condizioni cade al ramo legacy -> output BYTE-IDENTICO a oggi (BIT-invarianza).
  //
  // SCOPE (L-COL-006): in scope = i target_test il cui `file` ESISTE sul disco;
  // i mancanti (task non ancora costruiti in una BUILD incrementale) sono SALTATI,
  // mai RED. In-scope vuoto = DEGRADATO (non verde), mai falso verde.
  // FLOOR ANTI-VACUO: un file con <1 test eseguito e' RED (un file vuoto non puo'
  // far passare l'accettazione). Un target_test rosso e' RED. Un errore
  // d'esecuzione e' status='error'. L'oracolo e' l'exit/output reale (L-COL-002).
  const runFileTpl = manifest && manifest.test_runner && manifest.test_runner.run_file;
  if (mode === 'build' && blueprintDir && runFileTpl) {
    let tasks;
    try { tasks = loadTasks(blueprintDir); }
    catch (e) { return { id: 4, name: 'conformance', status: 'error', green: false, detail: `blueprint non caricabile: ${e.message}` }; }
    const inScope = [];
    for (const t of tasks) for (const tt of (t.target_tests || [])) {
      if (existsSync(join(referenceApp, tt.file))) inScope.push(tt.file);
    }
    inScope.sort();
    if (inScope.length === 0) {
      return { id: 4, name: 'conformance', status: 'degraded', green: false, detail: 'nessun target_test materializzato sul disco (BUILD incrementale): controllo DEGRADATO, NON verde' };
    }
    // <<< AT-1 Fase B — precondizione di TRACE (PRIMA di eseguire) >>>
    // Ogni AC valutato deve tracciare (tag covers: in commento) a un suo target_test
    // in-scope. Un AC valutato non tracciato → oracolo d'accettazione non valido →
    // controllo 4 RED PRIMA dell'esecuzione (anti-tamper della provenienza, L-COL-032/B).
    const trace = assertionTrace(tasks, referenceApp, inScope);
    if (!trace.ok) {
      return {
        id: 4, name: 'conformance', status: 'red', green: false,
        detail: `target_test non tracciabile all'AC — oracolo non valido: ${trace.detail}`,
      };
    }
    const fails = [];
    for (const file of inScope) {
      const r = runTargetFile(referenceApp, file, runFileTpl);
      if (r.error) return { id: 4, name: 'conformance', status: 'error', green: false, detail: `errore d'esecuzione ${file}: ${r.detail}` };
      if (r.testCount < 1) fails.push(`${file} (vacuo: nessun test eseguito)`);
      else if (!r.passed) fails.push(`${file} (test rosso)`);
    }
    if (fails.length > 0) {
      return {
        id: 4, name: 'conformance', status: 'red', green: false,
        detail: `accettazione AC fallita: ${fails.join('; ')}`,
      };
    }
    // <<< AT-1 Fase C — POTERE DELL'ASSERZIONE, solo su un controllo 4 GIA' VERDE >>>
    // L'ordine non e' un'ottimizzazione: su un run ROSSO il costo dev'essere ZERO, perche'
    // un test che gia' fallisce ha per definizione il suo potere di falsificare. La domanda
    // «questa asserzione poteva fallire?» ha senso solo dopo che tutti i target_test in
    // scope sono passati — un verde e' l'unico esito che una tautologia puo' contraffare.
    // Il `detail` RIPORTA cio' che l'oracolo dice, senza riscriverlo: le due specie di
    // irrisolto (structural non degrada, failure degrada) sono decise dentro assertionPower
    // e qui si propagano tali e quali, incluso `power.status`.
    const power = assertionPower(tasks, referenceApp, inScope, { runFileTpl });
    if (!power.ok) {
      return {
        id: 4, name: 'conformance', status: power.status, green: false,
        detail: `${inScope.length} target_test verdi, ma ${power.detail}`,
        power,
      };
    }
    // BIT-INVARIANZA, clausola 2: su un progetto SENZA candidati l'output del controllo 4
    // dev'essere BYTE-IDENTICO a prima dell'innesto. Il suffisso compare percio' solo dove
    // una misura c'e' stata davvero: a zero candidati non c'e' nulla da riferire, e
    // appenderlo comunque cambierebbe la riga di riepilogo di OGNI progetto che non ha
    // ancora un'asserzione analizzabile.
    // NON e' un verde muto (L-COL-006), ma SOLO grazie alla risalita di `assertion_power`
    // in cima all'esito di runCheckpoint (vedi powerSummary): il campo `power` che si
    // ritorna qui NON raggiunge da solo alcun output emesso — shapeControl e la proiezione
    // del loop lo scartano. Se quella risalita venisse tolta, questo ramo tornerebbe a
    // tacere e la clausola 2 diventerebbe una violazione: le due cose stanno insieme.
    const measured = power.coverage && power.coverage.candidates > 0;
    return {
      id: 4, name: 'conformance', status: 'green', green: true,
      detail: measured
        ? `accettazione AC: ${inScope.length} target_test verdi; ${power.detail}`
        : `accettazione AC: ${inScope.length} target_test verdi`,
      power,
    };
  }
  // --- RAMO LEGACY (invariato): characterization / npm test / degradato -------
  const charz = characterization || loadCharacterization(referenceApp);
  if (charz) {
    const inv = characterizationInvariance(referenceApp, charz, finding);
    if (!inv.ok) {
      return { id: 4, name: 'conformance', status: 'error', green: false, detail: inv.detail };
    }
    return {
      id: 4, name: 'conformance', status: inv.green ? 'green' : 'red', green: inv.green,
      detail: `invarianza characterization (06 §4): ${inv.detail}`,
      guard: inv.guard, impacted: inv.impacted, changedGuards: inv.changedGuards,
    };
  }
  // BACKWARD-COMPAT: nessuna characterization -> M1 invariato.
  const runner = detectTestRunner(referenceApp);
  if (!runner.present) {
    return {
      id: 4, name: 'conformance', status: 'degraded', green: false,
      detail: mode === 'build'
        ? 'nessun test di accettazione: controllo DEGRADATO, NON verde — M3 (11 §3)'
        : 'nessuna baseline characterization: controllo DEGRADATO, NON verde — M3 (06)',
    };
  }
  const res = runTests(referenceApp, runner);
  return {
    id: 4, name: 'conformance', status: res.green ? 'green' : 'red', green: res.green,
    detail: res.detail,
  };
}

// Rileva un test runner nel package.json del progetto target.
// manifest (opzionale, SP-0): se ha test_runner.detect, quella lista di candidati
// arricchisce la detection (in ordine di priorita'). Senza manifest: comportamento
// v1 invariato (controlla solo scripts.test non-placeholder).
function detectTestRunner(referenceApp, manifest = null) {
  const pkgPath = join(referenceApp, 'package.json');
  if (!existsSync(pkgPath)) return { present: false };
  let pkg;
  try { pkg = JSON.parse(readFileSync(pkgPath, 'utf8')); } catch { return { present: false }; }
  const testScript = (pkg.scripts && pkg.scripts.test) || '';
  // Un "test" placeholder ("no test specified") NON conta come runner.
  if (!testScript || /no test specified/i.test(testScript)) return { present: false };

  // Con manifest.test_runner.detect: controlla se uno dei candidati e' nello script.
  if (manifest && manifest.test_runner && Array.isArray(manifest.test_runner.detect) && manifest.test_runner.detect.length > 0) {
    const deps = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) };
    for (const candidate of manifest.test_runner.detect) {
      if (candidate === 'node:test') {
        if (/node\s+--test\b/.test(testScript) || /\bnode:test\b/.test(testScript)) return { present: true, script: 'test' };
      } else {
        const re = new RegExp(`\\b${candidate.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`);
        if (deps[candidate] || re.test(testScript)) return { present: true, script: 'test' };
      }
    }
    // Nessun candidato del manifest trovato ma scripts.test non-placeholder esiste:
    // non e' degradato, ma il runner specifico non e' riconosciuto -> present=true
    // (lo script test esiste comunque; il fallback e' "npm test").
    return { present: true, script: 'test' };
  }

  // Ramo legacy v1 invariato: scripts.test non-placeholder -> presente.
  return { present: true, script: 'test' };
}

function runTests(referenceApp, runner) {
  const res = spawnSync('npm', ['run', runner.script, '--silent'], {
    cwd: referenceApp, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, shell: true,
  });
  const green = !res.error && res.status === 0;
  return { green, detail: green ? 'test verdi' : `test rossi (exit=${res.status})` };
}

// Risolve l'ecosistema attivo dal progetto target (SP-0): classify -> manifest.
// Una dir non classificabile -> null (fallback al ramo cablato v1 in
// control2Security). Difensivo: qualunque errore della risoluzione -> null
// (mai un crash del checkpoint per colpa della risoluzione dell'ecosistema).
function resolveManifest(referenceApp) {
  try {
    const id = classify(referenceApp);
    return id ? loadManifest(id) : null;
  } catch { return null; }
}

// =============================================================================
// CHECKPOINT COMPLETO — esegue i 4 controlli e decide l'esito d'insieme.
// =============================================================================
//
// Ritorna { green, controls[], summary }. "green" (interamente verde) richiede
// che TUTTI i controlli siano green. Un controllo "degraded" (3/4 senza test)
// NON e' verde -> il checkpoint NON e' interamente verde (onesto, L-COL-006).
//
// Opzioni:
//   mode        "build" | "remediate" (default remediate)
//   baseline    Set<fingerprint> gia' noti (delta). Default: vuoto.
//   runOpts     { runId, createdAt } deterministici per riproducibilita.
//   gateOnDegraded  se true (default) i controlli degradati impediscono il verde.
//                   In M1 i 3/4 sono degradati per assenza di test: documentato.
export function runCheckpoint(referenceApp, opts = {}) {
  const {
    mode = 'remediate',
    baseline = new Set(),
    runOpts = { runId: 'checkpoint', createdAt: '1970-01-01T00:00:00.000Z' },
    withOsv = true,
    // finding: contesto per la partition GUARD/IMPACTED dei controlli 3/4 (06 §4).
    //   - presente (REMEDIATE su una fix): le assertion sulla stessa regione/tabella
    //     sono IMPACTED (re-baselined); le altre GUARD (invarianti).
    //   - assente (run_checkpoint "puro"): TUTTE le assertion sono GUARD
    //     (invarianza pura: tutto deve restare invariato vs baseline).
    finding = null,
    // characterization: snapshot pre-caricato { baseline, runnerPath }. Se null,
    // viene auto-rilevato da referenceApp (test/characterization/*).
    characterization = null,
    // manifest: ecosistema attivo (SP-0). Se non passato, lo risolviamo dal
    // referenceApp (classify -> loadManifest); fallback null -> control2Security
    // usa il ramo cablato v1 INVARIATO. Mai inventato: una dir non classificabile
    // resta null (la skill dichiara "non supportato", non finge un ecosistema).
    manifest = resolveManifest(referenceApp),
    // blueprintDir: opt-in AT-1 Fase A. Quando presente (BUILD) attiva il ramo
    // AC-acceptance del controllo 4 (esegue i target_test del blueprint). Default
    // null -> ramo legacy del controllo 4 INVARIATO (BIT-invarianza senza --blueprint).
    blueprintDir = null,
  } = opts;

  // A2c — baseline d'igiene COMMITTATO: unisci i suoi fingerprint (disgiunti per
  // oracolo da quelli di sicurezza) al baseline in-run, così dup/cycle pre-esistenti
  // sono grandfathered in BUILD. Vacuity guard: in BUILD con dup/cycle dichiarati ma
  // file assente -> hygieneBaselineMissing (control1 non verde). BIT-invarianza: nessun
  // pack dichiara dup/cycle e nessun file presente -> union vuota, guard false.
  const hb = loadHygieneBaseline(referenceApp);
  const baselineWithHygiene = hb.set.size ? new Set([...baseline, ...hb.set]) : baseline;
  const declaresHygiene = Boolean(manifest && manifest.oracles
    && (manifest.oracles.duplication || manifest.oracles.architecture));
  const hygieneBaselineMissing = mode === 'build' && declaresHygiene && !hb.present;
  const c1 = control1Hygiene(referenceApp, {
    baseline: baselineWithHygiene, runOpts, manifest, mode, blueprintDir, hygieneBaselineMissing,
  });
  const c2 = control2Security(referenceApp, { baseline, runOpts, withOsv, manifest });
  const c3 = control3Regressions(referenceApp, { mode, characterization, finding });
  const c4 = control4Conformance(referenceApp, { mode, characterization, finding, blueprintDir, manifest });

  const controls = [c1, c2, c3, c4];
  const green = controls.every((c) => c.green === true);
  const degraded = controls.filter((c) => c.status === 'degraded').map((c) => c.name);

  return {
    green,
    mode,
    controls,
    summary:
      `checkpoint=${green ? 'VERDE' : 'NON-VERDE'} | `
      + controls.map((c) => `${c.id}:${c.name}=${c.status}`).join(' '),
    degraded,
    // SCAN-SCOPE (PLAN §3.5): la coverage dell'esclusione risale in cima all'esito
    // del checkpoint, cosi' il chiamante (report REMEDIATE) non deve rovistare nei
    // controlli per dichiarare cio' che non e' stato guardato. null quando non c'e'
    // NESSUNA dichiarazione: senza esclusioni non c'e' niente da dichiarare, e la
    // forma dell'esito resta quella di prima (BIT-invarianza).
    scan_scope: (c2 && c2.scan_scope) || null,
    // POTERE DELL'ASSERZIONE (AT-1 Fase C): stessa risalita di scan_scope, e per la
    // stessa ragione. `c4.power` da solo NON raggiunge nessun output emesso —
    // shapeControl (run_checkpoint) e la proiezione dei controlli (run_loop) tengono
    // una WHITELIST di campi e lo scartano. Senza questa risalita la dichiarazione
    // muore in-process: a zero candidati il controllo 4 uscirebbe VERDE e MUTO, che e'
    // esattamente cio' che L-COL-006 vieta.
    // SINTESI, non l'oggetto intero: il report e' cio' che una persona legge, non un
    // dump. I conteggi dicono QUANTO e' stato guardato; `declared[]` dice CHE COSA non
    // lo e' stato e PERCHE', una voce per irrisolto — stessa forma di
    // `coverage.excluded_patterns` in scan_scope, che porta il `reason` per pattern fin
    // dentro il report del loop (L-COL-036). null quando il ramo AC non ha girato ->
    // forma invariata.
    //
    // La frase che stava qui — «i MOTIVI per esteso restano nel detail del controllo» —
    // era FALSA quando l'ha scritta il task 4 e va nominata: il detail portava gli
    // structural sul SOLO ramo verde, quindi su red, degraded ed error i motivi non
    // raggiungevano nessun output. Ora sono in entrambi i canali, e la ridondanza e'
    // voluta: `detail` e' la riga che una persona legge, `declared` e' il campo che una
    // macchina rilegge senza doverla parsare.
    assertion_power: powerSummary(c4 && c4.power),
  };
}

// Sintesi del potere dell'asserzione per il report. Fuori da runCheckpoint perche' la
// forma e' un contratto verso due emettitori diversi, e duplicarla li farebbe divergere.
function powerSummary(power) {
  if (!power || !power.coverage) return null;
  const cov = power.coverage;
  return {
    status: power.status,
    scanned: cov.scanned,
    candidates: cov.candidates,
    adjudicated: cov.adjudicated,
    inert: Array.isArray(power.inert) ? power.inert.length : 0,
    unresolved: cov.unresolved,
    unresolved_structural: cov.unresolved_structural,
    unresolved_failure: cov.unresolved_failure,
    // CIO' CHE NON E' STATO GUARDATO, COL SUO MOTIVO — non un conteggio.
    // Senza questo campo `coverage.declared` non raggiungeva NESSUN artefatto emesso:
    // shapeControl (run_checkpoint) e la proiezione del loop tengono una whitelist e
    // scartano `power`, e questa sintesi portava solo numeri. Tre artefatti SPEDITI
    // affermavano il contrario — incluso il commento di ac_assertion_power_check che
    // motiva l'esistenza di `declared` con «se non comparisse QUI sparirebbe del tutto».
    // Un numero dice che qualcosa non e' stato guardato; solo il motivo dice CHE COSA,
    // ed e' la differenza fra dichiarare e accennare (L-COL-006/L-COL-036).
    // Array VUOTO quando non c'e' nulla da dichiarare: la forma non cambia col contenuto.
    declared: Array.isArray(cov.declared) ? cov.declared : [],
  };
}
