#!/usr/bin/env node
// run_semgrep.mjs — wrapper dell'oracolo Semgrep VIA DOCKER (03 §5.1).
//
// Node ESM, solo moduli built-in (fs, path, child_process, os, url): nessun
// npm install, nessuna dipendenza di rete oltre l'immagine docker gia presente.
//
// COSA FA
//   Prende la directory di un progetto (default: eval/reference-app), monta
//   quella dir come /src dentro il container Semgrep, esegue `semgrep scan` col
//   ruleset AI curato (in M0 il PLACEHOLDER, vedi sotto) ed emette su stdout il
//   JSON NATIVO di Semgrep (campo `results`, eventualmente vuoto). La
//   normalizzazione native->finding (03 §6, 04) e a valle, nell'adapter.
//
// INVOCAZIONE DOCKER (verificata su Windows / Git-Bash)
//   MSYS_NO_PATHCONV=1 docker run --rm \
//     -v "//c/Users/.../eval/reference-app:/src" \
//     semgrep/semgrep:latest \
//     semgrep scan --config /src/<rules-rel> --json --metrics=off /src .
//   MSYS_NO_PATHCONV=1 evita che MSYS riscriva i path "/src" lato Windows.
//   Il mount Windows usa la forma "//c/Users/..." (doppio slash iniziale).
//
// RULESET (PLACEHOLDER in M0; curato in M4 — 07 §4)
//   Il ruleset vive tracciato in
//     trueline/references/oracles/semgrep-ai-ruleset/placeholder.yml
//   Poiche il container vede solo /src (= la dir progetto, che e gitignorata),
//   lo script COPIA il ruleset in una sottocartella effimera dentro la dir
//   progetto (.trueline/semgrep-rules/, gitignorata) cosi da poterlo montare
//   come /src/.trueline/semgrep-rules/<file>. La cartella effimera viene
//   ripulita a fine run.
//
// 2do ARG POSIZIONALE OPZIONALE [rulesetPath] (SP-1 / T2.0 — additivo)
//   run_semgrep.mjs <projectDir> [rulesetPath]
//   - ASSENTE  -> comportamento IDENTICO a oggi: ruleset condiviso
//                 trueline-ai-ruleset.yml (default v1 INVARIATO).
//   - FILE .yml -> come oggi ma su QUEL file (copiato nella dir effimera).
//   - DIR       -> copia TUTTI i .yml/.yaml della dir nella dir effimera e
//                 punta --config alla dir (semgrep aggrega le regole). Serve ai
//                 pack manifest-driven che portano un ruleset per-cartella
//                 (es. references/ecosystems/postgres-jsts/ruleset/, SP-1).
//   Il path e' relativo alla repo root o assoluto. Se non esiste -> exit 2
//   (errore dichiarato, MAI un falso verde / report 0-finding spacciato).
//   Mount Windows (//c/...), MSYS_NO_PATHCONV=1 e cleanup nel finally restano
//   invariati: la copia effimera vive comunque sotto /src.
//
// SMOKE TEST (gate M0)
//   Il gate verifica SOLO che il wrapper giri ed emetta JSON Semgrep valido.
//   La DETECTION di S6 (injection) e S7 (authz) e DIFFERITA a M4 e NON e parte
//   del gate M0 (10 §3; vedi registry expected/registry.json).

import { spawnSync } from 'node:child_process';
import {
  existsSync,
  statSync,
  readdirSync,
  mkdirSync,
  copyFileSync,
  rmSync,
} from 'node:fs';
import { resolve, dirname, basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Radice del repo: trueline/scripts/oracles -> repo root e 3 livelli sopra.
const REPO_ROOT = resolve(__dirname, '..', '..', '..');

// Immagine Semgrep PINNATA (semgrep 1.165.0). Non usare un tag mobile diverso:
// la riproducibilita dell'oracolo dipende dal pin (L-COL-002).
const SEMGREP_IMAGE = 'semgrep/semgrep:latest';

// Ruleset AI curato (07 §4), tracciato nel repo. In M0 era il placeholder.yml
// (solo smoke test); da M4 e' il ruleset CURATO trueline-ai-ruleset.yml, forma
// eseguibile dei pattern vietati (07 §4: secrets/injection/authz/crypto/sink).
const RULESET_SRC = resolve(
  REPO_ROOT,
  'trueline',
  'references',
  'oracles',
  'semgrep-ai-ruleset',
  'trueline-ai-ruleset.yml',
);

// Sottocartella EFFIMERA (gitignorata: .trueline/) dentro la dir progetto in
// cui copiare il ruleset, cosi da montarlo sotto /src.
const EPHEMERAL_ROOT = '.trueline';
const EPHEMERAL_RULES_SUBDIR = join(EPHEMERAL_ROOT, 'semgrep-rules');

/**
 * rmSync con piccolo retry/backoff BLOCCANTE deterministico (Atomics.wait, niente
 * timer/random): su Windows una dir appena usata da un figlio (docker mount,
 * copyFileSync) puo' restare momentaneamente LOCKED -> EPERM/EBUSY spurio. Il
 * retry assorbe il lock transitorio; un fallimento reale e persistente riemerge.
 * Stesso pattern di verify_workspace.mjs (rmWithRetry) per coerenza.
 */
function rmWithRetry(target, attempts = 5) {
  let lastErr = null;
  for (let i = 0; i < attempts; i += 1) {
    try {
      rmSync(target, { recursive: true, force: true, maxRetries: 3, retryDelay: 50 });
      return;
    } catch (e) {
      lastErr = e;
      if (i < attempts - 1) {
        try { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50 * (i + 1)); }
        catch { /* Atomics non disponibile: prosegui senza attesa */ }
      }
    }
  }
  if (lastErr) throw lastErr;
}

/**
 * Pota la radice .trueline/ SE ora e' vuota (nessun altro stato di tooling
 * trueline). Cosi' la rimozione della NOSTRA sottocartella semgrep-rules non
 * lascia un GUSCIO vuoto che avveleni i gate m4/m5 ("nessun residuo .trueline/").
 * Mirror di destroyVerifyWorkspace (verify_workspace.mjs): prune-if-empty,
 * best-effort, MAI distruttivo verso stato altrui (se .trueline/ contiene
 * ancora qualcosa, la lasciamo intatta).
 */
function pruneEmptyEphemeralRoot(ephemeralRootAbs) {
  try {
    if (existsSync(ephemeralRootAbs) && readdirSync(ephemeralRootAbs).length === 0) {
      rmWithRetry(ephemeralRootAbs);
    }
  } catch { /* best-effort: radice non vuota o lock concorrente non e' un errore */ }
}

/**
 * Converte un percorso assoluto Windows ("C:\\Users\\..." o "C:/Users/...")
 * nella forma di mount accettata da docker su Git-Bash: "//c/Users/...".
 * Se il percorso e gia in stile POSIX (inizia con "/"), lo restituisce com'e.
 */
function toDockerMountPath(absPath) {
  // Normalizza i separatori a "/".
  const slashed = absPath.replace(/\\/g, '/');
  // Drive letter Windows (es. "C:/Users/...") -> "//c/Users/...".
  const m = /^([A-Za-z]):\/(.*)$/.exec(slashed);
  if (m) {
    const drive = m[1].toLowerCase();
    const rest = m[2];
    return `//${drive}/${rest}`;
  }
  // Gia POSIX.
  return slashed;
}

/** Stampa un messaggio diagnostico su stderr (lo stdout resta JSON puro). */
function warn(msg) {
  process.stderr.write(`[run_semgrep] ${msg}\n`);
}

/** Elenca i file .yml/.yaml (NON ricorsivo) di una dir (best-effort, ordinati). */
function listYamlFiles(dir) {
  let entries;
  try { entries = readdirSync(dir); } catch { return []; }
  return entries
    .filter((e) => /\.ya?ml$/i.test(e))
    .map((e) => join(dir, e))
    .filter((p) => { try { return statSync(p).isFile(); } catch { return false; } })
    .sort();
}

/**
 * Risolve la SORGENTE del ruleset dal 2do arg posizionale opzionale [rulesetPath].
 * Ritorna { files: [absPath...], isDir, srcAbs } oppure null se il path dato non
 * esiste (il chiamante esce 2). Senza arg -> il ruleset condiviso (default v1).
 */
function resolveRulesetSrc(argRuleset) {
  if (argRuleset === undefined || argRuleset === null || argRuleset === '') {
    // Default INVARIATO: il singolo file condiviso trueline-ai-ruleset.yml.
    return { files: [RULESET_SRC], isDir: false, srcAbs: RULESET_SRC };
  }
  const srcAbs = resolve(REPO_ROOT, argRuleset);
  if (!existsSync(srcAbs)) return null;
  let st;
  try { st = statSync(srcAbs); } catch { return null; }
  if (st.isDirectory()) {
    const files = listYamlFiles(srcAbs);
    return { files, isDir: true, srcAbs };
  }
  // File singolo (qualsiasi .yml/.yaml dato esplicitamente).
  return { files: [srcAbs], isDir: false, srcAbs };
}

function main() {
  // 1) Risolvi la dir progetto (arg posizionale; default reference-app).
  const argProject = process.argv[2] ?? 'eval/reference-app';
  const projectDir = resolve(REPO_ROOT, argProject);

  if (!existsSync(projectDir)) {
    warn(`directory progetto non trovata: ${projectDir}`);
    process.exit(2);
  }

  // 1b) Risolvi la SORGENTE del ruleset dal 2do arg posizionale opzionale.
  //     Assente -> default condiviso (v1 invariato); file -> quel file; dir ->
  //     tutti i .yml/.yaml della dir. Path inesistente -> exit 2 (no falso verde).
  const argRuleset = process.argv[3];
  const rs = resolveRulesetSrc(argRuleset);
  if (rs === null) {
    warn(`ruleset non trovato: ${resolve(REPO_ROOT, argRuleset)}`);
    process.exit(2);
  }
  if (rs.files.length === 0) {
    warn(`ruleset vuoto (nessun .yml/.yaml): ${rs.srcAbs}`);
    process.exit(2);
  }
  for (const f of rs.files) {
    if (!existsSync(f)) { warn(`ruleset non trovato: ${f}`); process.exit(2); }
  }

  // 2) Copia effimera del ruleset dentro la dir progetto (per montarlo in /src).
  const ephemeralRootAbs = resolve(projectDir, EPHEMERAL_ROOT);
  const ephemeralDirAbs = resolve(projectDir, EPHEMERAL_RULES_SUBDIR);
  const ephemeralSubdirPosix = EPHEMERAL_RULES_SUBDIR.replace(/\\/g, '/');
  // --config COME VISTO nel container:
  //   - file singolo -> /src/.trueline/semgrep-rules/<file>
  //   - dir          -> /src/.trueline/semgrep-rules  (semgrep aggrega i .yml)
  const containerRulePath = rs.isDir
    ? `/src/${ephemeralSubdirPosix}`
    : `/src/${ephemeralSubdirPosix}/${basename(rs.files[0])}`;

  // SWEEP DEGLI ORFANI ALL'AVVIO: un run_semgrep KILLATO (SIGKILL durante il loop)
  // non raggiunge il proprio finally e lascia la NOSTRA sottocartella
  // .trueline/semgrep-rules/ orfana — che (con la radice .trueline/) avvelena
  // l'asserzione "nessun residuo .trueline/" dei gate m4/m5. Per definizione un
  // processo killato non puo' ripulirsi da solo: spazziamo qui, all'AVVIO del run
  // successivo, SOLO la nostra sottocartella (mai stato altrui dentro .trueline/).
  // Idempotente; nessun effetto se non c'e' nulla. Stesso spirito dello sweep
  // cleanupAllVerifyWorkspaces() che m4/m5 fanno per eval/.tmp-verify.
  if (existsSync(ephemeralDirAbs)) {
    try { rmWithRetry(ephemeralDirAbs); } catch { /* best-effort: gitignorata */ }
  }

  // Se .trueline/ non esisteva prima del run, e nostra e va rimossa intera a
  // fine run; se preesisteva (altra tooling trueline), rimuoviamo la nostra
  // sottocartella semgrep-rules e POI potiamo la radice SE rimasta vuota (cosi'
  // non lasciamo un guscio .trueline/ vuoto) — senza mai distruggere stato altrui
  // (se .trueline/ contiene altro, resta intatta). Rivalutato DOPO lo sweep sopra.
  const ephemeralRootPreexisted = existsSync(ephemeralRootAbs);

  try {
    mkdirSync(ephemeralDirAbs, { recursive: true });
    for (const f of rs.files) copyFileSync(f, join(ephemeralDirAbs, basename(f)));

    // 3) Costruisci il mount Windows ("//c/Users/...").
    const mountSrc = toDockerMountPath(projectDir);

    // 4) Esegui docker. MSYS_NO_PATHCONV=1 evita la riscrittura dei path POSIX.
    const dockerArgs = [
      'run',
      '--rm',
      '-v',
      `${mountSrc}:/src`,
      SEMGREP_IMAGE,
      'semgrep',
      'scan',
      '--config',
      containerRulePath,
      '--json',
      '--metrics=off',
      '/src',
    ];

    warn(`docker run ${SEMGREP_IMAGE} (mount ${mountSrc} -> /src, config ${containerRulePath})`);

    const res = spawnSync('docker', dockerArgs, {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024, // l'output JSON puo essere ampio
      env: { ...process.env, MSYS_NO_PATHCONV: '1' },
    });

    if (res.error) {
      warn(`impossibile avviare docker: ${res.error.message}`);
      return 2;
    }

    const stdout = res.stdout ?? '';
    const stderr = res.stderr ?? '';

    // Semgrep esce con codice 0 (nessun finding) oppure 1 (finding trovati):
    // entrambi sono esiti VALIDI con JSON sullo stdout. Codici >1 sono errori.
    if (res.status !== 0 && res.status !== 1) {
      warn(`semgrep ha terminato con exit ${res.status}`);
      if (stderr) warn(`stderr: ${stderr.slice(0, 2000)}`);
      // Emetti comunque lo stdout (se presente) per il debug, ma fallisci.
      if (stdout) process.stdout.write(stdout);
      return res.status === null ? 2 : res.status;
    }

    // 5) Emetti il JSON NATIVO di Semgrep sullo stdout, invariato.
    process.stdout.write(stdout);
    if (!stdout.trim()) {
      warn('stdout vuoto: nessun JSON emesso da semgrep');
      if (stderr) warn(`stderr: ${stderr.slice(0, 2000)}`);
      return 2;
    }
    return 0;
  } finally {
    // 6) Pulizia della copia effimera del ruleset. Eseguita SEMPRE prima di
    //    uscire: la cleanup vive nel finally e l'exit avviene a valle di main(),
    //    perche process.exit() interromperebbe il finally se chiamato qui.
    //    - Se .trueline/ NON preesisteva, e' interamente nostra -> rimossa tutta.
    //    - Se preesisteva (stato di altra tooling trueline), rimuoviamo SOLO la
    //      nostra sottocartella semgrep-rules e POI potiamo la radice .trueline/
    //      SE rimasta vuota (niente guscio vuoto residuo, ma stato altrui salvo).
    //    rmWithRetry assorbe un EPERM/EBUSY transitorio su Windows (handle non
    //    ancora rilasciato dal docker/copyFileSync appena terminato).
    try {
      if (ephemeralRootPreexisted) {
        rmWithRetry(ephemeralDirAbs);
        pruneEmptyEphemeralRoot(ephemeralRootAbs);
      } else {
        rmWithRetry(ephemeralRootAbs);
      }
    } catch {
      // best-effort: la cartella e comunque gitignorata (.trueline/).
    }
  }
}

// L'exit avviene FUORI da main(): cosi il `finally` di cleanup gira prima che
// il processo termini (process.exit() salterebbe i finally pendenti).
const exitCode = main();
process.exit(exitCode);
