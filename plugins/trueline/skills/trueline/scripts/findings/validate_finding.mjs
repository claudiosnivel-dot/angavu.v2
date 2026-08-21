// validate_finding.mjs — valida un finding (o un array di finding) contro
// finding.schema.json (04, finding model).
//
// Usa ajv se presente in node_modules; altrimenti ricade su un validator
// strutturale fatto a mano che copre il sottoinsieme di JSON Schema usato dallo
// schema del finding: type, enum, required, additionalProperties, properties,
// pattern, minLength, minimum, integer. Espone validateFinding/validateMany e
// una CLI: "node validate_finding.mjs <file.json>".

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { createRequire } from 'node:module';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SCHEMA_PATH = resolve(__dirname, 'finding.schema.json');

/** Carica lo schema del finding dal disco. */
function loadSchema() {
  return JSON.parse(readFileSync(SCHEMA_PATH, 'utf8'));
}

// --- Tentativo ajv (se installato) -----------------------------------------

let ajvValidator = null;
function tryBuildAjvValidator(schema) {
  try {
    const require = createRequire(import.meta.url);
    const Ajv = require('ajv');
    // Lo schema usa draft 2020-12; ajv classico copre comunque
    // type/enum/required/pattern/properties/additionalProperties che ci servono.
    const ajv = new Ajv({ allErrors: true, strict: false });
    return ajv.compile(schema);
  } catch {
    return null; // ajv assente -> fallback strutturale
  }
}

// --- Validator strutturale (fallback, nessuna dipendenza) -------------------

function jsType(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (Number.isInteger(value)) return 'integer';
  if (typeof value === 'number') return 'number';
  return typeof value; // string | boolean | object | undefined
}

function typeMatches(value, expected) {
  const types = Array.isArray(expected) ? expected : [expected];
  const actual = jsType(value);
  for (const t of types) {
    if (t === 'number' && (actual === 'number' || actual === 'integer')) return true;
    if (t === 'integer' && actual === 'integer') return true;
    if (t === actual) return true;
  }
  return false;
}

/**
 * Valida `value` contro `schema` (sottoinsieme di JSON Schema).
 * Accumula errori in `errors` con il path corrente.
 */
function validateAgainst(value, schema, path, errors) {
  if (schema.type !== undefined && !typeMatches(value, schema.type)) {
    errors.push(`${path || '(root)'}: tipo atteso ${JSON.stringify(schema.type)}, trovato ${jsType(value)}`);
    return; // se il tipo e sbagliato, gli altri vincoli sono rumore
  }

  if (schema.enum !== undefined && !schema.enum.includes(value)) {
    errors.push(`${path || '(root)'}: valore ${JSON.stringify(value)} fuori dall'enum ${JSON.stringify(schema.enum)}`);
  }

  if (typeof value === 'string') {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${path}: stringa piu corta di minLength=${schema.minLength}`);
    }
    if (schema.pattern !== undefined && !new RegExp(schema.pattern).test(value)) {
      errors.push(`${path}: stringa ${JSON.stringify(value)} non rispetta il pattern ${schema.pattern}`);
    }
  }

  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${path}: ${value} < minimum=${schema.minimum}`);
    }
  }

  if (schema.type === 'object' || (jsType(value) === 'object' && schema.properties)) {
    if (jsType(value) !== 'object') return; // gia segnalato sopra se type=object
    const props = schema.properties || {};

    for (const req of schema.required || []) {
      if (!(req in value)) {
        errors.push(`${path ? path + '.' : ''}${req}: campo obbligatorio mancante`);
      }
    }

    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) {
        if (!(key in props)) {
          errors.push(`${path ? path + '.' : ''}${key}: proprieta non ammessa (additionalProperties=false)`);
        }
      }
    }

    for (const [key, subSchema] of Object.entries(props)) {
      if (key in value) {
        validateAgainst(value[key], subSchema, `${path ? path + '.' : ''}${key}`, errors);
      }
    }
  }
}

function structuralValidate(value, schema) {
  const errors = [];
  validateAgainst(value, schema, '', errors);
  return { ok: errors.length === 0, errors };
}

// --- API pubblica -----------------------------------------------------------

/**
 * Valida un singolo finding. Ritorna { ok, errors }.
 */
export function validateFinding(value, schema = loadSchema()) {
  if (ajvValidator === null) {
    ajvValidator = tryBuildAjvValidator(schema) || false;
  }
  if (ajvValidator) {
    const ok = ajvValidator(value);
    const errors = ok
      ? []
      : (ajvValidator.errors || []).map((e) => `${e.instancePath || '(root)'} ${e.message}`);
    return { ok, errors };
  }
  return structuralValidate(value, schema);
}

/**
 * Valida un array di finding. Ritorna { ok, errors, count }.
 */
export function validateMany(values, schema = loadSchema()) {
  const errors = [];
  values.forEach((v, i) => {
    const res = validateFinding(v, schema);
    if (!res.ok) {
      for (const e of res.errors) errors.push(`[${i}] ${e}`);
    }
  });
  return { ok: errors.length === 0, errors, count: values.length };
}

/**
 * Valida un valore che puo essere un finding singolo o un array di finding.
 */
export function validate(value, schema = loadSchema()) {
  if (Array.isArray(value)) return validateMany(value, schema);
  return validateFinding(value, schema);
}

// --- CLI --------------------------------------------------------------------

function main(argv) {
  const file = argv[2];
  if (!file) {
    process.stderr.write('uso: node validate_finding.mjs <file.json>\n');
    return 2;
  }
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(resolve(file), 'utf8'));
  } catch (err) {
    process.stderr.write(`impossibile leggere/parsare ${file}: ${err.message}\n`);
    return 2;
  }
  const res = validate(parsed);
  if (res.ok) {
    const n = Array.isArray(parsed) ? `${res.count} finding` : '1 finding';
    process.stdout.write(`VALIDO: ${n} conforme/i allo schema. ok:true\n`);
    return 0;
  }
  process.stderr.write('INVALIDO. ok:false\n');
  for (const e of res.errors) process.stderr.write(`  - ${e}\n`);
  return 1;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] === __filename) {
  process.exit(main(process.argv));
}
