#!/usr/bin/env node
// validate_ecosystem.mjs — oracolo STRUTTURALE del manifest ecosistema (SP-0).
// Gemello di validate_blueprint: controlli manuali built-in, esito binario,
// niente ajv/dipendenze. Il "verde" e un FATTO di comando (L-COL-002).
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const REQUIRED = ['id','version','languages','backend','detect','triggers','oracles','floor','verified_set','coverage_policy'];
const COVERAGE_POLICIES = new Set(['declared']);

const nonEmptyStr = (v) => typeof v === 'string' && v.trim().length > 0;
const nonEmptyArr = (v) => Array.isArray(v) && v.length > 0;

export function validateEcosystem(m) {
  const errors = [];
  if (!m || typeof m !== 'object') return { ok: false, errors: ['manifest non è un oggetto'] };

  // (0) campi obbligatori presenti
  for (const k of REQUIRED) {
    const v = m[k];
    const present = (k === 'oracles' || k === 'detect') ? (v && typeof v === 'object')
      : (k === 'languages' || k === 'triggers' || k === 'floor') ? nonEmptyArr(v)
      : (k === 'verified_set') ? Array.isArray(v)
      : nonEmptyStr(v);
    if (!present) errors.push(`campo obbligatorio mancante/vuoto: ${k}`);
  }
  if (errors.length) return { ok: false, errors };

  const oracleKeys = new Set();
  for (const key of Object.keys(m.oracles)) for (const cat of key.split('|')) oracleKeys.add(cat.trim());

  // (1bis) vocabolario categorie: ogni chiave-categoria deve essere nell'enum
  // chiuso di finding.schema.json (A0). Un refuso (es. "injecton") non deve
  // passare silenzioso e far cadere la categoria dal gate a valle (L-COL-006).
  const CATEGORY_ENUM = new Set([
    'secret','rls','dead-code','injection','authz','crypto','dependency-vuln','config','misc',
    'duplication','architecture',
  ]);
  for (const c of oracleKeys) {
    if (!CATEGORY_ENUM.has(c)) errors.push(`categoria oracolo fuori vocabolario (finding.schema.json): "${c}"`);
  }

  // (5) ogni binding ha un tool non vuoto
  for (const [key, b] of Object.entries(m.oracles)) {
    if (!b || !nonEmptyStr(b.tool)) errors.push(`binding "${key}" senza tool`);
  }
  // (3) esattamente un binding con role: authz-surface
  const roles = Object.values(m.oracles).filter((b) => b && b.role === 'authz-surface');
  if (roles.length !== 1) errors.push(`atteso esattamente 1 binding role:authz-surface, trovati ${roles.length}`);
  // (2) ogni categoria del floor è legata a un oracolo
  for (const c of m.floor) if (!oracleKeys.has(c)) errors.push(`floor: categoria "${c}" non legata a un oracolo`);
  // (4) verified_set ⊆ categorie legate
  for (const c of m.verified_set) if (!oracleKeys.has(c)) errors.push(`verified_set: categoria "${c}" non legata a un oracolo`);
  // (6) coverage_policy nel set chiuso
  if (!COVERAGE_POLICIES.has(m.coverage_policy)) errors.push(`coverage_policy ignota: ${m.coverage_policy}`);
  // (7) SP-F6 Fase 0 — detect.deps_any OPZIONALE: se presente dev'essere un array non
  // vuoto di stringhe non vuote (nomi-dipendenza). Additivo: i manifest senza deps_any
  // non sono toccati (default-invariante).
  if (m.detect && 'deps_any' in m.detect) {
    const da = m.detect.deps_any;
    if (!nonEmptyArr(da) || !da.every(nonEmptyStr)) errors.push('detect.deps_any: atteso array non vuoto di stringhe');
  }

  return { ok: errors.length === 0, errors };
}

// CLI: node validate_ecosystem.mjs <path-a-ecosystem.json> [--json]
if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('validate_ecosystem.mjs')) {
  const args = process.argv.slice(2);
  const jsonMode = args.includes('--json');
  const p = args.find((a) => !a.startsWith('--'));
  if (!p || !existsSync(resolve(p))) { console.error('uso: validate_ecosystem.mjs <ecosystem.json>'); process.exit(2); }
  let m = null; try { m = JSON.parse(readFileSync(resolve(p), 'utf8')); } catch (e) { console.error(`JSON invalido: ${e.message}`); process.exit(1); }
  const r = validateEcosystem(m);
  if (jsonMode) console.log(JSON.stringify({ tool: 'validate_ecosystem', path: p, ...r }, null, 2));
  else { console.log(`validate_ecosystem — ${p}`); r.errors.forEach((e) => console.log(`  [FAIL] ${e}`)); console.log(r.ok ? 'RESULT: OK' : 'RESULT: FAIL'); }
  process.exit(r.ok ? 0 : 1);
}
