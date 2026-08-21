#!/usr/bin/env node
// =============================================================================
// pocketbase_rules_check.mjs — Oracolo CUSTOM di Trueline per le API rules di
// PocketBase (analisi statica del file `pb_schema.json`).
//
// Gemello strutturale di firestore_rules_check.mjs (stesso contratto: CLI
// posizionale, raccolta file ricorsiva, makeFinding nativo per rilievo, report
// JSON nativo su stdout, exit 2 senza argomenti, errori di parse catturati come
// parse_warnings — MAI un throw — ed exit 0 anche con rilievi presenti, perche'
// il verdetto vive nel payload JSON, non nell'exit code). Il parsing qui e'
// piu' semplice del tokenizer `.rules`: lo schema PocketBase e' JSON, quindi
// usiamo JSON.parse.
//
// CONFINE DI COPERTURA (static-first, dichiarato esplicitamente):
//   - Vede SOLO il testo dei file `pb_schema.json` passati. NON valuta le rules
//     contro il motore di permessi di PocketBase, NON conosce i record reali,
//     NON esegue alcuna simulazione comportamentale. I controlli sono
//     strutturali sui rule field di ciascuna collection.
//
// MODELLO DEI RULE FIELD DI POCKETBASE (trappola load-bearing):
//   Ogni collection ha cinque rule field: listRule, viewRule, createRule,
//   updateRule, deleteRule. La semantica del VALORE e' controintuitiva:
//     - ""   (stringa VUOTA esatta) = regola PUBBLICA, accesso incondizionato
//              a chiunque (anche non autenticato).  -> FLOOR POCKETBASE001.
//     - null = regola BLOCCATA (admin/superuser-only) = SICURA. -> NESSUN
//              finding. ⚠ Trattare null come "missing -> public" e' ESATTAMENTE
//              il contrario della realta'.
//     - field ASSENTE = NESSUN finding (non possiamo affermare nulla; in
//              pratica equivale a regola non-pubblica di default).
//     - stringa NON vuota = espressione di regola (es. "@request.auth.id != ''")
//              -> fuori dal floor deterministico.
//   Solo il valore "" (stringa vuota esatta) e' il floor.
//
// OUTPUT: JSON NATIVO (lista di rilievi), NON normalizzato (la normalizzazione
//   nel finding model e' compito di `normalize`). Stampa su stdout.
//
// USO: node trueline/scripts/oracles/pocketbase_rules_check.mjs <dir-o-file.json> [...]
//   Gli argomenti sono directory (scansione ricorsiva di file `pb_schema.json`)
//   oppure file `.json` (tipicamente `pb_schema.json`).
// =============================================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep, posix, basename } from 'node:path';

const ORACLE = 'pocketbase-rules';
const TOOL_VERSION = 'pocketbase-rules-check/1.0.0';

// I cinque rule field di una collection PocketBase, in ordine canonico.
const RULE_FIELDS = [
  'listRule',
  'viewRule',
  'createRule',
  'updateRule',
  'deleteRule',
];

// Mappa rule field -> verbo dell'operazione (per messaggi leggibili).
const RULE_VERB = {
  listRule: 'list',
  viewRule: 'view',
  createRule: 'create',
  updateRule: 'update',
  deleteRule: 'delete',
};

// -----------------------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    process.stderr.write(
      'uso: node pocketbase_rules_check.mjs <dir-o-file.json> [...]\n'
    );
    process.exit(2);
  }

  const files = collectSchemaFiles(args);
  const findings = [];
  const scannedFiles = [];
  const parseWarnings = [];

  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    scannedFiles.push(file);
    analyzeFile(file, text, findings, parseWarnings);
  }

  const report = {
    oracle: ORACLE,
    tool_version: TOOL_VERSION,
    coverage: 'static-schema',
    coverage_note:
      'Analisi statica del solo testo dei file pb_schema.json. Non valuta le ' +
      'rules contro il motore di permessi di PocketBase, non conosce i record ' +
      'ne esegue simulazioni comportamentali: i controlli sono strutturali sui ' +
      'rule field (listRule/viewRule/createRule/updateRule/deleteRule). ' +
      'Semantica del valore: "" = pubblico (floor), null = bloccato/sicuro ' +
      '(nessun finding), field assente = nessun finding.',
    scanned_files: scannedFiles.map(toPosixRel),
    parse_warnings: parseWarnings,
    findings,
  };

  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

// -----------------------------------------------------------------------------
// Analisi di un singolo file pb_schema.json
// -----------------------------------------------------------------------------
function analyzeFile(file, text, findings, parseWarnings) {
  const relPath = toPosixRel(file);

  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    // Il parser NON deve mai propagare: qualunque imprevisto diventa un warning.
    parseWarnings.push({
      file: relPath,
      line: 1,
      statement: 'pb_schema',
      message: `JSON non valido: ${firstLine(e.message)}`,
    });
    return;
  }

  const collections = extractCollections(data);
  if (collections == null) {
    parseWarnings.push({
      file: relPath,
      line: 1,
      statement: 'pb_schema',
      message:
        'schema PocketBase non riconosciuto: atteso un array di collections ' +
        'oppure un oggetto { collections: [...] }.',
    });
    return;
  }

  // Indice best-effort delle righe dove compare un rule field con valore "".
  // Le righe sono consumate in ordine di scansione testuale (che coincide con
  // l'ordine d'array delle collection in un pb_schema.json ben formato).
  const lineIndex = buildEmptyRuleLineIndex(text);

  collections.forEach((coll, idx) => {
    if (coll == null || typeof coll !== 'object' || Array.isArray(coll)) {
      return; // entry non-oggetto: non e' una collection, la ignoriamo
    }
    const collName = collectionName(coll, idx);

    for (const ruleField of RULE_FIELDS) {
      // field ASSENTE -> NESSUN finding (non affermiamo nulla).
      if (!Object.prototype.hasOwnProperty.call(coll, ruleField)) continue;

      const val = coll[ruleField];

      // ⚠ CRITICO: null = LOCKED/admin-only = SICURO -> NESSUN finding.
      if (val === null) continue;

      // [POCKETBASE001] PUBLIC_RULE (HIGH, FLOOR, deterministico): SOLO il
      // valore "" (stringa vuota ESATTA) e' accesso pubblico incondizionato.
      if (val === '') {
        const startLine = nextLineFor(lineIndex, ruleField);
        const matchPath = `${collName}.${ruleField}`;
        const snippet = `${ruleField}: ""`;
        const verb = RULE_VERB[ruleField] || ruleField;
        findings.push(
          makeFinding({
            controlId: 'POCKETBASE001_PUBLIC_RULE',
            severity: 'HIGH',
            matchPath,
            ruleField,
            collection: collName,
            file: relPath,
            startLine,
            snippet,
            message:
              `Il rule field "${ruleField}" della collection "${collName}" e' ` +
              `la stringa vuota (""), che in PocketBase concede accesso ` +
              `PUBBLICO incondizionato: chiunque (anche non autenticato) puo' ` +
              `eseguire l'operazione "${verb}" su questi record. (Nota: il ` +
              `valore null indicherebbe invece una regola bloccata/admin-only, ` +
              `quindi sicura; qui il valore e' "", non null.)`,
          })
        );
      }
    }
  });
}

// -----------------------------------------------------------------------------
// HELPER di estrazione/valutazione
// -----------------------------------------------------------------------------

// Ricava l'array di collection dalle due forme accettate:
//   - array di collection nudo:  [ {...}, {...} ]
//   - oggetto con campo collections:  { collections: [ {...} ] }
// Qualunque altra forma -> null (segnalata come parse_warning dal chiamante).
function extractCollections(data) {
  if (Array.isArray(data)) return data;
  if (data && typeof data === 'object' && Array.isArray(data.collections)) {
    return data.collections;
  }
  return null;
}

// Nome leggibile della collection: name, poi id, poi un placeholder posizionale.
function collectionName(coll, idx) {
  if (typeof coll.name === 'string' && coll.name.length > 0) return coll.name;
  if (typeof coll.id === 'string' && coll.id.length > 0) return coll.id;
  return `collection[${idx}]`;
}

// Costruisce una mappa ruleField -> coda di numeri di riga (1-based) in cui
// compare un'assegnazione `"<ruleField>": ""`. Best-effort: serve solo a
// popolare location.start_line; se la coda si esaurisce, la riga resta null.
function buildEmptyRuleLineIndex(text) {
  const idx = new Map();
  const re =
    /"(listRule|viewRule|createRule|updateRule|deleteRule)"\s*:\s*""/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const field = m[1];
    const line = lineAt(text, m.index);
    if (!idx.has(field)) idx.set(field, []);
    idx.get(field).push(line);
  }
  return idx;
}

function nextLineFor(lineIndex, ruleField) {
  const queue = lineIndex.get(ruleField);
  if (queue && queue.length > 0) return queue.shift();
  return null;
}

// Numero di riga 1-based dell'offset di carattere `offset` in `text`.
function lineAt(text, offset) {
  let line = 1;
  const end = Math.min(offset, text.length);
  for (let i = 0; i < end; i++) {
    if (text[i] === '\n') line++;
  }
  return line;
}

// -----------------------------------------------------------------------------
// Costruzione del rilievo NATIVO (non normalizzato).
// `match_path` e `rule_field` sono i campi portatori-di-simbolo che il
// normalizer leggera': nomi-chiave esatti.
// -----------------------------------------------------------------------------
function makeFinding(o) {
  const f = {
    control_id: o.controlId,
    severity: o.severity,
    category: 'authz',
    match_path: o.matchPath,
    rule_field: o.ruleField,
    location: {
      file: o.file,
      collection: o.collection,
      rule_field: o.ruleField,
      start_line: o.startLine,
      end_line: o.startLine,
      statement: o.snippet,
    },
    snippet: o.snippet,
    message: o.message,
  };
  if (o.heuristic) f.heuristic = true;
  return f;
}

// -----------------------------------------------------------------------------
// Utilita' varie
// -----------------------------------------------------------------------------
function firstLine(s) {
  return String(s).split('\n')[0];
}

// -----------------------------------------------------------------------------
// Raccolta file pb_schema.json dagli argomenti (dir ricorsiva o file).
// -----------------------------------------------------------------------------
function collectSchemaFiles(args) {
  const out = [];
  for (const a of args) {
    let st;
    try {
      st = statSync(a);
    } catch {
      process.stderr.write(`avviso: percorso inesistente, ignorato: ${a}\n`);
      continue;
    }
    if (st.isDirectory()) {
      walk(a, out);
    } else if (st.isFile() && a.toLowerCase().endsWith('.json')) {
      out.push(a);
    } else if (st.isFile()) {
      process.stderr.write(`avviso: non e' un file .json, ignorato: ${a}\n`);
    }
  }
  // ordinamento deterministico
  out.sort();
  return out;
}

function walk(dir, out) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    process.stderr.write(`avviso: directory illeggibile, ignorata: ${dir}\n`);
    return;
  }
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
    } else if (entry.isFile() && basename(entry.name) === 'pb_schema.json') {
      out.push(full);
    }
  }
}

function toPosixRel(file) {
  const rel = relative(process.cwd(), file);
  return rel.split(sep).join(posix.sep);
}

main();
