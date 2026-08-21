#!/usr/bin/env node
// =============================================================================
// rls_check.mjs — Oracolo CUSTOM di Trueline per Row Level Security (03 §5.4)
//
// Unico oracolo che costruiamo a mano: gli altri (gitleaks, osv-scanner, knip,
// semgrep) sono tool esterni di cui Trueline e' solo orchestratore. Questo
// checker analizza STATICAMENTE la DDL delle migration Supabase/PostgreSQL e
// segnala i difetti di isolamento dati piu' comuni.
//
// CONFINE DI COPERTURA (static-first, dichiarato esplicitamente — 03 §5.2/§7):
//   - Vede SOLO cio' che e' scritto nei file DDL passati (le migration).
//   - NON esegue il database, NON ispeziona lo schema effettivo a runtime, e
//     quindi NON vede tabelle/colonne/policy create fuori dalle migration
//     (es. tramite dashboard Supabase, script applicativi o seed dinamici).
//   - La verifica COMPORTAMENTALE per-tenant (es. S5) appartiene a rls-check
//     [DB-test] (10 §2): qui il controllo DEGRADA all'euristica statica e lo
//     dichiara nei campi `coverage`/`heuristic` del rilievo.
//
// USO DEL PARSER (NIENTE regex fragili sulla struttura):
//   pgsql-ast-parser 12.x parsa CREATE TABLE in modo completo (schema, nome,
//   colonne) ed e' la fonte autoritativa per la struttura delle tabelle e per
//   l'euristica multi-tenant (richiede la conoscenza delle COLONNE). La stessa
//   versione del parser NON supporta pero' due costrutti PostgreSQL che ci
//   servono — `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` e `CREATE POLICY` —
//   e solleva un errore di sintassi su di essi. Per questi due costrutti, che
//   il parser non puo' rappresentare, analizziamo il SINGOLO statement gia'
//   isolato (non l'intero file alla cieca) con un estrattore a token mirato.
//   Lo split in statement rispetta stringhe e commenti SQL.
//
// OUTPUT: JSON NATIVO (lista di rilievi), NON normalizzato (la normalizzazione
//   nel finding model 04 e' compito di `normalize`). Stampa su stdout.
//
// USO: node trueline/scripts/oracles/rls_check.mjs <dir-o-file> [<altro> ...]
//   Gli argomenti sono directory (scansione ricorsiva di **/*.sql) o file .sql.
// =============================================================================

import { parse } from 'pgsql-ast-parser';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep, posix } from 'node:path';

const ORACLE = 'rls-check';
const TOOL_VERSION = readToolVersion();

// Colonne che, se presenti, indicano una tabella "multi-tenant" o comunque
// soggetta a isolamento per soggetto: la policy DOVREBBE vincolare su una di
// queste (o su auth.uid()). Euristica dichiarata.
const TENANT_COLUMNS = [
  'tenant_id', 'org_id', 'organization_id', 'account_id', 'workspace_id',
  'company_id', 'customer_id', 'user_id', 'owner_id',
];

// Marcatori che indicano un vincolo di isolamento corretto dentro una policy.
const ISOLATION_TOKENS = ['auth.uid()', 'auth.jwt()', 'current_setting('];

// Marcatori di isolamento per le policy su storage.objects (Supabase Storage).
// owner-scoped: `owner = auth.uid()` oppure `(storage.foldername(name))[1] = auth.uid()::text`.
const STORAGE_ISOLATION_TOKENS = ['owner', 'storage.foldername', 'auth.uid()', 'auth.jwt()', 'current_setting('];

// -----------------------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    process.stderr.write(
      'uso: node rls_check.mjs <dir-o-file.sql> [...]\n'
    );
    process.exit(2);
  }

  const files = collectSqlFiles(args);
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
    coverage: 'static-ddl',
    coverage_note:
      'Analisi statica della sola DDL delle migration. Non vede schema/policy ' +
      'creati fuori dalle migration (es. dashboard Supabase) ne la semantica ' +
      'comportamentale per-tenant (verifica dinamica = rls-check [DB-test]).',
    scanned_files: scannedFiles.map(toPosixRel),
    parse_warnings: parseWarnings,
    findings,
  };

  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

// -----------------------------------------------------------------------------
// Analisi di un singolo file DDL
// -----------------------------------------------------------------------------
function analyzeFile(file, text, findings, parseWarnings) {
  const relPath = toPosixRel(file);
  const statements = splitStatements(text);

  // Modello in-memory delle tabelle in schema public dichiarate nel file.
  // chiave = "schema.table"
  const tables = new Map();

  // Prima passata: CREATE TABLE (via AST), ENABLE RLS e CREATE POLICY (via
  // estrattore a token sullo statement isolato).
  for (const st of statements) {
    const head = leadingKeywords(st.body);

    if (head.startsWith('CREATE TABLE')) {
      handleCreateTable(st, relPath, tables, parseWarnings);
    } else if (isEnableRls(st.body)) {
      handleEnableRls(st, tables);
    } else if (head.startsWith('CREATE POLICY')) {
      handleCreatePolicy(st, relPath, tables);
    }
    // Altri statement (CREATE INDEX, ALTER ... ADD COLUMN, ecc.) sono fuori
    // dallo scope di questo checker e vengono ignorati di proposito.
  }

  // Seconda passata: valutazione dei controlli deterministici per ogni tabella
  // in schema public.
  for (const t of tables.values()) {
    if (t.schema !== 'public') continue; // scope: solo schema public
    evaluateTable(t, findings);
  }

  // Passata storage (additiva): policy su storage.objects (tabella built-in,
  // registrata come ghost-table schema='storage' da handleCreatePolicy). Non
  // tocca lo scope public: per i pack senza policy storage e' un NO-OP.
  for (const t of tables.values()) {
    if (t.schema === 'storage' && t.name === 'objects') evaluateStorageObjects(t, findings);
  }
}

// -----------------------------------------------------------------------------
// CONTROLLI deterministici per tabella
// -----------------------------------------------------------------------------
function evaluateTable(t, findings) {
  const tableFqn = `${t.schema}.${t.name}`;

  // [S3] RLS assente: CREATE TABLE in public senza ENABLE ROW LEVEL SECURITY.
  if (!t.rlsEnabled) {
    findings.push(
      makeFinding({
        controlId: 'RLS001_MISSING_RLS',
        severity: 'HIGH',
        table: tableFqn,
        file: t.file,
        startLine: t.createLine,
        endLine: t.createLine,
        statement: 'CREATE TABLE',
        snippet: t.createSnippet,
        message:
          `La tabella ${tableFqn} in schema public non abilita Row Level ` +
          `Security: nessun "ALTER TABLE ... ENABLE ROW LEVEL SECURITY" la ` +
          `protegge, quindi e' leggibile/scrivibile da chiunque abbia una ` +
          `chiave anon.`,
        coverage: 'static-ddl',
      })
    );
    // Se RLS e' assente, non ha senso valutare le policy: il difetto e' a monte.
    return;
  }

  // Policy assente (deny-all): RLS abilitato ma nessuna CREATE POLICY.
  if (t.policies.length === 0) {
    findings.push(
      makeFinding({
        controlId: 'RLS002_NO_POLICY',
        severity: 'MEDIUM',
        table: tableFqn,
        file: t.file,
        startLine: t.enableLine ?? t.createLine,
        endLine: t.enableLine ?? t.createLine,
        statement: 'ENABLE ROW LEVEL SECURITY',
        snippet: t.enableSnippet ?? t.createSnippet,
        message:
          `La tabella ${tableFqn} ha RLS abilitato ma nessuna policy: il ` +
          `comportamento e' deny-all (nessuna riga accessibile via API). ` +
          `Probabile dimenticanza di definire le policy di accesso.`,
        coverage: 'static-ddl',
      })
    );
    return;
  }

  // Determina se la tabella e' multi-tenant (ha una colonna soggetto).
  const tenantCols = t.columns.filter((c) =>
    TENANT_COLUMNS.includes(c.toLowerCase())
  );
  const isMultiTenant = tenantCols.length > 0;

  for (const p of t.policies) {
    const exprs = [p.using, p.withCheck].filter(Boolean);
    const exprBlob = exprs.join(' ').toLowerCase();

    // [S4] Isolamento finto: USING (true) / WITH CHECK (true).
    const trueClause =
      isLiteralTrue(p.using) ? 'USING' : isLiteralTrue(p.withCheck) ? 'WITH CHECK' : null;
    if (trueClause) {
      findings.push(
        makeFinding({
          controlId: 'RLS003_PERMISSIVE_TRUE',
          severity: 'HIGH',
          table: tableFqn,
          policy: p.name,
          file: p.file,
          startLine: p.startLine,
          endLine: p.endLine,
          statement: 'CREATE POLICY',
          snippet: p.snippet,
          message:
            `La policy ${p.name} su ${tableFqn} usa ${trueClause} (true): ` +
            `la condizione e' sempre vera, quindi l'isolamento e' solo ` +
            `apparente e ogni riga e' visibile a chiunque superi RLS.`,
          coverage: 'static-ddl',
        })
      );
      // Una policy "true" e' gia' il difetto massimo: non doppiamo con S5.
      continue;
    }

    // [S5] auth.uid()/tenant mancante su tabella multi-tenant.
    if (isMultiTenant) {
      const hasIsolationToken = ISOLATION_TOKENS.some((tok) =>
        exprBlob.includes(tok)
      );
      const referencesTenantCol = tenantCols.some((col) =>
        new RegExp(`\\b${escapeRe(col.toLowerCase())}\\b`).test(exprBlob)
      );
      if (!hasIsolationToken && !referencesTenantCol) {
        findings.push(
          makeFinding({
            controlId: 'RLS004_MISSING_TENANT_PREDICATE',
            severity: 'HIGH',
            table: tableFqn,
            policy: p.name,
            file: p.file,
            startLine: p.startLine,
            endLine: p.endLine,
            statement: 'CREATE POLICY',
            snippet: p.snippet,
            message:
              `La policy ${p.name} su ${tableFqn} (tabella multi-tenant: ` +
              `colonne ${tenantCols.join(', ')}) non vincola l'accesso per ` +
              `auth.uid()/auth.jwt()/current_setting() ne per una colonna di ` +
              `tenancy: il predicato (${exprs.join(' ; ')}) non isola i dati ` +
              `per soggetto, quindi un tenant puo' vedere righe di altri.`,
            coverage: 'static-ddl',
            heuristic:
              'EURISTICA (static-first): "multi-tenant" e\' dedotto dalla ' +
              'presenza di una colonna nota di tenancy (' +
              TENANT_COLUMNS.join(', ') +
              '); l\'assenza di isolamento e\' dedotta dall\'assenza, nel testo ' +
              'del predicato, sia di un token di identita\' (auth.uid()/' +
              'auth.jwt()/current_setting()) sia di un riferimento a una ' +
              'colonna di tenancy. La conferma comportamentale e\' demandata ' +
              'a rls-check [DB-test].',
          })
        );
      }
    }
  }
}

// -----------------------------------------------------------------------------
// CONTROLLO storage (additivo): policy permissive su storage.objects (Supabase
// Storage). storage.objects e' una ghost-table (columns:[]) -> niente euristica
// multi-tenant: il verdetto e' l'ASSENZA, nel predicato, di un token di
// isolamento owner-scoped. Clone strutturale del pattern RLS003/RLS004.
// -----------------------------------------------------------------------------
function evaluateStorageObjects(t, findings) {
  for (const p of t.policies) {
    const exprs = [p.using, p.withCheck].filter(Boolean);
    const exprBlob = exprs.join(' ').toLowerCase();
    const hasIsolation = STORAGE_ISOLATION_TOKENS.some((tok) => exprBlob.includes(tok));
    if (!hasIsolation) {
      findings.push(
        makeFinding({
          controlId: 'RLS005_PUBLIC_BUCKET',
          severity: 'HIGH',
          table: 'storage.objects',
          policy: p.name,
          file: p.file,
          startLine: p.startLine,
          endLine: p.endLine,
          statement: 'CREATE POLICY',
          snippet: p.snippet,
          message:
            `La policy ${p.name} su storage.objects non vincola l'accesso per ` +
            `owner/auth.uid()/storage.foldername: il bucket e' di fatto pubblico ` +
            `(ogni oggetto leggibile/scrivibile da chiunque superi RLS).`,
          coverage: 'static-ddl',
          heuristic:
            'EURISTICA (static-first): bucket "pubblico" dedotto dall\'assenza, ' +
            'nel predicato della policy su storage.objects, di un token di ' +
            'isolamento (owner, storage.foldername(name), auth.uid(), auth.jwt(), current_setting()).',
        })
      );
    }
  }
}

// -----------------------------------------------------------------------------
// CREATE TABLE — via AST pgsql-ast-parser (fonte autoritativa per struttura)
// -----------------------------------------------------------------------------
function handleCreateTable(st, relPath, tables, parseWarnings) {
  let ast;
  try {
    ast = parse(st.body);
  } catch (e) {
    parseWarnings.push({
      file: relPath,
      line: st.startLine,
      statement: 'CREATE TABLE',
      message: `parser fallito su CREATE TABLE: ${firstLine(e.message)}`,
    });
    return;
  }
  const node = ast.find((s) => s.type === 'create table');
  if (!node) return;

  const schema = node.name.schema ?? 'public';
  const name = node.name.name;
  const fqn = `${schema}.${name}`;
  const columns = (node.columns ?? [])
    .filter((c) => c.kind === 'column')
    .map((c) => c.name?.name)
    .filter(Boolean);

  tables.set(fqn, {
    schema,
    name,
    columns,
    file: relPath,
    createLine: st.startLine,
    createSnippet: snippetOf(st.body),
    rlsEnabled: false,
    enableLine: null,
    enableSnippet: null,
    policies: [],
  });
}

// -----------------------------------------------------------------------------
// ALTER TABLE ... ENABLE ROW LEVEL SECURITY — costrutto NON supportato dal
// parser di questa versione: estrazione a token sullo statement isolato.
// -----------------------------------------------------------------------------
function isEnableRls(body) {
  const clean = stripComments(body).replace(/\s+/g, ' ').trim().toUpperCase();
  return (
    clean.startsWith('ALTER TABLE') &&
    /ENABLE\s+ROW\s+LEVEL\s+SECURITY/.test(clean)
  );
}

function handleEnableRls(st, tables) {
  const clean = stripComments(st.body);
  // ALTER TABLE [ONLY] [IF EXISTS] [schema.]table ENABLE ROW LEVEL SECURITY
  const m = clean.match(
    /ALTER\s+TABLE\s+(?:ONLY\s+)?(?:IF\s+EXISTS\s+)?(?:("?[\w$]+"?)\s*\.\s*)?("?[\w$]+"?)/i
  );
  if (!m) return;
  const schema = unquote(m[1]) ?? 'public';
  const name = unquote(m[2]);
  const fqn = `${schema}.${name}`;
  const t = tables.get(fqn);
  if (!t) return; // ALTER su tabella non dichiarata nei file in scope: ignora
  t.rlsEnabled = true;
  t.enableLine = st.startLine;
  t.enableSnippet = snippetOf(st.body);
}

// -----------------------------------------------------------------------------
// CREATE POLICY — costrutto NON supportato dal parser di questa versione:
// estrazione a token sullo statement isolato (nome, tabella, USING, WITH CHECK).
// -----------------------------------------------------------------------------
function handleCreatePolicy(st, relPath, tables) {
  const clean = stripComments(st.body);
  // CREATE POLICY name ON [schema.]table ...
  const m = clean.match(
    /CREATE\s+POLICY\s+("?[\w$]+"?)\s+ON\s+(?:("?[\w$]+"?)\s*\.\s*)?("?[\w$]+"?)/i
  );
  if (!m) return;
  const policyName = unquote(m[1]);
  const schema = unquote(m[2]) ?? 'public';
  const name = unquote(m[3]);
  const fqn = `${schema}.${name}`;

  const using = grabParenExpr(clean, /\bUSING\s*\(/i);
  const withCheck = grabParenExpr(clean, /\bWITH\s+CHECK\s*\(/i);

  const policy = {
    name: policyName,
    file: relPath,
    startLine: st.startLine,
    endLine: st.startLine + countLines(st.body) - 1,
    snippet: snippetOf(st.body),
    using,
    withCheck,
  };

  const t = tables.get(fqn);
  if (t) {
    t.policies.push(policy);
  } else {
    // Policy su tabella non dichiarata nei file in scope: registriamo una
    // tabella "fantasma" cosi' i controlli policy possano comunque girare se
    // pertinenti; ma senza CREATE TABLE non valutiamo S3/S5 (manca lo schema).
    tables.set(fqn, {
      schema,
      name,
      columns: [],
      file: relPath,
      createLine: null,
      createSnippet: null,
      rlsEnabled: true, // assumiamo abilitato altrove
      enableLine: null,
      enableSnippet: null,
      policies: [policy],
      ghost: true,
    });
  }
}

// -----------------------------------------------------------------------------
// HELPER di estrazione a token
// -----------------------------------------------------------------------------

// Estrae l'espressione tra la prima parentesi aperta dopo `kwRe` e la sua
// chiusura bilanciata. Rispetta stringhe single-quote e commenti gia' rimossi.
function grabParenExpr(text, kwRe) {
  const m = kwRe.exec(text);
  if (!m) return null;
  // posizione della "(" che fa parte del match (l'ultimo char del match)
  let i = m.index + m[0].length - 1;
  if (text[i] !== '(') {
    // cerca la prima "(" successiva
    while (i < text.length && text[i] !== '(') i++;
    if (i >= text.length) return null;
  }
  let depth = 0;
  let inStr = false;
  let out = '';
  for (; i < text.length; i++) {
    const ch = text[i];
    if (inStr) {
      out += ch;
      if (ch === "'") {
        if (text[i + 1] === "'") {
          out += text[++i];
          continue;
        }
        inStr = false;
      }
      continue;
    }
    if (ch === "'") {
      inStr = true;
      out += ch;
      continue;
    }
    if (ch === '(') {
      depth++;
      if (depth === 1) continue; // non includere la "(" esterna
      out += ch;
      continue;
    }
    if (ch === ')') {
      depth--;
      if (depth === 0) break;
      out += ch;
      continue;
    }
    if (depth >= 1) out += ch;
  }
  return out.trim();
}

function isLiteralTrue(expr) {
  if (!expr) return false;
  return /^true$/i.test(expr.trim());
}

// -----------------------------------------------------------------------------
// SPLIT in statement: rispetta stringhe single-quote, commenti -- e /* */.
// Ritorna { body, startLine } dove startLine e' la riga (1-based) del PRIMO
// token SQL non-commento dello statement.
// -----------------------------------------------------------------------------
function splitStatements(src) {
  const raw = [];
  let buf = '';
  let line = 1;
  let bufStartLine = 1;
  let bufHasContent = false;
  let inStr = false;
  let inLine = false;
  let inBlock = false;

  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    const n = src[i + 1];

    if (c === '\n') {
      line++;
      buf += c;
      if (inLine) inLine = false;
      continue;
    }
    if (inLine) {
      buf += c;
      continue;
    }
    if (inBlock) {
      buf += c;
      if (c === '*' && n === '/') {
        buf += n;
        i++;
      }
      continue;
    }
    if (inStr) {
      buf += c;
      if (c === "'") {
        if (n === "'") {
          buf += n;
          i++;
          continue;
        }
        inStr = false;
      }
      continue;
    }
    if (c === '-' && n === '-') {
      buf += c + n;
      i++;
      inLine = true;
      continue;
    }
    if (c === '/' && n === '*') {
      buf += c + n;
      i++;
      inBlock = true;
      continue;
    }
    if (c === "'") {
      inStr = true;
      buf += c;
      markContent();
      continue;
    }
    if (c === ';') {
      flush();
      continue;
    }
    buf += c;
    if (!/\s/.test(c)) markContent();
  }
  flush();
  return raw;

  function markContent() {
    if (!bufHasContent) {
      bufHasContent = true;
      // la riga del primo token reale = riga corrente, ma il buffer puo'
      // contenere commenti/whitespace iniziali: ricalcoliamo dopo in flush().
    }
  }
  function flush() {
    const body = buf.trim();
    if (body && hasSqlContent(body)) {
      const { sql, lineOffset } = stripLeading(buf);
      raw.push({ body: sql.trim(), startLine: bufStartLine + lineOffset });
    }
    buf = '';
    bufHasContent = false;
    bufStartLine = line;
  }
}

// Conta quante righe di solo-commento/whitespace precedono il primo token SQL,
// per attribuire startLine alla riga del costrutto e non al commento.
function stripLeading(buf) {
  let i = 0;
  let lineOffset = 0;
  let inLine = false;
  let inBlock = false;
  while (i < buf.length) {
    const c = buf[i];
    const n = buf[i + 1];
    if (inLine) {
      if (c === '\n') {
        inLine = false;
        lineOffset++;
      }
      i++;
      continue;
    }
    if (inBlock) {
      if (c === '*' && n === '/') {
        inBlock = false;
        i += 2;
        continue;
      }
      if (c === '\n') lineOffset++;
      i++;
      continue;
    }
    if (c === '-' && n === '-') {
      inLine = true;
      i += 2;
      continue;
    }
    if (c === '/' && n === '*') {
      inBlock = true;
      i += 2;
      continue;
    }
    if (c === '\n') {
      lineOffset++;
      i++;
      continue;
    }
    if (/\s/.test(c)) {
      i++;
      continue;
    }
    break; // primo token SQL reale
  }
  return { sql: buf.slice(i), lineOffset };
}

function hasSqlContent(body) {
  return stripComments(body).trim().length > 0;
}

// -----------------------------------------------------------------------------
// Utilita' varie
// -----------------------------------------------------------------------------
function stripComments(s) {
  // Rimuove commenti -- di riga e /* */ di blocco rispettando le stringhe.
  let out = '';
  let inStr = false;
  let inLine = false;
  let inBlock = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    const n = s[i + 1];
    if (inLine) {
      if (c === '\n') {
        inLine = false;
        out += c;
      }
      continue;
    }
    if (inBlock) {
      if (c === '*' && n === '/') {
        inBlock = false;
        i++;
      }
      continue;
    }
    if (inStr) {
      out += c;
      if (c === "'") {
        if (n === "'") {
          out += n;
          i++;
          continue;
        }
        inStr = false;
      }
      continue;
    }
    if (c === '-' && n === '-') {
      inLine = true;
      i++;
      continue;
    }
    if (c === '/' && n === '*') {
      inBlock = true;
      i++;
      continue;
    }
    if (c === "'") {
      inStr = true;
      out += c;
      continue;
    }
    out += c;
  }
  return out;
}

function leadingKeywords(body) {
  return stripComments(body).replace(/\s+/g, ' ').trim().toUpperCase();
}

function snippetOf(body, maxLen = 240) {
  const oneLine = body.replace(/\s+/g, ' ').trim();
  return oneLine.length > maxLen ? oneLine.slice(0, maxLen) + ' ...' : oneLine;
}

function countLines(s) {
  return s.split('\n').length;
}

function unquote(tok) {
  if (tok == null) return tok;
  const m = /^"(.*)"$/.exec(tok);
  return m ? m[1] : tok;
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function firstLine(s) {
  return String(s).split('\n')[0];
}

function makeFinding(o) {
  // Rilievo NATIVO (non normalizzato): la chiave `control_id` e' l'id-controllo
  // interno; la normalizzazione nel finding model (04) e' compito di normalize.
  const f = {
    control_id: o.controlId,
    severity: o.severity,
    category: 'rls',
    table: o.table,
    location: {
      file: o.file,
      start_line: o.startLine,
      end_line: o.endLine,
      statement: o.statement,
    },
    snippet: o.snippet,
    message: o.message,
    coverage: o.coverage,
  };
  if (o.policy) f.policy = o.policy;
  if (o.heuristic) f.heuristic = o.heuristic;
  return f;
}

// -----------------------------------------------------------------------------
// Raccolta file .sql dagli argomenti (dir ricorsiva o file).
// -----------------------------------------------------------------------------
function collectSqlFiles(args) {
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
    } else if (st.isFile() && a.toLowerCase().endsWith('.sql')) {
      out.push(a);
    }
  }
  // ordinamento deterministico
  out.sort();
  return out;
}

function walk(dir, out) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.isFile() && entry.name.toLowerCase().endsWith('.sql'))
      out.push(full);
  }
}

function toPosixRel(file) {
  const rel = relative(process.cwd(), file);
  return rel.split(sep).join(posix.sep);
}

function readToolVersion() {
  // Versione del parser come parte dell'identita' dell'oracolo (source_oracle).
  try {
    const url = new URL(
      '../../node_modules/pgsql-ast-parser/package.json',
      import.meta.url
    );
    const pkg = JSON.parse(readFileSync(url, 'utf8'));
    return `rls-check@trueline (pgsql-ast-parser@${pkg.version})`;
  } catch {
    return 'rls-check@trueline';
  }
}

main();
