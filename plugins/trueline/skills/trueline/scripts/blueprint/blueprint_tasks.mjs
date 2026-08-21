// blueprint_tasks.mjs — loader del blueprint (replica di ac_observability_check;
// validate_blueprint non esporta nulla). Sorgente unica per i consumatori NUOVI
// (control4 AC-acceptance + Fase B trace-check). Node ESM, solo built-in.
//
// Le funzioni extractYamlBlocks + parseTasks + loadAllTasks + nonEmptyStr sono
// REPLICATE VERBATIM da trueline/scripts/blueprint/ac_observability_check.mjs
// (stesso comportamento, nessuna modifica): validate_blueprint/ac_observability_check
// NON si toccano. L'unica aggiunta è loadTasks(dir), che normalizza `covers`.
//
// L-COL-002 (determinismo): nessun Date.now()/Math.random(); ordine di scansione
// stabile (readdirSync ... .sort(), come nel loader replicato).
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';

// --- Estrae i blocchi YAML (```yaml ... ```) dai file markdown del blueprint ---
// Identico a validate_blueprint: i due oracoli condividono l'idioma del loader.
function extractYamlBlocks(text) {
  const blocks = [];
  const re = /```ya?ml\s*\n([\s\S]*?)```/g;
  let m;
  while ((m = re.exec(text)) !== null) blocks.push(m[1]);
  return blocks;
}

// --- Mini-parser del solo subset YAML usato dallo schema 11 §3 ---------------
// Replica della logica di validate_blueprint: supporta a OGNI livello (campo del
// task E item di lista-di-mappe) scalari, liste inline [A, B], block-sequence
// ("- x"), block-scalar (|/>) e commenti di riga intera. Deterministico.
function parseTasks(yaml) {
  const lines = yaml.replace(/\r\n/g, '\n').split('\n');
  const tasks = [];
  let cur = null;
  let i = 0;

  const indentOf = (l) => l.length - l.trimStart().length;

  // Rimuove i commenti "#" non quotati. Se le virgolette risultano sbilanciate
  // (es. un apostrofo italiano in un valore non quotato), rifà la scansione
  // ignorando le virgolette, così il commento viene comunque tolto.
  const stripComment = (s) => {
    const scan = (honorQuotes) => {
      let inS = false, inD = false, out = '';
      for (let k = 0; k < s.length; k++) {
        const c = s[k];
        if (honorQuotes) {
          if (c === "'" && !inD) inS = !inS;
          else if (c === '"' && !inS) inD = !inD;
        }
        if (c === '#' && !inS && !inD) break;
        out += c;
      }
      return { out, balanced: !inS && !inD };
    };
    let r = scan(true);
    if (!r.balanced) r = scan(false);
    return r.out;
  };

  const unquote = (v) => {
    v = v.trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      return v.slice(1, -1);
    }
    return v;
  };
  const parseInlineList = (v) => {
    const inner = v.trim().slice(1, -1).trim();
    if (inner === '') return [];
    return inner.split(',').map((x) => unquote(x.trim()));
  };
  const isBlockScalarMarker = (v) =>
    v === '>' || v === '|' || v === '>-' || v === '|-' || v === '>+' || v === '|+';

  // Assegna a obj[key] il valore di una chiave dentro un item di lista-di-mappe,
  // consumando le righe successive se il valore è un block-scalar o una block-sequence.
  // keyIndent = colonna della chiave (i figli devono essere PIÙ indentati di questa).
  const assignItemValue = (obj, key, rawVal, keyIndent) => {
    const v = (rawVal || '').trim();
    if (isBlockScalarMarker(v)) {
      const blockLines = [];
      while (i < lines.length) {
        const bl = lines[i];
        if (bl.trim() === '') { blockLines.push(''); i++; continue; }
        if (indentOf(bl) <= keyIndent) break;
        blockLines.push(bl.trim());
        i++;
      }
      obj[key] = blockLines.join(' ').trim();
      return;
    }
    if (v.startsWith('[')) { obj[key] = parseInlineList(v); return; }
    if (v === '') {
      // Possibile block-sequence: righe "- x" più indentate della chiave.
      const seq = [];
      let consumed = false;
      while (i < lines.length) {
        const sl = lines[i];
        if (sl.trim() === '') { i++; continue; }
        if (indentOf(sl) <= keyIndent) break;
        const stext = stripComment(sl).trim();
        if (stext === '') { i++; continue; } // solo commento
        if (!stext.startsWith('- ')) break;
        seq.push(unquote(stext.slice(2).trim()));
        i++; consumed = true;
      }
      obj[key] = consumed ? seq : '';
      return;
    }
    obj[key] = unquote(v);
  };

  while (i < lines.length) {
    let raw = lines[i];
    let line = stripComment(raw).replace(/\s+$/, '');
    if (line.trim() === '') { i++; continue; }
    const ind = indentOf(line);
    const content = line.trim();

    // Nuovo task: "- id: ..." al livello di lista top
    if (content.startsWith('- id:')) {
      cur = { __indent: ind };
      tasks.push(cur);
      const val = content.slice('- id:'.length).trim();
      cur.id = unquote(val);
      i++;
      continue;
    }

    if (!cur) { i++; continue; }

    // Chiave: valore  (campi del task)
    const kv = content.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/);
    if (kv && ind > cur.__indent) {
      const key = kv[1];
      let val = kv[2];

      if (isBlockScalarMarker(val)) {
        // blocco scalare multilinea -> raccogli le righe più indentate
        const blockLines = [];
        i++;
        const baseInd = ind;
        while (i < lines.length) {
          const bl = lines[i];
          if (bl.trim() === '') { blockLines.push(''); i++; continue; }
          if (indentOf(bl) <= baseInd) break;
          blockLines.push(bl.trim());
          i++;
        }
        cur[key] = blockLines.join(' ').trim();
        continue;
      }

      if (val.startsWith('[')) {
        cur[key] = parseInlineList(val);
        i++;
        continue;
      }

      if (val === '') {
        // Una LISTA: di scalari ("- foo") o di mappe ("- key: val ...").
        // Salta righe vuote e di solo-commento; chiude al primo dedent <= ind.
        const childItems = [];
        i++;
        while (i < lines.length) {
          const craw = lines[i];
          if (craw.trim() === '') { i++; continue; }
          const cind = indentOf(craw);
          if (cind <= ind) break;
          const ctext = stripComment(craw).trim();
          if (ctext === '') { i++; continue; } // riga di solo commento
          if (!ctext.startsWith('- ')) break;  // non è un item di lista
          const after = ctext.slice(2);
          const innerKv = after.trim().match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/);
          if (innerKv) {
            // LISTA DI MAPPE: la prima chiave sta sulla riga del trattino.
            const obj = {};
            const itemBaseInd = cind; // colonna del "-"
            // colonna reale della prima chiave (dopo "- ", spazi variabili)
            const afterDash = craw.slice(itemBaseInd + 1);
            const firstKeyInd = itemBaseInd + 1 + (afterDash.length - afterDash.trimStart().length);
            i++; // consuma la riga "- key: val"
            assignItemValue(obj, innerKv[1], innerKv[2], firstKeyInd);
            // chiavi successive dello stesso item (più indentate del trattino)
            while (i < lines.length) {
              const nraw = lines[i];
              if (nraw.trim() === '') { i++; continue; }
              const nind = indentOf(nraw);
              if (nind <= itemBaseInd) break;
              const ntext = stripComment(nraw).trim();
              if (ntext === '') { i++; continue; } // solo commento dentro l'item
              const nkv = ntext.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/);
              if (!nkv) break;
              i++; // consuma la riga della chiave
              assignItemValue(obj, nkv[1], nkv[2], nind);
            }
            childItems.push(obj);
          } else {
            // lista di scalari
            childItems.push(unquote(after.trim()));
            i++;
          }
        }
        cur[key] = childItems;
        continue;
      }

      // scalare semplice
      cur[key] = unquote(val);
      i++;
      continue;
    }

    i++;
  }

  // pulizia del campo interno
  for (const t of tasks) delete t.__indent;
  return tasks;
}

// --- Carica tutti i task dai file .md del blueprint --------------------------
// Identico a validate_blueprint: i due oracoli leggono lo stesso materiale.
function loadAllTasks(dir) {
  if (!existsSync(dir) || !statSync(dir).isDirectory()) {
    return { tasks: [], error: `directory blueprint inesistente: ${dir}` };
  }
  const files = readdirSync(dir).filter((f) => f.endsWith('.md')).sort();
  let tasks = [];
  for (const f of files) {
    const text = readFileSync(join(dir, f), 'utf8');
    for (const block of extractYamlBlocks(text)) {
      const parsed = parseTasks(block);
      // Considera un blocco "di task" se contiene almeno un task con id reale,
      // ma INCLUDE anche i task con id vuoto/mancante (no falso verde).
      const hasRealTask = parsed.some((t) => typeof t.id === 'string' && t.id.trim().length > 0);
      if (hasRealTask) tasks = tasks.concat(parsed);
    }
  }
  return { tasks, error: null };
}

function nonEmptyStr(v) {
  return typeof v === 'string' && v.trim().length > 0;
}

// --- Normalizzazione di `covers` --------------------------------------------
// Coerente con validate_blueprint AC_COVERAGE: uno scalare diventa lista [scalare];
// undefined/null/'' -> []; una lista resta invariata.
function asArray(v) {
  if (Array.isArray(v)) return v;
  if (v === undefined || v === null || v === '') return [];
  return [v]; // scalare -> lista
}

// --- API pubblica ------------------------------------------------------------
// loadTasks(blueprintDir) -> Task[] con `target_tests[].covers` SEMPRE array.
// loadAllTasks (replicato) ritorna { tasks, error }; qui esponiamo solo i task,
// dopo aver normalizzato `covers`. nonEmptyStr è replicato per parità con la
// fonte (lo consumerà la Fase B trace-check).
export function loadTasks(blueprintDir) {
  const { tasks } = loadAllTasks(blueprintDir);
  for (const t of tasks) {
    for (const tt of (t.target_tests || [])) tt.covers = asArray(tt.covers);
  }
  return tasks;
}

// Esportazioni ausiliarie per i consumatori NUOVI (Fase B); non alterano loadTasks.
export { nonEmptyStr };
