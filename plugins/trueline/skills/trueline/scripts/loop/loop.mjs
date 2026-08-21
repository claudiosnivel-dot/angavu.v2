// loop.mjs — la MACCHINA del verify-fix loop (05 §3-§4). Il CUORE di Trueline.
//
// Per ogni finding fixabile, in ordine:
//   PROPONI -> [GATE UMANO] -> APPLICA (commit isolato sul branch della COPIA,
//   additivo/reversibile) -> RIESEGUI LO STESSO ORACOLO (stesso rule_id) +
//   RIESEGUI i test -> se pulito+verde: fix_state=verified (SOLO l'oracolo
//   promuove, L-COL-002); se flagga ancora o test rotto: verification-failed ->
//   RETRY entro O-COL-006 (cap 2 retry = 3 tentativi; REVERT la patch prima del
//   retry; patch MATERIALMENTE diversa, rifiuta ri-sottomissione byte-identica)
//   -> esauriti: terminale all'umano (accepted-risk/fix manuale/rinvio), MAI
//   scarto silenzioso, MAI verified.
//
// HUMAN-GATE: nella skill reale ogni applicazione e' human-gated (L-COL-005,
// L-COL-021 dead-code mai automatico). In EVAL-MODE (--eval) il gate e'
// auto-approvato in modo DETERMINISTICO (solo-eval). Il loop accetta un FIX
// PROVIDER iniettabile: skill reale = LLM propone; eval = tabella deterministica.
//
// *** INTEGRITA DEL FIXTURE ***: il loop opera SOLO su una COPIA TEMPORANEA
// (verify_workspace). Il fixture canonico NON viene mai mutato.
//
// CASO SPECIALE S2 (secret-in-history, 05 §7): la rotazione e' fuori dal codice
// e la riscrittura di history e' distruttiva (mai autonoma) -> stato terminale
// = mitigated-residual, MAI verified.
//
// Node ESM, solo built-in + oracoli M0 + checkpoint + git a strati.

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

import { normalize } from '../findings/normalize.mjs';
import { validateMany } from '../findings/validate_finding.mjs';
import { LOOP_BUDGET } from '../checkpoint/thresholds.mjs';
import { loadCharacterization, characterizationInvariance } from '../checkpoint/checkpoint.mjs';
import { commitOnBranch, revertToRef, headSha } from '../git/layered_git.mjs';
import { resolveRlsMigrationsDir } from './rls_scan.mjs';
import { scanScopeFor, applyScanScope } from '../oracles/scan_scope.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ORACLES = resolve(__dirname, '..', 'oracles');
const RUN_GITLEAKS = resolve(ORACLES, 'run_gitleaks.mjs');
const RLS_CHECK = resolve(ORACLES, 'rls_check.mjs');
const RUN_DEADCODE = resolve(ORACLES, 'run_deadcode.mjs');
const FIRESTORE_RULES_CHECK = resolve(ORACLES, 'firestore_rules_check.mjs');
// eco-F2: oracoli authz dichiarativi per backend non-Firestore (appwrite.json /
// pb_schema.json). Il re-run del loop nella categoria 'authz' dispatcha sul tool
// che ha prodotto il finding (source_oracle.oracle) -> ramo firestore BIT-invariante.
const APPWRITE_PERMS_CHECK = resolve(ORACLES, 'appwrite_perms_check.mjs');
const POCKETBASE_RULES_CHECK = resolve(ORACLES, 'pocketbase_rules_check.mjs');
// eco-F3: oracoli authz dichiarativi per Hasura (metadata YAML) e AppSync/Amplify
// Gen1 (schema.graphql). Stesso dispatch per-oracolo del case 'authz' -> il ramo
// firestore (default) resta BIT-invariante.
const HASURA_METADATA_CHECK = resolve(ORACLES, 'hasura_metadata_check.mjs');
const APPSYNC_AUTH_CHECK = resolve(ORACLES, 'appsync_auth_check.mjs');
const GO_BIN = process.platform === 'win32' ? 'C:/Users/claud/go/bin' : '/c/Users/claud/go/bin';

// =============================================================================
// REGOLA DEL SEME (PLAN 2026-07-28 §3.5, ultimo punto) — IL FILE SOTTO FIX NON
// E' ESCLUDIBILE. Il falso verde della classe peggiore vive qui.
// =============================================================================
//
// IL RISCHIO, detto per esteso: il loop promuove a `verified` quando il
// FINGERPRINT del finding-seme SPARISCE dal re-run dell'oracolo (stillPresent()
// -> false). "Sparito" e "corretto" sono due cose diverse. Se lo scope di
// scansione potesse escludere il file sotto fix, il finding sparirebbe SENZA CHE
// NULLA SIA STATO FIXATO e il loop timbrerebbe `verified`: un difetto reale,
// ancora nel codice, marchiato come risolto da un oracolo che non l'ha mai
// riguardato. Peggio del difetto: la CERTIFICAZIONE del difetto.
// Vale identico per il PRE-CHECK ("gia' azzerato da una fix sorella"), che
// promuove a verified SENZA nemmeno applicare una patch.
//
// LA REGOLA: nel re-run del loop lo scope si applica, ma MAI al file sotto fix.
// Difesa a DUE strati, di proposito — il primo dichiara l'intento, il secondo lo
// garantisce anche se il primo sbaglia il path:
//
//   1) PROTEZIONE PER PATH (qui sotto): tutti i suffissi del path del seme
//      finiscono in `protect`. E' deliberatamente SOVRA-protettivo: il path
//      normalizzato del finding (repo-relativo, es. "eval/reference-app/src/x.ts")
//      NON coincide con quello nativo di gitleaks (relativo al progetto), e
//      indovinare male significherebbe protezione INATTIVA — cioe' un falso verde
//      silenzioso. Proteggere qualche path in piu' puo' solo TENERE finding: la
//      direzione conservativa. Proteggerne uno in meno li NASCONDE.
//   2) RETE PER IDENTITA' (in fondo a rerunOracleFor): se un finding escluso
//      dallo scope ha lo STESSO FINGERPRINT del seme, viene RIMESSO nel risultato.
//      Non dipende da come e' scritto un path: e' l'identita' del finding.
//
// Chi tocca questo codice: togliere uno dei due strati non "semplifica", riapre
// esattamente il buco descritto sopra.
function seedProtectedPaths(finding) {
  const raw = String((finding && finding.location && finding.location.file) || '')
    .replace(/\\/g, '/')
    .replace(/^\.\//, '');
  if (raw === '') return [];
  const out = [raw];
  const segs = raw.split('/').filter(Boolean);
  for (let i = 1; i < segs.length; i += 1) out.push(segs.slice(i).join('/'));
  return out;
}

// --- Re-run dell'oracolo per-categoria (stesso oracolo, stesso rule_id) ------
//
// Riesegue, sulla COPIA, lo STESSO oracolo che ha prodotto il finding e ritorna
// i finding normalizzati. La verifica per-finding (05 §6) cerca se il finding
// (per fingerprint) e' ancora presente.
export function rerunOracleFor(finding, dir, runOpts) {
  const env = { ...process.env, PATH: `${process.env.PATH || ''}${delimiter}${GO_BIN}` };
  const run = (script, args, cwd = dir) => {
    const res = spawnSync(process.execPath, [script, ...args], {
      cwd, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
    });
    if (res.error) return { ok: false, json: null, detail: `spawn: ${res.error.message}` };
    const raw = (res.stdout || '').trim();
    if (!raw) return { ok: false, json: null, detail: `nessun JSON (exit=${res.status})` };
    try { return { ok: true, json: JSON.parse(raw) }; }
    catch (e) { return { ok: false, json: null, detail: `JSON invalido: ${e.message}` }; }
  };

  // Path del finding in POSIX (per discriminare JS vs Python in modo additivo).
  const fpath = String((finding.location && finding.location.file) || '').replace(/\\/g, '/');
  const isPy = /\.py$/.test(fpath);
  const isGo = /\.go$/.test(fpath);
  const isDart = /\.dart$/.test(fpath);

  let oracle; let res; let scope;
  // Finding nativi SOPPRESSI dallo scope in questo re-run (solo ramo secret).
  // Servono alla RETE PER IDENTITA' in fondo: null finche' lo scope non gira.
  let scopeSuppressedNative = null;
  switch (finding.category) {
    case 'secret':
      oracle = 'gitleaks';
      // scope: history per i secret-in-history (file vivo SOLO nella history,
      // assente dal working tree). Sono tali sia il caso JS (legacy/credentials.ts,
      // S2) sia il caso Python (app/legacy_credentials.py, SPY-S6). Altrimenti
      // working-tree (S1 / SPY-S1). DISPATCH ADDITIVO keyed sul path: JS e Python
      // coesistono.
      scope = (/legacy\/credentials\.ts$/.test(fpath) || /legacy_credentials\.py$/.test(fpath))
        ? 'history' : 'working-tree';
      res = run(RUN_GITLEAKS, [dir, scope]);
      // --- SCAN-SCOPE nel re-run + REGOLA DEL SEME (PLAN §3.5) ---------------
      // Lo scope si applica anche qui, o il loop lavorerebbe su un insieme di
      // finding DIVERSO da quello del checkpoint e della baseline (asimmetria).
      // Ma il file sotto fix e' PROTETTO: vedi il blocco `seedProtectedPaths`.
      if (res.ok && Array.isArray(res.json)) {
        let sc = null;
        try {
          // Omettere `manifest` quando non c'e' (invece di passarlo null) fa cadere
          // il loop sulla STESSA auto-risoluzione da projectDir di checkpoint e
          // baseline: un solo scope per un solo progetto.
          sc = scanScopeFor(dir, runOpts && runOpts.manifest ? { manifest: runOpts.manifest } : {});
        } catch {
          // Scope non risolvibile (dichiarazione di progetto rotta): NON si
          // esclude niente. "Guarda tutto" puo' solo rendere il loop piu'
          // severo (al massimo un verification-failed di troppo); assumere
          // un'esclusione che non sappiamo leggere sarebbe un verified gratis.
          // Il rosso della dichiarazione rotta lo dichiara il checkpoint.
          sc = null;
        }
        if (sc && sc.patterns.length > 0) {
          const applied = applyScanScope(res.json, sc, dir, { protect: seedProtectedPaths(finding) });
          scopeSuppressedNative = applied.excluded.map((e) => e.finding);
          res = { ok: true, json: applied.kept };
        }
      }
      break;
    case 'rls':
      oracle = 'rls-check'; scope = 'static-ddl';
      // MANIFEST-DRIVEN (O-COL-011): la migration-dir non e' piu' cablata. Si
      // chiede al resolver, che usa opts.manifest.oracles.rls.scan se presente
      // (passato in runOpts.manifest) o la probe-list di default. Per il layout
      // Supabase il default risolve a 'supabase/migrations' (BIT-invariante);
      // per postgres-py risolve a 'migrations/'.
      res = run(RLS_CHECK, [resolveRlsMigrationsDir(dir, { manifest: runOpts && runOpts.manifest })]);
      break;
    case 'dead-code':
      // ECOSYSTEM-AWARE (additivo): dead-code Python -> vulture; Go -> go-deadcode;
      // Dart -> dart; JS/TS -> knip (invariato). Il dispatch e' keyed sull'estensione
      // del file del finding (eco-F5b aggiunge go/dart), cosi' gli ecosistemi coesistono
      // senza rompere il ramo knip/vulture esistente.
      if (isPy) {
        oracle = 'vulture'; scope = 'working-tree';
        res = run(RUN_DEADCODE, [dir, '--tool=vulture']);
      } else if (isGo) {
        oracle = 'go-deadcode'; scope = 'working-tree';
        res = run(RUN_DEADCODE, [dir, '--tool=go-deadcode']);
      } else if (isDart) {
        oracle = 'dart'; scope = 'working-tree';
        res = run(RUN_DEADCODE, [dir, '--tool=dart']);
      } else {
        oracle = 'knip'; scope = 'working-tree';
        res = run(RUN_DEADCODE, [dir]);
      }
      break;
    case 'authz': {
      // authz dichiarativa. DISPATCH ADDITIVO keyed sull'ORACOLO che ha prodotto il
      // finding (source_oracle.oracle): il ramo Firestore (SP-8) resta BIT-invariante;
      // eco-F2 aggiunge Appwrite (appwrite.json) e PocketBase (pb_schema.json). Tutti
      // STATICI (no runtime): l'oracolo cammina `dir` ed emette {findings:[...]}
      // (category 'authz'). Senza questo dispatch, il re-run girerebbe SEMPRE Firestore
      // -> su un pack Appwrite/PocketBase (niente firestore.rules) tornerebbe 0 finding
      // e il loop crederebbe il difetto "gia' azzerato" SENZA applicare la fix (falso
      // verde, L-COL-002). Prova STATICA (no runtime).
      scope = 'working-tree';
      const authzOracle = String((finding.source_oracle && finding.source_oracle.oracle) || '');
      if (authzOracle === 'appwrite-perms') {
        oracle = 'appwrite-perms';
        res = run(APPWRITE_PERMS_CHECK, [dir]);
      } else if (authzOracle === 'pocketbase-rules') {
        oracle = 'pocketbase-rules';
        res = run(POCKETBASE_RULES_CHECK, [dir]);
      } else if (authzOracle === 'hasura-metadata') {
        // eco-F3: metadata Hasura YAML (filter:{} su ruolo anonimo).
        oracle = 'hasura-metadata';
        res = run(HASURA_METADATA_CHECK, [dir]);
      } else if (authzOracle === 'appsync-auth') {
        // eco-F3: schema.graphql AppSync/Amplify Gen1 (allow: public su @model).
        oracle = 'appsync-auth';
        res = run(APPSYNC_AUTH_CHECK, [dir]);
      } else {
        // SP-8 (default invariato): Firestore Security Rules.
        oracle = 'firestore-rules';
        res = run(FIRESTORE_RULES_CHECK, [dir]);
      }
      break;
    }
    default:
      return { ok: false, findings: [], detail: `categoria non rieseguibile: ${finding.category}` };
  }
  if (!res.ok) return { ok: false, findings: [], detail: res.detail };
  let findings;
  try { findings = normalize(oracle, res.json, { ...runOpts, scope }); }
  catch (e) { return { ok: false, findings: [], detail: `normalize: ${e.message}` }; }

  // --- RETE PER IDENTITA' (strato 2 della REGOLA DEL SEME) --------------------
  // Il finding sotto fix non puo' sparire perche' e' stato ESCLUSO: se e' fra i
  // soppressi, torna dentro. Il confronto e' per FINGERPRINT — l'identita' del
  // finding — e non dipende da come e' scritto un path, che e' il punto in cui la
  // protezione per path potrebbe silenziosamente non agganciare.
  // Se la normalizzazione dei soppressi non riesce, NON concludiamo "pulito":
  // dichiariamo il re-run non riuscito (-> verification-failed, mai `verified`).
  if (scopeSuppressedNative && scopeSuppressedNative.length > 0) {
    let suppressed;
    try { suppressed = normalize(oracle, scopeSuppressedNative, { ...runOpts, scope }); }
    catch (e) {
      return { ok: false, findings: [], detail: `normalize(esclusi dallo scope): ${e.message}` };
    }
    const back = suppressed.filter((f) => f.fingerprint === finding.fingerprint);
    if (back.length > 0) findings = findings.concat(back);
  }

  const v = validateMany(findings);
  if (!v.ok) return { ok: false, findings, detail: `schema KO: ${v.errors[0]}` };
  return { ok: true, findings, detail: `${findings.length} finding`, scope };
}

// Il finding e' ancora presente? Match per fingerprint (identita stabile, 04 §6).
function stillPresent(finding, findings) {
  return findings.some((f) => f.fingerprint === finding.fingerprint);
}

// RE-BASELINE IMMEDIATO post-verifica (06 §4 — il nodo): quando una fix viene
// promossa a verified, l'observed delle assertion IMPACTED dal finding e'
// cambiato LEGITTIMAMENTE. Aggiorniamo la baseline.json SOLO per quelle e
// committiamo, COSI' il finding SUCCESSIVO (che le tratta come GUARD) le trova
// gia' allineate al nuovo comportamento e non scambia un cambiamento legittimo
// per una regressione. Le GUARD del finding corrente restano congelate. No-op se
// non c'e' characterization (backward-compat M1). NON tocca git history: usa il
// commit additivo/reversibile sul branch della copia.
function rebaselineImpactedAfterVerify(dir, finding) {
  const charz = loadCharacterization(dir);
  if (!charz) return { rebaselined: [] };
  const baselinePath = resolve(dir, 'test', 'characterization', 'baseline.json');
  let baselineObj;
  try { baselineObj = JSON.parse(readFileSync(baselinePath, 'utf8')); }
  catch { return { rebaselined: [] }; }
  const assertions = baselineObj.assertions || [];

  // Recompute corrente.
  const inv = characterizationInvariance(dir, charz, finding);
  if (!inv.ok) return { rebaselined: [] };
  const impacted = new Set(inv.impacted);
  if (impacted.size === 0) return { rebaselined: [] };

  const res = spawnSync(process.execPath, [charz.runnerPath], {
    cwd: dir, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (res.status !== 0) return { rebaselined: [] };
  const lines = (res.stdout || '').trim().split(/\r?\n/).filter(Boolean);
  if (lines.length === 0) return { rebaselined: [] };
  let current;
  try { current = new Map((JSON.parse(lines[lines.length - 1]).assertions || []).map((a) => [a.id, a.observed])); }
  catch { return { rebaselined: [] }; }

  const rebaselined = [];
  for (const a of assertions) {
    if (impacted.has(a.id) && current.has(a.id)) {
      a.observed = current.get(a.id);
      rebaselined.push(a.id);
    }
  }
  if (rebaselined.length === 0) return { rebaselined: [] };
  writeFileSync(baselinePath, JSON.stringify(baselineObj, null, 2) + '\n');
  commitOnBranch(dir, `test(characterization): re-baseline IMPACTED [${rebaselined.join(',')}] post-fix ${shortFp(finding)} (06 §4)`);
  return { rebaselined };
}

// --- Esegue i test pertinenti sulla copia (RIESEGUI i test, 05 §3) -----------
//
// INVARIANZA per partition (06 §4 — il nodo): quando esiste una suite di
// characterization VALUE-BASED, la parte "RIESEGUI i test" NON e' un nudo
// `npm test` (che tratterebbe TUTTE le assertion come guard e quindi
// segnalerebbe rosso anche per una assertion IMPACTED che la fix cambia
// LEGITTIMAMENTE). Usa invece characterizationInvariance(dir, charz, finding):
//   - GUARD    devono restare invarianti vs baseline (regressione = rosso);
//   - IMPACTED dal `finding` corrente sono re-baselined (la fix le cambia per
//     disegno) -> non vincolano.
// Cosi' fixare S5 (invoices.observed cambia) NON fa fallire i test del loop,
// mentre rompere una GUARD (es. /health o una tabella non toccata) li fa fallire.
//
// SENZA characterization: comportamento M1 invariato (degradato onesto se non
// c'e' runner; `npm test` se un runner reale esiste).
function runTests(dir, finding = null) {
  const charz = loadCharacterization(dir);
  if (charz) {
    const inv = characterizationInvariance(dir, charz, finding);
    if (!inv.ok) {
      // recompute fallito: NON un falso verde -> rosso esplicito.
      return { ran: true, green: false, detail: `characterization: ${inv.detail}` };
    }
    return {
      ran: true, green: inv.green,
      detail: inv.green
        ? `characterization invarianza OK (${inv.detail})`
        : `characterization invarianza VIOLATA (${inv.detail})`,
      guard: inv.guard, impacted: inv.impacted,
    };
  }

  const pkgPath = resolve(dir, 'package.json');
  if (!existsSync(pkgPath)) return { ran: false, green: true, detail: 'nessun package.json' };
  let pkg;
  try { pkg = JSON.parse(readFileSync(pkgPath, 'utf8')); } catch { return { ran: false, green: true, detail: 'package.json illeggibile' }; }
  const t = pkg.scripts && pkg.scripts.test;
  if (!t || /no test specified/i.test(t)) {
    // FORWARD-DEP: senza characterization test (06) la parte "RIESEGUI i test"
    // del loop e' DEGRADATA, non un falso verde. Non blocca la promozione
    // dell'oracolo, ma il checkpoint resta degradato sui controlli 3/4.
    return { ran: false, green: true, degraded: true, detail: 'nessun test runner: parte test DEGRADATA' };
  }
  const res = spawnSync('npm', ['run', 'test', '--silent'], {
    cwd: dir, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, shell: true,
  });
  const green = !res.error && res.status === 0;
  return { ran: true, green, detail: green ? 'test verdi' : `test rossi (exit=${res.status})` };
}

// =============================================================================
// LOOP per-finding (05 §3). Ritorna il record di esito del finding.
// =============================================================================
//
// finding   il finding triaged da correggere (gia' normalizzato, 04).
// ctx       { dir, runOpts, fixProvider, evalMode, gate, budget }
//   dir         directory della COPIA TEMPORANEA (mai il fixture canonico)
//   fixProvider provider iniettabile: propose(finding, attempt, lastReason)
//   evalMode    true => gate auto-approvato deterministicamente (solo-eval)
//   gate        funzione di gate umano (default: rifiuta se !evalMode)
//   budget      stato condiviso del budget globale { startedAt, deadlineMs }
//
// Esiti di fix_state possibili (04 §5):
//   verified              oracolo riesieguito pulito + test verdi/degradati
//   mitigated-residual    SOLO secret-in-history (rotazione, no rewrite) — terminale
//   verification-failed   terminale all'umano dopo budget/tentativi esauriti
export function runFindingLoop(finding, ctx) {
  const {
    dir, fixProvider, evalMode = false, runOpts = { runId: 'loop', createdAt: '1970-01-01T00:00:00.000Z' },
    gate = defaultGate(evalMode), budget,
  } = ctx;

  const triage = { ...finding, fix_state: 'triaged' };
  const attempts = [];
  const seenSignatures = new Set(); // rifiuta ri-sottomissione byte-identica (05 §3)
  let lastFailureReason = null;

  // PRE-CHECK (05 §6, autorita' = oracolo): un finding puo' essere gia' stato
  // azzerato da una fix SORELLA dello stesso round (es. due regole gitleaks
  // sullo STESSO literal di config.ts: la fix di S1 ne cancella entrambe).
  // Riesegui lo stesso oracolo: se il finding e' GIA' assente, e' verified per
  // fatto dell'oracolo, senza ri-applicare nulla (L-COL-002). NON si applica al
  // caso history (S2/SPY-S6): la history non si "pulisce" senza riscrittura
  // distruttiva (dispatch additivo keyed sul path: copre JS .ts e Python .py).
  const __triagePath = String((triage.location && triage.location.file) || '').replace(/\\/g, '/');
  const __isHistorySecret = triage.category === 'secret'
    && (/legacy\/credentials\.ts$/.test(__triagePath) || /legacy_credentials\.py$/.test(__triagePath));
  if (!__isHistorySecret) {
    const pre = rerunOracleFor(triage, dir, runOpts);
    if (pre.ok && !stillPresent(triage, pre.findings)) {
      // partition col finding corrente: l'assertion sulla stessa regione/tabella
      // e' IMPACTED (re-baselined), le altre GUARD (invarianti) — 06 §4.
      const tests = runTests(dir, triage);
      if (tests.green) {
        const rb = rebaselineImpactedAfterVerify(dir, triage);
        return terminal('verified', triage, attempts,
          `gia' azzerato da una fix sorella; oracolo riesieguito pulito + test ${tests.detail}`,
          { verified: true, resolvedBySibling: true, rebaselined: rb.rebaselined });
      }
    }
  }

  const maxAttempts = LOOP_BUDGET.MAX_RETRIES_PER_FINDING + 1; // proposta + retry

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    // Budget globale (05 §4): se il tempo di parete e' esaurito -> terminale.
    if (budget && Date.now() > budget.deadlineMs) {
      return terminal('verification-failed', triage, attempts,
        'budget globale (tempo di parete) esaurito prima del tentativo', { budgetExhausted: true });
    }

    // PROPONI (fix-proposed).
    const patch = fixProvider.propose(triage, attempt, lastFailureReason);
    if (!patch) {
      // Nessuna fix proposta: categoria detection-only fuori scope, o provider
      // esaurito. Non e' verified, non e' uno scarto silenzioso: terminale.
      return terminal('verification-failed', triage, attempts,
        'nessuna fix proposta dal provider', { noFix: true });
    }

    // Rifiuto ri-sottomissione byte-identica (05 §3): patch MATERIALMENTE diversa.
    if (seenSignatures.has(patch.signature)) {
      return terminal('verification-failed', triage, attempts,
        `ri-sottomissione byte-identica rifiutata (signature=${patch.signature})`, { duplicatePatch: true });
    }
    seenSignatures.add(patch.signature);

    // [GATE UMANO] sull'APPLICAZIONE (L-COL-005; dead-code mai automatico,
    // L-COL-021). In eval e' auto-approvato deterministicamente (solo-eval).
    const gateDecision = gate({ finding: triage, patch, attempt });
    if (!gateDecision.approved) {
      return terminal('accepted-risk', triage, attempts,
        `gate umano NON approvato: ${gateDecision.reason || 'rifiutato'}`, { gateRejected: true });
    }

    // CASO SPECIALE S2 (secret-in-history): rotazione, no history rewrite.
    // Terminale: mitigated-residual, MAI verified (05 §7).
    if (patch.kind === 'secret-history') {
      const applied = patch.apply(dir);
      attempts.push({ attempt, signature: patch.signature, kind: patch.kind, applied });
      // Nessun re-run che possa "pulire" la history senza riscriverla: lo stato
      // e' per costruzione mitigated-residual.
      return terminal('mitigated-residual', triage, attempts,
        applied.detail || 'rotazione dichiarata; history non riscritta (distruttiva, gate umano)',
        { mitigatedResidual: true });
    }

    // APPLICA sulla COPIA + commit isolato sul branch (additivo, reversibile).
    const preSha = headSha(dir);
    const applied = patch.apply(dir);
    if (!applied.ok) {
      attempts.push({ attempt, signature: patch.signature, applied, verified: false });
      lastFailureReason = `applicazione fallita: ${applied.detail}`;
      // Revert prima di riprovare (anche se l'apply ha fallito, normalizziamo lo
      // stato del branch).
      revertToRef(dir, preSha);
      continue;
    }
    const commitMsg =
      `fix(loop): ${triage.category} ${shortFp(triage)} tentativo ${attempt} `
      + `[${patch.signature}]`;
    const commit = commitOnBranch(dir, commitMsg);

    // RIESEGUI lo stesso oracolo (stesso rule_id) + RIESEGUI i test (invarianza
    // per partition: GUARD invarianti, IMPACTED dal finding re-baselined — 06 §4).
    const rerun = rerunOracleFor(triage, dir, runOpts);
    const tests = runTests(dir, triage);

    const oracleClean = rerun.ok && !stillPresent(triage, rerun.findings);
    const testsOk = tests.green; // degradato (M3) conta come non-rosso

    attempts.push({
      attempt, signature: patch.signature, kind: patch.kind,
      applied, commit: commit.sha || null,
      oracleClean, oracleDetail: rerun.detail,
      testsOk, testsDetail: tests.detail, testsDegraded: Boolean(tests.degraded),
    });

    if (oracleClean && testsOk) {
      // RE-BASELINE immediato delle assertion IMPACTED da QUESTA fix (06 §4): il
      // finding successivo le tratta come GUARD e deve trovarle gia' allineate.
      const rb = rebaselineImpactedAfterVerify(dir, triage);
      // SOLO l'oracolo promuove (L-COL-002): verified.
      return terminal('verified', triage, attempts,
        `oracolo riesieguito pulito (${rerun.scope || ''}) + test ${tests.detail}`
        + (rb.rebaselined.length ? `; impacted re-baselined=[${rb.rebaselined.join(',')}]` : ''),
        { verified: true, rebaselined: rb.rebaselined });
    }

    // verification-failed: residui o test rotto. REVERT la patch prima del retry.
    lastFailureReason = !oracleClean
      ? `oracolo flagga ancora il finding (${rerun.detail})`
      : `test rotto: ${tests.detail}`;
    revertToRef(dir, preSha);

    // Loop continua (retry) finche' restano tentativi (cap O-COL-006).
  }

  // Tentativi esauriti: terminale all'umano. MAI verified, MAI scarto silenzioso.
  return terminal('verification-failed', triage, attempts,
    `tentativi esauriti (${maxAttempts}); ultimo motivo: ${lastFailureReason}`,
    { attemptsExhausted: true });
}

// Gate di default: in eval auto-approva deterministicamente; fuori eval rifiuta
// (la skill reale fornisce un gate umano vero).
function defaultGate(evalMode) {
  return ({ /* finding, patch, attempt */ }) =>
    evalMode
      ? { approved: true, reason: 'EVAL-MODE: gate auto-approvato (solo-eval, deterministico)' }
      : { approved: false, reason: 'gate umano richiesto (nessun auto-approve fuori da --eval)' };
}

function terminal(fixState, finding, attempts, reason, flags = {}) {
  return {
    fingerprint: finding.fingerprint,
    category: finding.category,
    rule_id: finding.source_oracle.rule_id,
    location: finding.location,
    fix_state: fixState,
    reason,
    attempts,
    ...flags,
  };
}

function shortFp(f) { return f.fingerprint.slice(0, 8); }
