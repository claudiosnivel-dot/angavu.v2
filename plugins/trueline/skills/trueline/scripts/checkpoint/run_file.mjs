// run_file.mjs — esegue UN file di test (oracolo d'accettazione AC, AT-1 Fase A).
// `node --test {file}` via spawnSync ARRAY-ARGV (NIENTE shell:true), cwd=app, PATH+GO_BIN.
// Parsa il riassunto del test-runner per `testCount`/`passed`. Node ESM, solo built-in.
//
// NOTA sul formato dell'output (verificato su Node 25): quando `node --test` e'
// spawnato NON-TTY il reporter di default e' lo "spec" (righe `ℹ tests N`, `✔`/`✖`),
// non il TAP storico (`# tests N`, `ok`/`not ok`). Il parser gestisce ENTRAMBI i
// formati cosi' da restare robusto al reporter di default.
//
// FLOOR ANTI-VACUO: un file SENZA alcun `test()` viene comunque contato da node:test
// come 1 "test" implicito (il file stesso, mostrato col proprio PATH come nome). Quel
// wrapper implicito NON e' un test reale: lo sottraiamo, cosi' un file vuoto -> testCount 0.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join, delimiter } from 'node:path';

const GO_BIN = process.platform === 'win32'
  ? 'C:/Users/claud/go/bin'
  : '/c/Users/claud/go/bin';

// Escapa i metacaratteri regex.
function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Pattern del percorso relativo `file`: segmenti escapati, separatore `/` o `\`
// (node:test echeggia il path-arg normalizzato al separatore dell'OS).
function pathPattern(file) {
  return file.split(/[\\/]/).filter(Boolean).map(escapeRe).join('[\\\\/]');
}

// Costruisce argv dal template sostituendo {file}. v1: solo "node --test {file}".
// `node` viene mappato su process.execPath (stesso binario, deterministico; come checkpoint.mjs).
function buildArgv(template, file) {
  const parts = template.trim().split(/\s+/).map((p) => (p === '{file}' ? file : p));
  let cmd = parts[0];
  if (cmd === 'node') cmd = process.execPath;
  return { cmd, args: parts.slice(1) };
}

export function runTargetFile(appDir, file, template) {
  if (!existsSync(join(appDir, file))) {
    return { error: true, testCount: 0, passed: false, detail: `file assente: ${file}` };
  }
  const { cmd, args } = buildArgv(template, file);
  const env = { ...process.env, PATH: `${process.env.PATH || ''}${delimiter}${GO_BIN}` };
  // Se IL NOSTRO processo gira gia' sotto `node --test`, node:test imposta
  // NODE_TEST_CONTEXT: il figlio lo erediterebbe e SALTEREBBE l'esecuzione
  // ("run() is being called recursively"). Lo togliamo: il file target deve
  // essere eseguito come run di test INDIPENDENTE e pulito.
  delete env.NODE_TEST_CONTEXT;
  const res = spawnSync(cmd, args, { cwd: appDir, encoding: 'utf8', env, maxBuffer: 32 * 1024 * 1024 });
  if (res.error) return { error: true, testCount: 0, passed: false, detail: `spawn: ${res.error.message}` };

  const out = `${res.stdout || ''}\n${res.stderr || ''}`;
  const num = (re) => { const x = out.match(re); return x ? Number(x[1]) : null; };

  // Riassunto: spec usa "ℹ tests N"/"ℹ fail N", TAP usa "# tests N"/"# fail N".
  const summaryTests = num(/^[#ℹ]\s*tests\s+(\d+)/m) ?? 0;
  const failCount = num(/^[#ℹ]\s*fail\s+(\d+)/m) ?? (res.status === 0 ? 0 : 1);

  // Rileva il "test" implicito a livello di file (presente SOLO quando il file non ha
  // alcun test() reale): in quel caso node:test riporta il PATH del file come nome.
  // spec: `✔ <file> (Nms)` / `✖ ...`; TAP: `ok N - <file>` o `# Subtest: <file>`.
  // `<file>` = il path-arg relativo passato, eventualmente con un prefisso di dir.
  const pp = pathPattern(file);
  const implicitFileTest = (
    new RegExp(`^[✔✖]\\s+(?:.*[\\\\/])?${pp}\\s*\\(`, 'm').test(out) ||
    new RegExp(`^(?:ok|not ok)\\s+\\d+\\s+-\\s+(?:.*[\\\\/])?${pp}\\s*$`, 'm').test(out) ||
    new RegExp(`^#\\s*Subtest:\\s+(?:.*[\\\\/])?${pp}\\s*$`, 'm').test(out)
  );

  const testCount = Math.max(0, summaryTests - (implicitFileTest ? 1 : 0));
  const passed = res.status === 0 && failCount === 0;
  return {
    error: false,
    testCount,
    passed,
    detail: `exit=${res.status} tests=${testCount} fail=${failCount}`,
  };
}
