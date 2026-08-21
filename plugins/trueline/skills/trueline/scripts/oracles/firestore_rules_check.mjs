#!/usr/bin/env node
// =============================================================================
// firestore_rules_check.mjs — Oracolo CUSTOM di Trueline per Firestore Security
// Rules (analisi statica del file `firestore.rules`).
//
// Gemello strutturale di rls_check.mjs (stesso contratto: CLI posizionale,
// raccolta file ricorsiva, split che rispetta commenti/stringhe, makeFinding
// per rilievo, report JSON nativo su stdout, exit 2 senza argomenti, errori di
// parse catturati come parse_warnings — MAI un throw — ed exit 0 anche con
// rilievi presenti, perche' il verdetto vive nel payload JSON, non nell'exit
// code).
//
// CONFINE DI COPERTURA (static-first, dichiarato esplicitamente):
//   - Vede SOLO il testo dei file `.rules` passati. NON valuta le rules contro
//     il Firestore Rules engine, NON conosce lo schema dei documenti, NON
//     esegue alcuna simulazione comportamentale. I controlli sono token/
//     strutturali sull'albero dei blocchi `match` e degli statement `allow`.
//
// USO DEL PARSER (NIENTE AST — non esiste un parser AST per `.rules`):
//   scansioniamo il testo rispettando i commenti `//` di riga, `/* */` di
//   blocco e l'annidamento delle graffe. Da questa scansione estraiamo ogni
//   blocco `match <path> { ... }` (tracciando il path) e ogni statement
//   `allow <methods>: if <condition>;` al suo interno, con la riga 1-based di
//   inizio dell'`allow`. Lo split rispetta commenti e stringhe.
//
// OUTPUT: JSON NATIVO (lista di rilievi), NON normalizzato (la normalizzazione
//   nel finding model e' compito di `normalize`). Stampa su stdout.
//
// USO: node trueline/scripts/oracles/firestore_rules_check.mjs <dir-o-file.rules> [...]
//   Gli argomenti sono directory (scansione ricorsiva di file `firestore.rules`
//   o terminanti `.rules`) oppure file terminanti `.rules`.
// =============================================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep, posix } from 'node:path';

const ORACLE = 'firestore-rules';
const TOOL_VERSION = 'firestore-rules-check/1.0.0';

// Token che, se presenti in una condizione non-literal-true, indicano un
// tentativo di vincolo di isolamento/identita'. Euristica dichiarata.
const FIRESTORE_ISOLATION_TOKENS = [
  'request.auth.uid',
  'request.auth != null',
  'resource.data',
  'request.resource.data',
  'request.auth.token',
];

// Marcatori che indicano un confronto di proprieta'/owner (non solo "loggato").
// Se la condizione contiene uno di questi (oltre a request.auth != null) NON
// la consideriamo "solo autenticazione" (FIRESTORE002).
const OWNER_COMPARISON_TOKENS = [
  'request.auth.uid ==',
  'resource.data',
  'request.resource.data',
  'request.auth.token',
];

// Metodi validi in uno statement `allow`.
const ALLOW_METHODS = new Set([
  'read', 'write', 'get', 'list', 'create', 'update', 'delete',
]);

// -----------------------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    process.stderr.write(
      'uso: node firestore_rules_check.mjs <dir-o-file.rules> [...]\n'
    );
    process.exit(2);
  }

  const files = collectRulesFiles(args);
  const findings = [];
  const scannedFiles = [];
  const parseWarnings = [];

  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    scannedFiles.push(file);
    analyzeFile(file, text, findings, parseWarnings);
  }

  const report = {
    oracle: ORACLE,
    tool_version: TOOL_VERSION,
    coverage: 'static-rules',
    coverage_note:
      'Analisi statica del solo testo dei file .rules. Non valuta le rules ' +
      'contro il Firestore Rules engine, non conosce lo schema dei documenti ' +
      'ne esegue simulazioni comportamentali: i controlli sono token/' +
      'strutturali sull\'albero dei blocchi match e degli statement allow.',
    scanned_files: scannedFiles.map(toPosixRel),
    parse_warnings: parseWarnings,
    findings,
  };

  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

// -----------------------------------------------------------------------------
// Analisi di un singolo file .rules
// -----------------------------------------------------------------------------
function analyzeFile(file, text, findings, parseWarnings) {
  const relPath = toPosixRel(file);

  let blocks;
  try {
    blocks = parseRules(text, relPath, parseWarnings);
  } catch (e) {
    // Il parser NON deve mai propagare: qualunque imprevisto diventa un warning.
    parseWarnings.push({
      file: relPath,
      line: 1,
      statement: 'rules',
      message: `parser fallito sul file: ${firstLine(e.message)}`,
    });
    return;
  }

  for (const block of blocks) {
    for (const allow of block.allows) {
      evaluateAllow(block, allow, relPath, findings);
    }
  }
}

// -----------------------------------------------------------------------------
// CONTROLLI deterministici/euristici per statement `allow`
// -----------------------------------------------------------------------------
function evaluateAllow(block, allow, relPath, findings) {
  const matchPath = block.path;
  const allowText = allow.text; // es. "read, write" oppure "read"
  const cond = allow.condition; // condizione grezza (puo' essere null)
  const condCollapsed = collapseWs(cond ?? '');

  // [FIRESTORE001] PUBLIC_ALLOW (HIGH, FLOOR, deterministico): condizione
  // letterale `true` (dopo collasso whitespace), anche fra parentesi bilanciate
  // (`(true)`, `((true))`). Copre la forma combinata (read, write), le forme
  // splittate e il wildcard ricorsivo. Tautologie semantiche fuori scope (vedi
  // isLiteralTrue).
  if (isLiteralTrue(condCollapsed)) {
    findings.push(
      makeFinding({
        controlId: 'FIRESTORE001_PUBLIC_ALLOW',
        severity: 'HIGH',
        matchPath,
        allow: allowText,
        file: relPath,
        startLine: allow.startLine,
        endLine: allow.endLine,
        statement: allow.snippet,
        snippet: allow.snippet,
        message:
          `La regola "allow ${allowText}: if true;" sul path ${matchPath} ` +
          `concede accesso pubblico incondizionato: la condizione e' la ` +
          `costante true, quindi chiunque (anche non autenticato) puo' ` +
          `eseguire ${allowText} su questi documenti.`,
      })
    );
    // Una allow "true" e' gia' il difetto massimo: non doppiamo con FIRESTORE002.
    return;
  }

  // [FIRESTORE002] MISSING_AUTH (MEDIUM, NON-floor, EURISTICO): la condizione
  // menziona `request.auth != null` ma NON contiene alcun confronto di owner
  // (request.auth.uid ==, resource.data, request.resource.data,
  // request.auth.token) E il path e' per-documento (ha un segmento {var}).
  // Conservativo: nel dubbio NON si segnala.
  if (cond != null) {
    const condLc = condCollapsed.toLowerCase();
    const mentionsAuthNotNull = condLc.includes('request.auth != null');
    const hasOwnerComparison = OWNER_COMPARISON_TOKENS.some((tok) =>
      condLc.includes(tok.toLowerCase())
    );
    const perDocument = pathIsPerDocument(matchPath);

    if (mentionsAuthNotNull && !hasOwnerComparison && perDocument) {
      findings.push(
        makeFinding({
          controlId: 'FIRESTORE002_MISSING_AUTH',
          severity: 'MEDIUM',
          matchPath,
          allow: allowText,
          file: relPath,
          startLine: allow.startLine,
          endLine: allow.endLine,
          statement: allow.snippet,
          snippet: allow.snippet,
          message:
            `La regola "allow ${allowText}" sul path per-documento ` +
            `${matchPath} verifica solo che l'utente sia autenticato ` +
            `(request.auth != null) ma non confronta l'identita' con il ` +
            `proprietario del documento (es. request.auth.uid == ` +
            `resource.data.ownerId): ogni utente autenticato puo' accedere ai ` +
            `documenti di chiunque altro.`,
          heuristic: true,
        })
      );
    }
  }
}

// -----------------------------------------------------------------------------
// PARSER token/strutturale del file .rules.
// Ritorna una lista di blocchi { path, allows: [...] } in ordine di scansione.
// Ogni allow: { text, condition, startLine, endLine, snippet }.
// Statement `allow` malformati (senza `: if <cond>;` completo) NON producono un
// allow ma un parse_warnings.
// -----------------------------------------------------------------------------
function parseRules(src, relPath, parseWarnings) {
  const toks = tokenize(src);
  const blocks = [];
  // Stack dei path `match` aperti, per ricostruire il path completo annidato.
  const matchStack = []; // [{ path, fullPath }]

  for (let i = 0; i < toks.length; i++) {
    const t = toks[i];

    if (t.type === 'word' && t.value === 'match') {
      // match <path> { ... }
      // ATTENZIONE: il path puo' contenere graffe di glob, es. /{document=**} o
      // /users/{userId}. La graffa che APRE il blocco e' una '{' PRECEDUTA da
      // whitespace (precededByWs) e a profondita'-glob 0; le '{'/'}' di un glob
      // {var} sono adiacenti al path (nessuno spazio) e vanno incluse nel path,
      // bilanciate. Doppia difesa: tracciamo anche la profondita' del glob.
      const pathToks = [];
      let j = i + 1;
      let globDepth = 0;
      while (j < toks.length) {
        const tj = toks[j];
        if (tj.type === 'punct' && tj.value === '{') {
          if (globDepth === 0 && tj.precededByWs) {
            break; // graffa di apertura del blocco match (preceduta da spazio)
          }
          globDepth++;
          pathToks.push(tj);
          j++;
          continue;
        }
        if (tj.type === 'punct' && tj.value === '}') {
          if (globDepth === 0) break; // '}' inattesa: match malformato
          globDepth--;
          pathToks.push(tj);
          j++;
          continue;
        }
        // Un ';' prima della graffa indica un match malformato: fermati.
        if (tj.type === 'punct' && tj.value === ';') {
          break;
        }
        pathToks.push(tj);
        j++;
      }
      const pathStr = pathToks.map((p) => p.value).join('').trim();
      const parent = matchStack.length > 0 ? matchStack[matchStack.length - 1].fullPath : '';
      const fullPath = joinMatchPath(parent, pathStr);
      if (j < toks.length && toks[j].type === 'punct' && toks[j].value === '{') {
        matchStack.push({ path: pathStr, fullPath, brace: toks[j] });
        i = j; // riprendi dopo la graffa aperta
      }
      continue;
    }

    if (t.type === 'word' && t.value === 'allow') {
      const res = parseAllow(toks, i, src);
      const matchPath = matchStack.length > 0
        ? matchStack[matchStack.length - 1].fullPath
        : '/';
      if (res.ok) {
        // Allega l'allow al blocco corrente (o crea un blocco "root").
        let block = blocks.find((b) => b.path === matchPath && b._open);
        if (!block) {
          block = { path: matchPath, allows: [], _open: true };
          blocks.push(block);
        }
        block.allows.push({
          text: res.methods,
          condition: res.condition,
          startLine: res.startLine,
          endLine: res.endLine,
          snippet: res.snippet,
        });
        i = res.nextIndex;
      } else {
        parseWarnings.push({
          file: relPath,
          line: res.startLine,
          statement: 'allow',
          message: `statement allow malformato o troncato: ${res.reason}`,
        });
        // Avanza fino al prossimo ';' o '}' per non ri-processare gli stessi token.
        i = res.nextIndex;
      }
      continue;
    }

    if (t.type === 'punct' && t.value === '}') {
      // Chiudi il match piu' interno (se presente) e marca i suoi blocchi.
      if (matchStack.length > 0) {
        const closed = matchStack.pop();
        for (const b of blocks) {
          if (b.path === closed.fullPath) b._open = false;
        }
      }
    }
  }

  // Pulisci il flag interno prima di restituire.
  for (const b of blocks) delete b._open;
  return blocks;
}

// Estrae un singolo statement `allow <methods> : if <condition> ;`.
// `startIndex` punta al token 'allow'. Ritorna:
//   ok:true  -> { ok, methods, condition, startLine, endLine, snippet, nextIndex }
//   ok:false -> { ok, reason, startLine, nextIndex }
function parseAllow(toks, startIndex, src) {
  const allowTok = toks[startIndex];
  const startLine = allowTok.line;

  // 1) metodi fino a ':'
  const methodToks = [];
  let i = startIndex + 1;
  let sawColon = false;
  while (i < toks.length) {
    const t = toks[i];
    if (t.type === 'punct' && t.value === ':') {
      sawColon = true;
      i++;
      break;
    }
    if (t.type === 'punct' && (t.value === ';' || t.value === '{' || t.value === '}')) {
      // fine inattesa prima dei ':'
      break;
    }
    methodToks.push(t);
    i++;
  }
  if (!sawColon) {
    return {
      ok: false,
      reason: "manca ':' dopo i metodi",
      startLine,
      nextIndex: advanceToTerminator(toks, startIndex + 1),
    };
  }

  // 2) keyword 'if'
  if (!(i < toks.length && toks[i].type === 'word' && toks[i].value === 'if')) {
    return {
      ok: false,
      reason: "manca la keyword 'if' dopo ':'",
      startLine,
      nextIndex: advanceToTerminator(toks, i),
    };
  }
  i++; // consuma 'if'

  // 3) condizione fino a ';' (rispettando parentesi/graffe bilanciate)
  const condToks = [];
  let depth = 0;
  let sawSemicolon = false;
  while (i < toks.length) {
    const t = toks[i];
    if (t.type === 'punct' && (t.value === '(' || t.value === '[' || t.value === '{')) {
      depth++;
      condToks.push(t);
      i++;
      continue;
    }
    if (t.type === 'punct' && (t.value === ')' || t.value === ']' || t.value === '}')) {
      if (depth === 0) {
        // graffa di chiusura del blocco match senza ';': allow troncato
        break;
      }
      depth--;
      condToks.push(t);
      i++;
      continue;
    }
    if (t.type === 'punct' && t.value === ';' && depth === 0) {
      sawSemicolon = true;
      i++; // consuma ';'
      break;
    }
    condToks.push(t);
    i++;
  }
  if (!sawSemicolon || condToks.length === 0) {
    return {
      ok: false,
      reason: condToks.length === 0
        ? "condizione vuota dopo 'if'"
        : "manca il ';' di chiusura dello statement allow",
      startLine,
      nextIndex: Math.max(i - 1, startIndex + 1),
    };
  }

  const methods = joinToks(methodToks).replace(/\s+/g, ' ').trim();
  const condition = joinToks(condToks).trim();
  const endLine = condToks.length > 0
    ? condToks[condToks.length - 1].line
    : startLine;
  const snippet = snippetOf(`allow ${methods}: if ${condition};`);

  return {
    ok: true,
    methods,
    condition,
    startLine,
    endLine,
    snippet,
    nextIndex: i - 1, // -1 perche' il for esterno fa i++
  };
}

// Avanza l'indice fino al prossimo terminatore ';' o '}' (incluso), per
// recuperare dopo uno statement malformato senza loop infiniti.
function advanceToTerminator(toks, fromIndex) {
  let i = fromIndex;
  while (i < toks.length) {
    const t = toks[i];
    if (t.type === 'punct' && (t.value === ';' || t.value === '}')) {
      return i;
    }
    i++;
  }
  return toks.length - 1 >= fromIndex ? toks.length - 1 : fromIndex;
}

// -----------------------------------------------------------------------------
// TOKENIZER: scompone il testo in token { type, value, line } rispettando i
// commenti // di riga, /* */ di blocco e le stringhe ' " `.
//   - word:  identificatori/keyword (incl. '.', necessario per request.auth.uid)
//   - punct: singolo carattere di punteggiatura significativo
//   - string: letterale di stringa (mantenuto come unico token "word"-like)
// Whitespace e commenti NON producono token.
// -----------------------------------------------------------------------------
function tokenize(src) {
  const toks = [];
  let line = 1;
  let i = 0;
  const n = src.length;
  // Diventa true quando, dopo l'ultimo token emesso, abbiamo consumato almeno
  // un whitespace/commento. Serve a distinguere la graffa di GLOB {var} (che e'
  // adiacente al path, senza spazio prima) dalla graffa che APRE un blocco match
  // (preceduta da spazio): "match /{document=**} {" — il primo '{' e' adiacente
  // a '/', il secondo e' preceduto da spazio.
  let gap = true;

  // Caratteri che fanno parte di un "word": identificatori, numeri, '.', '_',
  // '$', '*', '=', '!', '<', '>', '&', '|', '+', '-', '/', '%' — cosi' che
  // operatori come '==' o '!=' e path-glob come {document=**} restino coesi.
  const isWordChar = (c) => /[A-Za-z0-9_$.=!<>&|+\-%]/.test(c);

  const push = (tok) => {
    tok.precededByWs = gap;
    toks.push(tok);
    gap = false;
  };

  while (i < n) {
    const c = src[i];
    const d = src[i + 1];

    if (c === '\n') {
      line++;
      i++;
      gap = true;
      continue;
    }
    if (c === ' ' || c === '\t' || c === '\r' || c === '\f' || c === '\v') {
      i++;
      gap = true;
      continue;
    }
    // commento di riga //
    if (c === '/' && d === '/') {
      i += 2;
      while (i < n && src[i] !== '\n') i++;
      gap = true;
      continue;
    }
    // commento di blocco /* */
    if (c === '/' && d === '*') {
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        if (src[i] === '\n') line++;
        i++;
      }
      i += 2; // consuma '*/'
      gap = true;
      continue;
    }
    // stringa (', ", `)
    if (c === "'" || c === '"' || c === '`') {
      const quote = c;
      const startLine = line;
      let val = c;
      i++;
      while (i < n && src[i] !== quote) {
        if (src[i] === '\\' && i + 1 < n) {
          val += src[i] + src[i + 1];
          if (src[i + 1] === '\n') line++;
          i += 2;
          continue;
        }
        if (src[i] === '\n') line++;
        val += src[i];
        i++;
      }
      if (i < n) {
        val += src[i];
        i++;
      }
      push({ type: 'string', value: val, line: startLine });
      continue;
    }
    // word
    if (isWordChar(c)) {
      const startLine = line;
      let val = '';
      while (i < n && isWordChar(src[i])) {
        val += src[i];
        i++;
      }
      push({ type: 'word', value: val, line: startLine });
      continue;
    }
    // punteggiatura significativa singola
    push({ type: 'punct', value: c, line });
    i++;
  }
  return toks;
}

// -----------------------------------------------------------------------------
// HELPER di valutazione
// -----------------------------------------------------------------------------

// Ricostruisce il testo di una sequenza di token reinserendo UNO spazio dove il
// token era preceduto da whitespace nel sorgente (tranne il primo). Questo
// preserva costrutti come `request.auth != null` (i cui '!=' e 'null' sono token
// separati dallo spazio) senza incollare i token tra loro.
function joinToks(tokList) {
  let out = '';
  for (let k = 0; k < tokList.length; k++) {
    const t = tokList[k];
    if (k > 0 && t.precededByWs) out += ' ';
    out += t.value;
  }
  return out;
}

// Vero se la `(` iniziale di `e` e' chiusa esattamente dalla `)` finale, cioe'
// le parentesi avvolgono l'INTERA espressione (e non due gruppi distinti come
// `(a) == (b)`, dove la prima `(` chiude a meta').
function parensWrapWhole(e) {
  let depth = 0;
  for (let i = 0; i < e.length; i++) {
    const c = e[i];
    if (c === '(') depth++;
    else if (c === ')') {
      depth--;
      if (depth === 0) return i === e.length - 1;
    }
  }
  return false;
}

// Vero se l'espressione (gia' collassata) e' la costante letterale `true`,
// eventualmente avvolta da parentesi bilanciate: `true`, `(true)`, `( true )`,
// `((true))` sono tutte accesso pubblico incondizionato e DEVONO entrare nel
// floor FIRESTORE001. Le parentesi che non avvolgono l'intera espressione
// (es. `(a) == (b)`) NON vengono scartate, quindi nessun falso positivo.
// NOTA DI COPERTURA (L-COL-006): il controllo e' SINTATTICO sul letterale
// `true`; le tautologie SEMANTICHE (`true == true`, `1 == 1`) sono fuori dallo
// scope dichiarato del floor (richiederebbero valutazione) e non sono colte.
function isLiteralTrue(expr) {
  if (!expr) return false;
  let e = expr.trim();
  while (e.length >= 2 && e[0] === '(' && e[e.length - 1] === ')' && parensWrapWhole(e)) {
    e = e.slice(1, -1).trim();
  }
  return /^true$/i.test(e);
}

// Un path e' "per-documento" se, IGNORATO il prefisso strutturale standard
// `/databases/{database}/documents` (la cui '{database}' e' un wildcard di
// boilerplate, non un binding per-documento), contiene ancora un segmento
// variabile {var} (incluso il wildcard ricorsivo {document=**}). Una collection
// senza {var} propria (es. .../documents/settings) NON e' per-documento.
function pathIsPerDocument(p) {
  const remainder = String(p).replace(
    /^\/?databases\/\{[^}]*\}\/documents/,
    ''
  );
  return /\{[^}]*\}/.test(remainder);
}

// Unisce il path del match figlio a quello del genitore, normalizzando gli '/'.
function joinMatchPath(parent, child) {
  const c = child.trim();
  if (!parent) return c.startsWith('/') ? c : '/' + c;
  const p = parent.replace(/\/+$/, '');
  const ch = c.replace(/^\/+/, '');
  return `${p}/${ch}`;
}

function collapseWs(s) {
  return String(s).replace(/\s+/g, ' ').trim();
}

// -----------------------------------------------------------------------------
// Utilita' varie
// -----------------------------------------------------------------------------
function snippetOf(body, maxLen = 240) {
  const oneLine = String(body).replace(/\s+/g, ' ').trim();
  return oneLine.length > maxLen ? oneLine.slice(0, maxLen) + ' ...' : oneLine;
}

function firstLine(s) {
  return String(s).split('\n')[0];
}

function makeFinding(o) {
  // Rilievo NATIVO (non normalizzato). `match_path` e `allow` sono i campi
  // portatori-di-simbolo che il normalizer leggera': nomi-chiave esatti.
  const f = {
    control_id: o.controlId,
    severity: o.severity,
    category: 'authz',
    match_path: o.matchPath,
    allow: o.allow,
    location: {
      file: o.file,
      start_line: o.startLine,
      end_line: o.endLine,
      statement: o.statement,
    },
    snippet: o.snippet,
    message: o.message,
  };
  if (o.heuristic) f.heuristic = true;
  return f;
}

// -----------------------------------------------------------------------------
// Raccolta file .rules dagli argomenti (dir ricorsiva o file).
// -----------------------------------------------------------------------------
function collectRulesFiles(args) {
  const out = [];
  for (const a of args) {
    let st;
    try {
      st = statSync(a);
    } catch {
      process.stderr.write(`avviso: percorso inesistente, ignorato: ${a}\n`);
      continue;
    }
    if (st.isDirectory()) {
      walk(a, out);
    } else if (st.isFile() && a.toLowerCase().endsWith('.rules')) {
      out.push(a);
    } else if (st.isFile()) {
      process.stderr.write(`avviso: non e' un file .rules, ignorato: ${a}\n`);
    }
  }
  // ordinamento deterministico
  out.sort();
  return out;
}

function walk(dir, out) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    process.stderr.write(`avviso: directory illeggibile, ignorata: ${dir}\n`);
    return;
  }
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
    } else if (
      entry.isFile() &&
      (entry.name === 'firestore.rules' ||
        entry.name.toLowerCase().endsWith('.rules'))
    ) {
      out.push(full);
    }
  }
}

function toPosixRel(file) {
  const rel = relative(process.cwd(), file);
  return rel.split(sep).join(posix.sep);
}

main();
