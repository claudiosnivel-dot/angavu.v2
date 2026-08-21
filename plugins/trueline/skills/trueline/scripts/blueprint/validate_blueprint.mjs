#!/usr/bin/env node
// validate_blueprint.mjs — oracolo STRUTTURALE del blueprint (11 §5.1, L-COL-019).
//
// Artefatto di RUNTIME della skill: vive in trueline/scripts/blueprint/ e viaggia
// nel .skill (02 §4). È l'"oracolo del piano": controlli meccanici, esito binario,
// fuori dal contesto del modello (L-COL-002 — il verde è un FATTO di comando, mai
// una frase dell'LLM). La parte semantica NON oracolabile resta alla checklist di
// self-check (references/blueprint/self-check-checklist.md, 11 §5.2).
//
// Node ESM, SOLO moduli built-in: nessun npm install, nessuna dipendenza di rete.
//
// Controlli (11 §5.1):
//   (1) REQUIRED_FIELDS — ogni task ha id + objective + definition_of_done +
//       acceptance_criteria + target_tests NON vuoti, e con CONTENUTO non vacuo
//       (ogni voce di definition_of_done non vuota; ogni target_test nomina un
//       file). Enforcement diretto di L-COL-019 e dello schema §3;
//   (2) AC_COVERAGE     — ogni acceptance_criteria (id) è coperto da >=1 target_tests.covers;
//   (3) DAG_VALID       — depends_on senza cicli e senza riferimenti a id inesistenti;
//   (4) UNIQUE_IDS      — id univoci, non riusati;
//   (5) MACROTASK_OWNERSHIP — ogni task dichiara un macrotask non vuoto.
//
// Ogni acceptance_criteria, inoltre, deve portare id + given + when + then (11 §3).
//
// Fedeltà del parser: il subset YAML dello schema §3 è supportato in modo coerente
// a OGNI livello — scalari, liste inline [A, B], BLOCK-SEQUENCE ("- x" su più righe),
// BLOCK-SCALAR (| literal e > folded) E commenti di riga intera, sia per i campi del
// task sia DENTRO gli item di acceptance_criteria/target_tests. Così l'oracolo accetta
// i blueprint validi a prescindere dall'idioma di scrittura e rifiuta solo i difetti reali.
//
// Uso:
//   node validate_blueprint.mjs [dir-del-blueprint]   -> report umano, exit 0/1
//   node validate_blueprint.mjs [dir] --json          -> report JSON su stdout, exit 0/1
// Default dir: ../../../eval/seeded-blueprint (la fixture del gate di build, 10 §4).
//
// Esito: exit 0 SOLO se TUTTI i controlli passano; exit 1 altrimenti.

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadArchContract, validateArchContract } from './arch_contract.mjs';

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
function extractYamlBlocks(text) {
  const blocks = [];
  const re = /```ya?ml\s*\n([\s\S]*?)```/g;
  let m;
  while ((m = re.exec(text)) !== null) blocks.push(m[1]);
  return blocks;
}

// --- Mini-parser del solo subset YAML usato dallo schema 11 §3 ---------------
// Supporta, a OGNI livello (campo del task E item di lista-di-mappe): scalari,
// liste inline [A, B], block-sequence ("- x"), block-scalar (|/>) e commenti di
// riga intera. Deterministico e sufficiente per lo schema del task.
function parseTasks(yaml) {
  const lines = yaml.replace(/\r\n/g, '\n').split('\n');
  const tasks = [];
  let cur = null;
  let i = 0;

  const indentOf = (l) => l.length - l.trimStart().length;

  // Rimuove i commenti "#" non quotati. Se le virgolette risultano sbilanciate
  // (es. un apostrofo italiano in un valore non quotato: "chiama l'endpoint # x"),
  // rifà la scansione ignorando le virgolette, così il commento viene comunque tolto.
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
      // ma INCLUDE anche i task con id vuoto/mancante, così vengono SEGNALATI
      // dai controlli invece di sparire silenziosamente (no falso verde).
      const hasRealTask = parsed.some((t) => typeof t.id === 'string' && t.id.trim().length > 0);
      if (hasRealTask) tasks = tasks.concat(parsed);
    }
  }
  return { tasks, error: null };
}

function nonEmptyList(v) {
  return Array.isArray(v) && v.length > 0;
}
function nonEmptyStr(v) {
  return typeof v === 'string' && v.trim().length > 0;
}

// --- Esegui i controlli ------------------------------------------------------
const { tasks, error } = loadAllTasks(blueprintDir);
const results = [];
let allOk = true;
const check = (name, ok, detail) => {
  results.push({ name, ok: Boolean(ok), detail });
  if (!ok) allOk = false;
};

// Pre-condizione: la dir esiste e contiene task
check('TASKS_PRESENT', !error && tasks.length > 0,
  error || `${tasks.length} task trovati in ${blueprintDir}`);

// Se non c'è nulla da validare, salta i controlli sullo schema ma resta FAIL.
if (!error && tasks.length > 0) {
  // (1) campi obbligatori PRESENTI e con CONTENUTO non vacuo (L-COL-019 + schema §3)
  {
    const bad = [];
    for (const t of tasks) {
      const miss = [];
      if (!nonEmptyStr(t.id)) miss.push('id');
      if (!nonEmptyStr(t.objective)) miss.push('objective');
      if (!nonEmptyList(t.definition_of_done)) miss.push('definition_of_done');
      else if (!t.definition_of_done.every(nonEmptyStr)) miss.push('definition_of_done(voce vuota)');
      if (!nonEmptyList(t.acceptance_criteria)) miss.push('acceptance_criteria');
      if (!nonEmptyList(t.target_tests)) miss.push('target_tests');
      else if (!t.target_tests.every((tt) => tt && nonEmptyStr(tt.file))) miss.push('target_tests(file mancante)');
      if (miss.length) bad.push(`${t.id || '(?)'}: manca ${miss.join(',')}`);
    }
    check('(1) REQUIRED_FIELDS', bad.length === 0,
      bad.length ? bad.join(' | ') : 'tutti i campi obbligatori presenti e non vuoti');
  }

  // (2) ogni acceptance_criteria.id coperto da >=1 target_tests.covers; nessun criterio orfano.
  //     Verifica anche che ogni AC porti id + given + when + then (11 §3).
  {
    const orphans = [];
    const malformed = [];
    for (const t of tasks) {
      const covered = new Set();
      for (const tt of t.target_tests || []) {
        const c = tt && tt.covers;
        if (Array.isArray(c)) for (const x of c) covered.add(x);
        else if (nonEmptyStr(c)) covered.add(c);
      }
      for (const ac of t.acceptance_criteria || []) {
        if (!ac || !nonEmptyStr(ac.id)) {
          orphans.push(`${t.id}: acceptance_criteria senza id`);
          continue;
        }
        const missField = ['given', 'when', 'then'].filter((k) => !nonEmptyStr(ac[k]));
        if (missField.length) malformed.push(`${t.id}/${ac.id} senza ${missField.join(',')}`);
        if (!covered.has(ac.id)) orphans.push(`${t.id}/${ac.id} non coperto`);
      }
    }
    const issues = [...orphans, ...malformed];
    check('(2) AC_COVERAGE', issues.length === 0,
      issues.length ? issues.join(' | ') : 'ogni acceptance_criteria (id+given+when+then) coperto da >=1 target_test');
  }

  // (3) DAG: niente cicli, niente id inesistenti.
  {
    const ids = new Set(tasks.map((t) => t.id));
    const dangling = [];
    const graph = new Map();
    for (const t of tasks) {
      const deps = Array.isArray(t.depends_on) ? t.depends_on : [];
      graph.set(t.id, deps);
      for (const d of deps) if (!ids.has(d)) dangling.push(`${t.id} -> ${d} (inesistente)`);
    }
    // rilevamento cicli (DFS con colori bianco/grigio/nero)
    const WHITE = 0, GRAY = 1, BLACK = 2;
    const color = new Map([...ids].map((id) => [id, WHITE]));
    const cycles = [];
    const dfs = (node, path) => {
      color.set(node, GRAY);
      for (const dep of graph.get(node) || []) {
        if (!ids.has(dep)) continue; // dangling già segnalato
        if (color.get(dep) === GRAY) {
          cycles.push([...path, node, dep].join(' -> '));
        } else if (color.get(dep) === WHITE) {
          dfs(dep, [...path, node]);
        }
      }
      color.set(node, BLACK);
    };
    for (const id of ids) if (color.get(id) === WHITE) dfs(id, []);

    const ok = dangling.length === 0 && cycles.length === 0;
    const detail = ok
      ? 'DAG aciclico, nessun riferimento a id inesistente'
      : [...dangling, ...cycles.map((c) => `ciclo: ${c}`)].join(' | ');
    check('(3) DAG_VALID', ok, detail);
  }

  // (4) id univoci
  {
    const seen = new Map();
    const dups = [];
    for (const t of tasks) seen.set(t.id, (seen.get(t.id) || 0) + 1);
    for (const [id, n] of seen) if (n > 1) dups.push(`${id} x${n}`);
    check('(4) UNIQUE_IDS', dups.length === 0,
      dups.length ? `duplicati: ${dups.join(', ')}` : `${seen.size} id univoci`);
  }

  // (5) appartenenza: ogni task dichiara un macrotask non vuoto
  {
    const bad = [];
    for (const t of tasks) if (!nonEmptyStr(t.macrotask)) bad.push(`${t.id}: macrotask mancante`);
    check('(5) MACROTASK_OWNERSHIP', bad.length === 0,
      bad.length ? bad.join(' | ') : 'ogni task dichiara un macrotask');
  }

  // (6) ARCH_CONTRACT_WELL_FORMED — CONDIZIONALE (A2b): solo se il blueprint
  //     dichiara un blocco `architecture:`. Assente -> nessun controllo (skip):
  //     la fixture seeded senza strati resta verde (BIT-invarianza).
  {
    let contract = null, parseErr = null;
    try { contract = loadArchContract(blueprintDir); } catch (e) { parseErr = e.message; }
    if (parseErr) {
      check('(6) ARCH_CONTRACT_WELL_FORMED', false, `contratto architettura non parsabile: ${parseErr}`);
    } else if (contract) {
      const v = validateArchContract(contract);
      check('(6) ARCH_CONTRACT_WELL_FORMED', v.ok,
        v.ok ? 'contratto strati/forbidden ben formato' : v.errors.join(' | '));
    }
    // contract === null -> nessun blocco architecture -> nessun check (skip legittimo)
  }
}

// --- Report ------------------------------------------------------------------
if (jsonMode) {
  const report = {
    tool: 'validate_blueprint',
    blueprint_dir: blueprintDir,
    task_count: tasks.length,
    ok: allOk,
    checks: results,
  };
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(`validate_blueprint — dir: ${blueprintDir}`);
  for (const r of results) {
    console.log(`  [${r.ok ? 'OK' : 'FAIL'}] ${r.name} — ${r.detail}`);
  }
  console.log(allOk ? 'RESULT: OK (tutti i controlli strutturali passati)' : 'RESULT: FAIL');
}

process.exit(allOk ? 0 : 1);
