#!/usr/bin/env node
// ac_assertion_trace_check.mjs — oracolo deterministico dell'ANTI-TAMPER della
// PROVENIENZA del test d'accettazione (AT-1 Fase B, spec §5.3; completa L-COL-032).
//
// FRATELLO (sibling) di validate_blueprint/ac_observability_check, NON una loro
// modifica. RIUSA il loader esportato loadTasks(dir) di blueprint_tasks.mjs (Fase A):
// NESSUNA replica del parser YAML (riduce il debito 3ª-copia annotato in L-COL-029).
//
// SEMANTICA (spec §5.3 / brief §5): ogni acceptance_criteria VALUTATO deve essere
// TRACCIATO da ≥1 suo file coprante IN-SCOPE, tramite un tag `covers: <AC-id>` dentro
// un COMMENTO del file. Un AC valutato non tracciato → assertionTrace { ok:false } →
// control4 RED PRIMA di eseguire: un target_test che non dichiara QUALE AC esercita non
// e' una provenienza d'accettazione valida.
//
//   - VALUTATO: un AC e' valutato sse ≥1 dei suoi file copranti (i target_tests del suo
//     task il cui covers include l'AC) e' IN-SCOPE (presente su disco). Tutti i copranti
//     mancanti → SALTATO (non RED), coerente con lo skip della Fase A.
//   - TRACCIATO (per-AC GLOBALE): basta UN file coprante in-scope che contenga il tag.
//   - covers normalizzato scalar→[scalar] a monte (loadTasks).
//   - Tag valido: `covers:\s*<id>\b` ancorato all'id esatto (AC-1 NON matcha AC-10) che
//     compaia nella PORZIONE COMMENTATA di una riga (string-aware: un // dentro una
//     stringa NON apre un commento → chiude la gameabilita' tag-in-stringa).
//   - Tag spurio (id non tra i covers dichiarati del file) → IGNORATO: e' semplicemente
//     mai interrogato (si cerca covers:<id> solo per gli AC valutati di quel task).
//
// L-COL-002 (oracle-as-judge): il verde e' un FATTO (presenza/assenza fisica del tag),
// MAI una frase LLM. L-COL-006: la presenza-tag e' un FLOOR deterministico, NON prova di
// bonta' semantica dell'asserzione (resta advisory). Determinismo: nessun Date.now()/
// Math.random(); ordine stabile (localeCompare).
//
// Node ESM, SOLO built-in (+ loadTasks dep-free). Nessun npm install.

import { readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadTasks } from './blueprint_tasks.mjs';

// --- escape per regex (l'id e' interpolato in un pattern) --------------------
function escapeRegex(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// --- Porzione COMMENTATA di una riga, string-aware ---------------------------
// Scandisce la riga char-by-char tracciando lo stato di stringa (' " `) e di
// block-comment /* */ (propagato tra righe via `inBlock`). Ritorna { commented,
// inBlockAfter }: `commented` = concatenazione dei tratti DENTRO un commento (di
// riga // # --, o di blocco). Un marcatore di commento DENTRO una stringa NON apre
// un commento (gameabilita' tag-in-stringa chiusa). Lo stato di stringa NON e'
// propagato tra righe (le stringhe multilinea sono un limite advisory, brief §10).
function commentedPortion(line, inBlock) {
  let commented = '';
  let i = 0;
  let block = inBlock;
  let str = null; // null | "'" | '"' | '`'
  while (i < line.length) {
    const c = line[i];
    const c2 = i + 1 < line.length ? line[i + 1] : '';
    if (block) {
      if (c === '*' && c2 === '/') { commented += '*/'; block = false; i += 2; continue; }
      commented += c; i += 1; continue;
    }
    if (str) {
      if (c === '\\') { i += 2; continue; }       // escape: salta il prossimo char
      if (c === str) { str = null; i += 1; continue; }
      i += 1; continue;
    }
    if (c === '"' || c === "'" || c === '`') { str = c; i += 1; continue; }
    if (c === '/' && c2 === '*') { block = true; commented += '/*'; i += 2; continue; }
    if (c === '/' && c2 === '/') { commented += line.slice(i); break; } // line comment //
    if (c === '#') { commented += line.slice(i); break; }              // line comment #
    if (c === '-' && c2 === '-') { commented += line.slice(i); break; } // line comment -- (SQL)
    i += 1;
  }
  return { commented, inBlockAfter: block };
}

// --- Un testo traccia l'AC? (PURA, esportata per il test) --------------------
// True sse una porzione commentata di una qualunque riga contiene covers:<id>
// ancorato. Block-comment propagato tra righe.
export function textTracesAc(text, acId) {
  const re = new RegExp('covers:\\s*' + escapeRegex(acId) + '\\b');
  const lines = String(text).replace(/\r\n/g, '\n').split('\n');
  let inBlock = false;
  for (const line of lines) {
    const { commented, inBlockAfter } = commentedPortion(line, inBlock);
    if (commented && re.test(commented)) return true;
    inBlock = inBlockAfter;
  }
  return false;
}

// --- Un file (in-scope) traccia l'AC? ----------------------------------------
function fileTracesAc(absFile, acId) {
  if (!existsSync(absFile)) return false;
  let text;
  try { text = readFileSync(absFile, 'utf8'); } catch { return false; }
  return textTracesAc(text, acId);
}

// --- API: assertionTrace -----------------------------------------------------
export function assertionTrace(tasks, appDir, inScope) {
  const inScopeSet = new Set(inScope || []);
  const untracked = [];
  for (const t of (tasks || [])) {
    const taskId = (typeof t.id === 'string' && t.id.trim()) ? t.id : '(?)';
    // Per AC: i file copranti IN-SCOPE di questo task (covers gia' array da loadTasks).
    const coveringInScope = new Map(); // acId -> [file, ...]
    for (const tt of (t.target_tests || [])) {
      if (!tt || typeof tt.file !== 'string') continue;
      if (!inScopeSet.has(tt.file)) continue; // fuori scope (mancante) → non contribuisce
      for (const acId of (tt.covers || [])) {
        if (!coveringInScope.has(acId)) coveringInScope.set(acId, []);
        coveringInScope.get(acId).push(tt.file);
      }
    }
    for (const ac of (t.acceptance_criteria || [])) {
      if (!ac || typeof ac !== 'object') continue;
      const acId = (typeof ac.id === 'string' && ac.id.trim()) ? ac.id : null;
      if (!acId) continue;
      const covering = coveringInScope.get(acId) || [];
      if (covering.length === 0) continue; // AC non valutato → saltato (non RED)
      const traced = covering.some((file) => fileTracesAc(join(appDir, file), acId));
      if (!traced) untracked.push({ task_id: taskId, ac_id: acId });
    }
  }
  untracked.sort((a, b) =>
    `${a.task_id}/${a.ac_id}`.localeCompare(`${b.task_id}/${b.ac_id}`));
  const ok = untracked.length === 0;
  const detail = ok
    ? "ogni AC valutato e' tracciato da un file coprante in-scope (tag covers: in commento)"
    : untracked.map((u) => `${u.task_id}/${u.ac_id}`).join(' | ');
  return { ok, detail, untracked };
}

// --- CLI (eseguita solo se il modulo e' invocato direttamente) ---------------
function mainCli() {
  const argv = process.argv.slice(2);
  const jsonMode = argv.includes('--json');
  const pos = argv.filter((a) => !a.startsWith('--'));
  const blueprintDir = pos[0];
  const appDir = pos[1];
  if (!blueprintDir || !appDir) {
    console.error('uso: node ac_assertion_trace_check.mjs <blueprint-dir> <app-dir> [--json]');
    process.exit(2);
  }
  const tasks = loadTasks(blueprintDir);
  const inScope = [];
  for (const t of tasks) {
    for (const tt of (t.target_tests || [])) {
      if (tt && typeof tt.file === 'string' && existsSync(join(appDir, tt.file))) inScope.push(tt.file);
    }
  }
  inScope.sort();
  const res = assertionTrace(tasks, appDir, inScope);
  if (jsonMode) {
    console.log(JSON.stringify({
      tool: 'ac_assertion_trace_check', blueprint_dir: blueprintDir, app_dir: appDir,
      in_scope: inScope, ok: res.ok, untracked: res.untracked,
    }, null, 2));
  } else {
    console.log(`ac_assertion_trace_check — blueprint: ${blueprintDir} · app: ${appDir}`);
    console.log(`  in-scope: ${inScope.length} target_test`);
    console.log(`  [${res.ok ? 'OK' : 'FAIL'}] AC_TRACE — ${res.detail}`);
    console.log(res.ok ? 'RESULT: OK' : 'RESULT: FAIL (AC valutato non tracciato)');
  }
  process.exit(res.ok ? 0 : 1);
}

const invokedDirect = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirect) mainCli();
