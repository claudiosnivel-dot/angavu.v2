// run_deadcode.mjs — oracolo dead-code (03 §5.5).
//
// Esegue knip (strumento primario) con "--reporter json" sulla directory del
// progetto target e restituisce su stdout il JSON NATIVO di knip.
//
// INVOCAZIONE
//   node trueline/scripts/oracles/run_deadcode.mjs <project-dir>
//
// <project-dir> deve contenere un knip.json (o knip.config.ts) e il binario
// knip deve essere presente in <project-dir>/node_modules/.bin/knip.
//
// OUTPUT: JSON nativo di knip (struttura { issues: [...] }) emesso su stdout.
// Lo stderr di knip e passato trasparente allo stderr del processo padre.
//
// EXIT CODE: 0 se knip gira senza errori di esecuzione (anche se trova issue;
// knip esce 1 quando trova dead code — questo e normale e NON un errore).
// 1 se il tool non e trovato, la directory non esiste, o il JSON e malformato.
//
// FALLBACK: knip e lo strumento primario e basta per questo scope.
// ts-prune (deprecato, non manutenuto da 2022) e depcheck (non analizza
// export inutilizzati a livello di simbolo) sono menzionati come fallback
// teorici ma NON implementati: knip copre tutti i casi richiesti in M0–M4.
// Se knip venisse rimosso dal progetto target, il wrapper segnala l'assenza
// con un messaggio chiaro su stderr invece di eseguire silenziosamente un
// fallback meno preciso.

import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// ── Argomenti CLI ────────────────────────────────────────────────────────────
// Sintassi:
//   node run_deadcode.mjs <project-dir> [--tool=<nome>]
//
// --tool=<nome>  Seleziona il dead-code tool. Default: knip.
//                Valori supportati: knip (JS/TS, primario), vulture (Python — SP-2),
//                go-deadcode (Go — Eco-F5b), dart (Dart/Flutter — Eco-F5b).
//                Tool sconosciuto: esce con JSON vuoto + nota (mai falso verde).

const args = process.argv.slice(2);

// Estrai --tool=<nome> (flag opzionale; posizione libera dopo il primo arg)
const toolFlagArg = args.find((a) => a.startsWith('--tool='));
const toolName = toolFlagArg ? toolFlagArg.slice('--tool='.length) : 'knip';

// Filtra i flag per ottenere i positional args
const positionalArgs = args.filter((a) => !a.startsWith('--'));

if (positionalArgs.length < 1) {
  process.stderr.write(
    'uso: node run_deadcode.mjs <project-dir> [--tool=<nome>]\n' +
    'esempio: node trueline/scripts/oracles/run_deadcode.mjs eval/reference-app\n'
  );
  process.exit(1);
}

const projectDir = resolve(positionalArgs[0]);

// ── Dispatch: tool sconosciuto → JSON vuoto + nota (mai falso verde) ─────────
// I tool concreti supportati sono knip (JS/TS, primario) e vulture (Python, SP-2).
// Un tool non supportato non deve mai sembrare "nessun dead code trovato" —
// per questo si emette una nota esplicita accanto all'array vuoto.

const SUPPORTED_TOOLS = new Set(['knip', 'vulture', 'go-deadcode', 'dart']);

if (!SUPPORTED_TOOLS.has(toolName)) {
  const safeNote = `tool ${toolName} non supportato`;
  process.stdout.write(
    JSON.stringify({ issues: [], note: safeNote }, null, 2) + '\n'
  );
  process.exit(0);
}

if (!existsSync(projectDir)) {
  process.stderr.write(`ERRORE: la directory del progetto non esiste: ${projectDir}\n`);
  process.exit(1);
}

// ── Ramo vulture (Python — SP-2) ─────────────────────────────────────────────
// vulture analizza l'AST Python e stampa su stdout una riga per simbolo morto:
//   <path>:<line>: unused <type> '<name>' (<NN>% confidence)
// Le issue trovate sono INFORMAZIONE, non un errore: vulture esce 3 quando trova
// dead code, 0 quando pulito — NON usiamo l'exit code per il verdetto, ma il
// parsing dello stdout. EXIT 1 solo se il processo non parte (python assente /
// spawn error). Emettiamo { tool: "vulture", issues: [...] } (+ note se vuoto).

if (toolName === 'vulture') {
  // Eseguiamo "python -m vulture <project-dir>" (NON il bare `vulture`, che
  // potrebbe non essere sul PATH). cwd = projectDir per path relativi puliti.
  const vultureRes = spawnSync('python', ['-m', 'vulture', projectDir], {
    encoding: 'utf8',
    timeout: 120_000,
    env: process.env,
  });

  // Spawn error reale (python assente, ecc.) → EXIT 1.
  if (vultureRes.error) {
    process.stderr.write(
      `ERRORE: impossibile avviare vulture: ${vultureRes.error.message}\n` +
      'Verificare che python sia installato e che il modulo vulture sia presente (pip install vulture).\n'
    );
    process.exit(1);
  }

  // Propaga lo stderr di vulture (warning di sintassi, ecc.) al padre.
  if (vultureRes.stderr) {
    process.stderr.write(vultureRes.stderr);
  }

  // python introvabile dal launcher: spawnSync NON pone result.error ma esce con
  // status 9009 (Windows) e nessuno stdout. Distinguiamo dal "clean" (0 issue,
  // status 0, nessuno stdout) controllando lo status quando lo stdout e vuoto.
  const rawVulture = (vultureRes.stdout || '');
  if (!rawVulture.trim() && vultureRes.status !== 0 && vultureRes.status !== 3) {
    process.stderr.write(
      `ERRORE: vulture non e stato eseguito correttamente (exit ${vultureRes.status}, nessuno stdout).\n` +
      'Verificare che "python -m vulture" sia disponibile.\n'
    );
    process.exit(1);
  }

  // Parsing: una issue per riga.
  //   path:line: unused <type> '<name>' (NN% confidence)
  // Regex robusta: cattura file, line, type (parola/e dopo "unused"), name e
  // confidence. Tolleriamo path con ':' (es. drive Windows "C:") ancorando
  // sull'ultimo ":<digits>: unused" tramite componenti non-greedy mirati.
  const lineRe = /^(.*?):(\d+):\s*unused\s+([a-zA-Z ]+?)\s+'([^']+)'\s*\((\d+)%\s*confidence\)\s*$/;

  const issues = [];
  for (const rawLine of rawVulture.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    const m = lineRe.exec(line);
    if (!m) continue; // righe non conformi: ignorate (robustezza)
    issues.push({
      file: m[1],
      line: Number(m[2]),
      type: m[3].trim(),
      name: m[4],
      confidence: Number(m[5]),
    });
  }

  const out = { tool: 'vulture', issues };
  if (issues.length === 0) {
    out.note = 'vulture non ha trovato dead-code (o nessuna riga parsabile)';
  }

  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  // EXIT 0: vulture e stato eseguito e lo stdout e parsabile. Le issue sono
  // informazione, non errore — il chiamante decide se escalare.
  process.exit(0);
}

// ── Ramo go-deadcode (Go — Eco-F5b) ───────────────────────────────────────────
// 'deadcode' (golang.org/x/tools/cmd/deadcode) esegue l'analisi di
// raggiungibilita sul modulo Go; con -json emette un ARRAY di pacchetti, ognuno
// con i Funcs irraggiungibili:
//   [ { "Name": "<pkg>", "Path": "<importpath>",
//       "Funcs": [ { "Name": "<func>", "Position": {File,Line,Col}, ... } ] } ]
// Come vulture/knip, le funzioni morte sono INFORMAZIONE: deadcode esce 0 a
// prescindere. EXIT 1 SOLO se il processo non parte (binario assente / spawn
// error) o se lo stdout non e JSON parsabile (mai un falso vuoto). Emettiamo
// { tool:'go-deadcode', issues:[{ symbol, file, line, kind:'unused-function' }] }.
if (toolName === 'go-deadcode') {
  const res = spawnSync('deadcode', ['-json', './...'], {
    cwd: projectDir,
    encoding: 'utf8',
    timeout: 120_000,
    env: process.env,
    maxBuffer: 32 * 1024 * 1024,
  });

  // Spawn error reale (binario deadcode assente, ecc.) → EXIT 1 onesto.
  if (res.error) {
    process.stderr.write(
      `ERRORE: impossibile avviare deadcode: ${res.error.message}\n` +
      'Verificare che il binario "deadcode" (golang.org/x/tools/cmd/deadcode) sia sul PATH.\n'
    );
    process.exit(1);
  }
  // Propaga lo stderr di deadcode (diagnostica di build, ecc.) al padre.
  if (res.stderr) process.stderr.write(res.stderr);

  const raw = (res.stdout || '').trim();
  // Output vuoto con status != 0 = errore reale (es. modulo non compilabile),
  // NON "nessun dead code". Distinguiamo come per vulture (mai falso vuoto).
  if (!raw && res.status !== 0) {
    process.stderr.write(
      `ERRORE: deadcode non ha prodotto output (exit ${res.status}).\n` +
      'Verificare che la directory sia un modulo Go valido e compilabile.\n'
    );
    process.exit(1);
  }

  let parsed;
  try {
    parsed = JSON.parse(raw || '[]');
  } catch (err) {
    process.stderr.write(
      `ERRORE: l'output di deadcode non e JSON valido: ${err.message}\n` +
      `Output ricevuto (prime 500 car.): ${raw.slice(0, 500)}\n`
    );
    process.exit(1);
  }

  const issues = [];
  if (Array.isArray(parsed)) {
    for (const pkg of parsed) {
      const funcs = pkg && Array.isArray(pkg.Funcs) ? pkg.Funcs : [];
      for (const fn of funcs) {
        const pos = (fn && fn.Position) || {};
        const lineNo = Number(pos.Line);
        issues.push({
          symbol: fn && fn.Name,
          file: pos.File || '',
          line: Number.isInteger(lineNo) ? lineNo : 0,
          kind: 'unused-function',
        });
      }
    }
  }

  const out = { tool: 'go-deadcode', issues };
  if (issues.length === 0) {
    out.note = 'go-deadcode non ha trovato funzioni irraggiungibili';
  }
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  process.exit(0);
}

// ── Ramo dart (Dart/Flutter — Eco-F5b) ────────────────────────────────────────
// 'dart analyze --format=machine' emette una riga per diagnostica nel formato
// pipe-delimitato a 8 campi:
//   SEVERITY|TYPE|CODE|FILE|LINE|COL|LENGTH|MESSAGE
// I '|' e i '\' DENTRO i campi sono ESCAPATI con '\' (es. path Windows
// "C:\\Users\\.."). Filtriamo le diagnostiche dead-code (code 'unused_element' /
// 'dead_code', case-insensitive) e ricaviamo il simbolo dal messaggio
// ("The declaration '<name>' isn't referenced."). Come vulture, le diagnostiche
// sono INFORMAZIONE: dart esce 1/2/3 quando trova problemi (NON un errore
// d'esecuzione), 0 quando pulito → usiamo lo stdout, mai l'exit code. EXIT 1 SOLO
// se il processo non parte (spawn error). Emettiamo { tool:'dart', issues:[...] }.
if (toolName === 'dart') {
  // Nessun path-arg: dart analizza la cwd. Cosi evitiamo problemi di quoting con
  // path che contengono spazi quando serve il fallback con shell (Windows .bat).
  const dartArgs = ['analyze', '--format=machine'];
  const dartOpts = {
    cwd: projectDir,
    encoding: 'utf8',
    timeout: 180_000,
    env: process.env,
    maxBuffer: 32 * 1024 * 1024,
  };
  let res = spawnSync('dart', dartArgs, dartOpts);
  // Su Windows 'dart' e spesso un .bat che Node rifiuta di eseguire senza shell
  // (ENOENT). Riproviamo via shell: se dart e davvero assente, anche il retry
  // fallisce (res.error) → EXIT 1 onesto. Mai un falso vuoto.
  if (res.error && res.error.code === 'ENOENT') {
    res = spawnSync('dart', dartArgs, { ...dartOpts, shell: true });
  }

  if (res.error) {
    process.stderr.write(
      `ERRORE: impossibile avviare dart: ${res.error.message}\n` +
      'Verificare che il Dart SDK sia installato e che "dart" sia sul PATH.\n'
    );
    process.exit(1);
  }
  if (res.stderr) process.stderr.write(res.stderr);

  const rawDart = res.stdout || '';
  // Processo terminato senza output e senza status (kill/timeout) = errore onesto.
  if (!rawDart.trim() && res.status === null) {
    process.stderr.write('ERRORE: dart analyze non ha prodotto output (processo terminato).\n');
    process.exit(1);
  }

  const issues = [];
  for (const rawLine of rawDart.split(/\r?\n/)) {
    if (!rawLine.trim()) continue;
    const fields = splitMachineLine(rawLine);
    if (fields.length < 8) continue; // righe non conformi: ignorate (robustezza)
    const code = String(fields[2] || '').toLowerCase();
    if (code !== 'unused_element' && code !== 'dead_code') continue;
    const lineNo = Number(fields[4]);
    const message = fields.slice(7).join('|');
    issues.push({
      symbol: extractDartSymbol(message),
      file: fields[3],
      line: Number.isInteger(lineNo) ? lineNo : 0,
      kind: code === 'dead_code' ? 'dead-code' : 'unused-element',
      code,
      message,
    });
  }

  const out = { tool: 'dart', issues };
  if (issues.length === 0) {
    out.note = 'dart analyze non ha trovato diagnostiche dead-code (unused_element/dead_code)';
  }
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  process.exit(0);
}

// Divide una riga del formato machine di dart sui '|' NON escapati, eseguendo
// l'unescape inline ('\\'->'\', '\|'->'|', '\n'/'\r'/'\t' -> whitespace): cosi i
// path Windows ("C:\\Users\\..") tornano con un solo backslash e i campi col '|'
// interno restano integri.
function splitMachineLine(line) {
  const fields = [];
  let cur = '';
  for (let i = 0; i < line.length; i += 1) {
    const c = line[i];
    if (c === '\\' && i + 1 < line.length) {
      const n = line[i + 1];
      cur += n === 'n' ? '\n' : n === 'r' ? '\r' : n === 't' ? '\t' : n;
      i += 1;
      continue;
    }
    if (c === '|') { fields.push(cur); cur = ''; continue; }
    cur += c;
  }
  fields.push(cur);
  return fields;
}

// Estrae il nome del simbolo dal messaggio dart, es.
//   "The declaration '_unusedHelper' isn't referenced." -> "_unusedHelper"
// Prende il primo identificatore fra apici (singoli/doppi/backtick). undefined se
// assente (es. messaggi 'dead_code' senza nome di simbolo).
function extractDartSymbol(message) {
  const m = /[`'"]([A-Za-z_$][\w$]*)[`'"]/.exec(String(message || ''));
  return m ? m[1] : undefined;
}

// ── Individua il binario knip ────────────────────────────────────────────────
// Cerca prima in <project-dir>/node_modules/.bin/knip (installazione locale al
// progetto target, preferita per riproducibilita).

// Su Windows, lo shebang di "knip" in node_modules/.bin non funziona
// direttamente con spawnSync. Utilizziamo il file JS di knip direttamente.
const knipBinSh   = join(projectDir, 'node_modules', '.bin', 'knip');
const knipBinJs   = join(projectDir, 'node_modules', 'knip', 'bin', 'knip.js');

let knipCmd   = 'node';
let knipArgs;

if (existsSync(knipBinJs)) {
  // Percorso stabile: node <knip.js> [flags]
  knipArgs = [knipBinJs, '--reporter', 'json'];
} else if (existsSync(knipBinSh)) {
  // Fallback: prova lo sh-wrapper (funziona su Linux/macOS)
  knipCmd = knipBinSh;
  knipArgs = ['--reporter', 'json'];
} else {
  process.stderr.write(
    `ERRORE: knip non trovato in ${projectDir}/node_modules/knip/bin/knip.js\n` +
    'Assicurarsi che knip sia installato come dipendenza locale del progetto target.\n' +
    'Fallback disponibili NON implementati: ts-prune (deprecato), depcheck (non analizza export).\n'
  );
  process.exit(1);
}

// ── Esegui knip ──────────────────────────────────────────────────────────────
// Flag fissi per riproducibilita: --reporter json.
// cwd = projectDir (knip legge knip.json dalla directory di lavoro).

const result = spawnSync(knipCmd, knipArgs, {
  cwd: projectDir,
  encoding: 'utf8',
  // knip puo impiegare qualche secondo su codebase grandi
  timeout: 120_000,
  // Passa le variabili d'ambiente del processo padre (PATH, NODE_PATH, ecc.)
  env: process.env,
});

// ── Gestione errori di avvio ─────────────────────────────────────────────────

if (result.error) {
  process.stderr.write(`ERRORE: impossibile avviare knip: ${result.error.message}\n`);
  process.exit(1);
}

// Propaga stderr di knip (avvisi, progress) allo stderr del padre
if (result.stderr) {
  process.stderr.write(result.stderr);
}

// ── Valida che l'output sia JSON ben formato ──────────────────────────────────
// knip esce con 1 quando trova issue — e NORMALE. L'unico modo per distinguere
// un'uscita 1 "legittima" da un errore reale e parsare stdout come JSON.
// Se stdout e vuoto o non parsabile -> errore reale.

const rawOutput = (result.stdout || '').trim();

if (!rawOutput) {
  process.stderr.write(
    `ERRORE: knip non ha emesso nulla su stdout (exit ${result.status}).\n` +
    'Verificare che knip.json esista nella directory target e che il progetto sia valido.\n'
  );
  process.exit(1);
}

let parsed;
try {
  parsed = JSON.parse(rawOutput);
} catch (err) {
  process.stderr.write(
    `ERRORE: l'output di knip non e JSON valido: ${err.message}\n` +
    `Output ricevuto (prime 500 car.): ${rawOutput.slice(0, 500)}\n`
  );
  process.exit(1);
}

// ── Emetti il JSON nativo su stdout ──────────────────────────────────────────
// Il chiamante (adapter, harness, ecc.) parsa questo JSON — non l'exit code.

process.stdout.write(JSON.stringify(parsed, null, 2) + '\n');

// Esce sempre con 0 se il JSON e valido (il dead code trovato e informazione,
// non un errore del tool). Il chiamante decide se escalare in base al contenuto.
process.exit(0);
