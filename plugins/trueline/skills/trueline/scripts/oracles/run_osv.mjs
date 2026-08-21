#!/usr/bin/env node
// run_osv.mjs — wrapper dell'oracolo osv-scanner (03 §5.3).
//
// Node ESM, solo moduli built-in (fs, path, child_process, url): nessun
// npm install, nessuna dipendenza di rete.
//
// COSA FA
//   Prende il percorso di un lockfile (arg posizionale, relativo alla root del
//   repo oppure assoluto) ed esegue osv-scanner in modalita JSON sul lockfile
//   indicato. Emette su stdout il JSON NATIVO di osv-scanner (campo `results`,
//   eventualmente vuoto se non ci sono CVE). La normalizzazione
//   native->finding (03 §6, 04) e a valle, nell'adapter.
//
// INVOCAZIONE
//   node trueline/scripts/oracles/run_osv.mjs <lockfile>
//
//   Esempio:
//     export PATH="$PATH:/c/Users/claud/go/bin"
//     node trueline/scripts/oracles/run_osv.mjs eval/reference-app/package-lock.json
//
// POSIZIONE DEL TOOL
//   osv-scanner si trova in /c/Users/claud/go/bin (NON su PATH di default).
//   Prima di invocare questo script, eseguire:
//     export PATH="$PATH:/c/Users/claud/go/bin"
//   oppure impostare la variabile d'ambiente OSV_SCANNER_PATH.
//
// INVOCAZIONE osv-scanner (flag verificati con "osv-scanner scan --help")
//   osv-scanner scan --lockfile <basename> --format json --verbosity error
//   Eseguito con cwd = directory del lockfile (necessario su Windows: il tool
//   non accetta percorsi assoluti con drive letter, ma funziona con path relativi
//   dalla directory corrente).
//   Fallback (osv-scanner obsoleto senza sottocomando scan):
//     osv-scanner --format json --lockfile <basename>
//
// EXIT CODE
//   osv-scanner: 0 = nessuna vulnerabilita; 1 = vulnerabilita trovate; >1 = errore.
//   Entrambi 0 e 1 sono esiti VALIDI con JSON sullo stdout; il wrapper li tratta
//   come successo se stdout e JSON parsabile.
//
// SMOKE TEST (gate M0)
//   Il banco di prova NON ha CVE seminate: lo smoke verifica solo che emetta JSON
//   valido (results vuoto o array di risultati).

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { resolve, dirname, basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Radice del repo: trueline/scripts/oracles -> root e 3 livelli sopra.
const REPO_ROOT = resolve(__dirname, '..', '..', '..');

const IS_WINDOWS = process.platform === 'win32';

/** Stampa un messaggio diagnostico su stderr (lo stdout resta JSON puro). */
function warn(msg) {
  process.stderr.write(`[run_osv] ${msg}\n`);
}

// Risolve l'eseguibile osv-scanner. Precedenza (Task 4): binario project-local
// in `<dir>/.trueline/bin/` -> OSV_SCANNER_PATH -> `osv-scanner` sul PATH.
// ADDITIVO/BIT-INVARIANTE: se `.trueline/bin` e assente (o `dir` non passato),
// la risoluzione e identica a oggi (OSV_SCANNER_PATH ?? 'osv-scanner').
function resolveOsvBin(dir) {
  const exe = IS_WINDOWS ? 'osv-scanner.exe' : 'osv-scanner';
  if (dir) {
    const local = join(dir, '.trueline', 'bin', exe);
    if (existsSync(local)) return local;
  }
  return process.env.OSV_SCANNER_PATH ?? 'osv-scanner';
}

/**
 * Esegue osv-scanner con i flag indicati. Restituisce { stdout, stderr, status, error }.
 * Cambia la cwd nella directory del lockfile (workaround path Windows).
 */
function runOsv(osvBin, args, cwd) {
  return spawnSync(osvBin, args, {
    cwd,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
    env: process.env,
  });
}

/**
 * Tenta di parsare stdout come JSON. Restituisce { ok, parsed }.
 * Ignora le righe di diagnostica che osv-scanner stampa su stdout prima del JSON
 * (come "Scanned ... file and found N packages") filtrando fino al primo '{'.
 */
function tryParseJson(raw) {
  const trimmed = raw.trim();
  // Trova il primo '{' per saltare eventuali righe di intestazione testuali.
  const start = trimmed.indexOf('{');
  if (start === -1) return { ok: false, parsed: null };
  try {
    const parsed = JSON.parse(trimmed.slice(start));
    return { ok: true, parsed };
  } catch {
    return { ok: false, parsed: null };
  }
}

function main() {
  // 1) Risolvi il percorso del lockfile (argomento posizionale obbligatorio).
  const argLockfile = process.argv[2];
  if (!argLockfile) {
    warn('uso: node run_osv.mjs <lockfile>');
    warn('Esempio: node run_osv.mjs eval/reference-app/package-lock.json');
    process.exit(2);
  }

  // Percorso assoluto del lockfile (relativo alla root del repo se non assoluto).
  const lockfileAbs = resolve(REPO_ROOT, argLockfile);
  if (!existsSync(lockfileAbs)) {
    warn(`lockfile non trovato: ${lockfileAbs}`);
    process.exit(2);
  }

  // Directory del lockfile: cambiamo cwd li (osv-scanner su Windows non accetta
  // percorsi assoluti con drive letter per --lockfile).
  const lockfileDir = dirname(lockfileAbs);
  const lockfileBase = basename(lockfileAbs);

  // 2) Cerca osv-scanner: prima il project-local `<dir>/.trueline/bin`, poi
  //    OSV_SCANNER_PATH (se impostata), poi PATH. `dir` = directory del lockfile.
  const osvBin = resolveOsvBin(lockfileDir);

  warn(`lockfile: ${lockfileAbs}`);
  warn(`cwd invocazione: ${lockfileDir}`);
  warn(`osv-scanner: ${osvBin}`);

  // 3) Prima invocazione: "osv-scanner scan --lockfile <base> --format json --verbosity error"
  //    (flag moderni, osv-scanner >= 1.6.0).
  const argsModern = [
    'scan',
    '--lockfile',
    lockfileBase,
    '--format',
    'json',
    '--verbosity',
    'error',
  ];

  warn(`invocazione moderna: ${osvBin} ${argsModern.join(' ')}`);
  let res = runOsv(osvBin, argsModern, lockfileDir);

  // Se il sottocomando "scan" non e riconosciuto (exit 127 o stderr con "unknown command"),
  // proviamo il fallback senza sottocomando (osv-scanner < 1.6.0).
  // Nota: spawnSync imposta res.error a undefined (non null) in assenza di errori;
  // usiamo != null (loose equality) che copre sia null sia undefined.
  const usedFallback =
    res.error != null ||
    res.status === null ||
    (res.status !== 0 &&
      res.status !== 1 &&
      typeof res.stderr === 'string' &&
      /unknown command|no such command|subcommand/i.test(res.stderr));

  if (usedFallback) {
    const argsFallback = [
      '--format',
      'json',
      '--lockfile',
      lockfileBase,
    ];
    warn(`fallback (senza sottocomando): ${osvBin} ${argsFallback.join(' ')}`);
    res = runOsv(osvBin, argsFallback, lockfileDir);
  }

  // 4) Gestione dell'esito.
  if (res.error) {
    // Errore di avvio del processo (es. eseguibile non trovato).
    warn(`impossibile avviare osv-scanner: ${res.error.message}`);
    warn("verifica che osv-scanner sia nel PATH o imposta OSV_SCANNER_PATH");
    process.exit(2);
  }

  const stdout = res.stdout ?? '';
  const stderr = res.stderr ?? '';

  // Codici validi: 0 (nessuna vulnerabilita) e 1 (vulnerabilita trovate).
  // Entrambi producono JSON sullo stdout.
  const statusOk = res.status === 0 || res.status === 1;

  if (!statusOk) {
    warn(`osv-scanner ha terminato con exit ${res.status} (atteso 0 o 1)`);
    if (stderr) warn(`stderr: ${stderr.slice(0, 2000)}`);
    if (stdout) process.stdout.write(stdout);
    process.exit(res.status === null ? 2 : res.status);
  }

  // 5) Verifica che lo stdout sia JSON valido.
  const { ok: jsonOk, parsed } = tryParseJson(stdout);
  if (!jsonOk) {
    warn('stdout non contiene JSON valido');
    warn(`stdout (prime 500 char): ${stdout.slice(0, 500)}`);
    if (stderr) warn(`stderr: ${stderr.slice(0, 2000)}`);
    process.exit(2);
  }

  // 6) Emetti il JSON NATIVO di osv-scanner su stdout (invariato, senza righe extra).
  //    Usiamo il JSON riparsato per garantire output pulito (senza righe di intestazione).
  process.stdout.write(JSON.stringify(parsed, null, 2));
  process.stdout.write('\n');

  const numResults = Array.isArray(parsed?.results) ? parsed.results.length : 0;
  warn(`completato: ${numResults} risultato/i (0 vulnerabilita atteso nel banco di prova)`);

  process.exit(0);
}

// Esegui main() SOLO da CLI. Importato (es. dal test del bin-lookup) NON deve
// partire (main() farebbe process.exit su argomenti mancanti).
const __isMain = process.argv[1] && resolve(process.argv[1]) === __filename;
if (__isMain) main();

export { resolveOsvBin };
