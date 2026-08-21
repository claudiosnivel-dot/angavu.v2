#!/usr/bin/env node
// =============================================================================
// appsync_auth_check.mjs — Oracolo CUSTOM di Trueline per le regole @auth di
// AWS AppSync / Amplify (Gen1) dichiarate nello schema GraphQL SDL
// (`schema.graphql`).
//
// Gemello strutturale di firestore_rules_check.mjs (stesso contratto: CLI
// posizionale, raccolta file ricorsiva, makeFinding nativo per rilievo, report
// JSON nativo su stdout, exit 2 senza argomenti, errori di parse catturati come
// parse_warnings — MAI un throw — ed exit 0 anche con rilievi presenti, perche'
// il verdetto vive nel payload JSON, non nell'exit code).
//
// USO DEL PARSER (NIENTE dep, NIENTE AST GraphQL): scanner line/regex-based.
//   1) Maschera (rimpiazza con spazi, preservando lunghezza e newline cosi' che
//      gli offset/le righe restino esatti) i commenti `#` di riga, le stringhe
//      `"..."` e le descrizioni a tripla virgoletta `"""..."""`: cosi' i bracket
//      dentro stringhe non sballano il bilanciamento.
//   2) Trova ogni definizione `type <Name>` e ne isola l'HEADER, cioe' il tratto
//      di direttive PRIMA della graffa `{` del campo-set (la `{` a profondita'-0
//      rispetto a `(` e `[` delle direttive). Solo le direttive a livello-type
//      contano: il `@auth` su un singolo field e' fuori scope.
//   3) Nell'header verifica la presenza di `@model` e, se c'e', estrae il blocco
//      argomenti di `@auth( ... )` (matching di parentesi, robusto a whitespace
//      e multiline). Se le parentesi di `@auth` non bilanciano -> parse_warning
//      (SDL malformato), MAI un throw.
//   4) Nel contenuto di `@auth(...)` cerca una rule `{ allow: public }` con la
//      regex `/allow\s*:\s*public\b/`: una sola occorrenza basta a marcare il
//      type come pubblico (un finding per type).
//
// CONFINE DI COPERTURA (static-first, dichiarato esplicitamente):
//   - Vede SOLO il testo dei file `schema.graphql`. NON valuta le regole contro
//     il resolver/engine AppSync, NON conosce le API key/Cognito pool reali, NON
//     esegue simulazioni. Il controllo e' token/strutturale sulle direttive
//     `@model`/`@auth` a livello-type.
//   - GEN1 SOLTANTO: il floor copre la sintassi SDL `@auth(rules: [...])` di
//     Amplify Gen1. La sintassi Gen2 (`a.allow.publicApiKey()` in TypeScript)
//     e' diversa e resta detection-only fuori da questo oracolo.
//
// OUTPUT: JSON NATIVO (lista di rilievi), NON normalizzato (la normalizzazione
//   nel finding model e' compito di `normalize`). Stampa su stdout.
//
// USO: node trueline/scripts/oracles/appsync_auth_check.mjs <dir-o-file.graphql> [...]
//   Gli argomenti sono directory (scansione ricorsiva di `schema.graphql` o file
//   terminanti `.graphql`) oppure file terminanti `.graphql`.
// =============================================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep, posix } from 'node:path';

const ORACLE = 'appsync-auth';
const TOOL_VERSION = 'appsync-auth-check/1.0.0';

// Regola di accesso PUBBLICO incondizionato: una rule con `allow: public` dentro
// `@auth(rules: [...])`. La regex e' STATELESS (niente flag /g): `.test()` non
// avanza lastIndex e resta riusabile. Il `\b` finale evita match su ipotetici
// valori con prefisso `public` (es. `publicapikey`), che comunque appartengono
// alla sintassi Gen2 fuori scope.
const PUBLIC_AUTH_RE = /allow\s*:\s*public\b/;

// -----------------------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    process.stderr.write(
      'uso: node appsync_auth_check.mjs <dir-o-file.graphql> [...]\n'
    );
    process.exit(2);
  }

  const files = collectGraphqlFiles(args);
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
    coverage: 'static-graphql',
    coverage_note:
      'Analisi statica del solo testo dei file schema.graphql (scanner ' +
      'line/regex-based, nessuna dipendenza). Trova le definizioni type <Name> ' +
      '@model e ne valuta la direttiva @auth a livello-type: segnala come ' +
      'pubblica ogni @auth che contiene una rule { allow: public }. Non valuta ' +
      'le regole contro l\'engine AppSync ne conosce API key/Cognito reali: il ' +
      'controllo e\' token/strutturale. Gen1 soltanto (la sintassi Gen2 in ' +
      'TypeScript e\' fuori dallo scope del floor).',
    scanned_files: scannedFiles.map(toPosixRel),
    parse_warnings: parseWarnings,
    findings,
  };

  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

// -----------------------------------------------------------------------------
// Analisi di un singolo file schema.graphql
// -----------------------------------------------------------------------------
function analyzeFile(file, text, findings, parseWarnings) {
  const relPath = toPosixRel(file);

  try {
    // Maschera stringhe/commenti per non far sballare il bilanciamento bracket.
    const masked = maskStringsAndComments(text);

    // Raccoglie le posizioni di ogni definizione `type <Name>`.
    const typeMatches = [];
    const typeRe = /\btype\s+([A-Za-z_][A-Za-z0-9_]*)/g;
    let m;
    while ((m = typeRe.exec(masked)) !== null) {
      typeMatches.push({
        name: m[1],
        at: m.index,
        afterName: m.index + m[0].length,
      });
    }

    for (let k = 0; k < typeMatches.length; k++) {
      const tm = typeMatches[k];
      // La regione di questo type termina dove inizia il prossimo `type` (o EOF):
      // confine che impedisce a un @auth troncato di "sanguinare" nel type dopo.
      const regionLimit =
        k + 1 < typeMatches.length ? typeMatches[k + 1].at : masked.length;

      // Header = direttive prima della graffa `{` del campo-set.
      const headerEnd = findHeaderEnd(masked, tm.afterName, regionLimit);
      const headerMasked = masked.slice(tm.afterName, headerEnd);

      // Il floor riguarda SOLO i type con direttiva @model (Amplify @model).
      if (!/@model\b/.test(headerMasked)) continue;

      // Cerca `@auth(` nell'header (robusto a whitespace: `@auth (`).
      const authMatch = /@auth\s*\(/.exec(headerMasked);
      if (!authMatch) continue;

      const authAtAbs = tm.afterName + authMatch.index; // indice di '@'
      const authParenAbs = authAtAbs + authMatch[0].length - 1; // indice di '('
      const closeIdx = matchParen(masked, authParenAbs, regionLimit);

      // Parentesi @auth non bilanciate -> SDL malformato -> parse_warning.
      if (closeIdx === -1) {
        parseWarnings.push({
          file: relPath,
          line: lineAt(text, authParenAbs),
          statement: '@auth',
          message:
            `direttiva @auth con parentesi non bilanciate sul type ` +
            `"${tm.name}": blocco @auth troncato o malformato, type ignorato.`,
        });
        continue;
      }

      const authContentMasked = masked.slice(authParenAbs + 1, closeIdx);

      // Nessuna rule pubblica -> nessun finding (owner/private/groups sono ok).
      if (!PUBLIC_AUTH_RE.test(authContentMasked)) continue;

      // [APPSYNC001] PUBLIC_AUTH (HIGH, FLOOR, deterministico): un finding per
      // type. match_path = `<TypeName>@auth` (symbol-carrier per fix/normalize).
      const authOrig = text.slice(authAtAbs, closeIdx + 1);
      findings.push(
        makeFinding({
          controlId: 'APPSYNC001_PUBLIC_AUTH',
          severity: 'HIGH',
          matchPath: `${tm.name}@auth`,
          typeName: tm.name,
          file: relPath,
          startLine: lineAt(text, authAtAbs),
          endLine: lineAt(text, closeIdx),
          statement: snippetOf(authOrig),
          snippet: snippetOf(authOrig),
          message:
            `Il type GraphQL "${tm.name}" e' un @model AppSync/Amplify la cui ` +
            `direttiva @auth contiene una rule { allow: public }: concede ` +
            `accesso PUBBLICO incondizionato via API (chiunque disponga ` +
            `dell'endpoint, tipicamente con la sola API key, puo' leggere e ` +
            `scrivere questi record). Manca un vincolo di autorizzazione ` +
            `(owner/private/groups). Accesso pubblico incondizionato, CWE-862.`,
        })
      );
    }
  } catch (e) {
    // Il parser NON deve mai propagare: qualunque imprevisto diventa un warning.
    parseWarnings.push({
      file: relPath,
      line: 1,
      statement: 'schema.graphql',
      message: `parser fallito sul file: ${firstLine(e.message)}`,
    });
  }
}

// -----------------------------------------------------------------------------
// HELPER di scansione strutturale
// -----------------------------------------------------------------------------

// Maschera (rimpiazzandoli con spazi, preservando lunghezza e newline) i
// commenti `#`, le stringhe `"..."` e le descrizioni `"""..."""`. Gli offset e
// le righe del testo mascherato coincidono con l'originale, ma i bracket dentro
// stringhe/commenti spariscono: il bilanciamento di `()`/`[]`/`{}` diventa
// affidabile. I nomi-type e i token `@model`/`@auth`/`allow: public` non vivono
// in stringhe, quindi nel mascherato restano identici all'originale.
function maskStringsAndComments(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    // commento di riga #
    if (c === '#') {
      while (i < n && src[i] !== '\n') {
        out += ' ';
        i++;
      }
      continue;
    }
    // descrizione a tripla virgoletta """ ... """
    if (c === '"' && src[i + 1] === '"' && src[i + 2] === '"') {
      out += '   ';
      i += 3;
      while (i < n && !(src[i] === '"' && src[i + 1] === '"' && src[i + 2] === '"')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i++;
      }
      if (i < n) {
        out += '   ';
        i += 3;
      }
      continue;
    }
    // stringa " ... " (con escape \")
    if (c === '"') {
      out += ' ';
      i++;
      while (i < n && src[i] !== '"') {
        if (src[i] === '\\' && i + 1 < n) {
          out += '  ';
          i += 2;
          continue;
        }
        out += src[i] === '\n' ? '\n' : ' ';
        i++;
      }
      if (i < n) {
        out += ' ';
        i++;
      }
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

// Trova l'indice della graffa `{` che apre il campo-set del type (la prima `{` a
// profondita' 0 rispetto a `(` e `[` delle direttive), entro [start, limit).
// Le `{` annidate dentro gli argomenti di direttiva (`@auth(rules: [{...}])`)
// hanno profondita'-paren o profondita'-bracket > 0 e vengono ignorate. Se non
// si trova alcuna graffa di campo-set, ritorna `limit` (header = intera regione).
function findHeaderEnd(masked, start, limit) {
  let dp = 0; // depth parentesi ()
  let db = 0; // depth bracket []
  for (let i = start; i < limit; i++) {
    const c = masked[i];
    if (c === '(') dp++;
    else if (c === ')') {
      if (dp > 0) dp--;
    } else if (c === '[') db++;
    else if (c === ']') {
      if (db > 0) db--;
    } else if (c === '{') {
      if (dp === 0 && db === 0) return i;
    }
  }
  return limit;
}

// Dato l'indice di una `(` aperta, ritorna l'indice della `)` che la chiude
// (bilanciamento di sole parentesi, entro [openIdx, limit)). -1 se non bilancia.
function matchParen(masked, openIdx, limit) {
  let dp = 0;
  for (let i = openIdx; i < limit; i++) {
    const c = masked[i];
    if (c === '(') dp++;
    else if (c === ')') {
      dp--;
      if (dp === 0) return i;
    }
  }
  return -1;
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
// `match_path` e `type_name` sono i campi portatori-di-simbolo che il normalizer
// e il fix provider leggeranno: nomi-chiave esatti.
// -----------------------------------------------------------------------------
function makeFinding(o) {
  const f = {
    control_id: o.controlId,
    severity: o.severity,
    category: 'authz',
    match_path: o.matchPath,
    type_name: o.typeName,
    allow: 'public',
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
// Raccolta file schema.graphql dagli argomenti (dir ricorsiva o file).
// -----------------------------------------------------------------------------
function collectGraphqlFiles(args) {
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
    } else if (st.isFile() && a.toLowerCase().endsWith('.graphql')) {
      out.push(a);
    } else if (st.isFile()) {
      process.stderr.write(`avviso: non e' un file .graphql, ignorato: ${a}\n`);
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
    } else if (
      entry.isFile() &&
      (entry.name === 'schema.graphql' ||
        entry.name.toLowerCase().endsWith('.graphql'))
    ) {
      out.push(full);
    }
  }
}

function toPosixRel(file) {
  const rel = relative(process.cwd(), file);
  return rel.split(sep).join(posix.sep);
}

main();
