#!/usr/bin/env node
// run_gitleaks.mjs — wrapper dell'oracolo gitleaks (03-ORACLES §5.2).
//
// Esegue gitleaks in modalita JSON REDATTA e supporta due scope di scansione
// (03 §5.2):
//   - working-tree (scope BUILD): scansiona i FILE su disco. Difetto seminato
//     S1 (segreto nel sorgente, src/lib/config.ts) vive qui.
//   - history (scope REMEDIATE): scansiona i COMMIT della git history. Difetto
//     seminato S2 (segreto solo in history, src/legacy/credentials.ts, rimosso
//     dal working tree) vive qui; in history riappare anche S1.
//
// CONTRATTO: lo script prende `<dir> <scope>`, esegue gitleaks e stampa su
// stdout il JSON NATIVO di gitleaks (array di finding). NON normalizza: la
// normalizzazione nel finding model (04) e compito di normalize.* a valle.
// Il valore del segreto resta sempre REDATTO (`--redact`): in chiaro non esce
// mai (ne in stdout ne in stderr/diagnostica).
//
// PRINCIPIO (03 §3): si parsa il REPORT JSON, non l'exit code. Gli exit code di
// gitleaks sono ambigui (un path inesistente esce 0, una config rotta esce 1
// come "findings trovati"). Quindi forziamo `--exit-code 0` e decidiamo l'esito
// dal report: JSON valido => run riuscito (anche con 0 finding); spawn fallito o
// stdout non parsabile come JSON => ERRORE DI ESECUZIONE (exit 2), che a monte
// NON va interpretato come "verde" (L-COL-006, nessun falso via libera).
//
// Node ESM, solo moduli built-in (niente dipendenze npm, niente rete).
//
// Uso:
//   node run_gitleaks.mjs <dir> <working-tree|history>
// Esempi:
//   node trueline/scripts/oracles/run_gitleaks.mjs eval/reference-app working-tree
//   node trueline/scripts/oracles/run_gitleaks.mjs eval/reference-app history

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, resolve, join, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Config gitleaks versionata, accanto a questo script (03 §5.2).
const GITLEAKS_CONFIG = resolve(__dirname, 'gitleaks.toml');

// Codici di uscita del wrapper.
const EXIT_OK = 0; // run completato (con o senza finding); JSON nativo su stdout
const EXIT_USAGE = 2; // uso scorretto degli argomenti
const EXIT_EXEC_ERROR = 3; // errore di esecuzione (gitleaks non gira / output non parsabile)

const SCOPES = new Set(['working-tree', 'history']);
const IS_WINDOWS = process.platform === 'win32';

// Diagnostica su stderr (mai segreti: solo metadati di esecuzione).
function diag(msg) {
  process.stderr.write(`[run_gitleaks] ${msg}\n`);
}

// Risolve l'eseguibile gitleaks. Precedenza (Task 4): binario project-local in
// `<dir>/.trueline/bin/` -> PATH -> percorsi noti (incl. go/bin di questo
// ambiente, che NON e sul PATH). ADDITIVO/BIT-INVARIANTE: se `.trueline/bin`
// e assente (o `dir` non passato), la risoluzione e identica a oggi.
function resolveGitleaksBin(dir) {
  const exe = IS_WINDOWS ? 'gitleaks.exe' : 'gitleaks';
  // 0) Project-local: `<dir>/.trueline/bin/<exe>`. Vince sui candidati globali.
  //    Assente -> si prosegue col flusso odierno (nessun cambio di comportamento).
  if (dir) {
    const local = join(dir, '.trueline', 'bin', exe);
    if (existsSync(local)) return local;
  }
  // 1) PATH: lascia che sia spawn a risolvere "gitleaks".
  //    Verifichiamo prima con `gitleaks version` in modo da poter ripiegare.
  const onPath = spawnSync('gitleaks', ['version'], { encoding: 'utf8' });
  if (!onPath.error) return 'gitleaks';

  // 2) Percorsi candidati noti (go install).
  const home = process.env.HOME || process.env.USERPROFILE || '';
  const candidates = [
    process.env.GITLEAKS_BIN, // override esplicito
    home ? join(home, 'go', 'bin', exe) : null,
    'C:/Users/claud/go/bin/gitleaks.exe',
    '/c/Users/claud/go/bin/gitleaks',
  ].filter(Boolean);
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  // 3) Ultimo tentativo: estendi il PATH della env passata a spawn.
  return 'gitleaks';
}

// Costruisce gli argomenti per uno scope, con un subcomando primario e un
// fallback (per coprire versioni diverse di gitleaks).
//   working-tree -> primario `dir <dir>`, fallback `detect --no-git --source <dir>`
//   history      -> primario `git <dir>`, fallback `detect --source <dir>`
// Flag comuni: report JSON su stdout, redazione, niente banner, exit forzato 0.
function buildInvocations(dir, scope) {
  const common = [
    '-c', GITLEAKS_CONFIG,
    '--report-format', 'json',
    '--report-path', '-', // stdout: evita problemi di path su Windows/MSYS
    '--redact',
    '--no-banner',
    '--exit-code', '0', // l'esito si decide dal report, non dall'exit code
  ];
  if (scope === 'working-tree') {
    return [
      { label: 'dir', args: ['dir', dir, ...common] },
      { label: 'detect --no-git', args: ['detect', '--no-git', '--source', dir, ...common] },
    ];
  }
  // history
  return [
    { label: 'git', args: ['git', dir, ...common] },
    { label: 'detect', args: ['detect', '--source', dir, ...common] },
  ];
}

// Esegue una singola invocazione di gitleaks. Ritorna { spawned, parsed, json,
// raw, stderr }:
//   - spawned=false  => gitleaks non e partito (binario assente, ecc.)
//   - parsed=true    => stdout e un array JSON valido (run riuscita)
//   - parsed=false   => stdout NON parsabile come array JSON (subcomando non
//                       riconosciuto da questa versione, o errore di config)
function runOnce(bin, args, env) {
  const res = spawnSync(bin, args, {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    env,
  });
  if (res.error) {
    return { spawned: false, parsed: false, json: null, raw: '', stderr: String(res.error.message || res.error) };
  }
  const raw = res.stdout || '';
  const stderr = res.stderr || '';
  let json = null;
  let parsed = false;
  try {
    const data = JSON.parse(raw);
    if (Array.isArray(data)) {
      json = data;
      parsed = true;
    }
  } catch {
    parsed = false;
  }
  return { spawned: true, parsed, json, raw, stderr };
}

function main() {
  const [, , dirArg, scopeArg] = process.argv;

  if (!dirArg || !scopeArg) {
    diag('uso: node run_gitleaks.mjs <dir> <working-tree|history>');
    process.exit(EXIT_USAGE);
  }
  if (!SCOPES.has(scopeArg)) {
    diag(`scope non valido: "${scopeArg}". Ammessi: working-tree | history`);
    process.exit(EXIT_USAGE);
  }

  const dir = resolve(process.cwd(), dirArg);
  if (!existsSync(dir)) {
    diag(`directory di scansione assente: ${dir}`);
    process.exit(EXIT_EXEC_ERROR);
  }
  if (scopeArg === 'history' && !existsSync(join(dir, '.git'))) {
    diag(`scope=history ma ${dir} non e un repo git (.git assente)`);
    process.exit(EXIT_EXEC_ERROR);
  }
  if (!existsSync(GITLEAKS_CONFIG)) {
    diag(`config gitleaks assente: ${GITLEAKS_CONFIG}`);
    process.exit(EXIT_EXEC_ERROR);
  }

  // PATH arricchito col go/bin noto, nel caso gitleaks non sia sul PATH.
  const extraBin = IS_WINDOWS ? 'C:/Users/claud/go/bin' : '/c/Users/claud/go/bin';
  const env = {
    ...process.env,
    PATH: `${process.env.PATH || ''}${delimiter}${extraBin}`,
  };

  const bin = resolveGitleaksBin(dir);
  const invocations = buildInvocations(dir, scopeArg);

  let lastDiag = '';
  for (const inv of invocations) {
    const r = runOnce(bin, inv.args, env);
    if (!r.spawned) {
      lastDiag = `gitleaks non eseguibile (subcomando "${inv.label}"): ${r.stderr}`;
      // Errore di spawn: prova comunque il fallback (potrebbe cambiare nulla,
      // ma manteniamo il ciclo uniforme).
      continue;
    }
    if (r.parsed) {
      // Run riuscita: emetti il JSON NATIVO di gitleaks su stdout (re-serializzato
      // per garantire un array pulito anche se gitleaks avesse aggiunto rumore).
      process.stdout.write(JSON.stringify(r.json, null, 2) + '\n');
      diag(`scope=${scopeArg} subcomando="${inv.label}" finding=${r.json.length} (segreti redatti)`);
      process.exit(EXIT_OK);
    }
    // Spawnato ma stdout non parsabile: subcomando ignoto o config rotta.
    // Tieni la diagnostica e prova il fallback.
    lastDiag =
      `subcomando "${inv.label}" non ha prodotto un array JSON valido ` +
      `(probabile subcomando non supportato o errore di config). ` +
      `stderr: ${r.stderr.trim().split('\n').slice(-1)[0] || '(vuoto)'}`;
  }

  // Nessuna invocazione ha prodotto un report JSON valido => errore di esecuzione.
  diag(`ERRORE DI ESECUZIONE: ${lastDiag || 'gitleaks non ha prodotto output utilizzabile'}`);
  process.exit(EXIT_EXEC_ERROR);
}

// Esegui main() SOLO da CLI. Importato (es. dal test del bin-lookup) NON deve
// partire (main() farebbe process.exit su argomenti mancanti).
const __isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (__isMain) main();

export { resolveGitleaksBin };
