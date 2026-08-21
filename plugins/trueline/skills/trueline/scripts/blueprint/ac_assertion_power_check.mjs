#!/usr/bin/env node
// ac_assertion_power_check.mjs — oracolo del POTERE dell'asserzione d'accettazione.
//
// FRATELLO di ac_assertion_trace_check.mjs, NON una sua modifica: quello verifica la
// PROVENIENZA (l'asserzione discende dall'AC), questo verifica il POTERE (l'asserzione
// puo' FALLIRE). Un'asserzione tautologica passa la provenienza a pieni voti.
//
// DUE STADI, e la separazione e' il punto:
//   1) CANDIDATI (statico, SOVRA-INCLUSIVO): nessun verdetto. Misurato il 30/07/2026,
//      un rilevatore statico su raggiungibilita' dei moduli da 2 FALSI POSITIVI su 3.
//   2) VERDETTO (ESECUZIONE): si neutralizza TEMPORANEAMENTE il binding esportato nel
//      sorgente della dir che il checkpoint riceve, e si riesegue QUEL SOLO target_test.
//      Resta verde => l'asserzione e' INERTE. L'autorita' e' l'exit code del runner
//      (L-COL-002), mai l'analisi statica.
//      Quella dir NON e' sempre una copia: nel loop e' un workspace, ma con
//      run_checkpoint --in-place e' l'albero di lavoro VERO dell'utente (vedi RETE DI
//      RIPRISTINO, piu' sotto). La garanzia percio' NON e' l'isolamento: e' il ripristino
//      a BYTE GREZZI verificato per sha256, e un ripristino non bit-esatto esce
//      status:'error', mai un verde.
//
// DIREZIONE CONSERVATIVA, dichiarata: in caso di dubbio NON si segnala. Il file gira a
// livello di FILE, non di singolo test case, quindi un altro test dello stesso file che
// diventa rosso maschera l'inerzia => FALSO NEGATIVO possibile. E' il verso giusto in cui
// sbagliare: un falso positivo renderebbe rosso un progetto sano.
//
// Node ESM, solo built-in.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname, resolve as presolve, relative, isAbsolute } from 'node:path';

const NEUTRAL_STRING = "'\\u0000TRUELINE_NEUTRALIZED'";
const NEUTRAL_NUMBER = '-987654321';

// Trova la fine di un letterale bilanciato partendo da open ({ o [), ignorando
// le parentesi dentro stringhe. Ritorna l'indice del carattere di chiusura, o -1.
function matchBalanced(src, start) {
  const open = src[start];
  const close = open === '{' ? '}' : ']';
  let depth = 0, quote = null;
  for (let i = start; i < src.length; i++) {
    const ch = src[i];
    if (quote) {
      if (ch === '\\') { i++; continue; }
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '`') { quote = ch; continue; }
    if (ch === open) depth++;
    else if (ch === close) { depth--; if (depth === 0) return i; }
  }
  return -1;
}

// Una sola definizione della forma cercata, usata sia da chi neutralizza sia da chi spiega
// perche' non ci e' riuscito: due copie divergerebbero, e la spiegazione finirebbe per
// descrivere una ricerca diversa da quella davvero fatta.
//
// `name` va ESCAPATO, e il caso che lo impone non e' teorico: `$` e' un carattere legale
// in un identificatore JS, e con il flag `m` e' l'ancora di FINE RIGA. Per un binding
// `$el` il match non avverrebbe mai, e neutralizeFailureReason emetterebbe «nessun
// `export const $el` nel modulo» — che e' FALSO, la dichiarazione c'e'. Sarebbe proprio il
// motivo che manda l'utente a cercare il difetto dove non e', cioe' il difetto che la
// distinzione dei motivi qui sotto esiste per chiudere.
const reEscape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const declRe = (name) => new RegExp(`export\\s+const\\s+${reEscape(name)}\\b([^=]*)=\\s*`, 'm');

// Si CERCA sulla copia mascherata e si RISCRIVE sull'originale: maskComments preserva le
// lunghezze apposta, quindi ogni indice vale su entrambe.
//
// Senza questo, una dichiarazione COMMENTATA — il pattern «vecchia versione commentata
// sopra la nuova», o un @example in JSDoc — verrebbe neutralizzata al posto di quella
// viva, che resterebbe intatta. Il file riscritto e' ancora sintatticamente VALIDO, quindi
// niente a valle se ne accorge: lo stadio 2 rilancia il test, lo trova verde e dichiara
// INERTE un progetto sano. Cercare sul mascherato fa sparire il commento dal match, cosi'
// si trova la dichiarazione vera; se l'unica forma presente e' commentata non c'e' match e
// si torna null — il candidato finisce in unresolved, che e' la risposta onesta.
export function neutralizeExport(source, name) {
  const masked = maskComments(source);
  const m = declRe(name).exec(masked);
  if (!m) return null;
  const initStart = m.index + m[0].length;
  const head = source.slice(0, initStart);
  const ch = masked[initStart];
  if (ch === '{' || ch === '[') {
    // Anche il bilanciamento gira sul mascherato: una graffa dentro un commento
    // (`{ a: 1 /* } */ }`) non deve chiudere il letterale in anticipo.
    const end = matchBalanced(masked, initStart);
    if (end < 0) return null;
    return head + (ch === '{' ? '{}' : '[]') + source.slice(end + 1);
  }
  const tail = masked.slice(initStart);
  const strM = /^(['"])(?:\\.|(?!\1).)*\1/.exec(tail);
  if (strM) return head + NEUTRAL_STRING + source.slice(initStart + strM[0].length);
  const numM = /^-?\d+(?:\.\d+)?/.exec(tail);
  if (numM) return head + NEUTRAL_NUMBER + source.slice(initStart + numM[0].length);
  return null; // forma non riconosciuta: si dichiara, non si indovina
}

// Il `null` di neutralizeExport ha TRE cause diverse, e il motivo e' cio' che l'utente
// legge quando l'oracolo NON aggiudica: un motivo impreciso lo manda a cercare il difetto
// dove non e'. «Forma dell'export non riconosciuta» e' vero solo nel primo caso — negli
// altri due la forma e' riconoscibilissima, manca proprio la dichiarazione da mutare.
//   1. dichiarazione VIVA ma initializer non riducibile a inerte (una chiamata, un
//      identificatore, un'arrow) oppure letterale non bilanciato;
//   2. dichiarazione presente SOLO dentro un commento: e' codice MORTO, e neutralizzarlo
//      non cambierebbe nulla dell'esecuzione — mutarlo sarebbe anzi il falso positivo che
//      maskComments esiste per impedire;
//   3. nessuna dichiarazione affatto: il binding non e' un `export const` (funzione,
//      classe, default), o e' il nome di un `import * as ns` — che lo stadio 1 registra
//      apposta per lasciarne traccia, sapendo che qui non si trovera' per costruzione.
export function neutralizeFailureReason(source, name) {
  if (declRe(name).test(maskComments(source))) {
    return `initializer di '${name}' in una forma che il neutralizzatore non sa rendere inerte`;
  }
  if (declRe(name).test(source)) {
    return `dichiarazione di '${name}' presente SOLO in un commento: e' codice morto, non c'e' niente da neutralizzare`;
  }
  return `nessun 'export const ${name}' nel modulo: non e' una costante esportata (funzione, classe, default, o namespace 'import * as ${name}')`;
}

// Sbianca i caratteri DENTRO i commenti lasciando lunghezza e newline intatti, cosi'
// indici e numeri di riga restano quelli del sorgente vero. (PURA, esportata per il test,
// come textTracesAc del fratello ac_assertion_trace_check.mjs.)
//
// Serve perche' un'asserzione CITATA in un commento non viene mai eseguita: neutralizzare
// il suo modulo lascerebbe il file verde e lo stadio 2 la dichiarerebbe INERTE. Sarebbe un
// FALSO POSITIVO, cioe' la sola direzione d'errore che quest'oracolo si vieta. Non e'
// teorico: le fixture stesse ne contengono uno (inert-identity/tests/tokens.test.mjs cita
// la propria asserzione nell'header), misurato il 30/07/2026.
//
// String-aware come commentedPortion() del fratello, e per la stessa ragione al contrario:
// un // dentro una stringa ('http://x') NON apre un commento, altrimenti si perderebbe il
// resto della riga e con esso candidati REALI. I letterali di stringa restano INTATTI:
// ASSERT_RE ammette ' e " perche' deve vedere l'accesso a chiave (obj['k']).
// Limite dichiarato, ereditato dal fratello: i letterali regex non sono riconosciuti, e una
// quote dentro un regex (`/'/g`) puo' far misparsare la riga. Il danno e' pero' CONFINATO
// alla riga (vedi il reset su newline sotto): prima dilagava sul resto del file, e quello
// non era un falso negativo locale ma la disattivazione silenziosa dell'intera maschera.
export function maskComments(src) {
  const out = src.split('');
  let str = null;    // null | "'" | '"' | '`'
  let line = false;  // dentro //
  let block = false; // dentro /* */
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    const c2 = i + 1 < src.length ? src[i + 1] : '';
    if (line) {
      if (c === '\n') { line = false; continue; } // il newline regge il conteggio righe
      out[i] = ' ';
      continue;
    }
    if (block) {
      if (c === '*' && c2 === '/') { out[i] = ' '; out[i + 1] = ' '; i++; block = false; continue; }
      if (c !== '\n') out[i] = ' ';
      continue;
    }
    if (str) {
      // Una stringa '/" non puo' contenere un newline non-escapato. Se lo incontriamo il
      // parse era SBAGLIATO — tipicamente una quote dentro un letterale regex, `/'/g` o
      // `/don't/` — e lo si confina a QUESTA riga. Senza, lo stato stringa resta aperto e
      // da li' in poi nessun commento viene piu' mascherato: tornerebbe per intero il
      // difetto che maskComments esiste per chiudere, e in silenzio.
      if (c === '\n' && str !== '`') { str = null; continue; }
      if (c === '\\') { i++; continue; } // escape: il prossimo char non chiude nulla
      if (c === str) str = null;
      continue;
    }
    if (c === "'" || c === '"' || c === '`') { str = c; continue; }
    if (c === '/' && c2 === '/') { out[i] = ' '; out[i + 1] = ' '; i++; line = true; continue; }
    if (c === '/' && c2 === '*') { out[i] = ' '; out[i + 1] = ' '; i++; block = true; continue; }
  }
  return out.join('');
}

const EXT = ['.ts', '.tsx', '.mjs', '.js', '.jsx'];

// Risolve uno specificatore ai file del progetto. `@/x` -> <app>/src/x (convenzione
// piu' diffusa); relativo -> risolto dal file. Pacchetto npm -> null (fuori scope,
// dichiarato: un binding di libreria non e' codice d'autore da neutralizzare).
//
// ASSUNZIONE non verificata contro il tsconfig, che vale la pena nominare: `@/*` mappato
// alla ROOT del progetto invece che a src/ — configurazione frequente — qui non risolve e
// il binding sparisce in silenzio. L'effetto e' un candidato in meno, cioe' un possibile
// FALSO NEGATIVO: il verso giusto in cui sbagliare, ma resta un buco di copertura.
// Leggere i path del tsconfig e' il modo di chiuderlo, e non e' fatto.
export function resolveSpec(appDir, fromFile, spec) {
  let base;
  if (spec.startsWith('@/')) base = join(appDir, 'src', spec.slice(2));
  else if (spec.startsWith('.')) base = presolve(dirname(fromFile), spec);
  else return null;
  if (existsSync(base) && /\.[cm]?[jt]sx?$/.test(base)) return base;
  for (const e of EXT) if (existsSync(base + e)) return base + e;
  for (const e of EXT) if (existsSync(join(base, 'index' + e))) return join(base, 'index' + e);
  return null;
}

// `src` arriva gia' mascherato dal chiamante: un import commentato non deve registrare un
// binding che non esiste a runtime, per la stessa ragione dell'asserzione commentata.
function importBindings(appDir, file, src) {
  const out = new Map();
  // Apici SINGOLI E DOPPI: Prettier emette doppi di default, quindi riconoscendo i soli
  // singoli l'oracolo sarebbe cieco per costruzione su una fetta larga dei progetti
  // bersaglio — zero binding, zero candidati, un gate che non spara mai e non lo dice.
  for (const m of src.matchAll(/import\s+([^;]*?)\s+from\s+(['"])([^'"]+)\2/g)) {
    const target = resolveSpec(appDir, file, m[3]);
    if (!target) continue;
    const clause = m[1];
    const named = /\{([^}]*)\}/.exec(clause);
    if (named) for (const p of named[1].split(',')) {
      const n = p.trim().split(/\s+as\s+/).pop().trim();
      if (n) out.set(n, target);
    }
    // `import * as ns`: registrato come binding del modulo. Lo stadio 2 cerchera'
    // `export const ns` e non lo trovera', quindi il candidato finira' in unresolved con
    // un motivo. E' l'esito giusto: prima veniva scartato qui, senza lasciare traccia.
    const ns = /^\s*\*\s+as\s+(\w+)\s*$/.exec(clause);
    if (ns) out.set(ns[1], target);
    const def = /^\s*(\w+)\s*(?:,|$)/.exec(clause);
    if (def) out.set(def[1], target);
  }
  return out;
}

const ASSERT_RE = new RegExp(
  // vitest/jest: expect(A).toEqual(B) | .toStrictEqual | .toBe
  'expect\\(\\s*([A-Za-z_$][\\w$.\\[\\]\'"]*)\\s*\\)\\s*\\.\\s*(?:toEqual|toStrictEqual|toBe)\\(\\s*([A-Za-z_$][\\w$.\\[\\]\'"]*)\\s*\\)'
  // node:assert: assert.deepEqual(A, B) e varianti
  + '|assert\\s*\\.\\s*(?:deepEqual|deepStrictEqual|equal|strictEqual)\\(\\s*([A-Za-z_$][\\w$.\\[\\]\'"]*)\\s*,\\s*([A-Za-z_$][\\w$.\\[\\]\'"]*)\\s*\\)',
  'g',
);

export function findCandidates(appDir, testRelPath) {
  const abs = join(appDir, testRelPath);
  if (!existsSync(abs)) return [];
  // Letto e mascherato UNA volta: le due analisi devono vedere lo stesso testo, o un
  // import e la sua asserzione potrebbero non concordare su cosa e' codice vivo.
  const src = maskComments(readFileSync(abs, 'utf8'));
  const imps = importBindings(appDir, abs, src);
  // Il chiamante confronta testFile per uguaglianza con i path del blueprint, che usano
  // sempre `/`: su Windows un separativo nativo qui non matcherebbe mai.
  const testFile = testRelPath.replace(/\\/g, '/');
  const out = [];
  for (const m of src.matchAll(ASSERT_RE)) {
    const a = m[1] || m[3];
    const b = m[2] || m[4];
    if (!a || !b) continue;
    const rootA = a.split(/[.[]/)[0];
    const rootB = b.split(/[.[]/)[0];
    if (rootA === rootB) continue;
    const modA = imps.get(rootA); const modB = imps.get(rootB);
    if (!modA || !modB) continue; // almeno un lato non e' un binding importato
    out.push({
      testFile,
      line: src.slice(0, m.index).split('\n').length,
      // `assertionForm`, non `kind`: lo stadio 2 mette un `kind` sugli irrisolti
      // (structural | failure) che E' il contratto col chiamante, e uno spread
      // `{ ...c, kind }` cancellerebbe in silenzio la forma dell'asserzione.
      assertionForm: m[1] ? 'expect' : 'assert',
      actualRoot: rootA, expectedRoot: rootB,
      bindingName: rootB, bindingModule: modB,
    });
  }
  return out;
}

// -----------------------------------------------------------------------------
// STADIO 2 — il verdetto, che lo emette L'ESECUZIONE
// -----------------------------------------------------------------------------
import { runTargetFile } from '../checkpoint/run_file.mjs';

const sha = (buf) => createHash('sha256').update(buf).digest('hex');

// I DUE TIPI DI IRRISOLTO (deciso il 30/07/2026). «Irrisolto» copriva due situazioni
// OPPOSTE, e trattarle uguali produceva un FALSO BLOCCO: un progetto sano il cui unico
// target_test usa `import * as ns` finiva degraded -> controllo 4 rosso, pur non avendo
// nulla che non va.
//   structural — l'oracolo NON PUO' giudicare per costruzione (namespace, initializer non
//     riconosciuto, dichiarazione solo commentata, binding fuori da appDir). Non degrada
//     MAI: si DICHIARA. L-COL-006 e' rispettato dalla dichiarazione, non dal rosso — e' il
//     precedente di scan_scope (L-COL-036).
//   failure — l'oracolo DOVEVA farcela e qualcosa e' andato storto (run in errore, zero
//     test eseguiti, runner non configurato). Degrada SEMPRE, anche se e' l'unico e anche
//     se altri candidati sono stati aggiudicati.
const STRUCTURAL = 'structural';
const FAILURE = 'failure';

// Contenimento in appDir. `resolveSpec` risolve gli specificatori relativi senza alcun
// test di contenimento, quindi in un monorepo `import '../../packages/design/tokens.mjs'`
// da' un bindingModule FUORI dall'app — che lo stadio 2 riscriverebbe.
//
// Il ripristino resterebbe corretto (la guardia sha lo copre), ma il rilevatore
// INDIPENDENTE del keystone e' treeHash(app), rootato sulla dir dell'app: li' e' CIECO.
// Sarebbe l'unico caso in cui il gate non puo' controllare l'oracolo, ed e' esattamente
// quello che l'oracolo raggiungerebbe in silenzio. Si dichiara structural e non si scrive.
function insideDir(dir, p) {
  const rp = relative(presolve(dir), presolve(p));
  return rp !== '' && !rp.startsWith('..') && !isAbsolute(rp);
}

// RETE DI RIPRISTINO A LIVELLO DI PROCESSO.
//
// Lo stadio 2 scrive nell'albero di lavoro VERO dell'utente: control4Conformance riceve la
// stessa dir su cui girano gli altri oracoli, non una copia. Il `finally` copre il caso
// normale, ma non due:
//   - il write di ripristino che LANCIA (EBUSY, read-only, un antivirus che tiene il file
//     aperto — su Windows, che e' la piattaforma bersaglio): l'eccezione uscirebbe da
//     assertionPower lasciando il file NEUTRALIZZATO;
//   - un Ctrl-C dentro lo spawn (run_file.mjs non ha timeout: un test appeso resta li'):
//     il processo muore senza eseguire alcun `finally`, e nel sorgente dell'utente resta
//     `{}` o la sentinella, senza marcatore e senza traccia.
// Qui si tengono i byte ORIGINALI dei file in volo e si riscrivono su exit e sui segnali.
// I byte sono GREZZI, mai una stringa: un file non-utf8 valido non sopravviverebbe al
// giro decode/encode, e il ripristino corromperebbe cio' che dice di salvare.
const PENDING = new Map();
let netInstalled = false;

// ALBERO SPORCO — flag di PROCESSO, e la ragione e' MISURATA (30/07/2026, sonda su copia
// con un throw iniettato nel solo write di ripristino, fixture inert-identity).
//
// run_checkpoint.mjs rilancia l'INTERO checkpoint finche' un controllo esce 'error' (max 3
// tentativi, sovrascrivendo `cp`). Quel retry fu scritto per i tool che non emettono JSON —
// un oracolo che NON HA GIRATO, dove ri-leggere e' onesto. Qui incontra un 'error' che
// significa l'opposto: «ho MUTATO il sorgente dell'utente e non sono riuscito a rimetterlo
// a posto». Rieseguire non e' una seconda lettura: e' una seconda misura su un albero che
// nel frattempo l'oracolo stesso ha guastato.
//
// L'ESITO MISURATO, senza questo flag:
//   tentativo 1 -> status 'error', tokens.mjs resta `export const colors = {};`
//   tentativo 2 -> l'oracolo rilegge il file GIA' neutralizzato, neutralizeExport e' un
//                  no-op, il candidato finisce fra gli structural e il controllo 4 esce
//                  GREEN, dichiarando il proprio danno come una proprieta' benigna del
//                  progetto. La stessa asserzione tautologica che l'oracolo esiste per
//                  prendere passa da ROSSO a VERDE per un EBUSY transitorio.
//
// Alzato il flag, ogni assertionPower successiva esce 'error' SENZA TOCCARE NULLA: al terzo
// tentativo il checkpoint riporta 'error', che e' il verdetto vero. Il retry non puo' piu'
// convertire niente, e non serve toccare il retry — che tutto il resto del prodotto usa.
//
// E' di PROCESSO, non per-appDir, ed e' deliberato: un processo che ha dimostrato di non
// saper rimettere a posto cio' che ha mutato non torna a mutare un altro albero. La
// direzione conservativa vale anche contro l'oracolo stesso.
let TREE_DIRTY = null; // null | { path, reason }

function markTreeDirty(path, reason) { if (!TREE_DIRTY) TREE_DIRTY = { path, reason }; }

/** Stato dello sporco, per chi deve DICHIARARLO (nessun chiamante lo usa per decidere). */
export function treeDirtyState() { return TREE_DIRTY; }

/** SEAM DI TEST, e si dichiara come tale: azzera il flag di processo.
 *  In PRODUZIONE nessuno lo chiama e lo sporco NON si dimentica — dimenticarlo
 *  riaprirebbe esattamente CR-1. Esiste perche' i test del flag girano nello stesso
 *  processo degli altri (node:test esegue un file per processo) e senza reset
 *  avvelenerebbero ogni test successivo: un ordine implicito fra test e' fragile
 *  quanto l'ordine di righe che questa correzione elimina. */
export function resetTreeDirtyState() { TREE_DIRTY = null; PENDING.clear(); }

function rememberOriginal(path, bytes) {
  if (!netInstalled) {
    netInstalled = true;
    const restoreAll = () => {
      for (const [p, b] of PENDING) { try { writeFileSync(p, b); } catch { /* never-throw */ } }
      PENDING.clear();
    };
    process.on('exit', restoreAll);
    // SIGBREAK esiste solo su Windows e SIGHUP solo su POSIX: registrare un segnale
    // sconosciuto LANCIA, e la rete anti-danno non puo' essere lei stessa un crash.
    const signals = process.platform === 'win32'
      ? ['SIGINT', 'SIGTERM', 'SIGBREAK']
      : ['SIGINT', 'SIGTERM', 'SIGHUP'];
    for (const s of signals) {
      try { process.on(s, () => { restoreAll(); process.exit(130); }); }
      catch { /* segnale non supportato qui: gli altri bastano */ }
    }
  }
  // NON si sovrascrive una voce gia' in volo, e la tenuta della rete diventa cosi' una
  // proprieta' DICHIARATA invece di un effetto dell'ordine delle righe.
  //
  // Misurato: nella sonda di CR-1 la rete su exit rimetteva comunque i byte VERI, ma solo
  // perche' al secondo giro il ramo no-op ritornava PRIMA di arrivare qui — cioe' per la
  // posizione di un `continue`, non per disegno. Una riorganizzazione futura che spostasse
  // rememberOriginal sopra quel ramo avrebbe fatto memorizzare i byte NEUTRALIZZATI come
  // «originali», e la rete su exit avrebbe scritto il danno al posto della salvezza, in
  // silenzio. Chi e' entrato per primo ha per costruzione i byte veri: quelli si tengono.
  if (!PENDING.has(path)) PENDING.set(path, bytes);
}

// SINCRONA, e non e' un dettaglio di stile: il chiamante (il keystone, e control 4 dal
// task 4) la invoca senza `await`, quindi una versione async restituirebbe un Promise
// che nessuno srotola — ogni verdetto diventerebbe un oggetto opaco, piu' un unhandled
// rejection al termine. runTargetFile e' spawnSync apposta.
export function assertionPower(tasks, appDir, inScope, { runFileTpl } = {}) {
  const files = [];
  const inert = [];
  const unresolved = [];
  let adjudicated = 0;
  // PRIMA DI QUALUNQUE COSA: se questo processo ha gia' mutato un sorgente e non e'
  // riuscito a rimetterlo a posto, non si legge, non si scrive e non si giudica. Uscire
  // 'error' e' l'unico verdetto vero, e il retry di run_checkpoint lo ritrovera' identico
  // ai tentativi 2 e 3 invece di convertirlo in un verde (CR-1).
  if (TREE_DIRTY) {
    return {
      ok: false, status: 'error', inert, unresolved,
      coverage: {
        scanned: 0, files, candidates: 0, adjudicated: 0,
        unresolved: 0, unresolved_structural: 0, unresolved_failure: 0, declared: [],
      },
      detail: `ALBERO SPORCO da un giro precedente di questo processo: ${TREE_DIRTY.path} e' rimasto NEUTRALIZZATO (${TREE_DIRTY.reason}). Nessuna misura: un oracolo che ha guastato il sorgente non torna a giudicarlo`,
    };
  }
  const countCandidates = () => files.reduce((a, f) => a + f.candidates, 0);
  const declare = (c, kind, reason) => unresolved.push({ ...c, kind, reason });
  const ofKind = (k) => unresolved.filter((u) => u.kind === k);
  // La coverage si ricalcola a ogni uscita, anche su quella d'errore: un ritorno che tace
  // quanto aveva gia' esaminato costringe chi legge a indovinarlo.
  const coverageNow = () => ({
    scanned: files.length,
    files,
    candidates: countCandidates(),
    adjudicated,
    unresolved: unresolved.length,
    unresolved_structural: ofKind(STRUCTURAL).length,
    unresolved_failure: ofKind(FAILURE).length,
    // CIO' CHE NON SI E' GUARDATO SI SCRIVE, ognuno col suo motivo — stessa forma di
    // coverage.excluded_patterns in scan_scope (L-COL-036), ed e' il precedente su cui
    // poggia la decisione: uno structural non degrada, quindi se non comparisse QUI
    // sparirebbe del tutto, e «non degrada» diventerebbe «non si sa».
    declared: unresolved.map((u) => ({
      file: u.testFile, line: u.line, binding: u.bindingName, kind: u.kind, reason: u.reason,
    })),
  });

  const where = (u) => `${u.testFile}:${u.line} su '${u.bindingName}' — ${u.reason}`;
  // GLI STRUCTURAL SI APPENDONO A OGNI `detail`, NON AL SOLO RAMO VERDE.
  //
  // Prima stavano solo sul verde, e l'effetto era il rovescio dell'intenzione: nei tre
  // stati in cui l'utente ha piu' bisogno di sapere cosa NON e' stato guardato — red,
  // degraded, error — la dichiarazione spariva da ogni output. Il `detail` e' l'unico
  // canale che attraversa shapeControl e la proiezione del loop, quindi «non degrada»
  // tornava a essere «non si sa» esattamente dove costava di piu'.
  //
  // A ZERO structural il suffisso e' vuoto, e la clausola 2 della bit-invarianza regge
  // per costruzione: senza candidati non ci sono irrisolti, quindi la stringa del verde
  // resta byte-identica a prima dell'innesto.
  const withDeclared = (detail) => {
    const st = ofKind(STRUCTURAL);
    return st.length
      ? `${detail}; ${st.length} fuori portata dell'oracolo (dichiarati, non degradano): ${st.map(where).join('; ')}`
      : detail;
  };

  // `tasks` serve a dire QUALE AC e' guardato da una tautologia: un messaggio che
  // nomina solo il file lascia all'utente il lavoro di capire cosa non e' piu' provato.
  const acsOf = new Map();
  for (const t of tasks || []) for (const tt of (t.target_tests || [])) {
    const ids = Array.isArray(tt.covers) ? tt.covers : [tt.covers].filter(Boolean);
    acsOf.set(tt.file, [...(acsOf.get(tt.file) || []), ...ids]);
  }

  for (const raw of inScope) {
    // Separatori `/` UNA VOLTA SOLA e PRIMA di ogni uso, non solo sulla riga che
    // finisce in coverage: la stessa stringa deve risolvere il file su disco, rilanciare
    // il runner e comparire nel rapporto. Normalizzare solo all'atto di scriverla
    // lascerebbe divergere cio' che si DICHIARA da cio' che si e' davvero MISURATO —
    // ed e' il difetto (guardia messa dopo il join, quindi mai esercitata) gia' rilevato
    // sul `testFile` dello stadio 1. `inScope` porta la stringa YAML grezza, che il
    // chiamante riconfronta per uguaglianza: normalizzarla la lascia identica.
    const rel = raw.replace(/\\/g, '/');
    const cands = findCandidates(appDir, rel).map((c) => ({ ...c, acIds: acsOf.get(rel) || [] }));
    files.push({ file: rel, candidates: cands.length });
    for (const c of cands) {
      // Prima di sporcare l'albero: senza runner non c'e' esecuzione, quindi non c'e'
      // verdetto. Si dichiara irrisolto invece di lanciare — un crash non e' un verdetto
      // (L-COL-002) — e senza mutare un file che poi non si potrebbe comunque provare.
      if (!runFileTpl) {
        declare(c, FAILURE, "nessun template d'esecuzione (test_runner.run_file): niente runner, niente verdetto");
        continue;
      }
      // Fuori da appDir non si scrive: vedi insideDir. Prima di leggere, non solo di
      // scrivere, cosi' il percorso che porta al write non esiste proprio.
      if (!insideDir(appDir, c.bindingModule)) {
        declare(c, STRUCTURAL, `il modulo di '${c.bindingName}' sta FUORI da appDir (${c.bindingModule}): l'oracolo non muta cio' che il gate non sorveglia`);
        continue;
      }
      // Byte GREZZI: `src` serve come stringa solo per cercare e riscrivere, ma cio' che
      // si rimette al posto suo sono i byte letti, non il loro giro per utf8.
      const bytes = readFileSync(c.bindingModule);
      const src = bytes.toString('utf8');
      const mutated = neutralizeExport(src, c.bindingName);
      if (mutated === null) {
        declare(c, STRUCTURAL, neutralizeFailureReason(src, c.bindingName));
        continue;
      }
      if (mutated === src) {
        declare(c, STRUCTURAL, `neutralizzazione no-op per '${c.bindingName}': l'initializer e' gia' nella forma inerte, non c'e' mutazione che lo renda piu' inerte`);
        continue;
      }
      const h0 = sha(bytes);
      rememberOriginal(c.bindingModule, bytes);
      // ANCHE IL WRITE DI MUTAZIONE PUO' LANCIARE, e un crash non e' un verdetto
      // (L-COL-002). Misurato il 30/07/2026 costruendo la fixture restore-locked: con il
      // modulo del lato atteso in sola lettura, l'EPERM usciva da assertionPower, da
      // control4Conformance e da runCheckpoint, e run_checkpoint.mjs moriva con uno stack
      // trace invece di emettere il JSON del report — nessun verdetto, per nessun controllo.
      // Qui nulla e' stato scritto, quindi l'albero e' PULITO: e' un FAILURE (l'oracolo
      // doveva farcela e non ci e' riuscito), che degrada, non un albero sporco.
      try { writeFileSync(c.bindingModule, mutated); }
      catch (e) {
        PENDING.delete(c.bindingModule);
        declare(c, FAILURE, `impossibile scrivere la neutralizzazione di '${c.bindingName}' in ${c.bindingModule} (${String((e && e.message) || e)}): niente mutazione, niente verdetto — l'albero NON e' stato toccato`);
        continue;
      }
      let r;
      let restoreErr = null;
      try { r = runTargetFile(appDir, rel, runFileTpl); }
      finally {
        // Il ripristino che lancia NON deve propagare: l'eccezione uscirebbe da qui
        // lasciando il file dell'utente neutralizzato, e un crash non e' un verdetto
        // (L-COL-002). Si cattura e si esce in 'error', dicendo che il file e' sporco.
        //
        // `PENDING.delete` NON sta piu' qui: era la rete che dimenticava il file NELL'ISTANTE
        // ESATTO in cui il controllo lo dichiarava sporco. Era parcheggiato con la
        // motivazione «finestra stretta, lo status e' gia' error»; CR-1 ha falsificato quella
        // premessa — l'error non restava error, e nel frattempo la rete era l'unica cosa che
        // rimetteva i byte veri. Si dimentica solo cio' che si e' PROVATO di aver rimesso a
        // posto, e la prova e' la guardia sha piu' sotto.
        try { writeFileSync(c.bindingModule, bytes); }
        catch (e) { restoreErr = e; }
      }
      if (restoreErr) {
        const why = String((restoreErr && restoreErr.message) || restoreErr);
        markTreeDirty(c.bindingModule, `il write di ripristino ha lanciato: ${why}`);
        return {
          ok: false, status: 'error', inert, unresolved, coverage: coverageNow(),
          detail: withDeclared(`RIPRISTINO FALLITO di ${c.bindingModule} (${why}): il file e' rimasto NEUTRALIZZATO, nessun verdetto — la rete su exit provera' a rimetterlo a posto, e ogni giro successivo di questo processo esce 'error' senza toccare nulla`),
        };
      }
      if (sha(readFileSync(c.bindingModule)) !== h0) {
        markTreeDirty(c.bindingModule, 'il ripristino non e\' tornato bit-esatto (guardia sha256)');
        return {
          ok: false, status: 'error', inert, unresolved, coverage: coverageNow(),
          detail: withDeclared(`ripristino NON bit-esatto di ${c.bindingModule}: l'albero e' sporco, nessun verdetto`),
        };
      }
      // Solo ORA la rete puo' dimenticare questo file: il ripristino non e' soltanto
      // avvenuto senza lanciare, e' PROVATO bit-esatto. Finche' la prova non c'e', i byte
      // veri restano in PENDING ed e' l'handler su exit a rimetterli.
      PENDING.delete(c.bindingModule);
      if (r.error) { declare(c, FAILURE, `errore d'esecuzione: ${r.detail}`); continue; }
      // Zero test eseguiti NON e' un'aggiudicazione: l'exit code descrive un file che non
      // ha provato niente, e contarlo tra gli aggiudicati produrrebbe un verde che dichiara
      // «1/1 aggiudicati» senza una prova sotto. E' un guasto, non un limite: FAILURE.
      if (r.testCount < 1) {
        declare(c, FAILURE, `dopo la neutralizzazione il file non esegue alcun test (${r.detail}): nessuna prova`);
        continue;
      }
      adjudicated++;
      // VERDE dopo la neutralizzazione = l'asserzione non puo' fallire.
      if (r.passed) inert.push({ ...c, verdict: 'inerte' });
    }
  }

  const coverage = coverageNow();

  // ORDINE DEL VERDETTO: inerte -> red; un solo failure -> degraded; altrimenti green.
  if (inert.length > 0) {
    return {
      ok: false, status: 'red', inert, unresolved, coverage,
      detail: withDeclared(`asserzione INERTE (non puo' fallire): ${inert.map((i) => `${i.testFile}:${i.line} su '${i.bindingName}' [${i.acIds.join(', ') || 'AC ignoto'}]`).join('; ')}`),
    };
  }
  // UN SOLO failure degrada, anche se altri candidati sono stati aggiudicati. La regola
  // precedente — verde se ho aggiudicato almeno qualcosa — era una soglia SENZA PRINCIPIO:
  // due candidati identici in due file diversi finivano trattati in modo opposto a seconda
  // di cosa era successo nell'altro file.
  const failures = ofKind(FAILURE);
  if (failures.length > 0) {
    return {
      ok: false, status: 'degraded', inert, unresolved, coverage,
      detail: withDeclared(`${failures.length} candidati NON aggiudicati per un guasto dell'oracolo: ${failures.map(where).join('; ')}`),
    };
  }
  return {
    ok: true, status: 'green', inert, unresolved, coverage,
    // Il verde dice sempre quanto NON ha guardato. Gli structural NON degradano, ma
    // tacerli sarebbe la meta' sbagliata della decisione: si dichiarano qui, dove chi
    // legge il riepilogo li vede senza dover aprire l'oggetto.
    detail: withDeclared(`potere verificato: ${adjudicated}/${coverage.candidates} candidati aggiudicati su ${files.length} target_test`),
  };
}
