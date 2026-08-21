// layered_git.mjs — modello git a strati (01 §5, 05 §8).
//
// Tre strati di autorita' (01 §5.1):
//   - Branch di lavoro      -> AUTONOMO (init/checkout -b/stage/commit/push del branch)
//   - Merge su main         -> GATED dal checkpoint verde (autorita' = oracolo),
//                              con asimmetria per modalita' e gate di deploy (05 §8.3)
//   - Operazioni distruttive-> MAI autonome (push --force, reset --hard su branch
//                              pushato, rebase di storia pubblicata, delete branch,
//                              history rewrite) -> sempre gate umano esplicito.
//
// Questo modulo NON esegue merge/push verso un remote reale: e' la macchina di
// DECISIONE (puo' o non puo' procedere autonomamente?) piu' i commit isolati sul
// branch della COPIA TEMPORANEA. La decisione e' deterministica e ispezionabile;
// l'esecuzione effettiva del salto su main nella skill reale resta dietro il
// gate qui calcolato.
//
// Node ESM, solo built-in (child_process, path, url). Niente rete.

import { spawnSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { evaluateDeployCoupling } from './detect_deploy_coupling.mjs';

// trueline/scripts/git -> repo ESTERNO = 3 livelli sopra.
const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTER_REPO_ROOT = resolve(__dirname, '..', '..', '..');
const CANONICAL_REFERENCE_APP = resolve(OUTER_REPO_ROOT, 'eval', 'reference-app');
const normPath = (p) => resolve(String(p)).replace(/\\/g, '/').replace(/\/+$/, '').toLowerCase();

// GUARDRAIL D'ISOLAMENTO (L-COL-024) — la difesa DEFINITIVA contro la
// contaminazione ricorrente del repo esterno (M1/M2/M3/M4). Ogni operazione git
// MUTANTE del loop (checkout -b / add+commit / reset --hard+clean) DEVE girare su
// una COPIA temporanea con .git proprio (eval/.tmp-verify/<id>), MAI sul repo
// esterno ne' sul fixture canonico. Se per un bug d'isolamento del workspace il
// `dir` risolve al repo esterno/canonico, RIFIUTIAMO con errore esplicito invece
// di committare/resettare la' (fallimento RUMOROSO, non contaminazione silenziosa).
function assertIsolatedRepo(dir, op) {
  const top = git(dir, ['rev-parse', '--show-toplevel']);
  const topResolved = top.ok ? normPath(top.stdout) : null;
  if (topResolved === normPath(OUTER_REPO_ROOT)) {
    throw new Error(
      `RIFIUTO git a strati (${op}): "${dir}" risolve al REPO ESTERNO (${OUTER_REPO_ROOT}). `
      + 'Il verify-fix loop deve operare SOLO su una COPIA temporanea con .git proprio '
      + '(eval/.tmp-verify/<id>), MAI sul repo esterno (L-COL-024). Bug d\'isolamento del workspace.',
    );
  }
  if (topResolved === normPath(CANONICAL_REFERENCE_APP)) {
    throw new Error(
      `RIFIUTO git a strati (${op}): "${dir}" risolve al FIXTURE CANONICO ${CANONICAL_REFERENCE_APP}. `
      + 'Il loop deve usare una COPIA, mai il fixture canonico (L-COL-024).',
    );
  }
}

// Operazioni classificate come DISTRUTTIVE (01 §5.1 / 05 §8.4): mai autonome.
export const DESTRUCTIVE_OPS = new Set([
  'push --force',
  'reset --hard (branch pushato)',
  'rebase (storia pubblicata)',
  'delete branch',
  'history rewrite',
]);

// --- Strato 1: branch di lavoro (AUTONOMO) -----------------------------------

// Esegue un comando git in `dir`. Ritorna { ok, stdout, stderr, status }.
export function git(dir, args, env = process.env) {
  const res = spawnSync('git', ['-C', dir, ...args], {
    encoding: 'utf8',
    env,
    maxBuffer: 32 * 1024 * 1024,
  });
  return {
    ok: !res.error && res.status === 0,
    stdout: (res.stdout || '').trim(),
    stderr: (res.stderr || '').trim(),
    status: res.status,
    error: res.error ? String(res.error.message || res.error) : null,
  };
}

// Crea/seleziona il branch di lavoro (autonomo, additivo, reversibile).
// Convenzione (05 §8.1): trueline/<modalita>/<macrotask-o-lotto>.
export function createWorkBranch(dir, name) {
  assertIsolatedRepo(dir, 'createWorkBranch');
  // Se il branch esiste gia', selezionalo; altrimenti crealo.
  const exists = git(dir, ['rev-parse', '--verify', name]).ok;
  if (exists) return git(dir, ['checkout', name]);
  return git(dir, ['checkout', '-b', name]);
}

// Commit isolato sul branch (additivo, reversibile). Stage di `paths` (default:
// tutto) e commit con `message`. Configura un'identita' locale se assente, per
// non dipendere dalla config globale dell'ambiente.
export function commitOnBranch(dir, message, paths = ['-A']) {
  assertIsolatedRepo(dir, 'commitOnBranch');
  ensureLocalIdentity(dir);
  const add = git(dir, ['add', ...paths]);
  if (!add.ok) return { ok: false, step: 'add', detail: add.stderr || add.error };
  const commit = git(dir, ['commit', '-m', message, '--no-verify']);
  if (!commit.ok) {
    // "nothing to commit" non e' un errore fatale per il loop (es. fix che non
    // tocca file tracciati): lo segnaliamo ma non lo trattiamo come fallimento.
    const benign = /nothing to commit|niente da committare/i.test(commit.stdout + commit.stderr);
    return { ok: benign, step: 'commit', detail: commit.stdout || commit.stderr, benign };
  }
  return { ok: true, step: 'commit', sha: git(dir, ['rev-parse', 'HEAD']).stdout };
}

// Revert dell'ultimo tentativo: riporta il working tree del branch allo stato
// pre-patch (05 §3, "revert prima di riprovare"). Usa un reset hard + clean
// LOCALE alla COPIA temporanea — legittimo perche' il lavoro su branch e'
// reversibile (L-COL-024) e la copia e' usa-e-getta. NON e' un'operazione
// distruttiva su storia PUBBLICATA: agisce solo sulla copia temp non pushata.
export function revertToRef(dir, ref) {
  assertIsolatedRepo(dir, 'revertToRef');
  const reset = git(dir, ['reset', '--hard', ref]);
  if (!reset.ok) return { ok: false, detail: reset.stderr || reset.error };
  const clean = git(dir, ['clean', '-fd']);
  return { ok: clean.ok, detail: clean.ok ? '' : (clean.stderr || clean.error) };
}

export function headSha(dir) {
  return git(dir, ['rev-parse', 'HEAD']).stdout;
}

export function currentBranch(dir) {
  return git(dir, ['rev-parse', '--abbrev-ref', 'HEAD']).stdout;
}

// --- Strato 2: decisione del merge su main (GATED) ---------------------------

// Decide se il merge su main puo' procedere AUTONOMAMENTE. Non esegue il merge:
// restituisce la decisione (gate). Combina:
//   - checkpointGreen: il checkpoint e' interamente verde? (autorita' = oracolo)
//   - mode: "build" | "remediate"  (asimmetria 05 §8.2)
//   - deploy-coupling: se main e' coupled (o unknown non confermato) -> sospeso
//
// Ritorna { autonomous_merge_allowed, gate, reason, deploy }.
export function decideMerge({ dir, mode, checkpointGreen, confirmedCoupled = null }) {
  const deploy = evaluateDeployCoupling(dir, confirmedCoupled);

  // Regola dura (01 §4.2 / 05 §6): senza checkpoint verde non si tocca main.
  if (!checkpointGreen) {
    return {
      autonomous_merge_allowed: false,
      gate: 'blocked-red-checkpoint',
      reason: 'checkpoint NON verde: nessun merge su main (regola dura 01 §4.2)',
      deploy,
    };
  }

  // REMEDIATE: il merge su main resta un "vai" umano anche sul verde (05 §8.2).
  if (mode === 'remediate') {
    return {
      autonomous_merge_allowed: false,
      gate: 'human-gated-remediate',
      reason: 'REMEDIATE: merge su main e\' sempre un "vai" umano (05 §8.2)',
      deploy,
    };
  }

  // BUILD verde: merge autonomo SALVO il gate di deploy (05 §8.3).
  if (deploy.effective_gate === 'suspended') {
    return {
      autonomous_merge_allowed: false,
      gate: 'human-gated-deploy-coupled',
      reason: `BUILD verde ma deploy-coupling sospende il merge autonomo: ${deploy.reason}`,
      deploy,
    };
  }

  return {
    autonomous_merge_allowed: true,
    gate: 'autonomous',
    reason: 'BUILD verde + main NON coupled (confermato/chiaro): merge autonomo consentito',
    deploy,
  };
}

// --- Strato 3: operazioni distruttive (MAI autonome) -------------------------

// Una richiesta di operazione distruttiva e' SEMPRE bloccata in autonomia.
// Ritorna { allowed:false, requires_human_gate:true, op, reason }.
export function requestDestructive(op) {
  return {
    allowed: false,
    requires_human_gate: true,
    op,
    is_destructive: DESTRUCTIVE_OPS.has(op),
    reason:
      `operazione distruttiva "${op}" MAI autonoma (01 §5.1 / 05 §8.4): `
      + 'richiede gate umano esplicito',
  };
}

// --- Helper -------------------------------------------------------------------

function ensureLocalIdentity(dir) {
  const name = git(dir, ['config', 'user.name']);
  if (!name.ok || !name.stdout) {
    git(dir, ['config', 'user.name', 'Trueline Loop']);
    git(dir, ['config', 'user.email', 'loop@trueline.local']);
  }
}
