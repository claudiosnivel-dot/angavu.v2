// dart_deadcode_edit.mjs — helper RIUSABILE per la rimozione SICURA di una FUNZIONE
// Dart top-level morta (Eco-F5b). Importato dal fix provider (dispatch dead-code per
// i finding dart {file, symbol} di tipo unused-element).
//
// Gemello Dart di ts_deadcode_edit.mjs / go_deadcode_edit.mjs: stesso CONTRATTO e
// stesso PRINCIPIO DI SICUREZZA, adattato alla sintassi Dart. Lega il seed
// flutter-dart (SEED:FLUTTERDART-DC: funzione privata `_unusedHelper` in lib/dead.dart,
// segnalata da 'dart analyze --format=machine' come UNUSED_ELEMENT) al ramo dead-code
// del dispatch.
//
// CONTRATTO
//   removeDartSymbol(absFile, symbolName) -> { ok, detail, removed }
//   - absFile     path ASSOLUTO del file .dart nella COPIA temporanea (mai il fixture
//                 canonico: il chiamante opera gia' su verify_workspace).
//   - symbolName  nome della funzione morta da rimuovere (es. "_unusedHelper").
//
// PRINCIPIO DI SICUREZZA (non rompere il modulo):
//   - Si rimuove SOLO la definizione TOP-LEVEL di una FUNZIONE (col 0). Sono gestite
//     ENTRAMBE le forme del corpo Dart:
//       * arrow-body  `<Ret> <name>(...) => <expr>;`  (fine = primo `;` top-level);
//       * block-body  `<Ret> <name>(...) { ... }`     (fine = `}` bilanciata).
//     COMPRESO il blocco di commenti `//`/`///` immediatamente precedente attaccato
//     alla definizione (nessuna riga vuota in mezzo).
//   - Il bilanciamento ignora il contenuto di stringhe ('...', "...", '''...''',
//     """...""", raw r'...') e commenti (// e /* */): deterministico per i simboli
//     che dart analyze segnala come UNUSED_ELEMENT.
//   - Se il simbolo NON e' una funzione top-level (non trovato a col 0 con `(`), NON
//     si tocca nulla e si ritorna ok:false: meglio fallire ONESTAMENTE (il loop lo
//     trattera' come verification-failed) che corrompere il file. Mai una rimozione
//     approssimata.
//   - Niente parser AST esterno (niente dipendenze): un'analisi a riga + scansione
//     string-aware basta per le funzioni top-level.
//
// Node ESM, solo built-in (fs). Niente rete, niente dipendenze npm.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

function esc(name) {
  return String(name).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function isWordChar(c) {
  return c !== undefined && /[\w$]/.test(c);
}

// La riga apre la definizione top-level di una FUNZIONE `name`? (col 0; `<name>(`
// preceduto da inizio-riga o da un non-identificatore, es. il tipo di ritorno).
function isDartDeclLineFor(line, name) {
  if (!/^[^\s]/.test(line)) return false; // deve iniziare a col 0
  return new RegExp(`(?:^|[^\\w$])${esc(name)}\\s*\\(`).test(line);
}

// Una riga e' un commento Dart (`//`, `///`, o parte di `/* ... */`)? Usata SOLO per
// assorbire un blocco-doc ATTACCATO (nessuna riga vuota tra doc e def). CONSERVATIVO:
// la riga vuota INTERROMPE l'assorbimento.
function isCommentLine(line) {
  const t = line.trim();
  if (t === '') return false;
  return t.startsWith('//') || t.startsWith('/*') || t.startsWith('*') || t.endsWith('*/');
}

// Se a `i` inizia un commento o una stringa Dart, ritorna l'indice SUBITO DOPO il
// token; altrimenti -1. `prev` e' il carattere precedente (disambigua il prefisso
// raw `r"`). Gestisce stringhe singole/doppie, triple ('''/"""), raw, e commenti.
function skipToken(text, i, prev) {
  const c = text[i];
  const n = text[i + 1];
  // commenti
  if (c === '/' && n === '/') {
    let j = i + 2;
    while (j < text.length && text[j] !== '\n') j += 1;
    return j;
  }
  if (c === '/' && n === '*') {
    let j = i + 2;
    while (j < text.length && !(text[j] === '*' && text[j + 1] === '/')) j += 1;
    return Math.min(text.length, j + 2);
  }
  // stringa (eventualmente raw)
  let raw = false;
  let q = null;
  let start = i;
  if ((c === 'r' || c === 'R') && (n === '"' || n === "'") && !isWordChar(prev)) {
    raw = true; q = n; start = i + 1;
  } else if (c === '"' || c === "'") {
    q = c; start = i;
  } else {
    return -1;
  }
  const triple = text[start + 1] === q && text[start + 2] === q;
  let j = start + (triple ? 3 : 1);
  while (j < text.length) {
    const ch = text[j];
    if (!raw && ch === '\\') { j += 2; continue; }
    if (triple) {
      if (ch === q && text[j + 1] === q && text[j + 2] === q) return j + 3;
    } else {
      if (ch === q) return j + 1;
      if (ch === '\n') return j; // stringa non-triple non attraversa il newline (robustezza)
    }
    j += 1;
  }
  return text.length;
}

// Bilancia le parentesi tonde a partire dall'indice di `(` (incluso). Ritorna
// l'indice SUBITO DOPO la `)` di chiusura. -1 se non bilanciato.
function matchParens(text, openIdx) {
  let depth = 0;
  for (let i = openIdx; i < text.length;) {
    const t = skipToken(text, i, text[i - 1]);
    if (t !== -1) { i = t; continue; }
    const c = text[i];
    if (c === '(') depth += 1;
    else if (c === ')') { depth -= 1; if (depth === 0) return i + 1; }
    i += 1;
  }
  return -1;
}

// Dopo la lista parametri, individua l'inizio del corpo: il primo `=>` (arrow),
// `{` (block) o `;` (nessun corpo) top-level. Ritorna { type, idx } o null.
function findBodyStart(text, from) {
  for (let i = from; i < text.length;) {
    const t = skipToken(text, i, text[i - 1]);
    if (t !== -1) { i = t; continue; }
    const c = text[i];
    if (c === '=' && text[i + 1] === '>') return { type: 'arrow', idx: i };
    if (c === '{') return { type: 'brace', idx: i };
    if (c === ';') return { type: 'semi', idx: i };
    i += 1;
  }
  return null;
}

// Primo `;` top-level (depth 0 di (), [], {}) da `from`. Indice SUBITO DOPO. -1 se assente.
function endOfStatement(text, from) {
  let depth = 0;
  for (let i = from; i < text.length;) {
    const t = skipToken(text, i, text[i - 1]);
    if (t !== -1) { i = t; continue; }
    const c = text[i];
    if (c === '(' || c === '[' || c === '{') depth += 1;
    else if (c === ')' || c === ']' || c === '}') depth -= 1;
    else if (c === ';' && depth <= 0) return i + 1;
    i += 1;
  }
  return -1;
}

// `}` bilanciata a partire da `{` (incluso). Indice SUBITO DOPO. -1 se non bilanciato.
function endOfBracedBlock(text, openIdx) {
  let depth = 0;
  for (let i = openIdx; i < text.length;) {
    const t = skipToken(text, i, text[i - 1]);
    if (t !== -1) { i = t; continue; }
    const c = text[i];
    if (c === '{') depth += 1;
    else if (c === '}') { depth -= 1; if (depth === 0) return i + 1; }
    i += 1;
  }
  return -1;
}

/**
 * Rimuove in modo SICURO la definizione top-level della FUNZIONE `symbolName` dal
 * file `absFile`. Ritorna { ok, detail, removed }.
 *   - ok=true  + removed=true: la funzione e' stata rimossa e riscritta.
 *   - ok=false: simbolo non trovato come funzione top-level / file assente / corpo
 *               non determinabile: NESSUNA modifica (mai rimozione approssimata).
 */
export function removeDartSymbol(absFile, symbolName) {
  if (!absFile || !symbolName) {
    return { ok: false, detail: 'argomenti mancanti (absFile/symbolName)', removed: false };
  }
  if (!existsSync(absFile)) {
    return { ok: false, detail: `file assente: ${absFile}`, removed: false };
  }

  const original = readFileSync(absFile, 'utf8');
  const usesCRLF = /\r\n/.test(original);
  const norm = original.replace(/\r\n/g, '\n');
  const lines = norm.split('\n');

  // 1) Trova la riga di definizione della funzione top-level.
  let defLine = -1;
  for (let i = 0; i < lines.length; i += 1) {
    if (isDartDeclLineFor(lines[i], symbolName)) { defLine = i; break; }
  }
  if (defLine === -1) {
    return {
      ok: false,
      removed: false,
      detail: `simbolo "${symbolName}" non trovato come funzione top-level (col 0 con '(') in ${absFile}; nessuna modifica (mai rimozione approssimata)`,
    };
  }

  // 2) Assorbi un blocco-doc ATTACCATO (commenti immediatamente sopra, senza riga vuota).
  let startLine = defLine;
  while (startLine - 1 >= 0 && isCommentLine(lines[startLine - 1])) {
    startLine -= 1;
  }

  // 3) Offset di carattere; localizza la lista parametri e poi il corpo.
  const charIdxOfLine = (idx) => {
    let off = 0;
    for (let i = 0; i < idx; i += 1) off += lines[i].length + 1; // +1 per il '\n'
    return off;
  };
  const lineStart = charIdxOfLine(defLine);
  const nameInLine = lines[defLine].indexOf(symbolName);
  const parenOpen = norm.indexOf('(', lineStart + (nameInLine >= 0 ? nameInLine + symbolName.length : 0));
  if (parenOpen === -1) {
    return { ok: false, removed: false, detail: `lista parametri non trovata per "${symbolName}" in ${absFile}; nessuna modifica` };
  }
  const parenEnd = matchParens(norm, parenOpen);
  if (parenEnd === -1) {
    return { ok: false, removed: false, detail: `parentesi non bilanciate per "${symbolName}" in ${absFile}; nessuna modifica` };
  }
  const body = findBodyStart(norm, parenEnd);
  if (!body) {
    return { ok: false, removed: false, detail: `corpo (=> / { } / ;) non determinabile per "${symbolName}" in ${absFile}; nessuna modifica` };
  }

  let endChar = -1;
  if (body.type === 'arrow') {
    endChar = endOfStatement(norm, body.idx);
  } else if (body.type === 'brace') {
    endChar = endOfBracedBlock(norm, body.idx);
  } else { // semi
    endChar = body.idx + 1;
  }
  if (endChar === -1) {
    return { ok: false, removed: false, detail: `fine del corpo non determinabile per "${symbolName}" in ${absFile}; nessuna modifica` };
  }

  // 4) Espandi fino a fine riga (incluso il '\n').
  let cutEnd = endChar;
  while (cutEnd < norm.length && norm[cutEnd] !== '\n') cutEnd += 1;
  if (cutEnd < norm.length && norm[cutEnd] === '\n') cutEnd += 1;

  const cutStart = charIdxOfLine(startLine);
  const before = norm.slice(0, cutStart);
  const after = norm.slice(cutEnd);
  let out = `${before}${after}`;

  // 5) Normalizza la spaziatura: collassa run di >2 newline a 2, singolo newline finale.
  out = out.replace(/\n{3,}/g, '\n\n');
  out = out.replace(/\n*$/, '\n');
  if (usesCRLF) out = out.replace(/\n/g, '\r\n');

  if (out === original) {
    return { ok: false, removed: false, detail: `nessuna modifica effettiva su ${absFile} (simbolo gia' assente?)` };
  }

  writeFileSync(absFile, out, 'utf8');
  return {
    ok: true,
    removed: true,
    detail: `rimossa funzione top-level ${symbolName} da ${absFile}`,
  };
}
