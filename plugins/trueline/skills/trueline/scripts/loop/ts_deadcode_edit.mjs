// ts_deadcode_edit.mjs — helper RIUSABILE per la rimozione SICURA di un simbolo
// TypeScript/JavaScript morto (SP-7, T2.1). Importato dal fix provider (dispatch
// dead-code per i finding knip {file, symbol} di tipo unused-export/type/...).
//
// Gemello TS di py_deadcode_edit.mjs (SP-4): stesso CONTRATTO e stesso PRINCIPIO
// DI SICUREZZA, adattato alla sintassi TS. NON e' un nuovo algoritmo di fix: e' la
// primitiva di rimozione-simbolo che lega i seed postgres-jsts (PG-S5: simbolo
// `unusedDeadHelper` in src/dead.ts, segnalato da knip come unused-export) al ramo
// dead-code GIA' ESISTENTE del dispatch.
//
// CONTRATTO
//   removeTsSymbol(absFile, symbolName) -> { ok, detail, removed }
//   - absFile     path ASSOLUTO del modulo .ts/.js nella COPIA temporanea (mai il
//                 fixture canonico: il chiamante opera gia' su verify_workspace).
//   - symbolName  nome del simbolo morto da rimuovere (es. "unusedDeadHelper").
//
// PRINCIPIO DI SICUREZZA (non rompere il modulo):
//   - Si rimuove SOLO la definizione TOP-LEVEL ESPORTATA del simbolo (col 0):
//     `export function <name>(...) { ... }`, `export const <name> = ...;`,
//     `export class <name> ... { ... }`, COMPRESO il suo blocco { ... } bilanciato
//     (o, per const/type, fino al `;` o alla fine dell'espressione) e l'eventuale
//     blocco di commenti immediatamente precedente attaccato alla definizione.
//   - Il bilanciamento delle graffe ignora graffe dentro stringhe/template/commenti
//     (sufficiente e deterministico per i simboli che knip segnala come unused).
//   - Se il simbolo NON e' una definizione top-level esportata, NON si tocca nulla
//     e si ritorna ok:false: meglio fallire ONESTAMENTE (il loop lo trattera' come
//     verification-failed) che corrompere il file. Mai una rimozione approssimata.
//   - Niente parser AST esterno (niente dipendenze): un'analisi a riga + conteggio
//     graffe string-aware basta per le definizioni top-level esportate.
//
// Node ESM, solo built-in (fs). Niente rete, niente dipendenze npm.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

// Escapa un nome-simbolo per uso in regex.
function esc(name) {
  return String(name).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// La riga apre la definizione top-level ESPORTATA di `name`? (col 0, niente
// indentazione iniziale). Copre function/const/let/var/class/type/interface/enum.
function isExportedDefLineFor(line, name) {
  if (!/^[^\s]/.test(line)) return false; // deve iniziare a col 0
  const n = esc(name);
  const re = new RegExp(
    `^export\\s+(?:default\\s+)?(?:async\\s+)?`
    + `(?:function\\*?\\s+${n}\\b`
    + `|class\\s+${n}\\b`
    + `|(?:const|let|var)\\s+${n}\\b`
    + `|type\\s+${n}\\b`
    + `|interface\\s+${n}\\b`
    + `|enum\\s+${n}\\b)`,
  );
  return re.test(line);
}

// Una riga e' un commento (// ... o parte di un blocco /* ... */ o JSDoc)? Usata
// SOLO per assorbire un blocco-doc ATTACCATO (nessuna riga vuota tra doc e def).
// CONSERVATIVO: niente codice, e ci si ferma alla prima riga vuota -> non si
// inghiotte MAI un commento condiviso separato da una riga vuota (evita di
// corrompere blocchi di documentazione di modulo non pertinenti).
function isCommentLine(line) {
  const t = line.trim();
  if (t === '') return false; // la riga vuota INTERROMPE l'assorbimento all'indietro
  return t.startsWith('//') || t.startsWith('/*') || t.startsWith('*') || t.endsWith('*/');
}

// Trova l'indice della prima graffa `{` a partire da `fromCharIdx` nel testo,
// ignorando stringhe/template/commenti. Ritorna -1 se non c'e'.
// Conta le graffe bilanciate string-aware a partire dall'indice di `{` (incluso),
// e ritorna l'indice del carattere SUBITO DOPO la `}` di chiusura. -1 se non
// bilanciato (definizione malformata -> il chiamante fallira' onestamente).
function endOfBracedBlock(text, openIdx) {
  let depth = 0;
  let i = openIdx;
  let inSL = false; // // line comment
  let inML = false; // /* */ block comment
  let quote = null; // ' " `
  for (; i < text.length; i += 1) {
    const c = text[i];
    const next = text[i + 1];
    if (inSL) { if (c === '\n') inSL = false; continue; }
    if (inML) { if (c === '*' && next === '/') { inML = false; i += 1; } continue; }
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

// Trova la fine di una definizione const/let/var/type top-level (senza blocco {}):
// il primo `;` top-level (depth 0 di (), [], {}) a partire da `fromIdx`, string-aware.
// Ritorna l'indice SUBITO DOPO il `;`. Se la definizione contiene un blocco {}
// (oggetto/arrow con body), endOfBracedBlock e' preferito dal chiamante. -1 se non
// trova terminatore (la prendiamo fino a fine file in tal caso -> chiamante decide).
function endOfStatement(text, fromIdx) {
  let depth = 0;
  let i = fromIdx;
  let inSL = false; let inML = false; let quote = null;
  for (; i < text.length; i += 1) {
    const c = text[i];
    const next = text[i + 1];
    if (inSL) { if (c === '\n') inSL = false; continue; }
    if (inML) { if (c === '*' && next === '/') { inML = false; i += 1; } continue; }
    if (quote) {
      if (c === '\\') { i += 1; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && next === '/') { inSL = true; i += 1; continue; }
    if (c === '/' && next === '*') { inML = true; i += 1; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '(' || c === '[' || c === '{') depth += 1;
    else if (c === ')' || c === ']' || c === '}') depth -= 1;
    else if (c === ';' && depth === 0) return i + 1;
  }
  return -1;
}

/**
 * Rimuove in modo SICURO la definizione top-level ESPORTATA del simbolo
 * `symbolName` dal file `absFile`. Ritorna { ok, detail, removed }.
 *   - ok=true  + removed=true: la definizione e' stata rimossa e riscritta.
 *   - ok=false: simbolo non trovato come export top-level / file assente /
 *               blocco non bilanciato: NESSUNA modifica (mai rimozione approssimata).
 */
export function removeTsSymbol(absFile, symbolName) {
  if (!absFile || !symbolName) {
    return { ok: false, detail: 'argomenti mancanti (absFile/symbolName)', removed: false };
  }
  if (!existsSync(absFile)) {
    return { ok: false, detail: `file assente: ${absFile}`, removed: false };
  }

  const original = readFileSync(absFile, 'utf8');
  const usesCRLF = /\r\n/.test(original);
  // NORMALIZZA a '\n' per TUTTO lo scanning: cosi' gli offset di carattere
  // combaciano con `lines[i].length + 1` (il '\r' del CRLF altrimenti sfaserebbe
  // gli offset di 1 per riga -> taglio nel punto sbagliato). Si ri-emette con
  // l'EOL originale alla fine. `norm` e' la SOLA base per gli indici.
  const norm = original.replace(/\r\n/g, '\n');
  const lines = norm.split('\n');

  // 1) Trova la riga di definizione top-level esportata del simbolo.
  let defLine = -1;
  for (let i = 0; i < lines.length; i += 1) {
    if (isExportedDefLineFor(lines[i], symbolName)) { defLine = i; break; }
  }
  if (defLine === -1) {
    return {
      ok: false,
      removed: false,
      detail: `simbolo "${symbolName}" non trovato come export top-level in ${absFile}; nessuna modifica (mai rimozione approssimata)`,
    };
  }

  // 2) Estendi all'indietro per assorbire un blocco-doc ATTACCATO (commenti su
  //    righe immediatamente sopra la def, SENZA riga vuota in mezzo): appartiene
  //    alla definizione. La prima riga vuota o di codice INTERROMPE l'assorbimento,
  //    cosi' un commento di modulo/condiviso separato da una riga vuota NON viene
  //    mai inghiottito (conservativo: meglio un commento orfano che un file rotto).
  let startLine = defLine;
  while (startLine - 1 >= 0 && isCommentLine(lines[startLine - 1])) {
    startLine -= 1;
  }

  // 3) Offset di carattere (in `norm`, EOL='\n') d'inizio della riga di
  //    definizione, poi trova la fine del blocco. Function/class hanno un body
  //    { ... }: bilanciamento graffe. const/let/var/type senza body: fino al `;`
  //    top-level (o blocco {} se l'inizializzatore e' un oggetto/arrow con body).
  const charIdxOfLine = (idx) => {
    let off = 0;
    for (let i = 0; i < idx; i += 1) off += lines[i].length + 1; // +1 per il '\n'
    return off;
  };
  const defStartChar = charIdxOfLine(defLine);
  const defLineText = lines[defLine];
  const braceInLine = defLineText.indexOf('{');
  // Posizione assoluta della prima `{` dopo l'inizio della definizione, cercata
  // string-aware su tutto il resto del file (la `{` puo' essere su una riga dopo).
  let endChar = -1;
  const firstBrace = findFirstBrace(norm, defStartChar + (braceInLine >= 0 ? braceInLine : 0));
  const semiEnd = endOfStatement(norm, defStartChar);
  if (firstBrace !== -1 && (semiEnd === -1 || firstBrace < semiEnd)) {
    // C'e' un blocco {} prima del primo `;` top-level: rimuovo fino alla `}` bilanciata.
    const blockEnd = endOfBracedBlock(norm, firstBrace);
    if (blockEnd === -1) {
      return { ok: false, removed: false, detail: `blocco {} non bilanciato per "${symbolName}" in ${absFile}; nessuna modifica` };
    }
    // Per const/let/var con arrow-body, puo' seguire un `;` dopo la `}`: assorbilo.
    endChar = absorbTrailingSemicolon(norm, blockEnd);
  } else if (semiEnd !== -1) {
    endChar = semiEnd; // const/let/var/type terminata da `;`
  } else {
    return { ok: false, removed: false, detail: `fine definizione non determinabile per "${symbolName}" in ${absFile}; nessuna modifica` };
  }

  // 4) Espandi `endChar` per inglobare il resto della riga (incluso il '\n').
  let cutEnd = endChar;
  while (cutEnd < norm.length && norm[cutEnd] !== '\n') cutEnd += 1;
  if (cutEnd < norm.length && norm[cutEnd] === '\n') cutEnd += 1;

  const cutStart = charIdxOfLine(startLine);
  const before = norm.slice(0, cutStart);
  const after = norm.slice(cutEnd);
  let out = `${before}${after}`;

  // 5) Normalizza la spaziatura attorno al taglio: collassa run di >2 newline a 2.
  out = out.replace(/\n{3,}/g, '\n\n');
  // Garantisci un singolo newline finale.
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
    detail: `rimossa definizione top-level esportata ${symbolName} da ${absFile}`,
  };
}

// Trova la prima `{` non-stringa/non-commento a partire da `fromIdx`. -1 se nessuna.
function findFirstBrace(text, fromIdx) {
  let inSL = false; let inML = false; let quote = null;
  for (let i = fromIdx; i < text.length; i += 1) {
    const c = text[i];
    const next = text[i + 1];
    if (inSL) { if (c === '\n') inSL = false; continue; }
    if (inML) { if (c === '*' && next === '/') { inML = false; i += 1; } continue; }
    if (quote) {
      if (c === '\\') { i += 1; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && next === '/') { inSL = true; i += 1; continue; }
    if (c === '/' && next === '*') { inML = true; i += 1; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') return i;
    // un `;` top-level prima di qualsiasi `{` -> nessun blocco per questa def.
    if (c === ';') return -1;
  }
  return -1;
}

// Se dopo la `}` di chiusura segue (eventuali spazi e poi) un `;`, includilo.
function absorbTrailingSemicolon(text, idxAfterBrace) {
  let i = idxAfterBrace;
  while (i < text.length && (text[i] === ' ' || text[i] === '\t')) i += 1;
  if (i < text.length && text[i] === ';') return i + 1;
  return idxAfterBrace;
}
