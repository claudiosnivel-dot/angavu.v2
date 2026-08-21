#!/usr/bin/env node
// ac_observability_check.mjs — oracolo deterministico dell'OSSERVABILITÀ degli AC
// (floor del momento 1 "Think Before Coding", spec §5.4 / piano BD-1 T1.1, L-COL-031).
//
// FRATELLO (sibling) di validate_blueprint.mjs, NON una sua modifica: stesso
// scheletro (loader extractYamlBlocks + loadAllTasks, predicato nonEmptyStr;
// report JSON {tool, blueprint_dir, task_count, ok, checks:[{name,ok,detail}]};
// process.exit(allOk?0:1)). I due oracoli sono ORTOGONALI: validate_blueprint
// asserisce la STRUTTURA del task; questo asserisce che ogni `then` degli
// acceptance_criteria sia OSSERVABILE — cioè non si appoggi a un aggettivo vago
// e non oracolabile. Lo schema del task e validate_blueprint NON cambiano.
//
// L-COL-002 (oracle-as-judge): il verde è un FATTO di comando (exit/output),
// MAI una frase dell'LLM. Determinismo (L-COL-002): nessun Date.now()/Math.random().
//
// Node ESM, SOLO moduli built-in: nessun npm install, nessuna dipendenza di rete.
//
// Controllo (1) AC_OBSERVABILITY:
//   per ogni task, per ogni acceptance_criteria[].then, FAIL se il `then` contiene
//   (substring, case-insensitive) uno dei token vietati VERBATIM elencati in
//   references/blueprint/self-check-checklist.md §6 ("Misurabilità"):
//     "funziona bene", "robusto", "sicuro", "performante", "user-friendly".
//   detail = elenco degli `task_id/ac_id` offensivi, separati da ' | '.
//
// Uso:
//   node ac_observability_check.mjs [dir-del-blueprint]   -> report umano, exit 0/1
//   node ac_observability_check.mjs [dir] --json          -> report JSON su stdout, exit 0/1
// Default dir: ../../../eval/seeded-blueprint (la fixture del gate di build, 10 §4),
// che è canonicamente PULITA (nessun token vietato) -> exit 0.
//
// Esito: exit 0 SOLO se il controllo passa; exit 1 altrimenti.

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// --- Parsing degli argomenti -------------------------------------------------
const args = process.argv.slice(2);
const jsonMode = args.includes('--json');
const positional = args.filter((a) => !a.startsWith('--'));
// La dir del blueprint è passata da CLI, oppure default alla fixture seminata.
const blueprintDir = positional[0]
  ? resolve(positional[0])
  : resolve(__dirname, '..', '..', '..', 'eval', 'seeded-blueprint');

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

// --- Token vietati VERBATIM (self-check-checklist.md §6 "Misurabilità") -------
// Aggettivi senza un fatto misurabile dietro: rendono il `then` non osservabile.
// Confronto per SUBSTRING, case-insensitive.
const BANNED_TOKENS = [
  'funziona bene',
  'robusto',
  'sicuro',
  'performante',
  'user-friendly',
];

// --- Esegui il controllo -----------------------------------------------------
const { tasks, error } = loadAllTasks(blueprintDir);
const results = [];
let allOk = true;
const check = (name, ok, detail) => {
  results.push({ name, ok: Boolean(ok), detail });
  if (!ok) allOk = false;
};

// Pre-condizione: la dir esiste e contiene task.
check('TASKS_PRESENT', !error && tasks.length > 0,
  error || `${tasks.length} task trovati in ${blueprintDir}`);

// (1) AC_OBSERVABILITY — ogni acceptance_criteria.then è osservabile
//     (nessun token vietato verbatim, substring case-insensitive).
if (!error && tasks.length > 0) {
  const offenders = [];
  for (const t of tasks) {
    const taskId = nonEmptyStr(t.id) ? t.id : '(?)';
    for (const ac of t.acceptance_criteria || []) {
      if (!ac || typeof ac !== 'object') continue;
      const then = ac.then;
      if (!nonEmptyStr(then)) continue;
      const hay = then.toLowerCase();
      const hit = BANNED_TOKENS.find((tok) => hay.includes(tok));
      if (hit) {
        const acId = nonEmptyStr(ac.id) ? ac.id : '(?)';
        offenders.push(`${taskId}/${acId}`);
      }
    }
  }
  check('(1) AC_OBSERVABILITY', offenders.length === 0,
    offenders.length
      ? offenders.join(' | ')
      : 'ogni acceptance_criteria.then è osservabile (nessun token vietato)');
}

// --- Report ------------------------------------------------------------------
if (jsonMode) {
  const report = {
    tool: 'ac_observability_check',
    blueprint_dir: blueprintDir,
    task_count: tasks.length,
    ok: allOk,
    checks: results,
  };
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(`ac_observability_check — dir: ${blueprintDir}`);
  for (const r of results) {
    console.log(`  [${r.ok ? 'OK' : 'FAIL'}] ${r.name} — ${r.detail}`);
  }
  console.log(allOk ? 'RESULT: OK (ogni acceptance_criteria.then è osservabile)' : 'RESULT: FAIL');
}

process.exit(allOk ? 0 : 1);
