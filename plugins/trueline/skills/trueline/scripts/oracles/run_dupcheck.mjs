#!/usr/bin/env node
// run_dupcheck.mjs — wrapper jscpd (duplicazione verbatim). JSON nativo su stdout;
// il verdetto vive nel payload, l'exit del tool e' ignorato (03 §3). jscpd risolto
// da <dir>/node_modules (come knip) o via npx; assente -> exit 1 DICHIARATO, mai
// {duplicates:[]} nudo (L-COL-006).
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { tmpdir } from 'node:os';

const MIN_TOKENS_DEFAULT = 50;

// Su Windows npx e' npx.cmd: spawnSync('npx')->ENOENT, spawnSync('npx.cmd')->EINVAL
// (Node CVE-2024-27980 blocca .cmd/.bat senza shell:true; e shell:true mis-parsa il
// path con lo spazio "Trueline Skill"). Invochiamo npx via node sul suo cli JS.
function npxCli() {
  const nodeDir = dirname(process.execPath);
  const candidates = process.platform === 'win32'
    ? [join(nodeDir, 'node_modules', 'npm', 'bin', 'npx-cli.js')]
    : [join(nodeDir, '..', 'lib', 'node_modules', 'npm', 'bin', 'npx-cli.js')];
  return candidates.find((p) => existsSync(p)) || null;
}
function main() {
  const dir = process.argv[2];
  const minTokens = Number(process.argv[3] || MIN_TOKENS_DEFAULT);
  if (!dir || !existsSync(dir)) { console.error('uso: run_dupcheck.mjs <dir> [minTokens]'); process.exit(2); }
  const local = resolve(dir, 'node_modules', 'jscpd', 'bin', 'jscpd');
  const useLocal = existsSync(local);
  const out = mkdtempSync(join(tmpdir(), 'jscpd-'));
  // jscpd usa fast-glob: il target DEVE avere slash in avanti, altrimenti su Windows
  // il backslash di resolve() non matcha nulla -> nessun report -> falso "non eseguito".
  const target = resolve(dir).replace(/\\/g, '/');
  const NPX_CLI = useLocal ? null : npxCli();
  const head = useLocal ? [local] : (NPX_CLI ? [NPX_CLI, '--yes', 'jscpd@4'] : ['--yes', 'jscpd@4']);
  const args = head
    .concat([target, '--min-tokens', String(minTokens), '--reporters', 'json', '--silent',
      '--mode', 'strict', '--ignore', '**/*.test.ts,**/*.test.tsx,**/*.spec.ts,**/*.d.ts,**/node_modules/**',
      '--output', out]);
  // useLocal o npx-cli localizzato -> node su un file JS; solo se il cli npm non e'
  // localizzabile ripieghiamo sullo spawn diretto di 'npx' (best-effort).
  const bin = (useLocal || NPX_CLI) ? process.execPath : 'npx';
  const res = spawnSync(bin, args, { cwd: dir, encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 });
  const report = join(out, 'jscpd-report.json');
  if (!existsSync(report)) {
    rmSync(out, { recursive: true, force: true });
    console.error(`jscpd non eseguito (exit=${res.status}): ${(res.stderr || '').slice(-200)}`);
    process.exit(1); // NON un verde: oracolo non eseguito (L-COL-006)
  }
  const j = JSON.parse(readFileSync(report, 'utf8'));
  rmSync(out, { recursive: true, force: true });
  const duplicates = (j.duplicates || []).map((d) => ({
    firstFile: { name: d.firstFile.name, startLoc: d.firstFile.startLoc, endLoc: d.firstFile.endLoc },
    secondFile: { name: d.secondFile.name, startLoc: d.secondFile.startLoc, endLoc: d.secondFile.endLoc },
    lines: d.lines, tokens: d.tokens, fragment: d.fragment || '',
  }));
  process.stdout.write(JSON.stringify({ oracle: 'jscpd', minTokens, duplicates }));
  process.exit(0);
}
main();
