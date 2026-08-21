#!/usr/bin/env node
// =============================================================================
// appwrite_perms_check.mjs — Oracolo CUSTOM di Trueline per le permission
// dichiarative di Appwrite (analisi statica del file `appwrite.json`).
//
// Gemello strutturale di firestore_rules_check.mjs (stesso contratto: CLI
// posizionale, raccolta file ricorsiva, makeFinding nativo per rilievo, report
// JSON nativo su stdout, exit 2 senza argomenti, errori di parse catturati come
// parse_warnings — MAI un throw — ed exit 0 anche con rilievi presenti, perche'
// il verdetto vive nel payload JSON, non nell'exit code).
//
// USO DEL PARSER: a differenza di `.rules` (tokenizer dedicato), `appwrite.json`
//   e' JSON puro, quindi il parsing e' `JSON.parse`. Iteriamo `config.collections[]`
//   (ognuna con `$id`/`name`, `documentSecurity` booleano e `$permissions[]` di
//   stringhe nella forma `read("any")`, `create("users")`, ...). Per robustezza
//   verso il layout del CLI Appwrite recente raccogliamo anche le collection
//   annidate sotto `config.databases[].collections[]`. Le righe nel sorgente
//   sono ricostruite con una scansione testuale ausiliaria (JSON.parse perde le
//   posizioni): la location e' informativa.
//
// CONFINE DI COPERTURA (static-first, dichiarato esplicitamente):
//   - Vede SOLO il testo del file `appwrite.json`. NON interroga l'istanza
//     Appwrite, NON valuta le permission a livello-documento ne i ruoli/team
//     custom, NON simula alcun comportamento runtime. Il controllo e' token/
//     strutturale sul ruolo speciale `any` nelle permission a livello-collection.
//
// OUTPUT: JSON NATIVO (lista di rilievi), NON normalizzato (la normalizzazione
//   nel finding model e' compito di `normalize`). Stampa su stdout.
//
// USO: node trueline/scripts/oracles/appwrite_perms_check.mjs <dir-o-appwrite.json> [...]
//   Gli argomenti sono directory (scansione ricorsiva dei file `appwrite.json`)
//   oppure file (basename `appwrite.json`, o qualunque `.json` passato esplicito).
// =============================================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep, posix, basename } from 'node:path';

const ORACLE = 'appwrite-perms';
const TOOL_VERSION = 'appwrite-perms-check/1.0.0';

// Permission concessa al ruolo speciale `any` in uno scope mutante o di lettura:
// e' accesso PUBBLICO incondizionato (CWE-862, broken access control). La regex
// gira sul valore GIA' parsato della stringa permission (es. `read("any")`).
const PUBLIC_ANY_RE =
  /\b(read|create|update|delete|write)\s*\(\s*["']any["']\s*\)/;

// Variante della regex sopra che gira sul testo GREZZO del file JSON, dove le
// virgolette interne sono escapate (`read(\"any\")`): il `\\?` opzionale assorbe
// il backslash di escape. Serve solo a ricostruire la riga della permission.
const PUBLIC_ANY_RAW_RE =
  /\b(?:read|create|update|delete|write)\s*\(\s*\\?["']any\\?["']\s*\)/g;

// -----------------------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    process.stderr.write(
      'uso: node appwrite_perms_check.mjs <dir-o-appwrite.json> [...]\n'
    );
    process.exit(2);
  }

  const files = collectAppwriteFiles(args);
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
    coverage: 'static-appwrite',
    coverage_note:
      'Analisi statica del solo file appwrite.json (JSON.parse). Itera ' +
      'config.collections[] e ne valuta i $permissions a livello-collection: ' +
      "segnala come pubblica ogni permission concessa al ruolo speciale 'any'. " +
      "Non interroga l'istanza Appwrite, non valuta le permission a livello-" +
      'documento ne i ruoli/team custom: il controllo e\' token/strutturale ' +
      "sul ruolo 'any'.",
    scanned_files: scannedFiles.map(toPosixRel),
    parse_warnings: parseWarnings,
    findings,
  };

  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

// -----------------------------------------------------------------------------
// Analisi di un singolo file appwrite.json
// -----------------------------------------------------------------------------
function analyzeFile(file, text, findings, parseWarnings) {
  const relPath = toPosixRel(file);

  let config;
  try {
    config = JSON.parse(text);
  } catch (e) {
    // JSON malformato: parse_warnings, MAI un throw.
    parseWarnings.push({
      file: relPath,
      line: 1,
      statement: 'appwrite.json',
      message: `JSON malformato, file ignorato: ${firstLine(e.message)}`,
    });
    return;
  }

  // Qualunque imprevisto strutturale diventa un warning, mai un throw.
  try {
    const collections = gatherCollections(config);
    // Localizzatore di riga: scorre le occorrenze grezze di una permission `any`
    // in ordine testuale, in parallelo all'iterazione (array → ordine preservato).
    const rawLines = collectRawAnyLines(text);
    let rawPtr = 0;

    collections.forEach((coll, idx) => {
      const collectionId = collectionIdOf(coll, idx);
      const perms = permissionsOf(coll);
      for (const perm of perms) {
        if (typeof perm !== 'string') continue;
        if (!PUBLIC_ANY_RE.test(perm)) continue;

        // [APPWRITE001] PUBLIC_PERMISSION (HIGH, FLOOR, deterministico):
        // permission concessa al ruolo `any` → accesso pubblico incondizionato.
        const line = rawPtr < rawLines.length ? rawLines[rawPtr] : 1;
        rawPtr++;
        const matchPath = `${collectionId}#${perm}`;
        findings.push(
          makeFinding({
            controlId: 'APPWRITE001_PUBLIC_PERMISSION',
            severity: 'HIGH',
            matchPath,
            collection: collectionId,
            permission: perm,
            file: relPath,
            startLine: line,
            endLine: line,
            statement: `${collectionId}: ${perm}`,
            snippet: snippetOf(`${collectionId}: ${perm}`),
            message:
              `La collection "${collectionId}" concede la permission ` +
              `"${perm}" al ruolo speciale "any": chiunque (anche non ` +
              `autenticato) puo' eseguire questa operazione su tutti i ` +
              `documenti della collection. Manca un controllo di ` +
              `autorizzazione (accesso pubblico incondizionato, CWE-862).`,
          })
        );
      }
    });
  } catch (e) {
    parseWarnings.push({
      file: relPath,
      line: 1,
      statement: 'appwrite.json',
      message: `struttura inattesa, analisi interrotta: ${firstLine(e.message)}`,
    });
  }
}

// -----------------------------------------------------------------------------
// HELPER strutturali
// -----------------------------------------------------------------------------

// Raccoglie le collection da `config.collections[]` (forma dichiarata nello spec)
// e, per robustezza verso il CLI Appwrite recente, anche da
// `config.databases[].collections[]`. Difensivo: ignora forme non-array.
function gatherCollections(config) {
  const out = [];
  if (config && Array.isArray(config.collections)) {
    for (const c of config.collections) out.push(c);
  }
  if (config && Array.isArray(config.databases)) {
    for (const db of config.databases) {
      if (db && Array.isArray(db.collections)) {
        for (const c of db.collections) out.push(c);
      }
    }
  }
  return out;
}

// Identificatore portatore-di-simbolo della collection: `$id`, poi `name`,
// infine l'indice posizionale come ultima risorsa.
function collectionIdOf(coll, idx) {
  if (coll && typeof coll === 'object') {
    if (typeof coll.$id === 'string' && coll.$id.length > 0) return coll.$id;
    if (typeof coll.name === 'string' && coll.name.length > 0) return coll.name;
  }
  return `collection[${idx}]`;
}

// Le permission a livello-collection. Appwrite usa `$permissions`; accettiamo
// `permissions` come fallback difensivo. `null`/assente → lista vuota (0 finding).
function permissionsOf(coll) {
  if (!coll || typeof coll !== 'object') return [];
  if (Array.isArray(coll.$permissions)) return coll.$permissions;
  if (Array.isArray(coll.permissions)) return coll.permissions;
  return [];
}

// Scansione testuale ausiliaria: le righe (1-based) di ogni occorrenza grezza di
// una permission `any`, in ordine testuale. JSON.parse perde le posizioni, quindi
// ricostruiamo la riga qui; gli array JSON preservano l'ordine, percio' l'ordine
// testuale combacia con l'ordine d'iterazione delle permission.
function collectRawAnyLines(text) {
  const lines = [];
  PUBLIC_ANY_RAW_RE.lastIndex = 0;
  let m;
  while ((m = PUBLIC_ANY_RAW_RE.exec(text)) !== null) {
    lines.push(indexToLine(text, m.index));
    // Difesa anti-loop su eventuale match a larghezza zero (non dovrebbe capitare).
    if (m.index === PUBLIC_ANY_RAW_RE.lastIndex) PUBLIC_ANY_RAW_RE.lastIndex++;
  }
  return lines;
}

function indexToLine(text, idx) {
  let line = 1;
  for (let i = 0; i < idx && i < text.length; i++) {
    if (text[i] === '\n') line++;
  }
  return line;
}

// -----------------------------------------------------------------------------
// Utilita' varie
// -----------------------------------------------------------------------------
function snippetOf(body, maxLen = 240) {
  const oneLine = String(body).replace(/\s+/g, ' ').trim();
  return oneLine.length > maxLen ? oneLine.slice(0, maxLen) + ' ...' : oneLine;
}

function firstLine(s) {
  return String(s).split('\n')[0];
}

function makeFinding(o) {
  // Rilievo NATIVO (non normalizzato). `match_path` e' il campo portatore-di-
  // simbolo che il normalizer leggera' (fingerprint): nome-chiave esatto.
  const f = {
    control_id: o.controlId,
    severity: o.severity,
    category: 'authz',
    match_path: o.matchPath,
    collection: o.collection,
    permission: o.permission,
    location: {
      file: o.file,
      start_line: o.startLine,
      end_line: o.endLine,
      statement: o.statement,
    },
    snippet: o.snippet,
    message: o.message,
  };
  if (o.heuristic) f.heuristic = true;
  return f;
}

// -----------------------------------------------------------------------------
// Raccolta file appwrite.json dagli argomenti (dir ricorsiva o file).
// -----------------------------------------------------------------------------
function collectAppwriteFiles(args) {
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
    } else if (st.isFile()) {
      // File passato esplicitamente: accettiamo il basename canonico oppure
      // qualunque .json (cosi' una fixture rinominata resta utilizzabile).
      const base = basename(a).toLowerCase();
      if (base === 'appwrite.json' || base.endsWith('.json')) {
        out.push(a);
      } else {
        process.stderr.write(
          `avviso: non e' un file appwrite.json/.json, ignorato: ${a}\n`
        );
      }
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
    } else if (entry.isFile() && entry.name.toLowerCase() === 'appwrite.json') {
      out.push(full);
    }
  }
}

function toPosixRel(file) {
  const rel = relative(process.cwd(), file);
  return rel.split(sep).join(posix.sep);
}

main();
