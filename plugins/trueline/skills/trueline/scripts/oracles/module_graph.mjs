// module_graph.mjs — grafo import madge CONDIVISO (A2b). Estratto da run_cyclecheck.mjs
// (A2a) a comportamento invariato: madge costruisce il grafo (.ts-aware, dove
// dependency-cruiser è cieco); i consumatori (run_cyclecheck: cicli; arch_check:
// regole forbidden fra strati) lo usano. buildModuleGraph RITORNA lo stato (niente
// process.exit): il chiamante decide l'esito (L-COL-006: grafo vuoto = degradato,
// mai un verde). Node ESM, solo built-in.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';

// Su Windows npx è npx.cmd: spawnSync('npx')->ENOENT, spawnSync('npx.cmd')->EINVAL
// (CVE-2024-27980). Invochiamo npx via node sul suo cli JS.
export function npxCli() {
  const nodeDir = dirname(process.execPath);
  const candidates = process.platform === 'win32'
    ? [join(nodeDir, 'node_modules', 'npm', 'bin', 'npx-cli.js')]
    : [join(nodeDir, '..', 'lib', 'node_modules', 'npm', 'bin', 'npx-cli.js')];
  return candidates.find((p) => existsSync(p)) || null;
}

// Costruisce il grafo import con madge. Ritorna { graph, modules, degraded, detail }.
// degraded=true (grafo null/vuoto) = oracolo NON eseguito, MAI un verde (L-COL-006).
export function buildModuleGraph(dir) {
  const localBin = resolve(dir, 'node_modules', 'madge', 'bin', 'cli.js');
  const useLocal = existsSync(localBin);
  const target = existsSync(resolve(dir, 'src')) ? 'src' : '.';
  const NPX_CLI = useLocal ? null : npxCli();
  const head = useLocal ? [localBin] : (NPX_CLI ? [NPX_CLI, '--yes', 'madge'] : ['--yes', 'madge']);
  const argv = head.concat(['--json', '--extensions', 'ts,tsx,js,jsx,mjs,cjs', target]);
  const bin = (useLocal || NPX_CLI) ? process.execPath : 'npx';
  const res = spawnSync(bin, argv, { cwd: dir, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  const rawOut = (res.stdout || '').trim();
  if (!rawOut) return { graph: null, modules: [], degraded: true, detail: `madge non eseguito (exit=${res.status}): ${(res.stderr || '').slice(-200)}` };
  let graph;
  try { graph = JSON.parse(rawOut); } catch (e) { return { graph: null, modules: [], degraded: true, detail: `JSON invalido: ${e.message}` }; }
  const modules = Object.keys(graph || {});
  if (modules.length === 0) return { graph, modules, degraded: true, detail: 'madge ha costruito un grafo VUOTO (0 moduli): resolver/estensioni?', target };
  // `target` esposto (additivo; run_cyclecheck lo ignora -> comportamento invariato):
  // i path del grafo sono relativi al target ('src'|'.'), i consumatori che devono
  // matchare glob dir-relative (arch_check) lo usano per ri-prefissare.
  return { graph, modules, degraded: false, detail: `${modules.length} moduli`, target };
}

// Cicli elementari via DFS con rilevamento di back-edge sullo stack corrente.
export function findCycles(graph) {
  const cycles = [];
  const done = new Set();
  const stack = [];
  const onStack = new Set();
  function dfs(node) {
    stack.push(node); onStack.add(node);
    for (const dep of (graph[node] || [])) {
      if (onStack.has(dep)) {
        const idx = stack.indexOf(dep);
        if (idx >= 0) cycles.push(stack.slice(idx));
      } else if (!done.has(dep) && graph[dep] !== undefined) {
        dfs(dep);
      }
    }
    stack.pop(); onStack.delete(node); done.add(node);
  }
  for (const n of Object.keys(graph)) if (!done.has(n)) dfs(n);
  const uniq = new Map();
  for (const c of cycles) { const key = [...c].sort().join('|'); if (!uniq.has(key)) uniq.set(key, c); }
  return [...uniq.values()];
}
