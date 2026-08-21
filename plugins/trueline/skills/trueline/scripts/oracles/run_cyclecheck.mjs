#!/usr/bin/env node
// run_cyclecheck.mjs — oracolo CICLI DI IMPORT (A2a). Il grafo madge e il DFS
// vivono in module_graph.mjs (condiviso con arch_check, A2b). Comportamento
// INVARIATO: grafo vuoto/non eseguito -> exit 1 DICHIARATO (L-COL-006), mai
// {cycles:[]} nudo; JSON nativo su stdout col verdetto nel payload (03 §3).
import { existsSync } from 'node:fs';
import { buildModuleGraph, findCycles } from './module_graph.mjs';

function main() {
  const dir = process.argv[2];
  if (!dir || !existsSync(dir)) { console.error('uso: run_cyclecheck.mjs <dir>'); process.exit(2); }
  const { graph, modules, degraded, detail } = buildModuleGraph(dir);
  if (degraded) { console.error(`${detail}: oracolo non eseguito`); process.exit(1); } // non un verde (L-COL-006)
  const cycles = findCycles(graph).map((c) => ({ modules: c }));
  process.stdout.write(JSON.stringify({ oracle: 'cycle', tool: 'madge', modulesScanned: modules.length, cycles }));
  process.exit(0);
}
main();
