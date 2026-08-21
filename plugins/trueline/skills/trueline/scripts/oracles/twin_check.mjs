#!/usr/bin/env node
// twin_check.mjs — oracolo CUSTOM detection-only (A2a): segnala directory sorelle
// con basename PARALLELI modulo un token-entita' (clone-and-rename per-entita').
// FATTO strutturale ispezionabile, NON giudizio: emette le due dir + i file paralleli.
// Ecosystem-agnostic. JSON nativo su stdout. MAI gate (il chiamante lo esclude dai blockers).
import { existsSync, readdirSync, statSync } from 'node:fs';
import { resolve, join, basename } from 'node:path';

const MIN_PARALLEL = 3; // soglia K: >=3 file paralleli -> segnale (filtra, non e' un verdetto: detection-only)

// normalizza un basename rimuovendo il token-entita' (case-insensitive) e l'estensione.
// Il token-entita' e' lo STEM del nome-dir (>=4 char) piu' l'eventuale suffisso
// morfologico breve: cosi' plurale-dir e singolare-in-filename collimano
// (commesse~Commessa, preventivi~Preventivo) — clone-and-rename per-entita' reale.
function stripEntity(name, entity) {
  const noExt = name.replace(/\.[jt]sx?$/, '');
  const ent = entity.toLowerCase().replace(/[-_]/g, '');
  let stripped = noExt;
  for (let len = ent.length; len >= 4; len--) {
    const stem = ent.slice(0, len);
    if (new RegExp(stem + '[a-z]{0,2}', 'i').test(stripped)) {
      stripped = stripped.replace(new RegExp(stem + '[a-z]{0,2}', 'ig'), '');
      break;
    }
  }
  return stripped.replace(/[-_]/g, '').toLowerCase();
}
function listDirs(root) {
  if (!existsSync(root)) return [];
  return readdirSync(root).map((n) => join(root, n)).filter((p) => { try { return statSync(p).isDirectory() && basename(p) !== 'node_modules'; } catch { return false; } });
}
function filesOf(dir) {
  try { return readdirSync(dir).filter((n) => /\.[jt]sx?$/.test(n)); } catch { return []; }
}
function walk(root, acc) {
  for (const d of listDirs(root)) { acc.push(d); walk(d, acc); }
  return acc;
}
function main() {
  const dir = process.argv[2];
  if (!dir || !existsSync(dir)) { console.error('uso: twin_check.mjs <dir>'); process.exit(2); }
  const src = existsSync(resolve(dir, 'src')) ? resolve(dir, 'src') : resolve(dir);
  const allDirs = walk(src, []);
  const twins = [];
  // per ogni coppia di directory-SORELLE (stesso parent), confronta i basename modulo il nome-dir.
  const byParent = new Map();
  for (const d of allDirs) { const p = resolve(d, '..'); (byParent.get(p) || byParent.set(p, []).get(p)).push(d); }
  for (const [, sibs] of byParent) {
    for (let i = 0; i < sibs.length; i++) for (let j = i + 1; j < sibs.length; j++) {
      const A = sibs[i], B = sibs[j];
      const entA = basename(A), entB = basename(B);
      const setA = new Set(filesOf(A).map((f) => stripEntity(f, entA)));
      const parallel = filesOf(B).filter((f) => setA.has(stripEntity(f, entB)));
      if (parallel.length >= MIN_PARALLEL) {
        twins.push({ dirA: A, dirB: B, entityA: entA, entityB: entB, parallelFiles: parallel });
      }
    }
  }
  process.stdout.write(JSON.stringify({ oracle: 'twin', minParallel: MIN_PARALLEL, twins }));
  process.exit(0);
}
main();
