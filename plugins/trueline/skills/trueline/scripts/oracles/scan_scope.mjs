// scan_scope.mjs — CONFINE DELLO SCOPE DI SCANSIONE, dichiarato e visibile
// (PLAN 2026-07-28 §3.1; precedente manifest-driven: L-COL-029, cfr. rls_scan.mjs).
//
// PROBLEMA risolto: la misura su 4 progetti reali ha dato 192 finding secret e
// ZERO segreti veri. Il rumore non viene da una regola sbagliata, viene dal fatto
// che stiamo guardando file che non sono sorgente d'autore (artefatti di build,
// codegen tracciato dentro src/, dump di dati). Il confine "generato vs d'autore"
// NON e' inferibile dal path di primo livello: va DICHIARATO.
//
// DUE INVARIANTI, e sono la ragione per cui questo modulo puo' esistere senza
// diventare un interruttore per spegnere l'oracolo:
//
//   1) IL DEFAULT E' VUOTO (BIT-INVARIANZA). DEFAULT_SCAN_EXCLUDE = []. Senza
//      dichiarazioni, resolveScanScope torna zero pattern e applyScanScope non
//      esclude NULLA: l'insieme dei finding e' byte-identico a prima di questo
//      modulo. E' cio' che tiene in piedi m5 56/56 e i 16 verify_fix_check per
//      COSTRUZIONE, non per fortuna. Chi tocca questo file rompe quella prova.
//
//   2) NESSUNA ESCLUSIONE E' SILENZIOSA (L-COL-006). Tutto cio' che non si guarda
//      esce in scanScopeCoverage con pattern, PROVENIENZA e numero di finding
//      soppressi — anche i pattern che non hanno soppresso niente. Non scansionare
//      qualcosa non e' un verde: e' una copertura mancante, e va scritta nero su
//      bianco a ogni checkpoint. Un'esclusione taciuta sarebbe un bypass; una
//      ridichiarata a ogni giro no.
//
// PRECEDENZA — UNIONE, NON SOVRASCRITTURA. Il progetto AGGIUNGE alla conoscenza
// d'ecosistema, non la rimpiazza (chi dichiara `backups/**` non intende con cio'
// smettere di escludere `.next/**`). Quindi le tre fonti si SOMMANO, e ogni
// pattern si porta dietro la sua provenienza — senza provenienza la coverage non
// potrebbe dire A CHI attribuire un'esclusione:
//   1) opts.exclude                                   -> source 'caller'
//   2) <projectDir>/.trueline/scan-scope.json          -> source 'project'  (leva 3)
//   3) opts.manifest.oracles.secret.exclude            -> source 'manifest' (leva 1)
//   4) DEFAULT_SCAN_EXCLUDE = []
// L'ordine conta solo per l'ATTRIBUZIONE (primo pattern che matcha) e per la
// deduplica: l'insieme escluso e' l'unione, qualunque sia l'ordine.
//
// MATCHER MINIMALE, SENZA DIPENDENZE — e senza regex dell'utente. Un pattern non
// deve essere un canale per iniettare comportamento nel motore: ogni carattere che
// non sia `*` viene ESCAPATO prima di finire in una RegExp. Chi scrive `src/(a|b).ts`
// esclude il file che si chiama letteralmente cosi', non l'alternanza.
//
// Node ESM, solo built-in (fs, path). Niente rete, niente dipendenze npm.

import { existsSync, readFileSync } from 'node:fs';
import { isAbsolute, relative, resolve } from 'node:path';

import { classify, loadManifest } from '../ecosystem/resolve.mjs';

// Nome del file di dichiarazione di progetto (leva 3). Sta sotto `.trueline/`
// perche' e' configurazione DELLO STRUMENTO nel progetto ospite, non del progetto.
export const PROJECT_SCOPE_FILE = '.trueline/scan-scope.json';

// Le tre provenienze ammesse, in ordine di precedenza. Esportate perche' la
// coverage e i test devono poter asserire il vocabolario, non ricopiarlo.
export const SCAN_SCOPE_SOURCES = Object.freeze(['caller', 'project', 'manifest']);

// DEFAULT VUOTO = BIT-INVARIANZA (invariante 1). Congelato apposta: una mutazione
// accidentale (`DEFAULT_SCAN_EXCLUDE.push(...)` da un chiamante) cambierebbe il
// comportamento di OGNI progetto senza che nessuno l'abbia dichiarato.
export const DEFAULT_SCAN_EXCLUDE = Object.freeze([]);

// -----------------------------------------------------------------------------
// Path: normalizzazione a relativo-POSIX rispetto a projectDir.
// -----------------------------------------------------------------------------

// gitleaks emette path ASSOLUTI in working-tree e RELATIVI in history; su Windows
// con separatore `\`. Il match avviene SEMPRE sul path relativo a projectDir con
// separatore '/'. Sbagliare qui non da' un errore: da' silenziosamente "non esclude
// niente" (pattern `dist/` contro `dist\a.js`) oppure "esclude troppo" — ed e' il
// tipo di bug che nessun test di alto livello vede.
function toPosix(p) {
  return String(p).replace(/\\/g, '/');
}

// Ritorna il path relativo POSIX di `rawPath` rispetto a `projectDir`, oppure null
// se il path e' inutilizzabile o cade FUORI dal progetto. null => il finding NON e'
// escludibile: fuori dal perimetro dichiarato non si tocca niente (conservativo).
export function relativeScanPath(rawPath, projectDir) {
  if (rawPath === undefined || rawPath === null) return null;
  const raw = String(rawPath).trim();
  if (raw === '') return null;

  let rel;
  if (isAbsolute(raw) || /^[A-Za-z]:[\\/]/.test(raw)) {
    if (!projectDir) return null; // assoluto senza radice: non relativizzabile
    rel = relative(resolve(projectDir), resolve(raw));
  } else {
    rel = raw;
  }

  rel = toPosix(rel).replace(/^\.\//, '').replace(/\/+/g, '/').replace(/\/+$/, '');
  if (rel === '' || rel === '.') return null;
  // `..` in testa = il file sta fuori da projectDir: nessun pattern del progetto
  // ha titolo per parlarne. Lo dichiariamo non-escludibile invece di indovinare.
  if (rel === '..' || rel.startsWith('../')) return null;
  return rel;
}

// Estrae il path da un finding. Il modulo lavora PRIMA della normalizzazione
// (04): la forma nativa gitleaks (`File`) e' il caso reale. Le altre chiavi sono
// tolleranza deliberata verso il finding model normalizzato (`location.file`), in
// modo che lo stesso scope sia applicabile in baseline/checkpoint senza duplicare
// la logica. Un finding senza path riconoscibile ritorna null -> viene TENUTO.
export function findingScanPath(finding, projectDir) {
  if (!finding || typeof finding !== 'object') return null;
  const candidates = [
    finding.File,
    finding.file,
    finding.path,
    finding.location && finding.location.file,
  ];
  for (const c of candidates) {
    const rel = relativeScanPath(c, projectDir);
    if (rel !== null) return rel;
  }
  return null;
}

// -----------------------------------------------------------------------------
// Pattern: validazione e compilazione (niente regex utente)
// -----------------------------------------------------------------------------

const REGEX_META = /[.*+?^${}()|[\]\\]/g;

function escapeRegex(ch) {
  return ch.replace(REGEX_META, '\\$&');
}

// TETTI SULLA FORMA DEL PATTERN — i pattern arrivano anche da `.trueline/scan-scope.json`
// del progetto OSPITE, cioe' da un repo di terzi che Trueline scansiona in REMEDIATE:
// sono INPUT NON FIDATO. Non c'e' regex injection (ogni metacarattere e' escapato), ma
// `**` compila in `.*` e piu' `**` alternati a letterali producono backtracking
// esponenziale. MISURATO su `**a**a**a**a**a**a**a**b` contro un path di sole 'a':
// 20 char -> 3.4ms, 28 -> 11.8ms, 32 -> 35.8ms, 36 -> 94.2ms, 40 -> 222ms (~2.5x ogni
// +4 caratteri): un path reale di 60-80 caratteri porta il SINGOLO confronto a decine di
// secondi. E' una negazione di servizio a costo zero per chi la scrive.
// SI CONTANO SOLO I `**`, non i `*`: `*` compila in `[^/]*`, si ferma al separatore e
// non produce l'esplosione; e' `**` -> `.*` a farlo. Tetto = 3, misurato contro l'uso
// reale e contro il caso patologico (path di 400 caratteri di sola 'a'):
//   `**a**a**b`     (3 `**`) -> 13.6ms   <- il PEGGIO ammesso
//   `**a**a**a**b`  (4 `**`) -> 1726ms
//   `**a**a**a**a**a**a**a**b` (8 `**`) -> fuori scala
// Nessun pattern legittimo si avvicina: `.next/**` e `**/database.types.ts` ne hanno 1,
// `**/src/**/*.test.*` ne ha 2. E il rifiuto e' ESPLICITO, non silenzioso: un pattern
// scartato in silenzio sarebbe un'esclusione che il progetto crede attiva (L-COL-006).
const MAX_PATTERN_LEN = 512;
const MAX_PATTERN_DOUBLESTAR = 3;

// Un pattern malformato e' un ERRORE ESPLICITO, non un pattern ignorato: un
// pattern che non matcha niente perche' scritto male sembrerebbe "una regola che
// non serviva", mentre e' un'esclusione che il progetto CREDE attiva (L-COL-006).
function validatePattern(raw, source) {
  const where = `scope pattern (source=${source})`;
  if (typeof raw !== 'string') {
    throw new Error(`[scan_scope] ${where}: atteso una stringa, ricevuto ${typeof raw}`);
  }
  let p = toPosix(raw).trim();
  if (p === '') {
    throw new Error(`[scan_scope] ${where}: pattern vuoto`);
  }
  // SIMMETRIA CON relativeScanPath — il difetto sottile che questa riga chiude.
  // Il PATH viene normalizzato (`^./` tolto, `/+` collassati); se il PATTERN non lo
  // fosse, `./dist/**` verrebbe ACCETTATO senza obiezioni e non matcherebbe MAI
  // `dist/a.js` (verificato: `./dist/**` -> false, `dist/**` -> true). La direzione e'
  // conservativa (si guarda di piu'), quindi non produce falsi verdi — ma produce
  // esattamente la «copertura creduta e non presente» che questo modulo esiste per
  // chiudere, e nella coverage apparirebbe come matched=0, indistinguibile da un
  // pattern legittimo che non ha rumore da coprire. Le due normalizzazioni devono
  // essere LA STESSA, o il pattern e il path parlano due lingue diverse.
  p = p.replace(/^\.\//, '').replace(/\/+/g, '/').replace(/(^|\/)\.\//g, '$1');
  if (p === '' || p === '.') {
    throw new Error(`[scan_scope] ${where}: pattern vuoto dopo la normalizzazione: "${raw}"`);
  }
  if (p.length > MAX_PATTERN_LEN) {
    throw new Error(`[scan_scope] ${where}: pattern troppo lungo (${p.length} > ${MAX_PATTERN_LEN} caratteri)`);
  }
  const doubleStars = (p.match(/\*{2,}/g) || []).length;
  if (doubleStars > MAX_PATTERN_DOUBLESTAR) {
    throw new Error(
      `[scan_scope] ${where}: troppi \`**\` (${doubleStars} > ${MAX_PATTERN_DOUBLESTAR}) in "${raw}" — `
      + 'un pattern con molti `**` alternati a letterali fa esplodere il backtracking della RegExp '
      + '(negazione di servizio sulla scansione, e i pattern arrivano anche dal repo OSPITE): '
      + 'rifiutato invece che eseguito',
    );
  }
  if (p.startsWith('!')) {
    // La negazione implicherebbe un ordine di valutazione e "ri-inclusioni" non
    // visibili nella coverage: fuori contratto, e va detto, non ignorato.
    throw new Error(`[scan_scope] ${where}: la negazione non e' supportata: "${raw}"`);
  }
  if (p.startsWith('/') || /^[A-Za-z]:\//.test(p)) {
    // I pattern sono SEMPRE relativi a projectDir. Un pattern assoluto sembrerebbe
    // funzionare sulla macchina di chi l'ha scritto e su nessun'altra.
    throw new Error(`[scan_scope] ${where}: i pattern devono essere relativi al progetto: "${raw}"`);
  }
  if (p === '..' || p.startsWith('../') || p.includes('/../') || p.endsWith('/..')) {
    throw new Error(`[scan_scope] ${where}: "${raw}" esce dal progetto (segmento "..")`);
  }
  // UN PATTERN CHE PRENDE TUTTO NON E' UN CONFINE DI SCANSIONE: E' L'ORACOLO SPENTO.
  // Misurato PRIMA di questa guardia: `{"exclude":["**"],"reason":"x"}` era ACCETTATO e
  // sopprimeva il 100% dei finding (kept 0/4). La coverage lo dichiarerebbe — ed e' la
  // visibilita' a rendere legittima la leva 3 — ma «dichiarato» non basta quando
  // l'effetto e' spegnere l'oracolo dei segreti: quella non e' una decisione da prendere
  // dentro un file di scope, dove passa senza che nessuno la legga come tale.
  // Il riconoscimento e' PER COMPORTAMENTO, non per testo: si compila il pattern e lo si
  // prova su path-sonda di forme diverse. Cosi' cade anche `**/*`, `**/**`, `./**` e
  // qualunque altra scrittura equivalente che una lista di stringhe vietate mancherebbe.
  // `**/*.js` non cade (non prende i path senza estensione): aggressivo ma mirato, resta
  // una scelta del progetto, dichiarata nella coverage.
  const CATCH_ALL_PROBES = ['a', 'a/b', 'a/b/c.txt', 'x.js', 'deep/dir/name/file.min.map'];
  const probeRe = compilePattern(p);
  if (CATCH_ALL_PROBES.every((s) => probeRe.test(s))) {
    throw new Error(
      `[scan_scope] ${where}: "${raw}" escluderebbe l'INTERO progetto — non e' un confine di `
      + 'scansione, e\' l\'oracolo dei segreti spento. Dichiara i path che non sono sorgente '
      + 'd\'autore (es. "dist/**", "backups/**"), non tutto.',
    );
  }
  return p;
}

// Compila un pattern in RegExp. UNICI metacaratteri riconosciuti:
//   `**/`  zero o piu' segmenti di directory  (`**/database.types.ts` prende anche
//          il file in radice: e' la semantica che ci si aspetta da un pattern
//          "ovunque si chiami cosi'")
//   `**`   attraversa '/'
//   `*`    NON attraversa '/'
// Un pattern che finisce con '/' e' un PREFISSO-DIRECTORY (`dist/` == `dist/**`).
// Un pattern senza wildcard e' un match ESATTO sul path relativo.
// Tutto il resto e' letterale: `.` e' un punto, `(` e' una parentesi.
function compilePattern(pattern) {
  // `***` e `****` sono `**` scritti male: collassati PRIMA di compilare, o
  // genererebbero `.*.*` — semanticamente identico, esponenzialmente piu' lento.
  const p0 = pattern.replace(/\*{3,}/g, '**');
  const p = p0.endsWith('/') ? `${p0}**` : p0;
  let re = '^';
  let i = 0;
  while (i < p.length) {
    if (p[i] === '*' && p[i + 1] === '*') {
      if (p[i + 2] === '/') {
        re += '(?:.*/)?'; // `**/` = zero o piu' segmenti
        i += 3;
        continue;
      }
      re += '.*';
      i += 2;
      continue;
    }
    if (p[i] === '*') {
      re += '[^/]*'; // `*` si ferma al separatore
      i += 1;
      continue;
    }
    re += escapeRegex(p[i]);
    i += 1;
  }
  re += '$';
  // Case-SENSITIVE anche su Windows: git tratta i path come case-sensitive, e un
  // match case-insensitive escluderebbe piu' di quanto dichiarato.
  return new RegExp(re);
}

// -----------------------------------------------------------------------------
// Leva 3 — dichiarazione di progetto
// -----------------------------------------------------------------------------

// Legge <projectDir>/.trueline/scan-scope.json.
//   File ASSENTE          -> normale, nessun errore, nessun pattern (il caso comune).
//   File PRESENTE e rotto -> ERRORE. Un'esclusione che il progetto crede attiva e
//                            che noi ignoriamo in silenzio e' peggio di nessuna
//                            esclusione: e' una copertura creduta e non c'e'.
//   exclude non vuoto senza `reason` -> RIFIUTATO. La legittimita' di questa leva
//                            sta tutta nella visibilita': un'esclusione senza
//                            motivo dichiarato non e' riportabile nella coverage,
//                            quindi non e' ammessa (PLAN §3.4).
export function readProjectScanScope(projectDir) {
  if (!projectDir) return { exclude: [], reason: null, present: false };
  const file = resolve(projectDir, '.trueline', 'scan-scope.json');
  if (!existsSync(file)) return { exclude: [], reason: null, present: false, file };

  let raw;
  try {
    raw = readFileSync(file, 'utf8');
  } catch (err) {
    throw new Error(`[scan_scope] ${PROJECT_SCOPE_FILE} illeggibile: ${err.message}`);
  }

  let data;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    throw new Error(`[scan_scope] ${PROJECT_SCOPE_FILE} non e' JSON valido: ${err.message}`);
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error(`[scan_scope] ${PROJECT_SCOPE_FILE}: atteso un oggetto JSON`);
  }

  const { exclude } = data;
  if (exclude === undefined) {
    throw new Error(`[scan_scope] ${PROJECT_SCOPE_FILE}: campo "exclude" mancante (atteso un array)`);
  }
  if (!Array.isArray(exclude)) {
    throw new Error(`[scan_scope] ${PROJECT_SCOPE_FILE}: "exclude" deve essere un array`);
  }

  const reason = typeof data.reason === 'string' ? data.reason.trim() : '';
  if (exclude.length > 0 && reason === '') {
    throw new Error(
      `[scan_scope] ${PROJECT_SCOPE_FILE}: "reason" obbligatorio e non vuoto quando "exclude" non e' vuoto ` +
      '(un\'esclusione senza motivo dichiarato non e\' riportabile nella coverage: rifiutata, non ignorata)',
    );
  }

  return { exclude, reason: reason === '' ? null : reason, present: true, file };
}

// -----------------------------------------------------------------------------
// resolveScanScope
// -----------------------------------------------------------------------------

function manifestExclude(opts) {
  const m = opts && opts.manifest;
  const fromManifest = m && m.oracles && m.oracles.secret && m.oracles.secret.exclude;
  if (fromManifest === undefined || fromManifest === null) return [];
  if (!Array.isArray(fromManifest)) {
    throw new Error('[scan_scope] manifest.oracles.secret.exclude deve essere un array');
  }
  return fromManifest;
}

// resolveScanScope(projectDir, opts) -> { patterns, sources, project_reason }
//
//   projectDir  radice del progetto (o della copia temp) — base dei path relativi
//   opts        { exclude?: string[], manifest?: <ecosystem.json> }
//
//   patterns         [{ pattern, source, regex, reason? }] — UNIONE delle tre fonti
//                    in ordine di precedenza, deduplicata sul testo del pattern
//                    (la prima occorrenza vince: cosi' la coverage attribuisce
//                    l'esclusione alla fonte piu' vicina a chi l'ha decisa).
//   sources          { caller: n, project: n, manifest: n } — conteggio DOPO la
//                    deduplica: la somma e' esattamente patterns.length.
//   project_reason   il `reason` della dichiarazione di progetto (o null).
//
// Con zero dichiarazioni: patterns = [] (BIT-invarianza, invariante 1).
export function resolveScanScope(projectDir, opts = {}) {
  const callerExclude = Array.isArray(opts.exclude) ? opts.exclude : [];
  const project = readProjectScanScope(projectDir);

  const groups = [
    ['caller', callerExclude],
    ['project', project.exclude],
    ['manifest', manifestExclude(opts)],
  ];

  const patterns = [];
  const sources = { caller: 0, project: 0, manifest: 0 };
  const seen = new Set();

  for (const [source, list] of groups) {
    for (const raw of list) {
      const pattern = validatePattern(raw, source);
      // Deduplica: lo stesso pattern dichiarato due volte NON deve contare due
      // volte nella coverage, o "matched" sembrerebbe raddoppiare le esclusioni.
      if (seen.has(pattern)) continue;
      seen.add(pattern);
      const entry = { pattern, source, regex: compilePattern(pattern) };
      if (source === 'project' && project.reason) entry.reason = project.reason;
      patterns.push(entry);
      sources[source] += 1;
    }
  }

  return { patterns, sources, project_reason: project.reason };
}

// -----------------------------------------------------------------------------
// scanScopeFor — LA SORGENTE UNICA DELLO SCOPE PER I CHIAMANTI DELLA MACCHINA
// -----------------------------------------------------------------------------

// resolveScanScope pretende il manifest GIA' risolto. Se ogni chiamante lo
// risolvesse a modo suo, checkpoint e baseline potrebbero calcolare due scope
// DIVERSI sullo STESSO progetto — ed e' esattamente il bug che genera il DELTA
// FANTASMA: la baseline congela un fingerprint che il checkpoint non vede piu'
// (o viceversa, e allora un finding gia' noto torna 'new' e BLOCCA a ogni giro,
// senza che nessuno abbia introdotto niente).
//
// Quindi la risoluzione del manifest sta QUI, una volta sola, e checkpoint.mjs /
// baseline.mjs / run_loop.mjs / loop.mjs chiamano TUTTI questa funzione con lo
// STESSO projectDir. Stesso input -> stesso scope, per costruzione.
//
//   opts.manifest === undefined  -> risolto da projectDir (classify -> loadManifest)
//   opts.manifest === null       -> DELIBERATAMENTE nessun manifest (chiamata legacy)
//   opts.manifest === <oggetto>  -> usato com'e' (il chiamante l'ha gia' risolto)
//
// La risoluzione e' DIFENSIVA come resolveManifest del checkpoint: una dir non
// classificabile -> null -> nessun pattern 'manifest'. Non si inventa un
// ecosistema. NB: un errore della DICHIARAZIONE DI PROGETTO (leva 3) NON viene
// invece assorbito: resolveScanScope lancia, e il chiamante deve dichiararlo
// rosso — un'esclusione che il progetto crede attiva e che noi ignoriamo in
// silenzio e' peggio di nessuna esclusione (L-COL-006).
export function scanScopeFor(projectDir, opts = {}) {
  let manifest = opts.manifest;
  if (manifest === undefined) {
    try {
      const id = classify(projectDir);
      manifest = id ? loadManifest(id) : null;
    } catch { manifest = null; }
  }
  return resolveScanScope(projectDir, { ...opts, manifest });
}

// -----------------------------------------------------------------------------
// applyScanScope
// -----------------------------------------------------------------------------

// Normalizza la lista dei path PROTETTI: file che nessun pattern puo' escludere.
// Serve al loop (PLAN §3.5): il loop verifica la SPARIZIONE di un fingerprint; se
// lo scope escludesse il file sotto fix, il loop timbrerebbe `verified` senza che
// nessuno abbia fixato niente. Un verde gratis e' esattamente cio' che questo
// prodotto esiste per impedire.
function protectedSet(protect, projectDir) {
  const out = new Set();
  const list = Array.isArray(protect) ? protect : (protect ? [protect] : []);
  for (const p of list) {
    const rel = relativeScanPath(p, projectDir);
    if (rel !== null) out.add(rel);
  }
  return out;
}

// applyScanScope(findings, scope, projectDir, opts) -> { kept, excluded }
//
//   findings   array di finding (nativi gitleaks o normalizzati)
//   scope      l'oggetto di resolveScanScope (o { patterns: [...] })
//   projectDir radice per il calcolo del path relativo
//   opts       { protect?: string[] } file mai escludibili (loop, §3.5)
//
//   kept      i finding TENUTI, stessi oggetti e stesso ORDINE dell'input
//   excluded  [{ finding, path, pattern, source }] — l'elemento porta il pattern
//             che l'ha soppresso perche' scanScopeCoverage deve poter dire QUANTI
//             finding ha soppresso OGNI pattern: senza attribuzione, la coverage
//             direbbe solo un totale, e "quanto" senza "per cosa" non e' una
//             dichiarazione di copertura.
//
// PRIMO pattern che matcha vince (ordine di precedenza): l'attribuzione e'
// deterministica e un finding non viene mai contato due volte.
// Scope vuoto => kept === findings (per elemento) e excluded === [] : BIT-invarianza.
export function applyScanScope(findings, scope, projectDir, opts = {}) {
  const list = Array.isArray(findings) ? findings : [];
  const patterns = (scope && Array.isArray(scope.patterns)) ? scope.patterns : [];

  // Nessun pattern: uscita immediata SENZA toccare i path. Il cammino
  // BIT-invariante non deve nemmeno dipendere dalla correttezza del matcher.
  if (patterns.length === 0) return { kept: list.slice(), excluded: [] };

  const protectedPaths = protectedSet(opts.protect, projectDir);
  const kept = [];
  const excluded = [];

  for (const finding of list) {
    const path = findingScanPath(finding, projectDir);
    // Senza un path utilizzabile non si esclude: si tiene. Un finding scartato
    // perche' non sapevamo dove fosse sarebbe una perdita silenziosa.
    if (path === null || protectedPaths.has(path)) {
      kept.push(finding);
      continue;
    }
    let hit = null;
    for (const p of patterns) {
      if (p.regex.test(path)) { hit = p; break; }
    }
    if (hit) {
      excluded.push({ finding, path, pattern: hit.pattern, source: hit.source });
    } else {
      kept.push(finding);
    }
  }

  return { kept, excluded };
}

// -----------------------------------------------------------------------------
// scanScopeCoverage
// -----------------------------------------------------------------------------

// scanScopeCoverage(scope, excluded) -> { excluded_patterns, excluded_total }
//
//   excluded_patterns  [{ pattern, source, matched, reason? }] — OGNI pattern
//                      DICHIARATO, anche quelli con matched=0. Un pattern che non
//                      matcha niente e' un'informazione: o il rumore che doveva
//                      coprire non c'e' piu', o il pattern e' sbagliato. Nasconderlo
//                      toglierebbe l'unico segnale che lo distingue.
//   excluded_total     numero di finding soppressi in totale.
//
// Blocco da innestare in coverage.declared_uncovered (04 §10 / 06 §7): e' la
// contropartita dell'invariante 2 — cio' che non si guarda si dichiara.
export function scanScopeCoverage(scope, excluded = []) {
  const patterns = (scope && Array.isArray(scope.patterns)) ? scope.patterns : [];
  const list = Array.isArray(excluded) ? excluded : [];

  // SEPARATORE DELLA CHIAVE (provenienza + pattern): il carattere U+0000 e' scritto
  // come ESCAPE di sei caratteri, mai come byte NUL LETTERALE nel sorgente. Il NUL
  // letterale funziona a runtime ma rende il file BINARIO per grep/ripgrep — che su un
  // modulo di sicurezza smettono di mostrare le corrispondenze e rispondono solo
  // «Binary file matches» — ed e' invisibile in lettura: chi riscrivesse la riga a mano
  // cambierebbe la semantica senza accorgersene. (Difetto reale, corretto il 2026-07-29.)
  const counts = new Map();
  for (const e of list) {
    if (!e || typeof e !== 'object') continue;
    const key = `${e.source}\u0000${e.pattern}`;
    counts.set(key, (counts.get(key) || 0) + 1);
  }

  const excluded_patterns = patterns.map((p) => {
    const row = {
      pattern: p.pattern,
      source: p.source,
      matched: counts.get(`${p.source}\u0000${p.pattern}`) || 0,
    };
    if (p.reason) row.reason = p.reason;
    return row;
  });

  return { excluded_patterns, excluded_total: list.length };
}

export default resolveScanScope;
