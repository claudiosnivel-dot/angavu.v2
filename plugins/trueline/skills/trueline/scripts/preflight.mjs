#!/usr/bin/env node
// preflight.mjs — rilevazione degli oracoli esterni e proposta di install (03 §4, 09 §6).
//
// Node ESM, SOLO moduli built-in (child_process, fs, path, os, url): nessun npm
// install, nessuna dipendenza di rete. Viaggia nel .skill (02 §4, 09 §2).
//
// COSA FA
//   Per ciascun tool esterno (semgrep via docker, gitleaks, osv-scanner, knip):
//     1. Rileva la PRESENZA del binario/canale di esecuzione.
//     2. Confronta la versione rilevata contro un MINIMO PINNATO.
//     3. Se il tool è assente o sotto versione, PROPONE il comando di install
//        adatto all'OS rilevato — non lo esegue (gate umano, L-COL-005).
//     4. Se il tool non ha un canale di install disponibile sull'OS corrente,
//        lo dichiara NON INSTALLABILE e il controllo DEGRADA a "not-run"
//        (mai un verde finto, L-COL-006).
//
//   rls_check NON è in questa tabella: è il nostro unico oracolo custom,
//   viaggia con la skill, dipende solo dal runtime Node/JS. Sempre disponibile.
//
// STRUTTURA JSON PER TOOL (--json)
//   {
//     "tool": "<nome>",
//     "channel": "<canale>",        // "docker" | "go-bin" | "npx" | "path" | "none"
//     "present": true|false,        // il tool è rilevabile ed eseguibile
//     "version": "<x.y.z>"|null,    // versione rilevata (null se non rilevabile)
//     "version_ok": true|false,     // version >= MINIMUM (false se present=false)
//     "installable": true|false,    // esiste un canale di install sull'OS corrente
//     "install_cmd": "<cmd>"|null,  // comando PROPOSTO (null se non installabile)
//     "status": "ok"|"missing"|"version-low"|"non-installable",
//     "note": "<stringa leggibile>"
//   }
//
// SEMANTICA DI "status"
//   ok              → presente E versione >= minimo.
//   missing         → binario assente; installabile → installa con install_cmd.
//   version-low     → presente ma versione < minimo; aggiorna con install_cmd.
//   non-installable → assente E nessun canale di install sull'OS corrente:
//                     il controllo che dipende da questo tool DEGRADA a "not-run"
//                     (L-COL-006 — mai un verde finto; l'assenza è dichiarata).
//
// DETERMINISMO (L-COL-002): il risultato dipende SOLO dall'output dei comandi
// di rilevazione, mai da un parere del modello.
//
// USO
//   node trueline/scripts/preflight.mjs [<project-dir>]         # report umano, exit 0/1
//   node trueline/scripts/preflight.mjs --json [<project-dir>]  # JSON su stdout, exit 0
//   node trueline/scripts/preflight.mjs --json --simulate-missing=gitleaks  # self-test
//   node trueline/scripts/preflight.mjs --install              # propone + installa SOLO
//                                                              # col consenso (TTY: y/N)
//   node trueline/scripts/preflight.mjs --install --yes        # consenso esplicito dato
//   node trueline/scripts/preflight.mjs --install --yes --dry-run  # mostra senza eseguire
//   node trueline/scripts/preflight.mjs --install --yes --only=gitleaks  # un solo tool

import { spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import { existsSync, readFileSync, writeFileSync, mkdirSync, mkdtempSync, chmodSync, copyFileSync } from 'node:fs';
import { join, delimiter, resolve, dirname } from 'node:path';
import { homedir, platform, tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import https from 'node:https';
import http from 'node:http';

const __dirname = dirname(fileURLToPath(import.meta.url));

// --- Argomenti CLI -----------------------------------------------------------
const argv = process.argv.slice(2);
const JSON_MODE = argv.includes('--json');

// Strumento da simulare come mancante (self-test / gate di eval).
const SIMULATE_MISSING_ARG = argv.find((a) => a.startsWith('--simulate-missing='));
const SIMULATE_MISSING = SIMULATE_MISSING_ARG
  ? SIMULATE_MISSING_ARG.replace('--simulate-missing=', '').toLowerCase()
  : null;

// Argomento posizionale: directory del progetto target (per trovare knip locale).
const PROJECT_DIR_ARG = argv.find((a) => !a.startsWith('--')) || null;

// --- Flag di install CONSENT-GATED (09 §6, L-COL-005) ------------------------
// La skill PROPONE sempre il comando; lo ESEGUE solo col consenso ESPLICITO,
// MAI in autonomia. (--install vale nel flusso report umano/agente, non con --json.)
//   --install      dopo la rilevazione, tenta di soddisfare i tool mancanti/
//                  sotto-versione INSTALLABILI — solo col consenso esplicito.
//   --yes | -y     consenso esplicito non-interattivo (es. l'agente lo passa DOPO
//                  che l'utente ha approvato in chat). Senza, e con stdin NON-TTY,
//                  NON installa: salta e lo dichiara (mai un install silenzioso).
//   --dry-run      mostra i comandi che ESEGUIREBBE (consenso permettendo) senza
//                  eseguirli. NON aggira il consenso.
//   --only=<tool>  limita l'install a un solo tool (semgrep|gitleaks|osv-scanner|knip).
const INSTALL_MODE = argv.includes('--install');
const ASSUME_YES = argv.includes('--yes') || argv.includes('-y');
const DRY_RUN = argv.includes('--dry-run');
const ONLY_ARG = argv.find((a) => a.startsWith('--only='));
const ONLY_TOOL = ONLY_ARG ? ONLY_ARG.replace('--only=', '').toLowerCase() : null;

// --- Target dell'install (Fase 1, Task 3) ------------------------------------
//   --target=project  (DEFAULT) scarica i binary-release project-local in
//                      <project>/.trueline/bin/ (additivo, nessuna scrittura globale).
//   --target=global   ripristina il comportamento storico: install via il canale
//                      di sistema (go install / brew / docker / npm i -D ...).
// Senza --yes e su un TTY, il consenso viene chiesto per tool [project/global/skip].
const TARGET_ARG = argv.find((a) => a.startsWith('--target='));
const TARGET = (TARGET_ARG && TARGET_ARG.replace('--target=', '').toLowerCase() === 'global')
  ? 'global'
  : 'project';

/**
 * Directory project-local dove la skill scarica i binary-release.
 * @param {string} [projectDir] directory del progetto (default: cwd corrente).
 * @returns {string} '<projectDir>/.trueline/bin'
 */
function projectBinDir(projectDir) {
  return join(resolve(projectDir || process.cwd()), '.trueline', 'bin');
}

// --- Costanti di piattaforma -------------------------------------------------
const IS_WIN = platform() === 'win32';
const IS_MAC = platform() === 'darwin';
const IS_LINUX = platform() === 'linux';

// go/bin dove vivono gitleaks e osv-scanner su questa macchina.
// Su Windows usiamo il percorso noto (go in USERPROFILE\go\bin);
// su POSIX usiamo $HOME/go/bin (go install standard).
const GO_BIN = IS_WIN
  ? join(process.env.USERPROFILE || 'C:/Users/claud', 'go', 'bin')
  : join(homedir(), 'go', 'bin');

// PATH arricchito col go/bin (come negli altri wrapper della skill).
const ENV_WITH_GOBIN = {
  ...process.env,
  PATH: `${process.env.PATH || ''}${delimiter}${GO_BIN}`,
};

// --- Versioni MINIME PINNATE -------------------------------------------------
// Valori pin basati sulle feature usate nei wrapper (03 §4):
//   semgrep  1.60.0 → --metrics=off stabile + output JSON affidabile.
//   gitleaks 8.18.0 → --report-path - (stdout) + subcomando git per la history.
//   osv-scanner 1.6.0 → sottocomando "scan" + --lockfile relativo.
//   knip     5.0.0  → --reporter json stabile.
//   jscpd    4.0.0  → --reporters json + --min-tokens stabile (A2a dup_check).
//   madge    6.0.0  → --json (grafo import) stabile su .ts/.tsx (A2a cycle_check).
const MINIMUM_VERSIONS = {
  semgrep: [1, 60, 0],
  gitleaks: [8, 18, 0],
  'osv-scanner': [1, 6, 0],
  knip: [6, 0, 0], // knip 5.x emette enumMembers/namespaceMembers come OGGETTO (non array);
                   // normalizeKnip itera assumendo array -> il floor reale e' knip 6 (reference-app: 6.16.1).
  jscpd: [4, 0, 0],
  madge: [6, 0, 0],
};

// --- Versioni PINNATE ESATTE per i binary-release scaricabili ----------------
// A differenza di MINIMUM_VERSIONS (soglia minima accettata), questi sono i pin
// ESATTI delle release GitHub che la skill scarica project-local in
// `<project>/.trueline/bin/` (Fase 1, install consent-gated). Devono restare
// >= ai minimi sopra. semgrep/knip NON sono qui: semgrep degrada (docker/pip),
// knip resta `npm i -D` project-local.
// NB: osv-scanner NON pubblica un tag v1.6.0 (i tag saltano da v1.5.0 a v1.6.1/
// v1.6.2); pinniamo a v1.6.2 — un tag reale e >= al minimo [1,6,0] sopra.
const PINNED_VERSIONS = {
  gitleaks: '8.18.0',
  'osv-scanner': '1.6.2',
};

// Metadati delle release GitHub per i tool con asset scaricabile.
//   owner/repo  → coordinate del repository di release.
//   archive     → 'tar.gz'|'zip' (estrarre) | 'raw' (binario grezzo); può essere
//                 una funzione di {plat} per i tool con formato OS-dipendente.
//   assetName   → costruisce il nome dell'asset dato {os, arch, ext, ver, archive}.
//   binName     → nome dell'eseguibile risultante dato {ext}.
const RELEASE_ASSETS = {
  gitleaks: {
    owner: 'gitleaks',
    repo: 'gitleaks',
    // gitleaks distribuisce .tar.gz su linux/darwin ma .zip su Windows.
    archive: ({ plat }) => (plat === 'win32' ? 'zip' : 'tar.gz'),
    // es. gitleaks_8.18.0_linux_x64.tar.gz | gitleaks_8.18.0_windows_x64.zip
    assetName: ({ os, arch, ver, archive }) => `gitleaks_${ver}_${os}_${arch}.${archive}`,
    binName: ({ ext }) => `gitleaks${ext}`,
  },
  'osv-scanner': {
    owner: 'google',
    repo: 'osv-scanner',
    archive: 'raw',
    // I nomi asset osv includono il segmento versione, altrimenti 404.
    // es. osv-scanner_1.6.2_linux_amd64 | osv-scanner_1.6.2_windows_amd64.exe
    assetName: ({ os, arch, ext, ver }) => `osv-scanner_${ver}_${os}_${arch}${ext}`,
    binName: ({ ext }) => `osv-scanner${ext}`,
  },
};

// Mappa process.platform → token OS usato nei nomi degli asset di release.
function osToken(plat) {
  if (plat === 'win32') return 'windows';
  if (plat === 'darwin') return 'darwin';
  if (plat === 'linux') return 'linux';
  return null;
}

// Mappa process.arch → token arch. NB: gitleaks usa "x64"/"arm64";
// osv-scanner usa "amd64"/"arm64". Restituiamo entrambe le varianti.
function archTokens(arch) {
  if (arch === 'x64') return { x: 'x64', amd: 'amd64' };
  if (arch === 'arm64') return { x: 'arm64', amd: 'arm64' };
  return null;
}

/**
 * Risolve l'asset di release scaricabile per un tool su una data piattaforma.
 *
 * @param {string} tool  nome del tool ('gitleaks' | 'osv-scanner' | ...).
 * @param {string} plat  process.platform ('linux' | 'darwin' | 'win32').
 * @param {string} arch  process.arch ('x64' | 'arm64').
 * @returns {{url:string, archive:'tar.gz'|'zip'|'raw', binName:string}|null}
 *          null se il tool non ha un asset noto o la piattaforma non è supportata.
 */
function resolveAsset(tool, plat, arch) {
  const meta = RELEASE_ASSETS[tool];
  const ver = PINNED_VERSIONS[tool];
  if (!meta || !ver) return null;
  const os = osToken(plat);
  const arches = archTokens(arch);
  if (!os || !arches) return null;
  const ext = plat === 'win32' ? '.exe' : '';
  // gitleaks usa x64/arm64; osv-scanner usa amd64/arm64.
  const archTok = tool === 'osv-scanner' ? arches.amd : arches.x;
  // L'archivio può dipendere dalla piattaforma (gitleaks: zip su Windows).
  const archive = typeof meta.archive === 'function' ? meta.archive({ plat }) : meta.archive;
  const asset = meta.assetName({ os, arch: archTok, ext, ver, archive });
  const url = `https://github.com/${meta.owner}/${meta.repo}/releases/download/v${ver}/${asset}`;
  return { url, archive, binName: meta.binName({ ext }) };
}

// --- Downloader binary-release → <project>/.trueline/bin/ (Task 2) ------------
// SOLO built-in Node (node:https / node:http), niente curl, niente npm deps.
// GitHub redirige le release a S3: seguiamo i redirect 30x. Estraiamo i .tar.gz
// con `tar` di sistema; i raw li scriviamo direttamente. chmod 0o755 su POSIX.

/**
 * GET di un URL via node:https|http seguendo i redirect 30x, restituendo i byte.
 * @param {string} url
 * @param {number} redirectsLeft  redirect residui prima di arrendersi.
 * @returns {Promise<Buffer>}
 */
function httpGetBuffer(url, redirectsLeft = 6) {
  return new Promise((res, rej) => {
    let mod;
    try {
      mod = String(url).startsWith('https:') ? https : http;
    } catch (e) {
      return rej(e);
    }
    const req = mod.get(url, (resp) => {
      const { statusCode, headers } = resp;
      // Redirect (GitHub → S3): ri-richiedi sulla nuova location.
      if (statusCode >= 300 && statusCode < 400 && headers.location) {
        resp.resume(); // drena il body per liberare il socket
        if (redirectsLeft <= 0) return rej(new Error('troppi redirect'));
        let next;
        try {
          next = new URL(headers.location, url).toString();
        } catch (e) {
          return rej(e);
        }
        return res(httpGetBuffer(next, redirectsLeft - 1));
      }
      if (statusCode !== 200) {
        resp.resume();
        return rej(new Error(`HTTP ${statusCode}`));
      }
      const chunks = [];
      resp.on('data', (c) => chunks.push(c));
      resp.on('end', () => res(Buffer.concat(chunks)));
      resp.on('error', rej);
    });
    req.on('error', rej);
  });
}

/**
 * Scarica il binary-release di un tool nella directory di destinazione.
 *
 * Risolve i metadati dell'asset via resolveAsset() per l'OS/arch corrente, a
 * meno che non vengano forniti via override (urlOverride/archive/binName — usati
 * dal test con un server locale). Scarica i byte, poi:
 *   - archive 'raw'    → scrive il binario direttamente in <destDir>/<binName>;
 *   - archive 'tar.gz' → scrive l'archivio in un tmp ed estrae con `tar -xzf`
 *                        di sistema in <destDir> (se `tar` assente → ok:false);
 *   - archive 'zip'    → estrae con `tar -xf` (bsdtar gestisce zip; se assente
 *                        → ok:false dichiarato).
 * chmod 0o755 sul binario su POSIX. Version-check best-effort (non fa fallire).
 * Mai stampa segreti; la diagnostica va su stderr.
 *
 * @param {string} tool     'gitleaks' | 'osv-scanner' | ...
 * @param {string} destDir  directory di destinazione (es. <project>/.trueline/bin).
 * @param {{urlOverride?:string, archive?:string, binName?:string}} [opts]
 * @returns {Promise<{ok:boolean, path:string|null, version:string|null, detail:string}>}
 */
async function downloadBinaryRelease(tool, destDir, opts = {}) {
  const { urlOverride, archive: archiveOverride, binName: binNameOverride } = opts || {};

  // Metadati asset: override prima, poi resolveAsset per l'OS/arch corrente.
  const resolved = resolveAsset(tool, process.platform, process.arch);
  const url = urlOverride || (resolved && resolved.url) || null;
  const archive = archiveOverride || (resolved && resolved.archive) || null;
  const binName = binNameOverride || (resolved && resolved.binName) || null;

  if (!url || !archive || !binName) {
    return {
      ok: false,
      path: null,
      version: null,
      detail: `nessun asset risolvibile per ${tool} su ${process.platform}/${process.arch}`,
    };
  }

  // Assicura la directory di destinazione (idempotente).
  try {
    mkdirSync(destDir, { recursive: true });
  } catch (e) {
    return { ok: false, path: null, version: null, detail: `impossibile creare ${destDir}: ${e && e.message ? e.message : e}` };
  }

  // Scarica i byte.
  let buf;
  try {
    buf = await httpGetBuffer(url);
  } catch (e) {
    process.stderr.write(`downloadBinaryRelease: download fallito (${tool})\n`);
    return { ok: false, path: null, version: null, detail: `download fallito: ${e && e.message ? e.message : e}` };
  }

  const binPath = join(destDir, binName);

  if (archive === 'raw') {
    try {
      writeFileSync(binPath, buf);
    } catch (e) {
      return { ok: false, path: null, version: null, detail: `scrittura fallita: ${e && e.message ? e.message : e}` };
    }
  } else {
    // tar.gz | zip: scrivi l'archivio in un tmp ed estrai con `tar` di sistema.
    // NB: estraiamo con cwd=arcDir e nomi RELATIVI (niente path con drive-letter
    // `C:\`), perché GNU tar interpreta il `:` come host remoto e bsdtar rifiuta
    // `--force-local`: i nomi relativi funzionano con entrambe le implementazioni.
    let arcDir;
    try {
      arcDir = mkdtempSync(join(tmpdir(), 'tl-arc-'));
    } catch (e) {
      return { ok: false, path: null, version: null, detail: `tmp non creabile: ${e && e.message ? e.message : e}` };
    }
    const arcName = archive === 'zip' ? 'asset.zip' : 'asset.tgz';
    const arcPath = join(arcDir, arcName);
    try {
      writeFileSync(arcPath, buf);
    } catch (e) {
      return { ok: false, path: null, version: null, detail: `scrittura archivio fallita: ${e && e.message ? e.message : e}` };
    }
    const tarArgs = archive === 'zip' ? ['-xf', arcName] : ['-xzf', arcName];
    const ex = spawnSync('tar', tarArgs, { encoding: 'utf8', timeout: 60_000, cwd: arcDir });
    if (ex.error || ex.status !== 0) {
      const why = ex.error && ex.error.code === 'ENOENT'
        ? 'tar non disponibile'
        : `estrazione fallita (status=${ex.status})`;
      process.stderr.write(`downloadBinaryRelease: ${why} (${tool})\n`);
      return { ok: false, path: null, version: null, detail: why };
    }
    // Copia il binario estratto (atteso al root dell'archivio) in destDir.
    const extracted = join(arcDir, binName);
    if (!existsSync(extracted)) {
      return { ok: false, path: null, version: null, detail: `binario ${binName} non trovato nell'archivio estratto` };
    }
    try {
      copyFileSync(extracted, binPath);
    } catch (e) {
      return { ok: false, path: null, version: null, detail: `copia in destDir fallita: ${e && e.message ? e.message : e}` };
    }
  }

  // chmod 0o755 su POSIX (best-effort; su Windows non si applica).
  if (process.platform !== 'win32') {
    try {
      chmodSync(binPath, 0o755);
    } catch {
      // best-effort
    }
  }

  if (!existsSync(binPath)) {
    return {
      ok: false,
      path: null,
      version: null,
      detail: `binario atteso non trovato dopo l'estrazione: ${binPath}`,
    };
  }

  // Version-check best-effort: NON fa fallire il download (L-COL-006: onesto su
  // ciò che riesce a verificare, ma il file è comunque scaricato).
  let version = null;
  try {
    const flag = tool === 'gitleaks' ? 'version' : '--version';
    const vr = spawnSync(binPath, [flag], { encoding: 'utf8', timeout: 20_000 });
    if (!vr.error) {
      const parsed = parseVersion(`${vr.stdout || ''}${vr.stderr || ''}`.trim());
      version = parsed ? fmtVer(parsed) : null;
    }
  } catch {
    // best-effort: il version-check non è bloccante.
  }

  return { ok: true, path: binPath, version, detail: `scaricato ${tool} in ${binPath}` };
}

// --- Parsing e confronto versioni --------------------------------------------

/**
 * Estrae la prima occorrenza di major.minor.patch da una stringa.
 * Restituisce null se il parsing fallisce.
 * Esempio: "gitleaks version version is set by build process" → null.
 */
function parseVersion(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const m = raw.match(/(\d+)\.(\d+)\.(\d+)/);
  if (!m) return null;
  return [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)];
}

/** true se actual >= required (tuple [major, minor, patch]). */
function versionAtLeast(actual, required) {
  if (!actual || !required) return false;
  for (let i = 0; i < 3; i++) {
    if (actual[i] > required[i]) return true;
    if (actual[i] < required[i]) return false;
  }
  return true;
}

function fmtVer(tuple) {
  return tuple ? tuple.join('.') : null;
}

// --- Helper di spawn sincrono ------------------------------------------------

/**
 * Esegue un comando e restituisce { ok, stdout, stderr, status }.
 *
 * Su Windows, i comandi come npm/pnpm/yarn/pipx sono script .cmd e NON sono
 * eseguibili direttamente via spawnSync senza shell. Usiamo shell:true solo
 * per i comandi che ne hanno bisogno (rilevabili dall'estensione .cmd o dalla
 * lista esplicita). Per i comandi con path assoluto o binari nativi (docker,
 * gitleaks, osv-scanner, node) usiamo shell:false per sicurezza.
 */
const WIN_CMD_SCRIPTS = new Set(['npm', 'pnpm', 'yarn', 'npx', 'pip', 'pip3', 'pipx', 'brew', 'winget', 'go']);

function runCmd(cmd, args, opts) {
  // Su Windows, i comandi della lista richiedono shell:true per funzionare
  // (sono script .cmd nel PATH, non eseguibili nativi).
  const needsShell = IS_WIN && WIN_CMD_SCRIPTS.has(cmd.split(/[\\/]/).pop().toLowerCase());
  const res = spawnSync(cmd, args, {
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
    timeout: 20_000,
    env: ENV_WITH_GOBIN,
    shell: needsShell,
    ...opts,
  });
  return {
    ok: !res.error && res.status !== null,
    stdout: res.stdout || '',
    stderr: res.stderr || '',
    status: res.status,
  };
}

// --- Proposta di install per OS ----------------------------------------------

/**
 * Determina il canale di install disponibile sull'OS e restituisce
 * { installable, channel, cmd }.
 *
 * Regole (03 §4):
 *   semgrep   → docker pull (cross-OS); pipx/pip fallback su Linux/Mac.
 *   gitleaks  → go install (se go presente); brew su Mac; binary release su Win/Linux.
 *   osv-scan  → go install (se go presente); binary release altrimenti.
 *   knip      → npm/pnpm/yarn --save-dev (per-progetto).
 */
function suggestInstall(toolName) {
  switch (toolName) {
    case 'semgrep': {
      const dockerOk = runCmd('docker', ['version', '--format', '{{.Server.Version}}']).ok;
      if (dockerOk) {
        return { installable: true, channel: 'docker', cmd: 'docker pull semgrep/semgrep:latest' };
      }
      const pipxOk = runCmd('pipx', ['--version']).ok;
      if (pipxOk) {
        return { installable: true, channel: 'pipx', cmd: 'pipx install semgrep' };
      }
      const pip3Ok = runCmd('pip3', ['--version']).ok;
      if (pip3Ok) {
        return { installable: true, channel: 'pip', cmd: 'pip3 install semgrep' };
      }
      const pipOk = runCmd('pip', ['--version']).ok;
      if (pipOk) {
        return { installable: true, channel: 'pip', cmd: 'pip install semgrep' };
      }
      return { installable: false, channel: 'none', cmd: null };
    }

    case 'gitleaks': {
      const goOk = runCmd('go', ['version']).ok;
      if (goOk) {
        return {
          installable: true,
          channel: 'go-install',
          cmd: 'go install github.com/zricethezav/gitleaks/v8@latest',
        };
      }
      if (IS_MAC) {
        const brewOk = runCmd('brew', ['--version']).ok;
        if (brewOk) {
          return { installable: true, channel: 'brew', cmd: 'brew install gitleaks' };
        }
      }
      if (IS_LINUX) {
        return {
          installable: true,
          channel: 'binary-release',
          cmd: 'curl -sSfL https://raw.githubusercontent.com/gitleaks/gitleaks/main/scripts/install.sh | sh -s -- v8.18.0',
        };
      }
      if (IS_WIN) {
        return {
          installable: true,
          channel: 'binary-release',
          cmd: 'winget install gitleaks  # oppure: scaricare da https://github.com/gitleaks/gitleaks/releases',
        };
      }
      return { installable: false, channel: 'none', cmd: null };
    }

    case 'osv-scanner': {
      const goOk = runCmd('go', ['version']).ok;
      if (goOk) {
        return {
          installable: true,
          channel: 'go-install',
          cmd: 'go install github.com/google/osv-scanner/cmd/osv-scanner@latest',
        };
      }
      // Binary release disponibile su tutti gli OS (non richiede Go).
      const releaseNote = IS_WIN
        ? 'https://github.com/google/osv-scanner/releases  (osv-scanner_windows_amd64.exe)'
        : IS_MAC
          ? 'https://github.com/google/osv-scanner/releases  (osv-scanner_macos_amd64 o _arm64)'
          : 'https://github.com/google/osv-scanner/releases  (osv-scanner_linux_amd64)';
      return {
        installable: true,
        channel: 'binary-release',
        cmd: `# Download binario da: ${releaseNote}`,
      };
    }

    case 'knip': {
      const npmOk = runCmd('npm', ['--version']).ok;
      if (npmOk) {
        return {
          installable: true,
          channel: 'npm',
          cmd: 'npm install --save-dev knip  # nella directory del progetto target',
        };
      }
      const pnpmOk = runCmd('pnpm', ['--version']).ok;
      if (pnpmOk) {
        return {
          installable: true,
          channel: 'pnpm',
          cmd: 'pnpm add --save-dev knip  # nella directory del progetto target',
        };
      }
      const yarnOk = runCmd('yarn', ['--version']).ok;
      if (yarnOk) {
        return {
          installable: true,
          channel: 'yarn',
          cmd: 'yarn add --dev knip  # nella directory del progetto target',
        };
      }
      return { installable: false, channel: 'none', cmd: null };
    }

    // jscpd/madge (A2a — igiene strutturale) sono devDependency project-local come
    // knip: stesso canale npm/pnpm/yarn --save-dev. jscpd/madge si risolvono anche
    // via la cache di npx (i wrapper hanno il fallback), ma la proposta d'install
    // resta project-local per un ambiente deterministico.
    case 'jscpd':
      return npmDevInstall('jscpd');
    case 'madge':
      return npmDevInstall('madge');

    default:
      return { installable: false, channel: 'none', cmd: null };
  }
}

// Proposta d'install project-local di un pacchetto npm (devDependency), col primo
// package manager disponibile. Mirror del ramo knip di suggestInstall.
function npmDevInstall(pkg) {
  if (runCmd('npm', ['--version']).ok) {
    return { installable: true, channel: 'npm', cmd: `npm install --save-dev ${pkg}  # nella directory del progetto target` };
  }
  if (runCmd('pnpm', ['--version']).ok) {
    return { installable: true, channel: 'pnpm', cmd: `pnpm add --save-dev ${pkg}  # nella directory del progetto target` };
  }
  if (runCmd('yarn', ['--version']).ok) {
    return { installable: true, channel: 'yarn', cmd: `yarn add --dev ${pkg}  # nella directory del progetto target` };
  }
  return { installable: false, channel: 'none', cmd: null };
}

// --- Costruttore del risultato strutturato -----------------------------------

function buildResult(tool, channel, present, versionTuple, versionOk, suggest) {
  const { installable, cmd } = suggest;
  const minVer = MINIMUM_VERSIONS[tool];
  const minStr = minVer ? fmtVer(minVer) : null;
  const verStr = versionTuple ? fmtVer(versionTuple) : null;

  let status;
  let note;

  if (present && versionOk) {
    status = 'ok';
    note = `${tool} presente, versione ${verStr} >= minimo richiesto ${minStr}.`;
  } else if (present && !versionOk) {
    if (versionTuple === null) {
      // Presente ma versione non parsabile (es. build dev senza tag git):
      // non possiamo garantire che soddisfi il minimo → non-installable per precauzione
      // (L-COL-006: mai un verde finto).
      status = 'non-installable';
      note =
        `${tool} presente ma la versione non è parsabile ` +
        `(build di sviluppo senza tag git). ` +
        `Impossibile verificare il rispetto del minimo ${minStr}. ` +
        `Installa una release ufficiale taggata.` +
        (installable && cmd ? ` Comando suggerito: ${cmd}` : '');
    } else {
      status = 'version-low';
      note =
        `${tool} presente ma versione ${verStr} < minimo richiesto ${minStr}. ` +
        `Aggiorna: ${cmd || '(nessun canale disponibile su questo OS)'}`;
    }
  } else if (!present && installable) {
    status = 'missing';
    note =
      `${tool} non trovato. ` +
      `Installa (gate umano richiesto — la skill non lo esegue da sola, L-COL-005): ${cmd}`;
  } else {
    // Non presente e non installabile.
    status = 'non-installable';
    note =
      `${tool} non trovato e nessun canale di install disponibile sull'OS corrente. ` +
      `Il controllo che dipende da ${tool} DEGRADA a "not-run" ` +
      `(mai un verde finto, L-COL-006 — l'assenza è dichiarata).`;
  }

  return {
    tool,
    channel,
    present,
    version: verStr,
    version_ok: present ? versionOk : false,
    installable,
    install_cmd: cmd,
    status,
    note,
  };
}

// --- Rilevazione per tool ----------------------------------------------------

// semgrep — VIA DOCKER (il canale usato dal wrapper run_semgrep.mjs, 03 §5.1).
// Non cerca semgrep sul PATH: la skill lo esegue sempre tramite docker per
// garantire la versione pinnata (determinismo, L-COL-002).
function detectSemgrep(simMissing) {
  const tool = 'semgrep';
  const min = MINIMUM_VERSIONS[tool];

  if (simMissing) {
    return buildResult(tool, 'docker', false, null, false, suggestInstall(tool));
  }

  // 1) docker disponibile?
  const dockerCheck = runCmd('docker', ['version', '--format', '{{.Server.Version}}']);
  if (!dockerCheck.ok || dockerCheck.status !== 0) {
    return buildResult(tool, 'docker', false, null, false, suggestInstall(tool));
  }

  // 2) Immagine pinnata presente localmente?
  const imgCheck = runCmd('docker', ['images', '-q', 'semgrep/semgrep:latest']);
  const imgId = (imgCheck.stdout || '').trim();
  if (!imgId) {
    // Immagine non presente: propone docker pull.
    const suggest = { installable: true, channel: 'docker', cmd: 'docker pull semgrep/semgrep:latest' };
    return buildResult(tool, 'docker', false, null, false, suggest);
  }

  // 3) Versione dall'immagine.
  const verRun = runCmd(
    'docker',
    ['run', '--rm', 'semgrep/semgrep:latest', 'semgrep', '--version'],
    { env: { ...process.env, MSYS_NO_PATHCONV: '1' }, timeout: 60_000 },
  );
  const raw = (verRun.stdout || '').trim();
  const parsed = parseVersion(raw);
  const vOk = versionAtLeast(parsed, min);
  return buildResult(tool, 'docker', true, parsed, vOk, suggestInstall(tool));
}

// gitleaks — binario nel go/bin noto o sul PATH.
function detectGitleaks(simMissing) {
  const tool = 'gitleaks';
  const min = MINIMUM_VERSIONS[tool];

  if (simMissing) {
    return buildResult(tool, 'go-bin', false, null, false, suggestInstall(tool));
  }

  // Prova prima via PATH arricchito.
  let verRun = runCmd('gitleaks', ['version']);
  if (!verRun.ok) {
    // Prova il percorso assoluto noto.
    const exeName = IS_WIN ? 'gitleaks.exe' : 'gitleaks';
    const knownPath = join(GO_BIN, exeName);
    if (!existsSync(knownPath)) {
      return buildResult(tool, 'go-bin', false, null, false, suggestInstall(tool));
    }
    verRun = runCmd(knownPath, ['version']);
    if (!verRun.ok) {
      return buildResult(tool, 'go-bin', false, null, false, suggestInstall(tool));
    }
  }

  // gitleaks version output: "gitleaks version <semver>" oppure
  // "version is set by build process" (build dev senza tag git).
  const raw = (verRun.stdout || '').trim();
  const parsed = parseVersion(raw);
  const vOk = versionAtLeast(parsed, min);
  return buildResult(tool, 'go-bin', true, parsed, vOk, suggestInstall(tool));
}

// osv-scanner — binario nel go/bin noto o sul PATH.
function detectOsvScanner(simMissing) {
  const tool = 'osv-scanner';
  const min = MINIMUM_VERSIONS[tool];

  if (simMissing) {
    return buildResult(tool, 'go-bin', false, null, false, suggestInstall(tool));
  }

  let verRun = runCmd('osv-scanner', ['--version']);
  if (!verRun.ok) {
    const exeName = IS_WIN ? 'osv-scanner.exe' : 'osv-scanner';
    const knownPath = join(GO_BIN, exeName);
    if (!existsSync(knownPath)) {
      return buildResult(tool, 'go-bin', false, null, false, suggestInstall(tool));
    }
    verRun = runCmd(knownPath, ['--version']);
    if (!verRun.ok) {
      return buildResult(tool, 'go-bin', false, null, false, suggestInstall(tool));
    }
  }

  // osv-scanner output: "osv-scanner version: 1.9.2\ncommit: ...\nbuilt at: ..."
  const raw = (verRun.stdout || '').trim();
  const parsed = parseVersion(raw);
  const vOk = versionAtLeast(parsed, min);
  return buildResult(tool, 'go-bin', true, parsed, vOk, suggestInstall(tool));
}

// knip — installato come devDependency nel progetto target (node_modules).
// Cerca knip.js nella directory del progetto passata o nella CWD.
function detectKnip(simMissing, projectDir) {
  const tool = 'knip';
  const min = MINIMUM_VERSIONS[tool];

  if (simMissing) {
    return buildResult(tool, 'npx', false, null, false, suggestInstall(tool));
  }

  // Ordine di ricerca: projectDir (se passata), poi CWD.
  const searchDirs = [
    projectDir ? resolve(projectDir) : null,
    process.cwd(),
  ].filter(Boolean);

  for (const dir of searchDirs) {
    const knipJs = join(dir, 'node_modules', 'knip', 'bin', 'knip.js');
    const knipPkg = join(dir, 'node_modules', 'knip', 'package.json');
    if (!existsSync(knipJs)) continue;

    // Versione da package.json (più veloce).
    let parsed = null;
    if (existsSync(knipPkg)) {
      try {
        const pkg = JSON.parse(readFileSync(knipPkg, 'utf8'));
        parsed = parseVersion(String(pkg.version || ''));
      } catch {
        // best-effort
      }
    }

    // Fallback: esegui node <knip.js> --version.
    if (!parsed) {
      const verRun = runCmd(process.execPath, [knipJs, '--version'], { cwd: dir });
      if (verRun.ok) {
        parsed = parseVersion((verRun.stdout || '').trim());
      }
    }

    const vOk = versionAtLeast(parsed, min);
    return buildResult(tool, 'npx', true, parsed, vOk, suggestInstall(tool));
  }

  // Prova npx --no-install knip --version (se knip è installato globalmente).
  const npxRun = runCmd('npx', ['--no-install', 'knip', '--version']);
  if (npxRun.ok && npxRun.status === 0) {
    const parsed = parseVersion((npxRun.stdout || '').trim());
    const vOk = versionAtLeast(parsed, min);
    return buildResult(tool, 'npx', true, parsed, vOk, suggestInstall(tool));
  }

  return buildResult(tool, 'npx', false, null, false, suggestInstall(tool));
}

// jscpd/madge (A2a) — devDependency project-local nel node_modules del progetto
// target, come knip. La versione si legge da <dir>/node_modules/<tool>/package.json
// (piu' veloce e senza eseguire il tool). Assente -> missing installabile via
// npm i -D. NB: i wrapper run_dupcheck/run_cyclecheck hanno anche un fallback via
// la cache di npx, quindi l'assenza del node_modules NON e' fatale a runtime; il
// preflight la dichiara comunque (mai un verde finto, L-COL-006).
function detectProjectNpmTool(tool, simMissing, projectDir) {
  const min = MINIMUM_VERSIONS[tool];

  if (simMissing) {
    return buildResult(tool, 'npx', false, null, false, suggestInstall(tool));
  }

  const searchDirs = [
    projectDir ? resolve(projectDir) : null,
    process.cwd(),
  ].filter(Boolean);

  for (const dir of searchDirs) {
    const pkgJson = join(dir, 'node_modules', tool, 'package.json');
    if (!existsSync(pkgJson)) continue;
    let parsed = null;
    try {
      parsed = parseVersion(String(JSON.parse(readFileSync(pkgJson, 'utf8')).version || ''));
    } catch {
      // best-effort
    }
    const vOk = versionAtLeast(parsed, min);
    return buildResult(tool, 'npx', true, parsed, vOk, suggestInstall(tool));
  }

  return buildResult(tool, 'npx', false, null, false, suggestInstall(tool));
}

// --- rls_check: sempre disponibile, nessuna dipendenza esterna ---------------
const RLS_CHECK_ENTRY = {
  tool: 'rls_check',
  channel: 'built-in',
  present: true,
  version: null,
  version_ok: true,
  installable: true,
  install_cmd: null,
  status: 'ok',
  note: 'rls_check viaggia con la skill (03 §5.4). Dipende solo dal runtime Node/JS. Sempre disponibile.',
};

// --- Install CONSENT-GATED (L-COL-005) ---------------------------------------

// Un suggerimento d'install e' AUTO-ESEGUIBILE solo se, tolto l'eventuale commento
// inline (" # ..."), resta un comando reale (non una nota che inizia per '#', tipo
// "# Download binario da: ..."). Le note manuali NON si eseguono mai.
function executableInstall(cmd) {
  if (!cmd || typeof cmd !== 'string') return { executable: false, cmd: null };
  const noInline = cmd.replace(/\s+#.*$/, '').trim();
  if (!noInline || noInline.startsWith('#')) return { executable: false, cmd: null };
  return { executable: true, cmd: noInline };
}

// Conferma interattiva (solo su TTY). Accetta s/si/y/yes (case-insensitive).
function askYesNo(question) {
  return new Promise((res) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, (ans) => { rl.close(); res(/^\s*(s|si|y|yes)\s*$/i.test(ans)); });
  });
}

// Scelta interattiva del target d'install per un tool (solo su TTY).
// Ritorna 'project' | 'global' | 'skip'. Se il tool non ha un binary-release
// scaricabile (asset==null), 'project' non è offerto (resta global/skip).
function askTarget(tool, hasAsset) {
  const opts = hasAsset ? '[project/global/skip]' : '[global/skip]';
  return new Promise((res) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    rl.question(`  Installo ${tool}? ${opts} `, (ans) => {
      rl.close();
      const a = (ans || '').trim().toLowerCase();
      if (hasAsset && /^(p|project)$/.test(a)) return res('project');
      if (/^(g|global)$/.test(a)) return res('global');
      return res('skip');
    });
  });
}

// Esegue gli install dei tool mancanti/sotto-versione INSTALLABILI, uno per uno,
// SOLO col consenso esplicito (L-COL-005): mai in autonomia. Senza --yes e senza un
// TTY su cui chiedere, salta e lo dichiara. rls_check non e' mai un target (built-in).
// Ritorna un riepilogo { targets, installed, skipped, failed }.
async function runInstall(results) {
  const HR = '─'.repeat(64);
  console.log('');
  console.log(HR);
  console.log(` TRUELINE — install oracoli (consenso esplicito, L-COL-005)${DRY_RUN ? '  [DRY-RUN]' : ''}`);
  console.log(`  target predefinito: ${TARGET}`);
  console.log(HR);

  const projectDir = PROJECT_DIR_ARG || process.cwd();
  const binDir = projectBinDir(projectDir);

  // Un tool è un target d'install se manca/è sotto-versione E può essere risolto
  // in almeno un modo: project-local (resolveAsset) oppure global (install_cmd).
  const targets = results.filter((r) => r.tool !== 'rls_check'
    && (r.status === 'missing' || r.status === 'version-low')
    && (resolveAsset(r.tool, process.platform, process.arch) || (r.installable && r.install_cmd))
    && (!ONLY_TOOL || r.tool === ONLY_TOOL));

  if (targets.length === 0) {
    console.log(ONLY_TOOL
      ? `  Niente da installare per --only=${ONLY_TOOL} (gia' pronto, non-installabile, o sconosciuto).`
      : '  Niente da installare: gli oracoli esterni sono gia\' pronti (o non-installabili).');
    console.log(HR);
    return { targets: 0, installed: 0, skipped: 0, failed: 0 };
  }

  let installed = 0; let skipped = 0; let failed = 0;
  for (const r of targets) {
    const asset = resolveAsset(r.tool, process.platform, process.arch);

    // CONSENSO ESPLICITO + scelta target (L-COL-005). Con --yes si usa il TARGET
    // di default; su TTY si chiede [project/global/skip]; senza TTY e senza --yes
    // si salta e lo si dichiara (mai un install silenzioso).
    let choice = TARGET; // 'project' | 'global'
    if (!ASSUME_YES) {
      if (process.stdin.isTTY) {
        choice = await askTarget(r.tool, !!asset);
      } else {
        console.log(`  [skip] ${r.tool}: consenso esplicito richiesto — ri-esegui con --yes (o conferma su un terminale interattivo).`);
        skipped++;
        continue;
      }
    }

    if (choice === 'skip') {
      console.log(`  [skip] ${r.tool}: non installato (scelta: skip).`);
      skipped++;
      continue;
    }

    // PROJECT-LOCAL: scarica il binary-release in <project>/.trueline/bin/.
    // Solo per i tool con un asset risolvibile (gitleaks/osv-scanner).
    if (choice === 'project' && asset) {
      if (DRY_RUN) {
        console.log(`  [dry-run] ${r.tool}: scaricherei ${r.tool} ${PINNED_VERSIONS[r.tool]} in ${binDir} (project-local).`);
        installed++;
        continue;
      }
      console.log(`  [install] ${r.tool}: scarico project-local in ${binDir} ...`);
      const out = await downloadBinaryRelease(r.tool, binDir);
      if (out.ok) {
        console.log(`  [ok] ${r.tool}: ${out.detail}${out.version ? ` (v${out.version})` : ''}`);
        installed++;
      } else {
        console.log(`  [fail] ${r.tool}: download project-local fallito — ${out.detail}`);
        failed++;
      }
      continue;
    }

    // GLOBAL (o project senza asset: knip → npm i -D nel projectDir;
    // semgrep → docker/pip). Usa il canale di sistema via suggestInstall.
    const suggest = suggestInstall(r.tool);
    const { executable, cmd } = executableInstall(suggest.cmd);
    if (!executable) {
      console.log(`  [manuale] ${r.tool}: passo manuale richiesto (nessun comando auto-eseguibile): ${suggest.cmd || r.install_cmd}`);
      skipped++;
      continue;
    }

    if (DRY_RUN) {
      console.log(`  [dry-run] ${r.tool}: eseguirei: ${cmd}`);
      installed++;
      continue;
    }

    console.log(`  [install] ${r.tool}: eseguo: ${cmd}`);
    const spawnOpts = { shell: true, stdio: 'inherit', env: ENV_WITH_GOBIN, timeout: 600_000 };
    if (r.tool === 'knip') spawnOpts.cwd = resolve(projectDir); // knip è per-progetto.
    const res = spawnSync(cmd, spawnOpts);
    if (!res.error && res.status === 0) {
      console.log(`  [ok] ${r.tool}: installato.`);
      installed++;
    } else {
      console.log(`  [fail] ${r.tool}: install fallito (status=${res.status}${res.error ? `, ${res.error.message}` : ''}).`);
      failed++;
    }
  }

  console.log(HR);
  console.log(`  Esito install: ${installed} ${DRY_RUN ? 'pianificati (dry-run)' : 'eseguiti'}, ${skipped} saltati, ${failed} falliti.`);
  if (!DRY_RUN && installed > 0) console.log('  Ri-esegui il preflight per confermare lo stato aggiornato.');
  console.log(HR);
  return { targets: targets.length, installed, skipped, failed };
}

// --- Punto di ingresso -------------------------------------------------------

async function main() {
  const results = [
    detectSemgrep(SIMULATE_MISSING === 'semgrep'),
    detectGitleaks(SIMULATE_MISSING === 'gitleaks'),
    detectOsvScanner(SIMULATE_MISSING === 'osv-scanner'),
    detectKnip(SIMULATE_MISSING === 'knip', PROJECT_DIR_ARG),
    detectProjectNpmTool('jscpd', SIMULATE_MISSING === 'jscpd', PROJECT_DIR_ARG),
    detectProjectNpmTool('madge', SIMULATE_MISSING === 'madge', PROJECT_DIR_ARG),
    RLS_CHECK_ENTRY,
  ];

  if (JSON_MODE) {
    const out = {
      schema_version: '1.0',
      platform: platform(),
      go_bin: GO_BIN,
      tools: results,
      summary: {
        ok: results.filter((r) => r.status === 'ok').length,
        missing: results.filter((r) => r.status === 'missing').length,
        version_low: results.filter((r) => r.status === 'version-low').length,
        non_installable: results.filter((r) => r.status === 'non-installable').length,
      },
      minimum_versions: Object.fromEntries(
        Object.entries(MINIMUM_VERSIONS).map(([k, v]) => [k, v.join('.')]),
      ),
    };
    process.stdout.write(JSON.stringify(out, null, 2) + '\n');
    // JSON mode: exit 0 sempre (il chiamante legge il JSON e decide).
    process.exit(0);
  }

  // --- Target project-local: riscrive l'azione proposta nel report umano ------
  // Per i tool con un binary-release scaricabile (gitleaks/osv-scanner), quando
  // il target è 'project' (default) l'azione proposta è un download project-local
  // in <project>/.trueline/bin/, NON il canale globale (go install / brew / ...).
  // NB: questa riscrittura è SOLO per il flusso umano/install; il JSON sopra resta
  // identico (BIT-invarianza dei gate che leggono --json).
  if (TARGET === 'project') {
    const binDir = projectBinDir(PROJECT_DIR_ARG || process.cwd());
    for (const r of results) {
      if (r.tool === 'rls_check') continue;
      if (r.status !== 'missing' && r.status !== 'version-low') continue;
      if (!resolveAsset(r.tool, process.platform, process.arch)) continue;
      r.channel = 'binary-release (project-local)';
      r.install_cmd = `# download project-local: ${r.tool} ${PINNED_VERSIONS[r.tool]} -> ${binDir}`;
      r.note =
        `${r.tool}: download project-local disponibile in ${binDir} ` +
        `(versione pinnata ${PINNED_VERSIONS[r.tool]}; gate umano richiesto, L-COL-005). ` +
        `Usa --target=global per il canale di sistema.`;
    }
  }

  // --- Report umano -----------------------------------------------------------
  const HR = '─'.repeat(64);
  console.log(HR);
  console.log(' TRUELINE — preflight rilevazione oracoli (03 §4 / 09 §6)');
  console.log(` OS: ${platform()}  |  go/bin atteso: ${GO_BIN}`);
  console.log(HR);
  console.log('');

  let anyProblem = false;

  for (const r of results) {
    const isBuiltIn = r.tool === 'rls_check';
    const icon = r.status === 'ok' ? '✓' : '✗';
    const minEntry = MINIMUM_VERSIONS[r.tool];
    const minLabel = minEntry ? `  (minimo: ${fmtVer(minEntry)})` : '';
    const verLabel = r.version ? ` v${r.version}` : '';
    console.log(`  [${icon}] ${r.tool}${verLabel}${minLabel}`);
    console.log(`       canale: ${r.channel}  |  status: ${r.status}`);
    console.log(`       ${r.note}`);

    if (r.status !== 'ok' && !isBuiltIn) {
      anyProblem = true;
      if (r.install_cmd) {
        console.log('');
        console.log('       AZIONE RICHIESTA (la skill NON installa da sola — gate umano, L-COL-005):');
        console.log(`         ${r.install_cmd}`);
      } else {
        console.log('');
        console.log('       TOOL NON INSTALLABILE su questo OS: il controllo dipendente DEGRADA a "not-run".');
        console.log('       Nessun verde finto (L-COL-006).');
      }
    }
    console.log('');
  }

  console.log(HR);
  const externalTotal = results.filter((r) => r.tool !== 'rls_check').length;
  const externalOk = results.filter((r) => r.tool !== 'rls_check' && r.status === 'ok').length;

  if (!anyProblem) {
    console.log(` PREFLIGHT OK — tutti i ${externalTotal} tool esterni pronti + rls_check built-in.`);
  } else {
    console.log(` PREFLIGHT: ${externalOk}/${externalTotal} tool esterni pronti.`);
    console.log(' Tool mancanti o sotto-versione: vedi AZIONI RICHIESTE sopra.');
    console.log(' I controlli che dipendono da tool assenti DEGRADANO a "not-run" (L-COL-006).');
  }
  console.log(HR);

  // Install CONSENT-GATED (L-COL-005): solo se richiesto, DOPO il report.
  let exitCode = anyProblem ? 1 : 0;
  if (INSTALL_MODE) {
    const sum = await runInstall(results);
    if (DRY_RUN) {
      // dry-run non risolve nulla: se c'erano target, l'azione resta pendente.
      exitCode = sum.targets > 0 ? 1 : exitCode;
    } else {
      // verde solo se non resta nulla di non-soddisfatto (saltato/fallito).
      exitCode = (sum.failed > 0 || sum.skipped > 0) ? 1 : (sum.installed > 0 ? 0 : exitCode);
    }
  }

  // Exit 1 se almeno un tool esterno è non-ok (per i chiamanti che usano l'exit code).
  process.exit(exitCode);
}

// Esegui la CLI SOLO quando il file è invocato direttamente (non in import:
// i test importano `resolveAsset` senza far girare la rilevazione/install).
const __isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (__isMain) {
  main().catch((e) => {
    console.error(`preflight: errore inatteso — ${e && e.message ? e.message : e}`);
    process.exit(2);
  });
}

export { PINNED_VERSIONS, resolveAsset, downloadBinaryRelease, projectBinDir };
