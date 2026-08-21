// authz_oracles.mjs — sorgente UNICA della mappa authz dichiarativa (A0).
// I 5 oracoli authz per-ecosistema condividono un contratto (CLI posizionale,
// JSON su stdout con {findings:[...]}, category 'authz', exit 0 anche con rilievi).
// Consumato dal checkpoint (control2Security) e dalla baseline del loop
// (collectFindings): il gate batch esegue lo STESSO oracolo del verify-fix loop
// (loop.mjs::rerunOracleFor), senza tabelle divergenti (L-COL-002/L-COL-029).
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { resolve, dirname, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';
import { normalize } from '../findings/normalize.mjs';

const ORACLES = dirname(fileURLToPath(import.meta.url));
const GO_BIN = process.platform === 'win32' ? 'C:/Users/claud/go/bin' : '/c/Users/claud/go/bin';

// manifest tool-name -> { script, normalizeKey }. normalizeKey = nome-oracolo atteso
// da `normalize` (= source_oracle.oracle del finding, = ramo di loop.mjs::rerunOracleFor).
export const AUTHZ_ORACLES = {
  firestore_rules_check:  { script: resolve(ORACLES, 'firestore_rules_check.mjs'),  normalizeKey: 'firestore-rules' },
  appwrite_perms_check:   { script: resolve(ORACLES, 'appwrite_perms_check.mjs'),   normalizeKey: 'appwrite-perms' },
  pocketbase_rules_check: { script: resolve(ORACLES, 'pocketbase_rules_check.mjs'), normalizeKey: 'pocketbase-rules' },
  hasura_metadata_check:  { script: resolve(ORACLES, 'hasura_metadata_check.mjs'),  normalizeKey: 'hasura-metadata' },
  appsync_auth_check:     { script: resolve(ORACLES, 'appsync_auth_check.mjs'),     normalizeKey: 'appsync-auth' },
};

export const AUTHZ_TOOL_NAMES = new Set(Object.keys(AUTHZ_ORACLES));

// dir di scansione dal binding (manifest.oracles.authz.scan), default ['.'].
export function authzScanTarget(dir, binding) {
  const scans = (binding && Array.isArray(binding.scan) && binding.scan.length) ? binding.scan : ['.'];
  const found = scans.find((s) => existsSync(resolve(dir, s)));
  return resolve(dir, found || '.');
}

// Esegue l'oracolo authz sullo scan target e normalizza (category 'authz').
// ran:false se lo script e' assente o non produce JSON (il chiamante decide se
// questo e' un floor-miss o un degrado onesto — L-COL-006). MAI un throw.
export function runAuthzOracle(toolName, dir, binding, runOpts) {
  const entry = AUTHZ_ORACLES[toolName];
  if (!entry) return { ok: false, ran: false, findings: [], detail: `tool authz ignoto: ${toolName}` };
  if (!existsSync(entry.script)) return { ok: false, ran: false, findings: [], detail: `oracolo assente: ${entry.script}` };
  const target = authzScanTarget(dir, binding);
  const env = { ...process.env, PATH: `${process.env.PATH || ''}${delimiter}${GO_BIN}` };
  const res = spawnSync(process.execPath, [entry.script, target], { cwd: dir, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (res.error) return { ok: false, ran: false, findings: [], detail: `spawn: ${res.error.message}` };
  const raw = (res.stdout || '').trim();
  if (!raw) return { ok: false, ran: false, findings: [], detail: `nessun JSON (exit=${res.status})` };
  let json; try { json = JSON.parse(raw); } catch (e) { return { ok: false, ran: true, findings: [], detail: `JSON invalido: ${e.message}` }; }
  let findings; try { findings = normalize(entry.normalizeKey, json, { ...runOpts, scope: 'working-tree' }); }
  catch (e) { return { ok: false, ran: true, findings: [], detail: `normalize(${entry.normalizeKey}): ${e.message}` }; }
  return { ok: true, ran: true, findings, detail: `${findings.length} finding` };
}
