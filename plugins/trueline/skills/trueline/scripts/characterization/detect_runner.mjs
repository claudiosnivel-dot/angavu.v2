// detect_runner.mjs — rilevatore del test runner di un progetto target (06 §5).
//
// GENERICO sopra un progetto utente qualunque (NON hardcoded alla reference app).
// Ispeziona package.json per capire quale runner di test e' gia' dichiarato, in
// ordine di preferenza: vitest > jest > node:test. Se il progetto NON dichiara
// alcun runner, il generatore (generate.mjs) puo' impalcare un runner basato su
// `node:test` (sempre disponibile col Node toolchain, zero dipendenze npm). Se
// nemmeno questo e' possibile, si DICHIARA la degradazione — MAI un falso verde
// (06 §3, L-COL-006).
//
// Node ESM, solo built-in.

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Legge e parsa il package.json del progetto. Ritorna null se assente/illeggibile.
function readPkg(projectDir) {
  const p = resolve(projectDir, 'package.json');
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, 'utf8')); }
  catch { return null; }
}

// Un test script "placeholder" ("no test specified") NON conta come runner reale.
function isPlaceholder(script) {
  return !script || /no test specified/i.test(script);
}

// Lista di candidati di default (ordine di preferenza invariato con v1).
const DEFAULT_DETECT = ['vitest', 'jest', 'node:test'];

// Cerca un runner tra le dipendenze dichiarate (dev + prod) e gli script.
// candidates: lista di nomi di runner da cercare (dal manifest o default).
function detectDeclared(pkg, candidates = DEFAULT_DETECT) {
  const deps = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) };
  const testScript = (pkg.scripts && pkg.scripts.test) || '';

  for (const candidate of candidates) {
    if (candidate === 'node:test') {
      // node:test: invocato esplicitamente (node --test) nello script.
      if (/node\s+--test\b/.test(testScript) || /\bnode:test\b/.test(testScript)) return 'node:test';
    } else {
      // altri runner: dipendenza dichiarata o invocato nello script test.
      const re = new RegExp(`\\b${candidate.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`);
      if (deps[candidate] || re.test(testScript)) return candidate;
    }
  }
  return null;
}

// detectRunner(projectDir, manifest?) -> { present, runner, degraded, detail }
//
//   present   true se un runner REALE e' gia' dichiarato dal progetto.
//   runner    nome del runner rilevato | 'node:test' (fallback) | null
//   degraded  true se NON c'e' runner reale E nemmeno e' impalcabile node:test
//             (es. nessun package.json) -> il generatore deve dichiarare il limite.
//   detail    spiegazione leggibile (per il report di copertura).
//
// manifest (opzionale, SP-0): se fornito e ha test_runner.detect, quella lista
// diventa i candidati (in ordine di priorita'). Default = DEFAULT_DETECT
// (vitest > jest > node:test), invarianza v1.
//
// Politica: se il progetto NON dichiara un runner ma esiste un package.json
// scrivibile, NON e' degradato: il generatore puo' impalcare `node:test`
// (runner='node:test', present=false). La degradazione vera scatta solo quando
// non c'e' nemmeno un package.json su cui agganciare lo script test.
export function detectRunner(projectDir, manifest = null) {
  const pkg = readPkg(projectDir);
  if (!pkg) {
    return {
      present: false,
      runner: null,
      degraded: true,
      detail: 'nessun package.json: impossibile rilevare o impalcare un test runner (degradato, NON verde)',
    };
  }

  // Risolvi la lista di candidati: manifest.test_runner.detect se disponibile,
  // altrimenti DEFAULT_DETECT (comportamento v1 invariato).
  const candidates = (manifest && manifest.test_runner && Array.isArray(manifest.test_runner.detect) && manifest.test_runner.detect.length > 0)
    ? manifest.test_runner.detect
    : DEFAULT_DETECT;

  const declared = detectDeclared(pkg, candidates);
  if (declared) {
    return {
      present: true,
      runner: declared,
      degraded: false,
      detail: `runner gia' dichiarato dal progetto: ${declared}`,
    };
  }

  const testScript = (pkg.scripts && pkg.scripts.test) || '';
  const placeholder = isPlaceholder(testScript);
  return {
    present: false,
    runner: 'node:test',
    degraded: false,
    detail: placeholder
      ? "nessun runner dichiarato (script test placeholder/assente): impalcabile node:test (zero dipendenze npm)"
      : `script test presente ma runner non riconosciuto (${testScript.slice(0, 40)}): fallback node:test impalcabile`,
  };
}

export default detectRunner;
