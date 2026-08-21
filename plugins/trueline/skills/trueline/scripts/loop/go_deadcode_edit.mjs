// go_deadcode_edit.mjs — helper RIUSABILE per la rimozione SICURA di una FUNZIONE
// Go top-level morta (Eco-F5b). Importato dal fix provider (dispatch dead-code per
// i finding go-deadcode {file, symbol} di tipo unused-function).
//
// Gemello Go di ts_deadcode_edit.mjs (SP-7) e py_deadcode_edit.mjs (SP-4): stesso
// CONTRATTO e stesso PRINCIPIO DI SICUREZZA, adattato alla sintassi Go. NON e' un
// nuovo algoritmo di fix: e' la primitiva di rimozione-simbolo che lega il seed
// postgres-go (SEED:POSTGRESGO-DC: funzione `UnusedHelper` in dead.go, segnalata da
// 'deadcode -json ./...' come irraggiungibile) al ramo dead-code del dispatch.
//
// CONTRATTO
//   removeGoSymbol(absFile, symbolName) -> { ok, detail, removed }
//   - absFile     path ASSOLUTO del file .go nella COPIA temporanea (mai il fixture
//                 canonico: il chiamante opera gia' su verify_workspace).
//   - symbolName  nome della funzione morta da rimuovere (es. "UnusedHelper").
//
// PRINCIPIO DI SICUREZZA (non rompere il modulo):
//   - Si rimuove SOLO la definizione TOP-LEVEL di una FUNZIONE (col 0):
//     `func <name>(...) ... { ... }`, COMPRESO il suo blocco { ... } bilanciato e
//     l'eventuale blocco di commenti `//` immediatamente precedente attaccato alla
//     definizione (nessuna riga vuota in mezzo).
//   - I METODI (`func (r *T) <name>(...)`) NON sono toccati: il loro nome non e' a
//     ridosso di `func` -> isFuncDeclFor ritorna false e si fallisce ONESTAMENTE.
//     (deadcode segnala le funzioni semplici per Name; i metodi restano fuori scope.)
//   - Il bilanciamento delle graffe ignora graffe dentro stringhe (",`), rune ('),
//     e commenti (// e /* */): sufficiente e deterministico per i func che deadcode
//     segnala come irraggiungibili.
//   - Se il simbolo NON e' una funzione top-level, NON si tocca nulla e si ritorna
//     ok:false: meglio fallire ONESTAMENTE (il loop lo trattera' come
//     verification-failed) che corrompere il file. Mai una rimozione approssimata.
//   - Niente parser AST esterno (niente dipendenze): un'analisi a riga + conteggio
//     graffe string-aware basta per le funzioni top-level.
//
// Node ESM, solo built-in (fs). Niente rete, niente dipendenze npm.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

// Escapa un nome-simbolo per uso in regex.
function esc(name) {
  return String(name).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// La riga apre la definizione top-level di una FUNZIONE `name`? (col 0, niente
// indentazione iniziale; `func <name>(` oppure `func <name>[` per le generiche).
// Esclude i metodi `func (recv T) name(` (il nome non segue subito `func`).
function isFuncDeclFor(line, name) {
  if (!/^[^\s]/.test(line)) return false; // deve iniziare a col 0
  const n = esc(name);
  return new RegExp(`^func\\s+${n}\\s*[\\(\\[]`).test(line);
}

// Una riga e' un commento Go (`//` o parte di un blocco `/* ... */`)? Usata SOLO per
// assorbire un blocco-doc ATTACCATO (nessuna riga vuota tra doc e def). CONSERVATIVO:
// la riga vuota INTERROMPE l'assorbimento -> non si inghiotte mai un commento di
// modulo separato da una riga vuota.
function isCommentLine(line) {
  const t = line.trim();
  if (t === '') return false;
  return t.startsWith('//') || t.startsWith('/*') || t.startsWith('*') || t.endsWith('*/');
}

// Trova la prima `{` non-stringa/non-commento a partire da `fromIdx`. -1 se nessuna.
// String-aware Go: stringhe interpretate ("..."), stringhe raw (`...`, senza escape),
// rune ('...'), commenti // e /* */.
function findFirstBrace(text, fromIdx) {
  let inSL = false; let inML = false; let quote = null; // quote: '"' | '`' | "'"
  for (let i = fromIdx; i < text.length; i += 1) {
    const c = text[i];
    const next = text[i + 1];
    if (inSL) { if (c === '\n') inSL = false; continue; }
    if (inML) { if (c === '*' && next === '/') { inML = false; i += 1; } continue; }
    if (quote === '`') { if (c === '`') quote = null; continue; } // raw string: niente escape
    if (quote) { // " oppure '
      if (c === '\\') { i += 1; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && next === '/') { inSL = true; i += 1; continue; }
    if (c === '/' && next === '*') { inML = true; i += 1; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') return i;
  }
  return -1;
}

// Conta le graffe bilanciate string-aware a partire dall'indice di `{` (incluso) e
// ritorna l'indice del carattere SUBITO DOPO la `}` di chiusura. -1 se non bilanciato.
function endOfBracedBlock(text, openIdx) {
  let depth = 0;
  let inSL = false; let inML = false; let quote = null;
  for (let i = openIdx; i < text.length; i += 1) {
    const c = text[i];
    const next = text[i + 1];
    if (inSL) { if (c === '\n') inSL = false; continue; }
    if (inML) { if (c === '*' && next === '/') { inML = false; i += 1; } continue; }
    if (quote === '`') { if (c === '`') quote = null; continue; }
    if (quote) {
      if (c === '\\') { i += 1; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && next === '/') { inSL = true; i += 1; continue; }
    if (c === '/' && next === '*') { inML = true; i += 1; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth += 1;
    else if (c === '}') {
      depth -= 1;
      if (depth === 0) return i + 1;
    }
  }
  return -1;
}

/**
 * Rimuove in modo SICURO la definizione top-level della FUNZIONE `symbolName` dal
 * file `absFile`. Ritorna { ok, detail, removed }.
 *   - ok=true  + removed=true: la funzione e' stata rimossa e riscritta.
 *   - ok=false: simbolo non trovato come funzione top-level / file assente / blocco
 *               non bilanciato: NESSUNA modifica (mai rimozione approssimata).
 */
export function removeGoSymbol(absFile, symbolName) {
  if (!absFile || !symbolName) {
    return { ok: false, detail: 'argomenti mancanti (absFile/symbolName)', removed: false };
  }
  if (!existsSync(absFile)) {
    return { ok: false, detail: `file assente: ${absFile}`, removed: false };
  }

  const original = readFileSync(absFile, 'utf8');
  const usesCRLF = /\r\n/.test(original);
  // NORMALIZZA a '\n' per TUTTO lo scanning: cosi' gli offset di carattere
  // combaciano con `lines[i].length + 1`. Si ri-emette con l'EOL originale.
  const norm = original.replace(/\r\n/g, '\n');
  const lines = norm.split('\n');

  // 1) Trova la riga di definizione della funzione top-level.
  let defLine = -1;
  for (let i = 0; i < lines.length; i += 1) {
    if (isFuncDeclFor(lines[i], symbolName)) { defLine = i; break; }
  }
  if (defLine === -1) {
    return {
      ok: false,
      removed: false,
      detail: `simbolo "${symbolName}" non trovato come funzione top-level (func a col 0) in ${absFile}; nessuna modifica (mai rimozione approssimata)`,
    };
  }

  // 2) Assorbi un blocco-doc ATTACCATO (commenti su righe immediatamente sopra,
  //    SENZA riga vuota in mezzo). La prima riga vuota/di codice interrompe.
  let startLine = defLine;
  while (startLine - 1 >= 0 && isCommentLine(lines[startLine - 1])) {
    startLine -= 1;
  }

  // 3) Offset di carattere d'inizio della riga di definizione, poi trova il blocco.
  const charIdxOfLine = (idx) => {
    let off = 0;
    for (let i = 0; i < idx; i += 1) off += lines[i].length + 1; // +1 per il '\n'
    return off;
  };
  const defStartChar = charIdxOfLine(defLine);
  const firstBrace = findFirstBrace(norm, defStartChar);
  if (firstBrace === -1) {
    return { ok: false, removed: false, detail: `corpo { } non trovato per "${symbolName}" in ${absFile}; nessuna modifica` };
  }
  const blockEnd = endOfBracedBlock(norm, firstBrace);
  if (blockEnd === -1) {
    return { ok: false, removed: false, detail: `blocco { } non bilanciato per "${symbolName}" in ${absFile}; nessuna modifica` };
  }

  // 4) Espandi fino a fine riga (incluso il '\n') della `}` di chiusura.
  let cutEnd = blockEnd;
  while (cutEnd < norm.length && norm[cutEnd] !== '\n') cutEnd += 1;
  if (cutEnd < norm.length && norm[cutEnd] === '\n') cutEnd += 1;

  const cutStart = charIdxOfLine(startLine);
  const before = norm.slice(0, cutStart);
  const after = norm.slice(cutEnd);
  let out = `${before}${after}`;

  // 5) Normalizza la spaziatura attorno al taglio: collassa run di >2 newline a 2 e
  //    garantisci un singolo newline finale.
  out = out.replace(/\n{3,}/g, '\n\n');
  out = out.replace(/\n*$/, '\n');
  // Ri-emetti con l'EOL ORIGINALE.
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
