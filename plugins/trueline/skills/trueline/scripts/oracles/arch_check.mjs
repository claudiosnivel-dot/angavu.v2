#!/usr/bin/env node
// arch_check.mjs — oracolo ALTITUDINE (A2b). Verifica il contratto strati/forbidden
// dichiarato nel blueprint contro il grafo import reale (madge, via module_graph).
// Famiglia dichiarativa (rls_check/firestore_rules_check): JSON nativo su stdout, il
// verdetto vive nel payload; il PARSER non fa throw. VACUITY GUARD obbligatorio
// (L-COL-006): grafo vuoto / 0 regole / regola con strato a 0 moduli -> exit 1
// DICHIARATO (stderr, stdout vuoto), mai findings:[] nudo. BUILD-only (il contratto
// vive nel blueprint). Gate ASSOLUTO deciso dal checkpoint (ABSOLUTE_GATE_ORACLES).
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { buildModuleGraph } from './module_graph.mjs';
import { loadArchContract } from '../blueprint/arch_contract.mjs';

const __filename = fileURLToPath(import.meta.url);

// glob -> RegExp: supporta ** (qualunque, incl. /) e * (qualunque tranne /).
function globToRegExp(glob) {
  let re = '^';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') { re += '.*'; i++; if (glob[i + 1] === '/') i++; }
      else re += '[^/]*';
    } else if ('/.+?^${}()|[]\\'.includes(c)) { re += '\\' + c; }
    else re += c;
  }
  return new RegExp(re + '$');
}

// Strato di un modulo: fra i glob che matchano, vince il PIÙ SPECIFICO (prefisso
// letterale più lungo); pari merito -> ordine di dichiarazione. Nessun match -> null.
export function layerOf(modulePath, layers) {
  let best = null, bestLen = -1;
  for (const [name, glob] of Object.entries(layers || {})) {
    if (globToRegExp(String(glob)).test(modulePath)) {
      const litLen = String(glob).split('*')[0].length; // prefisso letterale
      if (litLen > bestLen) { best = name; bestLen = litLen; }
    }
  }
  return best;
}

// Insieme dei moduli (chiavi + valori del grafo) assegnati a ciascuno strato.
function modulesByLayer(graph, layers) {
  const all = new Set(Object.keys(graph));
  for (const deps of Object.values(graph)) for (const d of deps) all.add(d);
  const byLayer = {};
  for (const name of Object.keys(layers)) byLayer[name] = [];
  for (const m of all) { const L = layerOf(m, layers); if (L) byLayer[L].push(m); }
  return byLayer;
}

// Un modulo di layer `to` è raggiungibile da `src`? Traversa TUTTI gli edge (anche
// verso le foglie value-non-key: guard rilassato vs findCycles). Ritorna il path
// minimo verso il bersaglio lessicograficamente minimo, o null.
function reachTo(graph, src, toSet) {
  const prev = new Map([[src, null]]);
  const queue = [src];
  const hits = [];
  while (queue.length) {
    const node = queue.shift();
    for (const dep of (graph[node] || [])) {
      if (prev.has(dep)) continue;
      prev.set(dep, node);
      if (toSet.has(dep)) hits.push(dep);
      queue.push(dep); // rilassato: prosegue anche se dep non è chiave del grafo
    }
  }
  if (!hits.length) return null;
  const target = hits.sort()[0];
  const path = [];
  for (let n = target; n != null; n = prev.get(n)) path.unshift(n);
  return { target, path };
}

// Riporta i path del grafo madge (relativi al TARGET: 'src' se esiste, altrimenti
// '.') allo spazio-path DIR-RELATIVE del contratto, così i glob dichiarati (es.
// "src/ui/**") matchano i moduli. target '.' -> path già dir-relative (invariato).
// Senza questo, madge --json src restituisce "ui/panel.ts" e il glob "src/ui/**"
// non aggancerebbe nulla -> vacuity spuria (falso "regola morta").
export function prefixGraph(graph, target) {
  if (!graph || !target || target === '.') return graph;
  const pfx = target.endsWith('/') ? target : target + '/';
  const out = {};
  for (const [k, deps] of Object.entries(graph)) out[pfx + k] = (deps || []).map((d) => pfx + d);
  return out;
}

// Valuta il contratto sul grafo. Ritorna { degraded, detail, violations }.
export function evaluateContract(graph, contract) {
  const layers = contract.layers || {};
  const rules = contract.forbidden || [];
  if (!graph || Object.keys(graph).length === 0) return { degraded: true, detail: 'grafo vuoto', violations: [] };
  if (rules.length === 0) return { degraded: true, detail: '0 regole forbidden (contratto vacuo)', violations: [] };
  const byLayer = modulesByLayer(graph, layers);
  // Vacuity: ogni regola deve agganciare moduli reali su ENTRAMBI gli strati.
  for (const r of rules) {
    if ((byLayer[r.from] || []).length === 0 || (byLayer[r.to] || []).length === 0) {
      return { degraded: true, detail: `regola ${r.from}->${r.to}: uno strato mappa 0 moduli reali (regola morta)`, violations: [] };
    }
  }
  const allow = contract.allow || [];
  const isAllowed = (from, to, src) => allow.some((a) =>
    a.from === from && a.to === to && (!a.module || a.module === src || globToRegExp(String(a.module)).test(src)));
  const violations = [];
  const seen = new Set();
  for (const r of rules) {
    const toSet = new Set(byLayer[r.to]);
    for (const src of byLayer[r.from].slice().sort()) {
      let hit = null;
      if (r.mode === 'direct') {
        const t = (graph[src] || []).filter((d) => toSet.has(d)).sort()[0];
        if (t) hit = { target: t, path: [src, t] };
      } else {
        hit = reachTo(graph, src, toSet);
      }
      if (!hit) continue;
      const key = `${r.from}|${r.to}|${src}`;
      if (seen.has(key)) continue;
      seen.add(key);
      violations.push({
        control_id: 'ARCH001_FORBIDDEN_DEPENDENCY',
        from: r.from, to: r.to, source_module: src, target_module: hit.target, path: hit.path,
        accepted_exception: isAllowed(r.from, r.to, src) || undefined,
      });
    }
  }
  return { degraded: false, detail: `${violations.length} violazioni`, violations };
}

function main() {
  const args = process.argv.slice(2);
  const codeDir = args[0];
  const bpIdx = args.indexOf('--blueprint');
  const blueprintDir = bpIdx >= 0 ? args[bpIdx + 1] : null;
  if (!codeDir || !existsSync(codeDir) || !blueprintDir) {
    process.stderr.write('uso: node arch_check.mjs <codeDir> --blueprint <blueprintDir>\n');
    process.exit(2);
  }
  const contract = loadArchContract(blueprintDir);
  if (!contract) { process.stderr.write('nessun contratto architecture nel blueprint: non applicabile\n'); process.exit(1); }
  const { graph, target, degraded: gdeg, detail: gdet } = buildModuleGraph(codeDir);
  if (gdeg) { process.stderr.write(`${gdet}: oracolo non eseguito\n`); process.exit(1); } // L-COL-006
  const dirGraph = prefixGraph(graph, target); // path madge -> spazio dir-relative del contratto
  const { degraded, detail, violations } = evaluateContract(dirGraph, contract);
  if (degraded) { process.stderr.write(`vacuity: ${detail}: oracolo non eseguito\n`); process.exit(1); } // L-COL-006
  const report = {
    oracle: 'arch',
    tool_version: 'arch-check@trueline (madge)',
    coverage: 'static-import-graph',
    coverage_note: 'Verifica statica delle regole forbidden fra strati sul grafo import (madge). Non vede dipendenze via reflection/DI dinamica. BUILD-only.',
    scanned_files: Object.keys(dirGraph).sort(),
    parse_warnings: [],
    findings: violations,
  };
  process.stdout.write(JSON.stringify(report));
  process.exit(0);
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] === __filename) {
  main();
}
