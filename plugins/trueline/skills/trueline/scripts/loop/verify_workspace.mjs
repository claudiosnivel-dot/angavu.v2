// verify_workspace.mjs — gestore della COPIA TEMPORANEA di verifica.
//
// *** REGOLA CRITICA — INTEGRITA DEL FIXTURE ***
// Il loop APPLICA fix (modifica codice/migration) e committa. NON deve MAI
// mutare il fixture canonico eval/reference-app: romperebbe i gate ripetibili
// di M-1/M0. Ogni esecuzione del loop/verify gira su una COPIA TEMPORANEA:
// copiamo eval/reference-app (INCLUSO .git — serve per lo scope history di S2)
// in una dir temp gitignorata (eval/.tmp-verify/<id>), operiamo li', e a fine
// ESEGUIAMO cleanup (rm -rf della temp). Dopo, il fixture canonico DEVE essere
// bit-identico (detection/present ancora EXIT 0).
//
// Node ESM, solo built-in (fs, path, url). Niente dipendenze npm, niente rete.

import {
  cpSync, rmSync, existsSync, mkdirSync, readdirSync,
} from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
// trueline/scripts/loop -> root e' 3 livelli sopra.
export const REPO_ROOT = resolve(__dirname, '..', '..', '..');

export const CANONICAL_REFERENCE_APP = resolve(REPO_ROOT, 'eval', 'reference-app');
// Radice delle copie temporanee (gitignorata: vedi .gitignore "eval/.tmp-*/").
// ADDITIVO (BD-1): un override via env TRUELINE_TMP_VERIFY_ROOT consente a un harness di
// isolare le proprie copie in una radice PRIVATA (es. per-pid) ed evitare la contesa
// Windows sulla .tmp-verify CONDIVISA (race cpSync/chmod sotto esecuzioni back-to-back).
// Default = comportamento storico: env ASSENTE -> bit-invariante per m1..m5 /
// ecosystem_conformance / run_eval (che NON impostano l'env). Il guardrail di
// destroyVerifyWorkspace usa questa stessa costante, quindi resta coerente.
export const TMP_VERIFY_ROOT = process.env.TRUELINE_TMP_VERIFY_ROOT
  ? resolve(process.env.TRUELINE_TMP_VERIFY_ROOT)
  : resolve(REPO_ROOT, 'eval', '.tmp-verify');

// Cosa NON copiare: node_modules e' enorme e non serve agli oracoli del loop
// (rls_check/gitleaks/knip leggono i sorgenti). MA knip ha bisogno del suo
// binario locale (node_modules/.bin) — vedi nota in createVerifyWorkspace.
const SKIP_TOP_LEVEL = new Set([]);

// Contatore monotono per-processo: garantisce un id UNICO anche per piu' copie
// create dallo STESSO processo, SENZA Date.now()/Math.random (determinismo del
// gate, 10 §5 / L-COL-002: niente sorgenti di non-determinismo nel codice che il
// gate esegue). Combinato con process.pid l'id e' unico per-run E per-chiamata.
let __wsCounter = 0;

// Genera un id UNICO-per-run deterministico: pid + contatore monotono. Niente
// Math.random/Date.now. Due copie dello stesso processo ricevono id distinti
// (counter incrementale); processi diversi differiscono per pid. Cosi' una dir
// temp stale di un run precedente NON collide con quella di un run nuovo.
function uniqueWorkspaceId(label) {
  __wsCounter += 1;
  const safe = String(label || 'verify').replace(/[^A-Za-z0-9._-]/g, '-');
  return `${safe}-pid${process.pid}-${__wsCounter}`;
}

// rmSync con piccolo retry/backoff: su Windows una dir temp puo' restare
// momentaneamente LOCKED (handle non ancora rilasciato da un processo figlio
// appena terminato: tsc, npm, git), provocando un EPERM/EBUSY spurio. Riproviamo
// con un backoff BLOCCANTE deterministico (Atomics.wait, niente timer/random)
// cosi' un lock transitorio non genera un rosso flaky. Il backoff e' brevissimo
// e a passi fissi: nessuna sorgente di non-determinismo nel valore osservato.
function rmWithRetry(target, attempts = 5) {
  let lastErr = null;
  for (let i = 0; i < attempts; i += 1) {
    try {
      rmSync(target, { recursive: true, force: true, maxRetries: 3, retryDelay: 50 });
      return;
    } catch (e) {
      lastErr = e;
      // Backoff bloccante deterministico (50ms, 100ms, 150ms, ...). Atomics.wait
      // su un buffer dedicato non introduce non-determinismo nell'output.
      if (i < attempts - 1) {
        try { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50 * (i + 1)); }
        catch { /* Atomics non disponibile: prosegui senza attesa */ }
      }
    }
  }
  // Esaurito il retry: rilancia l'ultimo errore (un fallimento REALE deve
  // emergere, non essere mascherato).
  if (lastErr) throw lastErr;
}

// Crea una copia temporanea isolata della reference app.
//
// Opzioni:
//   id            etichetta della copia (default: timestamp+random). La dir e'
//                 eval/.tmp-verify/<id>.
//   includeGit    copia anche .git (default true: necessario per lo scope
//                 history di S2 e per i commit isolati del loop).
//   sourceApp     ADDITIVO (BD-1): dir SORGENTE da copiare. Default
//                 CANONICAL_REFERENCE_APP -> comportamento BIT-INVARIANTE
//                 (i chiamanti esistenti non passano sourceApp e copiano la
//                 canonica esattamente come prima). Override usato SOLO dal
//                 path eval-only di run_loop (--fixture-app) per copiare una
//                 reference-app di fixture al posto della canonica. La
//                 DESTINAZIONE resta SEMPRE eval/.tmp-verify/<id> (dentro
//                 TMP_VERIFY_ROOT) -> i guardrail di destroyVerifyWorkspace
//                 restano INVARIATI (rifiutano la canonica e i path fuori da
//                 TMP_VERIFY_ROOT, indipendentemente dalla sorgente).
//   linkNodeModules  se true, NON copia node_modules ma lo richiama via symlink
//                 (piu' veloce). Default: false (copia integrale, piu' robusta
//                 su Windows dove i symlink possono richiedere privilegi).
//
// Ritorna { dir, id, cleanup }.
export function createVerifyWorkspace(opts = {}) {
  const { includeGit = true } = opts;
  // sourceApp ADDITIVO: default = canonica (BIT-invariante). Se passato, e' la
  // reference-app del fixture da copiare. Risolto a path assoluto.
  const sourceApp = opts.sourceApp ? resolve(opts.sourceApp) : CANONICAL_REFERENCE_APP;
  // id UNICO-per-run: pid + contatore monotono (NO Date.now/Math.random). SEMPRE
  // derivato da uniqueWorkspaceId, ANCHE quando il chiamante passa un'etichetta:
  // l'etichetta diventa il PREFISSO e vi appendiamo pid+counter. Il default di
  // destrutturazione (id = uniqueWorkspaceId(opts.id)) scattava SOLO con
  // id===undefined: poiche' run_loop/run_checkpoint passano un id ESPLICITO, lo
  // bypassava e ricadeva sul path FISSO (es. 'loop-loop-session') -> due run
  // concorrenti (piu' gate in parallelo) condividevano la stessa dir e si
  // distruggevano a vicenda nel cleanup (ENOENT su chmod) -> run_loop usciva 1 ->
  // m1/m2/m3 rossi INTERMITTENTI. Ora l'unicita' e' incondizionata.
  const id = uniqueWorkspaceId(opts.id);

  if (!existsSync(sourceApp)) {
    throw new Error(`reference-app sorgente assente: ${sourceApp}`);
  }

  mkdirSync(TMP_VERIFY_ROOT, { recursive: true });
  const dir = join(TMP_VERIFY_ROOT, id);

  // Copia pulita: se per qualche motivo la dir esiste gia', azzerala prima
  // (con retry/backoff: una dir stale potrebbe essere ancora locked su Windows).
  if (existsSync(dir)) rmWithRetry(dir);

  // cpSync ricorsivo. Filtriamo via le entry indesiderate. NB: includiamo
  // node_modules perche' run_deadcode (knip) richiede il binario locale del
  // progetto target (node_modules/knip/bin/knip.js) — senza, l'oracolo
  // dead-code fallirebbe. Includiamo .git per lo scope history.
  cpSync(sourceApp, dir, {
    recursive: true,
    dereference: false,
    filter: (src) => {
      const base = src.slice(sourceApp.length + 1).split(/[\\/]/)[0];
      if (!includeGit && base === '.git') return false;
      if (SKIP_TOP_LEVEL.has(base)) return false;
      return true;
    },
  });

  const cleanup = () => destroyVerifyWorkspace(dir);
  return { dir, id, cleanup };
}

// Rimuove una copia temporanea (rm -rf). Idempotente: no-op se assente.
export function destroyVerifyWorkspace(dir) {
  if (!dir) return;
  const abs = resolve(dir);
  // Guardrail: non rimuovere mai nulla fuori da eval/.tmp-verify, e MAI il
  // fixture canonico. Errore esplicito se qualcuno passa un path sbagliato.
  if (abs === CANONICAL_REFERENCE_APP) {
    throw new Error('RIFIUTO: tentata rimozione del fixture canonico eval/reference-app');
  }
  if (!abs.startsWith(TMP_VERIFY_ROOT)) {
    throw new Error(`RIFIUTO: cleanup fuori da eval/.tmp-verify: ${abs}`);
  }
  // rm con retry/backoff: assorbe un EPERM/EBUSY transitorio su Windows (handle
  // non ancora rilasciato da un figlio appena terminato) -> niente rosso flaky.
  if (existsSync(abs)) rmWithRetry(abs);
  // Pota la radice .tmp-verify se ora e' vuota (nessuna altra copia residua).
  try {
    if (existsSync(TMP_VERIFY_ROOT) && readdirSync(TMP_VERIFY_ROOT).length === 0) {
      rmWithRetry(TMP_VERIFY_ROOT);
    }
  } catch { /* best-effort: una radice non vuota o concorrente non e' un errore */ }
}

// Pulisce TUTTE le copie temporanee residue (es. dopo un crash). Idempotente.
export function cleanupAllVerifyWorkspaces() {
  // rmWithRetry (NON rmSync nudo): su Windows TMP_VERIFY_ROOT puo' essere
  // transitoriamente LOCKED da un figlio appena terminato -> un rmSync nudo
  // lancerebbe EPERM/EBUSY e farebbe CRASHARE il chiamante (es. il gate M4 che
  // chiama questa funzione in cima, prima di ogni check). Il retry/backoff
  // assorbe il lock transitorio; un fallimento reale e persistente riemerge.
  if (existsSync(TMP_VERIFY_ROOT)) rmWithRetry(TMP_VERIFY_ROOT);
}
