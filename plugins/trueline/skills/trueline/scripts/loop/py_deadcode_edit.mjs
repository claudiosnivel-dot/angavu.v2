// py_deadcode_edit.mjs — helper RIUSABILE per la rimozione SICURA di un simbolo
// Python morto (SP-4, T2.1). Importato dal fix provider (dispatch dead-code per i
// finding vulture {file, line, symbol}).
//
// CONTRATTO
//   removePySymbol(absFile, symbolName, { kindHint }) -> { ok, detail, removed }
//   - absFile     path ASSOLUTO del modulo .py nella COPIA temporanea (mai il
//                 fixture canonico: il chiamante opera gia' su verify_workspace).
//   - symbolName  nome del simbolo morto da rimuovere (es. "_unused_helper").
//   - kindHint    opzionale: "function" | "class" (default: "function"). vulture
//                 emette il tipo nel finding; lo usiamo solo come euristica del
//                 keyword di definizione (def/class), non cambia la sicurezza.
//
// PRINCIPIO DI SICUREZZA (non rompere il modulo):
//   - Si rimuove SOLO la definizione TOP-LEVEL del simbolo (indentazione 0):
//     `def <name>(...)` o `class <name>...`, COMPRESO il suo blocco indentato
//     (corpo + docstring + eventuale decoratore immediatamente precedente).
//   - Il confine del blocco e' la prima riga NON vuota a indentazione 0 dopo la
//     riga di definizione (la def/class successiva, o EOF). Le righe vuote e i
//     commenti interni al blocco appartengono al blocco e vengono rimossi con
//     esso; le righe vuote di separazione DOPO il blocco vengono normalizzate.
//   - Se il simbolo NON e' una definizione top-level (non trovato a col 0),
//     NON si tocca nulla e si ritorna ok:false: meglio fallire ONESTAMENTE (il
//     loop lo trattera' come verification-failed) che corrompere il file.
//   - NON si usa un parser AST esterno (niente dipendenze): un'analisi a
//     indentazione e' sufficiente e deterministica per i simboli top-level che
//     vulture segnala. Casi annidati / overload restano fuori scope (ritornano
//     ok:false, mai una rimozione approssimata).
//
// Node ESM, solo built-in (fs). Niente rete, niente dipendenze npm.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

// Una riga e' "a indentazione 0" se inizia con un carattere non-spazio.
function isTopLevel(line) {
  return line.length > 0 && !/^\s/.test(line);
}

// La riga apre la definizione top-level di `name`? Tollera decoratori sopra (li
// gestisce il chiamante guardando all'indietro). Match su `def name(` / `async
// def name(` / `class name(` / `class name:`.
function isDefLineFor(line, name) {
  if (!isTopLevel(line)) return false;
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`^(?:async\\s+)?def\\s+${escaped}\\s*\\(|^class\\s+${escaped}\\s*[\\(:]`);
  return re.test(line);
}

// Una riga top-level che e' un decoratore (@...) appartiene alla definizione che
// la segue: se rimuoviamo la def, dobbiamo rimuovere anche i suoi decoratori.
function isDecorator(line) {
  return isTopLevel(line) && /^@/.test(line);
}

/**
 * Rimuove in modo SICURO la definizione top-level del simbolo `symbolName` dal
 * file `absFile`. Ritorna { ok, detail, removed }.
 *   - ok=true  + removed=true: la definizione e' stata rimossa e riscritta.
 *   - ok=false: simbolo non trovato come definizione top-level / file assente:
 *               NESSUNA modifica (mai una rimozione approssimata).
 */
export function removePySymbol(absFile, symbolName, opts = {}) {
  const kindHint = opts.kindHint || 'function';
  if (!absFile || !symbolName) {
    return { ok: false, detail: 'argomenti mancanti (absFile/symbolName)', removed: false };
  }
  if (!existsSync(absFile)) {
    return { ok: false, detail: `file assente: ${absFile}`, removed: false };
  }

  const original = readFileSync(absFile, 'utf8');
  // Preserva il fine-riga dominante per non sporcare il diff (CRLF vs LF).
  const usesCRLF = /\r\n/.test(original);
  const lines = original.split(/\r?\n/);

  // 1) Trova la riga di definizione top-level del simbolo.
  let defIdx = -1;
  for (let i = 0; i < lines.length; i += 1) {
    if (isDefLineFor(lines[i], symbolName)) { defIdx = i; break; }
  }
  if (defIdx === -1) {
    return {
      ok: false,
      removed: false,
      detail: `simbolo "${symbolName}" non trovato come definizione top-level (def/class a col 0) in ${absFile}; nessuna modifica (mai rimozione approssimata)`,
    };
  }

  // 2) Estendi all'indietro per assorbire i decoratori immediatamente precedenti
  //    (appartengono alla stessa definizione).
  let start = defIdx;
  while (start - 1 >= 0 && isDecorator(lines[start - 1])) start -= 1;

  // 3) Trova la fine del blocco: la prima riga NON vuota a indentazione 0 DOPO la
  //    riga di definizione (un'altra def/class/assegnazione top-level), oppure EOF.
  //    Le righe vuote e i commenti indentati nel mezzo restano dentro il blocco.
  let end = defIdx + 1;
  while (end < lines.length) {
    const ln = lines[end];
    if (ln.trim() === '') { end += 1; continue; } // riga vuota: ancora nel blocco
    if (isTopLevel(ln)) break; // prima riga top-level non vuota = inizio del prossimo simbolo
    end += 1; // riga indentata = corpo del blocco
  }
  // `end` punta alla prima riga top-level successiva (o lines.length). Le righe
  // vuote che precedono `end` sono separatori: le includiamo nella rimozione e
  // poi normalizziamo la spaziatura (max 2 righe vuote consecutive, stile PEP8).

  const kept = lines.slice(0, start).concat(lines.slice(end));

  // 4) Normalizza la spaziatura attorno al taglio: collassa eventuali run di
  //    righe vuote (>2) introdotti dalla rimozione, e togli righe vuote in coda.
  const normalized = collapseBlankRuns(kept);

  let out = normalized.join(usesCRLF ? '\r\n' : '\n');
  // Garantisci un singolo newline finale (i moduli Python finiscono con \n).
  out = out.replace(/[\r\n]*$/, usesCRLF ? '\r\n' : '\n');

  if (out === original) {
    return { ok: false, removed: false, detail: `nessuna modifica effettiva su ${absFile} (simbolo gia' assente?)` };
  }

  writeFileSync(absFile, out, 'utf8');
  const kw = kindHint === 'class' ? 'class' : 'def';
  return {
    ok: true,
    removed: true,
    detail: `rimossa definizione top-level ${kw} ${symbolName} (righe ${start + 1}-${end}) da ${absFile}`,
  };
}

// Collassa run di >2 righe vuote consecutive a 2 (stile PEP8 fra def top-level).
function collapseBlankRuns(lines) {
  const out = [];
  let blanks = 0;
  for (const ln of lines) {
    if (ln.trim() === '') {
      blanks += 1;
      if (blanks <= 2) out.push(ln);
    } else {
      blanks = 0;
      out.push(ln);
    }
  }
  return out;
}
