// build_discipline.mjs — disciplina di costruzione BUILD: tidy advisory (BD-1, §5.2/§5.3).
//
// *** ADVISORY, MAI GATE (L-COL-006) ***
// Questo modulo emette un SEGNALE ISPEZIONABILE di complessita di scrittura
// ("troppo complicato? ogni riga traccia?", momento 3 della costruzione). Il
// segnale e' ADVISORY: NON entra MAI negli input di runCheckpoint — l'oracolo
// resta l'unico giudice (L-COL-002). Il sotto-test §7.2a dell'harness PROVA che
// il flag puo' essere settato MENTRE il checkpoint e' verde (flag != gate).
//
// *** DETERMINISMO (L-COL-002) ***
// Il segnale e' un CONTEGGIO statico di marcatori di sovra-astrazione nei
// sorgenti del fixture (interface/class/abstract declarations). Niente
// Date.now()/Math.random(): l'output e' funzione PURA dell'albero sorgente.
// I file sono visitati in ordine LESSICOGRAFICO stabile (sort), cosi' `notes`
// e i conteggi sono riproducibili byte-per-byte (k=2).
//
// Node ESM, solo built-in (fs, path). Niente rete, niente dipendenze npm.

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

// Soglia di sovra-astrazione PER-FILE: oltre questo numero di marcatori
// (interface/class/abstract) in un SINGOLO file sorgente, il file e' segnalato
// come sospetto di sovra-astrazione. Calibrata sui fixture BD-1: la fixture
// `overcomplicated-correct` ha validators.ts con >3 marcatori (interface +
// abstract class + 2 class concrete + abstract method); la fixture
// `orphan-injecting` (scrittura minima) ne ha 0. Soglia conservativa: un
// modulo con piu' di 3 astrazioni dichiarate per un compito single-use e' il
// segnale advisory cercato dal momento 3.
const PER_FILE_ABSTRACTION_THRESHOLD = 3;

// Estensioni dei sorgenti su cui contare i marcatori. Solo codice TS/JS: i
// marcatori `interface`/`abstract` sono idiomi TS; `class ` copre anche JS.
const SOURCE_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs']);

// Cartelle da NON visitare: artefatti, dipendenze, build, VCS. Escluderle tiene
// il segnale ancorato al codice SCRITTO (non alle librerie di terze parti, dove
// `class `/`interface ` abbondano e falserebbero il conteggio).
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'build', 'coverage', '.tmp-verify']);

// Sotto-directory del fixture in cui cercare i sorgenti. Le reference-app
// canoniche del progetto tengono il codice scritto sotto `src/` (TS/JS) o
// `app/` (Python — qui non contato, niente marcatori OOP TS). Limitiamo la
// scansione a queste radici quando esistono per non visitare l'intera copia;
// se nessuna esiste, ricadiamo sulla radice del fixture (filtrata da SKIP_DIRS).
const SOURCE_ROOTS = ['src', 'app', 'lib'];

// Marcatori di sovra-astrazione, contati per OCCORRENZA di dichiarazione su
// riga (ancorati a inizio-riga, eventuale `export `/whitespace davanti). NON
// usiamo un parser: un conteggio testuale e' sufficiente e DETERMINISTICO per
// un segnale advisory. L'ordine e la lista sono fissi.
const ABSTRACTION_MARKERS = [
  // `interface Foo {` — contratto astratto.
  { name: 'interface', re: /^\s*(?:export\s+)?interface\s+[A-Za-z_$]/ },
  // `abstract class Foo` o `abstract method(...)` — astrazione dichiarata.
  { name: 'abstract', re: /^\s*(?:export\s+)?(?:public\s+|private\s+|protected\s+)?abstract\s+/ },
  // `class Foo` (inclusa `export class`, esclusa gia' contata `abstract class`
  // via il marcatore `abstract` — ma per il conteggio le trattiamo separate:
  // una `abstract class` incrementa SIA `abstract` SIA `class`, segnale
  // coerente "due astrazioni sulla stessa riga").
  { name: 'class', re: /^\s*(?:export\s+)?(?:abstract\s+)?class\s+[A-Za-z_$]/ },
];

// Conta i marcatori di sovra-astrazione in un singolo file sorgente. Ritorna
// il totale (somma su tutte le righe e tutti i marcatori). Lettura UTF-8;
// nessuna sorgente di non-determinismo.
function countAbstractionMarkers(absFile) {
  let src;
  try { src = readFileSync(absFile, 'utf8'); } catch { return 0; }
  const lines = src.split(/\r?\n/);
  let count = 0;
  for (const line of lines) {
    for (const marker of ABSTRACTION_MARKERS) {
      if (marker.re.test(line)) count += 1;
    }
  }
  return count;
}

// Raccoglie ricorsivamente i file sorgente sotto `root` (assoluto), in ordine
// LESSICOGRAFICO STABILE. Salta le SKIP_DIRS. Determinismo: readdirSync seguito
// da sort esplicito -> ordine di visita riproducibile su ogni piattaforma.
function collectSourceFiles(root) {
  const out = [];
  if (!existsSync(root)) return out;
  let entries;
  try { entries = readdirSync(root); } catch { return out; }
  entries.sort(); // ordine stabile, niente dipendenza dall'ordine del FS.
  for (const name of entries) {
    if (SKIP_DIRS.has(name)) continue;
    const abs = join(root, name);
    let st;
    try { st = statSync(abs); } catch { continue; }
    if (st.isDirectory()) {
      out.push(...collectSourceFiles(abs));
    } else if (st.isFile()) {
      const dot = name.lastIndexOf('.');
      const ext = dot >= 0 ? name.slice(dot) : '';
      if (SOURCE_EXTENSIONS.has(ext)) out.push(abs);
    }
  }
  return out;
}

// Determina le radici di scansione: le SOURCE_ROOTS esistenti sotto il fixture,
// oppure il fixture stesso (filtrato da SKIP_DIRS) se nessuna esiste.
function scanRoots(referenceApp) {
  const present = SOURCE_ROOTS
    .map((r) => resolve(referenceApp, r))
    .filter((p) => existsSync(p));
  return present.length > 0 ? present : [resolve(referenceApp)];
}

// tidyAdvisory(referenceApp, { runOpts }) -> segnale advisory DETERMINISTICO.
//
//   referenceApp  dir radice del fixture (la COPIA temp del loop, mai il
//                 fixture canonico). I sorgenti sono cercati sotto src/app/lib.
//   runOpts       opzioni di run (createdAt deterministico). Accettato per
//                 simmetria con gli altri attori del loop; NON usato per
//                 generare valori (nessun timestamp nell'output).
//
// Ritorna SEMPRE { advisory:true, complexity_flag:boolean, notes:[...] }.
//   - advisory:true        marca il record come advisory (mai un verdetto).
//   - complexity_flag      true se ALMENO un file supera la soglia di
//                          sovra-astrazione per-file.
//   - notes                elenco ISPEZIONABILE e DETERMINISTICO: per ogni file
//                          oltre soglia, una nota {file (relativo), markers,
//                          threshold, reason}. Ordine lessicografico stabile.
//
// *** Questo oggetto NON deve MAI essere passato a runCheckpoint. ***
export function tidyAdvisory(referenceApp, opts = {}) {
  const root = resolve(referenceApp);
  const roots = scanRoots(root);

  const files = [];
  for (const r of roots) files.push(...collectSourceFiles(r));
  // Dedup + ordine stabile globale (radici multiple potrebbero sovrapporsi solo
  // in casi anomali; sort finale garantisce comunque determinismo).
  const unique = Array.from(new Set(files)).sort();

  const notes = [];
  let complexityFlag = false;
  for (const abs of unique) {
    const markers = countAbstractionMarkers(abs);
    if (markers > PER_FILE_ABSTRACTION_THRESHOLD) {
      complexityFlag = true;
      // Path RELATIVO al fixture per una nota stabile (niente path assoluto
      // della copia temp, che varia per pid/counter -> non riproducibile).
      const rel = abs.startsWith(root) ? abs.slice(root.length + 1).replace(/\\/g, '/') : abs;
      notes.push({
        file: rel,
        markers,
        threshold: PER_FILE_ABSTRACTION_THRESHOLD,
        reason: 'sovra-astrazione: marcatori (interface/class/abstract) oltre soglia per file single-use',
      });
    }
  }

  return {
    advisory: true,
    complexity_flag: complexityFlag,
    notes,
  };
}
