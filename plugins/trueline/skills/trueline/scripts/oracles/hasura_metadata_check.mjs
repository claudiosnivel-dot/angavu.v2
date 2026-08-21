#!/usr/bin/env node
// =============================================================================
// hasura_metadata_check.mjs — Oracolo CUSTOM di Trueline per i permessi
// dichiarativi di Hasura (analisi statica della metadata: `metadata/**/*.yaml`,
// `config.yaml`, o un `metadata.json`/`tables.json`).
//
// Gemello strutturale di firestore_rules_check.mjs (stesso contratto: CLI
// posizionale, raccolta file ricorsiva, makeFinding nativo per rilievo, report
// JSON nativo su stdout, exit 2 senza argomenti, errori di parse catturati come
// parse_warnings — MAI un throw — ed exit 0 anche con rilievi presenti, perche'
// il verdetto vive nel payload JSON, non nell'exit code).
//
// USO DEL PARSER (YAML DEP-FREE, SUBSET):
//   La metadata Hasura e' YAML. Non importiamo nessuna dipendenza: scriviamo un
//   parser del SOTTOINSIEME effettivamente usato dalla metadata Hasura — mappe
//   annidate per indentazione a spazi, sequenze `- `, scalari quoted/unquoted,
//   flow vuoto/inline `{}`/`[]`/`{k: v}`. NON supporta anchor/alias, flow
//   multilinea, blocchi `|`/`>`. I file `.json` (es. `metadata.json`) usano
//   `JSON.parse` come fallback diretto (JSON e' un caso degenere di YAML).
//
// STRUTTURA HASURA:
//   ogni tabella ha select_permissions / insert_permissions /
//   update_permissions / delete_permissions, ognuna una lista di
//   { role, permission: { filter: {...}, columns: [...] } }. Le table-entry
//   compaiono come mappa singola (un file per tabella), come sequenza
//   (`tables.yaml`) o annidate sotto `sources[].tables[]` (metadata.json).
//
// CONFINE DI COPERTURA (static-first, dichiarato esplicitamente):
//   - Vede SOLO il testo dei file di metadata passati. NON interroga l'istanza
//     Hasura, NON valuta i permessi contro lo schema reale ne le custom claim
//     della sessione, NON simula alcun comportamento runtime. Il controllo e'
//     strutturale sul ruolo (anonymous/public/*) e sul filtro di riga vuoto.
//
// OUTPUT: JSON NATIVO (lista di rilievi), NON normalizzato (la normalizzazione
//   nel finding model e' compito di `normalize`). Stampa su stdout.
//
// USO: node trueline/scripts/oracles/hasura_metadata_check.mjs <dir-o-file> [...]
//   Gli argomenti sono directory (scansione ricorsiva di `*.yaml`/`*.yml` e dei
//   `metadata.json`/`tables.json`) oppure file `.yaml`/`.yml`/`.json`.
// =============================================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep, posix, basename, extname } from 'node:path';

const ORACLE = 'hasura-metadata';
const TOOL_VERSION = 'hasura-metadata-check/1.0.0';

// I quattro gruppi di permessi di una tabella Hasura.
const PERM_KEYS = [
  'select_permissions',
  'insert_permissions',
  'update_permissions',
  'delete_permissions',
];

// Ruoli che rappresentano accesso pubblico/non autenticato. `anonymous` e' il
// ruolo di default per le richieste senza JWT; `public` e' una convenzione
// diffusa; `*` e' il wildcard. Confronto esatto + fallback case-insensitive.
const PUBLIC_ROLES = new Set(['anonymous', 'public', '*']);

// WeakMap nodo-parsato -> numero di riga 1-based della sua prima riga sorgente.
// Popolata dal parser YAML per dare una location informativa ai rilievi.
const nodeLines = new WeakMap();

// -----------------------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    process.stderr.write(
      'uso: node hasura_metadata_check.mjs <dir-o-file> [...]\n'
    );
    process.exit(2);
  }

  const files = collectMetadataFiles(args);
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
    coverage: 'static-hasura',
    coverage_note:
      'Analisi statica della sola metadata Hasura (YAML subset dep-free, o ' +
      'JSON.parse per i .json). Itera le *_permissions di ogni tabella e segnala ' +
      'come pubblica ogni permission con role in {anonymous,public,*} e filtro di ' +
      'riga vuoto ({}). Non interroga l\'istanza Hasura, non valuta i permessi ' +
      'contro lo schema reale ne le custom claim: il controllo e\' strutturale ' +
      'sul ruolo e sul filtro vuoto.',
    scanned_files: scannedFiles.map(toPosixRel),
    parse_warnings: parseWarnings,
    findings,
  };

  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

// -----------------------------------------------------------------------------
// Analisi di un singolo file di metadata
// -----------------------------------------------------------------------------
function analyzeFile(file, text, findings, parseWarnings) {
  const relPath = toPosixRel(file);
  const isJson = extname(file).toLowerCase() === '.json';

  let doc;
  try {
    doc = isJson ? JSON.parse(text) : parseYaml(text);
  } catch (e) {
    // Il parser NON deve mai propagare: qualunque imprevisto diventa un warning.
    parseWarnings.push({
      file: relPath,
      line: 1,
      statement: 'metadata',
      message: `${isJson ? 'JSON' : 'YAML'} non parsabile, file ignorato: ${firstLine(e.message)}`,
    });
    return;
  }

  // Qualunque imprevisto strutturale diventa un warning, mai un throw.
  try {
    const entries = [];
    collectTableEntries(doc, entries);
    entries.forEach((entry, idx) => {
      evaluateTableEntry(entry, idx, relPath, findings);
    });
  } catch (e) {
    parseWarnings.push({
      file: relPath,
      line: 1,
      statement: 'metadata',
      message: `struttura inattesa, analisi interrotta: ${firstLine(e.message)}`,
    });
  }
}

// -----------------------------------------------------------------------------
// CONTROLLO deterministico (FLOOR) per una table-entry
// -----------------------------------------------------------------------------
function evaluateTableEntry(entry, idx, relPath, findings) {
  if (!entry || typeof entry !== 'object') return;
  const tableName = tableNameOf(entry, idx);

  for (const permKey of PERM_KEYS) {
    const perms = entry[permKey];
    if (!Array.isArray(perms)) continue;
    const permType = permKey.replace(/_permissions$/, ''); // select/insert/...

    for (const perm of perms) {
      if (!perm || typeof perm !== 'object') continue;
      const role = perm.role;
      if (typeof role !== 'string') continue;
      if (!isPublicRole(role)) continue;

      const permission = perm.permission;
      const filter = permission && typeof permission === 'object'
        ? permission.filter
        : undefined;

      // [HASURA001] PUBLIC_PERMISSION (HIGH, FLOOR, deterministico): role
      // pubblico (anonymous/public/*) E filtro di riga vuoto ({}) = nessun
      // vincolo di riga = accesso pubblico incondizionato a tutte le righe.
      if (!isEmptyFilter(filter)) continue;

      const matchPath = `${tableName}.${permType}.${role}`;
      const startLine =
        nodeLines.get(perm) ?? nodeLines.get(entry) ?? 1;
      findings.push(
        makeFinding({
          controlId: 'HASURA001_PUBLIC_PERMISSION',
          severity: 'HIGH',
          matchPath,
          table: tableName,
          permType,
          role,
          file: relPath,
          startLine,
          statement: `${tableName}.${permType}: { role: ${role}, filter: {} }`,
          snippet: snippetOf(
            `${tableName} ${permType}_permissions: role=${role}, filter={}`
          ),
          message:
            `La ${permType}_permissions della tabella "${tableName}" concede al ` +
            `ruolo pubblico "${role}" un filtro di riga vuoto (filter: {}): non ` +
            `c'e' alcun vincolo di riga, quindi chiunque (anche non autenticato, ` +
            `via ruolo ${role}) puo' eseguire ${permType} su TUTTE le righe della ` +
            `tabella. Manca un controllo di autorizzazione (accesso pubblico ` +
            `incondizionato, CWE-862).`,
        })
      );
    }
  }
}

// `filter` e' "vuoto" SOLO se e' un oggetto/mappa senza chiavi ({}). null,
// assente o un filtro con almeno una chiave (es. { user_id: { _eq: ... } })
// NON sono vuoti -> nessun rilievo (conservativo: nel dubbio non si segnala).
function isEmptyFilter(v) {
  return (
    v !== null &&
    typeof v === 'object' &&
    !Array.isArray(v) &&
    Object.keys(v).length === 0
  );
}

function isPublicRole(role) {
  const r = String(role).trim();
  return PUBLIC_ROLES.has(r) || PUBLIC_ROLES.has(r.toLowerCase());
}

// Nome portatore-di-simbolo della tabella. `table` puo' essere:
//   - oggetto { name, schema } -> name (schema-qualificato se schema != public)
//   - stringa -> usata cosi' com'e'
//   - assente -> placeholder posizionale.
function tableNameOf(entry, idx) {
  const t = entry.table;
  if (t && typeof t === 'object' && !Array.isArray(t)) {
    const name = typeof t.name === 'string' && t.name.length > 0 ? t.name : null;
    const schema = typeof t.schema === 'string' && t.schema.length > 0 ? t.schema : null;
    if (name) {
      return schema && schema !== 'public' ? `${schema}.${name}` : name;
    }
  }
  if (typeof t === 'string' && t.length > 0) return t;
  return `table[${idx}]`;
}

// Raccoglie ricorsivamente ogni oggetto che e' una table-entry, cioe' che
// possiede almeno una chiave *_permissions come array. Gestisce mappa singola,
// sequenza (tables.yaml) e annidamento sources[].tables[] (metadata.json). Una
// volta riconosciuta una table-entry non si discende oltre (le permission al
// suo interno non contengono altre *_permissions).
function collectTableEntries(node, out) {
  if (Array.isArray(node)) {
    for (const el of node) collectTableEntries(el, out);
    return;
  }
  if (node && typeof node === 'object') {
    if (PERM_KEYS.some((k) => Array.isArray(node[k]))) {
      out.push(node);
      return;
    }
    for (const k of Object.keys(node)) collectTableEntries(node[k], out);
  }
}

// =============================================================================
// PARSER YAML — subset dep-free. Ritorna l'albero (mappe = oggetti, sequenze =
// array, scalari = string/number/bool/null). Annota nodeLines per la location.
// =============================================================================
function parseYaml(text) {
  const rawLines = text.split(/\r?\n/);
  const lines = [];
  for (let i = 0; i < rawLines.length; i++) {
    const stripped = stripComment(rawLines[i]);
    if (stripped.trim() === '') continue; // riga vuota
    const trimmedStart = stripped.replace(/^\s*/, '');
    if (trimmedStart.startsWith('---') || trimmedStart.startsWith('...')) continue; // marker documento
    if (trimmedStart.startsWith('%')) continue; // direttiva (%YAML, %TAG)
    if (/^\t/.test(stripped)) {
      // YAML vieta i tab nell'indentazione: errore esplicito -> parse_warning.
      throw new Error(`tab nell'indentazione alla riga ${i + 1} (non ammesso in YAML)`);
    }
    const indent = stripped.length - trimmedStart.length;
    lines.push({ indent, content: trimmedStart.replace(/\s+$/, ''), lineNo: i + 1 });
  }
  if (lines.length === 0) return null;
  const cur = { i: 0 };
  const value = parseNode(lines, cur, lines[0].indent);
  return value;
}

function parseNode(lines, cur, minIndent) {
  if (cur.i >= lines.length) return null;
  const line = lines[cur.i];
  if (line.indent < minIndent) return null;
  if (isSeqItem(line.content)) return parseSequence(lines, cur, line.indent);
  return parseMapping(lines, cur, line.indent);
}

function parseMapping(lines, cur, indent) {
  const map = {};
  const firstLineNo = lines[cur.i].lineNo;
  while (cur.i < lines.length) {
    const line = lines[cur.i];
    if (line.indent < indent) break;
    if (line.indent > indent) break; // indentazione incoerente: stop difensivo
    if (isSeqItem(line.content)) break; // la sequenza appartiene alla chiave genitore
    const colon = findKeyColon(line.content);
    if (colon === -1) break; // riga non-chiave a livello mappa: stop difensivo
    const key = unquoteScalar(line.content.slice(0, colon).trim());
    const inlineVal = line.content.slice(colon + 1).trim();
    cur.i++;
    if (inlineVal !== '') {
      map[key] = parseScalarOrFlow(inlineVal);
    } else if (cur.i < lines.length) {
      const nxt = lines[cur.i];
      if (nxt.indent > indent) {
        map[key] = parseNode(lines, cur, indent + 1);
      } else if (nxt.indent === indent && isSeqItem(nxt.content)) {
        map[key] = parseSequence(lines, cur, indent);
      } else {
        map[key] = null;
      }
    } else {
      map[key] = null;
    }
  }
  nodeLines.set(map, firstLineNo);
  return map;
}

function parseSequence(lines, cur, indent) {
  const arr = [];
  const firstLineNo = lines[cur.i].lineNo;
  while (cur.i < lines.length) {
    const line = lines[cur.i];
    if (line.indent !== indent) break;
    if (!isSeqItem(line.content)) break;
    const itemLineNo = line.lineNo;
    const body = line.content.slice(1); // dopo il '-'
    const lead = body.length - body.replace(/^\s+/, '').length;
    const inlineContent = body.slice(lead);
    const effIndent = indent + 1 + lead; // colonna effettiva del contenuto inline

    if (inlineContent === '') {
      // valore sulle righe seguenti, piu' indentate
      cur.i++;
      arr.push(parseNode(lines, cur, indent + 1));
    } else if (findKeyColon(inlineContent) !== -1) {
      // item di tipo mappa con prima chiave inline: riscrivo la riga corrente
      // alla colonna effettiva e lascio che parseMapping consumi le chiavi
      // successive allineate.
      lines[cur.i] = { indent: effIndent, content: inlineContent, lineNo: itemLineNo };
      arr.push(parseMapping(lines, cur, effIndent));
    } else {
      // scalare o flow inline
      cur.i++;
      arr.push(parseScalarOrFlow(inlineContent));
    }
  }
  nodeLines.set(arr, firstLineNo);
  return arr;
}

function isSeqItem(content) {
  return content === '-' || content.startsWith('- ') || content.startsWith('-\t');
}

// Indice del ':' che separa chiave e valore in una riga di mappa: primo ':' a
// profondita' 0 (fuori da quote e da []/{}) seguito da spazio o fine-riga.
function findKeyColon(s) {
  let inSingle = false;
  let inDouble = false;
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inSingle) {
      if (c === "'") inSingle = false;
      continue;
    }
    if (inDouble) {
      if (c === '"' && s[i - 1] !== '\\') inDouble = false;
      continue;
    }
    if (c === "'") { inSingle = true; continue; }
    if (c === '"') { inDouble = true; continue; }
    if (c === '[' || c === '{') { depth++; continue; }
    if (c === ']' || c === '}') { if (depth > 0) depth--; continue; }
    if (c === ':' && depth === 0) {
      const next = s[i + 1];
      if (next === undefined || next === ' ' || next === '\t') return i;
    }
  }
  return -1;
}

// Rimuove un commento `#` di fine riga (fuori da quote). Un '#' conta come
// commento solo se a inizio riga o preceduto da whitespace (per non spezzare
// scalari come `a#b` o `#1`).
function stripComment(line) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inSingle) {
      if (c === "'") inSingle = false;
      continue;
    }
    if (inDouble) {
      if (c === '"' && line[i - 1] !== '\\') inDouble = false;
      continue;
    }
    if (c === "'") { inSingle = true; continue; }
    if (c === '"') { inDouble = true; continue; }
    if (c === '#' && (i === 0 || line[i - 1] === ' ' || line[i - 1] === '\t')) {
      return line.slice(0, i);
    }
  }
  return line;
}

// Interpreta un valore scalare o un flow inline (`{}`, `[]`, `{k: v}`, `[a,b]`).
function parseScalarOrFlow(s) {
  const t = s.trim();
  if (t === '') return null;
  if (t[0] === '{' || t[0] === '[') {
    try {
      return parseFlow(t);
    } catch {
      return t; // fallback: mai un throw, il valore resta la stringa grezza
    }
  }
  return coerceScalar(t);
}

function coerceScalar(t) {
  if (t[0] === '"' || t[0] === "'") return unquoteScalar(t);
  if (t === 'null' || t === 'Null' || t === 'NULL' || t === '~') return null;
  if (t === 'true' || t === 'True' || t === 'TRUE') return true;
  if (t === 'false' || t === 'False' || t === 'FALSE') return false;
  if (/^-?\d+$/.test(t)) return parseInt(t, 10);
  if (/^-?\d*\.\d+$/.test(t)) return parseFloat(t);
  return t;
}

function unquoteScalar(t) {
  if (t.length >= 2 && t[0] === '"' && t[t.length - 1] === '"') {
    return t.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  }
  if (t.length >= 2 && t[0] === "'" && t[t.length - 1] === "'") {
    return t.slice(1, -1).replace(/''/g, "'");
  }
  return t;
}

// --- Parser FLOW inline (single-line) -------------------------------------
// Supporta `{}`, `[]`, `{k: v, k2: v2}`, `[a, b]` con annidamento. Guardia
// anti-loop: ogni passo deve consumare almeno un carattere.
function parseFlow(str) {
  const ctx = { s: str, i: 0 };
  const v = readFlowValue(ctx);
  return v;
}

function skipFlowWs(ctx) {
  while (ctx.i < ctx.s.length && /\s/.test(ctx.s[ctx.i])) ctx.i++;
}

function readFlowValue(ctx) {
  skipFlowWs(ctx);
  const c = ctx.s[ctx.i];
  if (c === '{') return readFlowMap(ctx);
  if (c === '[') return readFlowSeq(ctx);
  if (c === '"' || c === "'") return readFlowQuoted(ctx);
  return coerceScalar(readFlowScalar(ctx).trim());
}

function readFlowMap(ctx) {
  const obj = {};
  ctx.i++; // consuma '{'
  skipFlowWs(ctx);
  if (ctx.s[ctx.i] === '}') { ctx.i++; return obj; }
  let guard = 0;
  while (ctx.i < ctx.s.length && guard++ < 10000) {
    skipFlowWs(ctx);
    let key;
    if (ctx.s[ctx.i] === '"' || ctx.s[ctx.i] === "'") key = readFlowQuoted(ctx);
    else key = coerceScalarKey(readFlowKey(ctx).trim());
    skipFlowWs(ctx);
    if (ctx.s[ctx.i] === ':') ctx.i++;
    const val = readFlowValue(ctx);
    obj[String(key)] = val;
    skipFlowWs(ctx);
    if (ctx.s[ctx.i] === ',') { ctx.i++; continue; }
    if (ctx.s[ctx.i] === '}') { ctx.i++; break; }
    break; // carattere inatteso: esci (no throw)
  }
  return obj;
}

function readFlowSeq(ctx) {
  const arr = [];
  ctx.i++; // consuma '['
  skipFlowWs(ctx);
  if (ctx.s[ctx.i] === ']') { ctx.i++; return arr; }
  let guard = 0;
  while (ctx.i < ctx.s.length && guard++ < 10000) {
    const val = readFlowValue(ctx);
    arr.push(val);
    skipFlowWs(ctx);
    if (ctx.s[ctx.i] === ',') { ctx.i++; continue; }
    if (ctx.s[ctx.i] === ']') { ctx.i++; break; }
    break;
  }
  return arr;
}

function readFlowQuoted(ctx) {
  const quote = ctx.s[ctx.i];
  ctx.i++;
  let val = '';
  while (ctx.i < ctx.s.length) {
    const c = ctx.s[ctx.i];
    if (quote === '"' && c === '\\' && ctx.i + 1 < ctx.s.length) {
      val += ctx.s[ctx.i + 1];
      ctx.i += 2;
      continue;
    }
    if (c === quote) { ctx.i++; break; }
    val += c;
    ctx.i++;
  }
  return val;
}

function readFlowScalar(ctx) {
  let val = '';
  while (ctx.i < ctx.s.length) {
    const c = ctx.s[ctx.i];
    if (c === ',' || c === ']' || c === '}') break;
    val += c;
    ctx.i++;
  }
  return val;
}

function readFlowKey(ctx) {
  let val = '';
  while (ctx.i < ctx.s.length) {
    const c = ctx.s[ctx.i];
    if (c === ':' || c === ',' || c === '}') break;
    val += c;
    ctx.i++;
  }
  return val;
}

function coerceScalarKey(t) {
  if (t === '') return t;
  return unquoteScalar(t);
}

// -----------------------------------------------------------------------------
// Costruzione del rilievo NATIVO (non normalizzato).
// `match_path` (e i carrier table/perm_type/role) sono i campi portatori-di-
// simbolo che il normalizer leggera': nomi-chiave esatti.
// -----------------------------------------------------------------------------
function makeFinding(o) {
  const f = {
    control_id: o.controlId,
    severity: o.severity,
    category: 'authz',
    match_path: o.matchPath,
    table: o.table,
    perm_type: o.permType,
    role: o.role,
    location: {
      file: o.file,
      start_line: o.startLine,
      end_line: o.startLine,
      statement: o.statement,
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
function snippetOf(body, maxLen = 240) {
  const oneLine = String(body).replace(/\s+/g, ' ').trim();
  return oneLine.length > maxLen ? oneLine.slice(0, maxLen) + ' ...' : oneLine;
}

function firstLine(s) {
  return String(s).split('\n')[0];
}

// -----------------------------------------------------------------------------
// Raccolta file di metadata dagli argomenti (dir ricorsiva o file).
// -----------------------------------------------------------------------------
function collectMetadataFiles(args) {
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
      if (isMetadataFileArg(a)) {
        out.push(a);
      } else {
        process.stderr.write(
          `avviso: non e' un file di metadata (.yaml/.yml/.json), ignorato: ${a}\n`
        );
      }
    }
  }
  out.sort();
  return out;
}

// File passato esplicitamente: accettiamo qualunque .yaml/.yml/.json.
function isMetadataFileArg(p) {
  const ext = extname(p).toLowerCase();
  return ext === '.yaml' || ext === '.yml' || ext === '.json';
}

// Walk di una directory: raccoglie i .yaml/.yml e i .json che sembrano metadata
// Hasura (basename metadata.json/tables.json, o un percorso con segmento
// `metadata`). Cosi' un package-lock.json o un knip.json non vengono raccolti.
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
    } else if (entry.isFile() && isWalkedMetadataFile(full, entry.name)) {
      out.push(full);
    }
  }
}

function isWalkedMetadataFile(fullPath, name) {
  const ext = extname(name).toLowerCase();
  if (ext === '.yaml' || ext === '.yml') return true;
  if (ext === '.json') {
    const base = name.toLowerCase();
    if (base === 'metadata.json' || base === 'tables.json') return true;
    const segs = fullPath.split(sep).map((s) => s.toLowerCase());
    if (segs.includes('metadata')) return true;
  }
  return false;
}

function toPosixRel(file) {
  const rel = relative(process.cwd(), file);
  return rel.split(sep).join(posix.sep);
}

main();
