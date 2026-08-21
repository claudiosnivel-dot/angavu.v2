// rls_characterize.mjs — characterization RLS a runtime, con DEGRADAZIONE onesta
// allo static checker quando il DB non e' disponibile (06 §6.1, 06 §6.3).
//
// OBIETTIVO: catturare il comportamento CORRENTE (insicuro) dell'isolamento
// multi-tenant come un VALORE OSSERVATO, non come giudizio. Come tenant A,
// fotografare per ogni tabella RLS { visible_rows, sees_other_tenant }. Per le
// tabelle che perdono (invoices S5, documents S4, audit_logs S3) il tenant A
// VEDE righe del tenant B (sees_other_tenant=true): e' il comportamento attuale,
// e una assertion che congela questo VALORE e' verde-per-costruzione sul codice
// corrente. Per le tabelle di contrasto (profiles, notes) sees_other_tenant=false.
// Questa ASIMMETRIA — calcolata dalla vera valutazione RLS di Postgres, non
// hardcoded — e' la prova che la caratterizzazione e' sana e falsificabile:
// fixare S5 (l'isolamento ritorna) cambia l'observed di invoices; rompere il
// contrasto cambia l'observed di notes/profiles. (10 §5, L-COL-002: "verde" e'
// l'output di un comando, mai un giudizio.)
//
// METODO a runtime (quando il comando psql risolto e' raggiungibile):
//   1) leggi TUTTE le migration supabase/migrations/*.sql (ordinate), concatena
//      e RISCRIVI i riferimenti 'public.<x>' -> '<schema>.<x>' (lasciando auth.*
//      e altri schemi intatti);
//   2) applica in uno SCHEMA EFFIMERO usa-e-getta con search_path impostato;
//   3) GRANT USAGE/SELECT/INSERT a 'authenticated' (RLS e' valutato DOPO il
//      privilegio sulla base-table);
//   4) introspeziona dal catalogo le tabelle con RLS e le loro colonne;
//   5) per ogni tabella RLS deriva la colonna discriminante di tenancy
//      (tenant_id|owner_id|user_id|actor_id); se assente, DICHIARA e salta;
//   6) semina COME postgres (bypassa RLS) due tenant (A, B) con righe
//      deterministiche;
//   7) interroga COME tenant A (SET LOCAL ROLE authenticated + request.jwt.claims
//      cosi' auth.uid() risolve all'utente di A) in UNA transazione per query;
//   8) fotografa per tabella { visible_rows, sees_other_tenant };
//   9) DROP dello schema effimero in un finally (nessuno stato residuo, non
//      mutante su public).
//
// DEGRADAZIONE (06 §6.1): se il comando psql e' assente/irraggiungibile o un
// qualsiasi passo fallisce, NON un falso verde: si usa lo static rls_check e si
// DICHIARA il confine ("RLS behavior not characterized at runtime; static
// checker used"), con observed = { static_flagged: true } e degraded: true.
//
// GENERICO sopra projectDir: glob di supabase/migrations/*.sql (non hardcoded
// 0001_init.sql), discriminante di tenancy derivata genericamente.
//
// DETERMINISMO: nessun Date.now()/Math.random nel codice che il gate esegue; lo
// schema effimero porta process.pid (isolamento per-processo contro le collisioni
// concorrenti), mentre l'ID delle assertion usa uno schema LOGICO fisso ('public')
// stabile tra il processo che genera la baseline e quello che la ricalcola.
//
// Node ESM, solo built-in (child_process per psql; nessuna dipendenza npm).

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { resolveRlsMigrationsDir } from '../loop/rls_scan.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RLS_CHECK = resolve(__dirname, '..', 'oracles', 'rls_check.mjs');

// Schema effimero ISOLATO PER-PROCESSO (no collisioni con public, NE con un altro
// processo che caratterizza l'RLS in parallelo). PRIMA era un nome FISSO
// ('trueline_charz_ephemeral'): due caratterizzazioni concorrenti (es. piu' gate
// in parallelo, o generate.mjs e run_loop che si sovrappongono) facevano
// DROP/CREATE dello STESSO schema, corrompendosi a vicenda -> snapshot RLS
// sporco -> degrado allo static (rlsRuntime=false, rebaselined=[], static_flagged)
// in modo INTERMITTENTE. Ora il nome porta process.pid: ogni processo ha il suo
// schema usa-e-getta. process.pid NON e' Date.now()/Math.random (resta
// deterministico nel senso di L-COL-002: l'OUTPUT osservato — visible_rows,
// sees_other_tenant — non dipende dal nome dello schema). Resta usa-e-getta:
// DROP in un finally.
const EPHEMERAL_SCHEMA = `trueline_charz_ephemeral_p${process.pid}`;

// SCHEMA LOGICO STABILE per gli ID delle assertion. CRUCIALE: l'ID di una
// assertion RLS ('rls:<schema>.<tabella>') deve essere IDENTICO tra il processo
// che GENERA la baseline e il processo (figlio, altro pid) che la RICALCOLA. Se
// l'ID portasse EPHEMERAL_SCHEMA (ora per-pid), gli ID divergerebbero -> il
// recompute non troverebbe l'id in baseline -> observed { missing:true } ->
// deep-equal rosso (il sintomo intermittente {missing:true}). Quindi l'ID usa un
// namespace LOGICO FISSO ('public', lo schema d'origine delle tabelle nelle
// migration), mentre lo schema EFFIMERO usa-e-getta resta per-pid solo per
// l'isolamento a livello di DB. Il gate valida gli id via regex
// `rls:[^.]+\.[^.]+`: 'rls:public.invoices' passa; il nome-tabella nudo
// (split('.').pop()) resta 'invoices'.
const ID_SCHEMA = 'public';

// UUID deterministici dei due tenant (A = utente "corrente", B = altro tenant).
const TENANT_A = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const TENANT_B = '22222222-2222-2222-2222-222222222222';

// Colonne candidate a discriminante di tenancy, in ordine di priorita'. La prima
// presente sulla tabella e' usata sia per seminare i due tenant sia per misurare
// sees_other_tenant. Euristica dichiarata e generica.
const TENANT_DISCRIMINATORS = ['tenant_id', 'owner_id', 'user_id', 'actor_id'];

// -----------------------------------------------------------------------------
// Risoluzione del comando psql (eval-only; la SKILL resta generica).
// Ordine: opts.psqlCmd -> TRUELINE_TEST_PSQL -> (dbUrl ? `psql "<dbUrl>"` : null).
// Un comando docker (es. `docker exec -i ... psql ...`) conta come disponibile.
// -----------------------------------------------------------------------------
function resolvePsqlCmd(opts = {}, dbUrl = null) {
  if (opts.psqlCmd) return opts.psqlCmd;
  if (process.env.TRUELINE_TEST_PSQL) return process.env.TRUELINE_TEST_PSQL;
  if (dbUrl) return `psql "${dbUrl}"`;
  return null;
}

// Runner: passa l'SQL su STDIN al comando risolto, appendendo i flag
// `-v ON_ERROR_STOP=1 -At`. status 0 = ok. (shell:true perche' il comando puo'
// essere una pipeline `docker exec ... psql ...`.)
function makeRunner(psqlCmd) {
  const full = `${psqlCmd} -v ON_ERROR_STOP=1 -At`;
  return (sql) => spawnSync(full, {
    input: sql,
    shell: true,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });
}

// psqlAvailable: il comando psql risolto gira davvero 'SELECT 1' e ritorna 0?
// (Sostituisce il vecchio check `psql --version` sul PATH, che falliva su un
// comando docker-based pur essendo perfettamente utilizzabile.)
function psqlAvailable(psqlCmd) {
  if (!psqlCmd) return false;
  const run = makeRunner(psqlCmd);
  const r = run('SELECT 1;');
  return !r.error && r.status === 0 && (r.stdout || '').trim().split('\n').includes('1');
}

// -----------------------------------------------------------------------------
// Static rls_check (path degradato)
// -----------------------------------------------------------------------------
function staticRls(projectDir, opts = {}) {
  // MANIFEST-DRIVEN (O-COL-011): chiede al resolver la migration-dir. Default
  // BIT-invariante 'supabase/migrations' per il layout Supabase; 'migrations/'
  // per postgres-py.
  const migrations = resolveRlsMigrationsDir(projectDir, { manifest: opts.manifest });
  if (!existsSync(migrations)) {
    return { ok: false, findings: [], detail: `migrations assenti: ${migrations}` };
  }
  const r = spawnSync(process.execPath, [RLS_CHECK, migrations], {
    cwd: projectDir, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
  });
  if (r.error) return { ok: false, findings: [], detail: `spawn rls_check: ${r.error.message}` };
  const raw = (r.stdout || '').trim();
  if (!raw) return { ok: false, findings: [], detail: 'rls_check: nessun output' };
  try {
    const j = JSON.parse(raw);
    return { ok: true, findings: j.findings || [], scanned: j.scanned_files || [] };
  } catch (e) {
    return { ok: false, findings: [], detail: `rls_check JSON invalido: ${e.message}` };
  }
}

// Costruisce assertion 'rls' DEGRADATE (statiche) a partire dai finding dello
// static checker. Ogni finding (tabella senza isolamento) diventa una assertion
// che CONGELA il fatto statico corrente con observed = { static_flagged: true }.
// Sono verdi-per-costruzione sul codice corrente (la migration insicura esiste).
function degradedAssertions(staticResult, reason) {
  const assertions = [];
  for (const f of (staticResult.findings || [])) {
    const table = (f.table || (f.location && f.location.table) || 'unknown').toString();
    const ctrl = f.control_id || f.controlId || f.rule_id || 'rls';
    assertions.push({
      id: `rls-static:${table}:${ctrl}`,
      kind: 'rls',
      target: table,
      file: 'supabase/migrations',
      observed: { static_flagged: true },
      degraded: true,
      description:
        `[DEGRADATA static] tabella ${table}: isolamento NON garantito a livello DDL `
        + `(${ctrl}). Comportamento corrente congelato staticamente.`,
    });
  }
  return {
    assertions,
    runtime: false,
    degraded: true,
    reason,
    tables: assertions.map((a) => a.target),
  };
}

// -----------------------------------------------------------------------------
// characterizeRls(projectDir, { dbUrl, psqlCmd }) -> {
//   assertions: [{ id, kind:'rls', target, file, observed, degraded? }],
//   runtime:    boolean,   true se caratterizzata a runtime contro Postgres
//   degraded:   boolean,   true se si e' ricaduti sullo static checker
//   reason:     string,    motivo della degradazione (se degraded)
//   tables:     [string],  tabelle coinvolte
// }
//
// Ritorna runtime:true + assertion-con-observed quando il DB e' raggiungibile;
// degrada e DICHIARA altrimenti. Mai un falso verde.
// -----------------------------------------------------------------------------
export function characterizeRls(projectDir, opts = {}) {
  const { dbUrl = null } = opts;
  const psqlCmd = resolvePsqlCmd(opts, dbUrl);

  // 1) Nessun comando psql risolvibile (ne psqlCmd, ne TRUELINE_TEST_PSQL, ne
  //    dbUrl) -> DEGRADA allo static checker e DICHIARA il confine.
  if (!psqlCmd) {
    const st = staticRls(projectDir, opts);
    if (!st.ok) {
      return {
        assertions: [], runtime: false, degraded: true, error: true,
        reason: `RLS non caratterizzata: nessun comando psql risolvibile e static checker KO (${st.detail})`,
        tables: [],
      };
    }
    return degradedAssertions(
      st,
      'RLS behavior not characterized at runtime; static checker used (nessun comando psql risolto)',
    );
  }

  // 2) Comando psql risolto ma NON funzionante ('SELECT 1' != 0) -> DEGRADA.
  if (!psqlAvailable(psqlCmd)) {
    const st = staticRls(projectDir, opts);
    if (!st.ok) {
      return {
        assertions: [], runtime: false, degraded: true, error: true,
        reason: `RLS non caratterizzata: comando psql irraggiungibile e static checker KO (${st.detail})`,
        tables: [],
      };
    }
    return degradedAssertions(
      st,
      'RLS behavior not characterized at runtime; static checker used (comando psql non raggiungibile)',
    );
  }

  // 3) Path RUNTIME: schema effimero -> apply -> seed -> query come tenant A ->
  //    snapshot -> DROP. Se QUALSIASI passo fallisce, DEGRADA (mai falso verde).
  try {
    const snapshot = runtimeSnapshot(projectDir, psqlCmd, opts);
    if (!snapshot.ok) {
      const st = staticRls(projectDir, opts);
      return degradedAssertions(
        st.ok ? st : { findings: [] },
        `RLS runtime fallita (${snapshot.detail}); static checker used`,
      );
    }
    return {
      assertions: snapshot.assertions,
      runtime: true,
      degraded: false,
      reason: null,
      tables: snapshot.assertions.map((a) => a.target),
    };
  } catch (e) {
    const st = staticRls(projectDir, opts);
    return degradedAssertions(
      st.ok ? st : { findings: [] },
      `RLS runtime eccezione (${e.message}); static checker used`,
    );
  }
}

// characterizePostFix(projectDir, { dbUrl, psqlCmd }) — ri-osserva dopo un
// cambio di policy. runtimeSnapshot e' gia' ri-eseguibile (DROP+CREATE schema a
// ogni invocazione): il loop verify-fix chiama questa per ri-misurare l'observed
// sul codice CORRENTE (es. dopo aver fixato S5, invoices.sees_other_tenant deve
// passare da true a false — l'assertion e' falsificabile).
export function characterizePostFix(projectDir, opts = {}) {
  return characterizeRls(projectDir, opts);
}

// -----------------------------------------------------------------------------
// runtimeSnapshot — flusso completo dello schema effimero.
// Ritorna { ok, assertions, detail }. Difensivo: DROP SCHEMA in un finally.
// -----------------------------------------------------------------------------
function runtimeSnapshot(projectDir, psqlCmd, opts = {}) {
  // MANIFEST-DRIVEN (O-COL-011): la migration-dir e' risolta dal resolver, non
  // cablata. Default BIT-invariante 'supabase/migrations'; 'migrations/' per
  // postgres-py.
  const migDir = resolveRlsMigrationsDir(projectDir, { manifest: opts.manifest });
  if (!existsSync(migDir)) {
    return { ok: false, detail: `migrations assenti: ${migDir}` };
  }

  // Glob generico delle migration *.sql ordinate (non hardcoded 0001_init.sql).
  let files;
  try {
    files = readdirSync(migDir)
      .filter((f) => f.toLowerCase().endsWith('.sql'))
      .sort()
      .map((f) => join(migDir, f));
  } catch (e) {
    return { ok: false, detail: `lettura migrations KO: ${e.message}` };
  }
  if (files.length === 0) {
    return { ok: false, detail: `nessuna migration *.sql in ${migDir}` };
  }

  // Concatena tutte le migration e riscrivi i riferimenti public.<x> -> <s>.<x>.
  // Lascia intatti auth.* e altri schemi: solo il prefisso 'public.' viene
  // riscritto sull'identificatore che segue.
  const S = EPHEMERAL_SCHEMA;
  let concatenated;
  try {
    concatenated = files.map((f) => readFileSync(f, 'utf8')).join('\n');
  } catch (e) {
    return { ok: false, detail: `lettura file migration KO: ${e.message}` };
  }
  const rewritten = concatenated.replace(
    /\bpublic\.([A-Za-z_][A-Za-z0-9_]*)/g,
    `${S}.$1`,
  );

  const run = makeRunner(psqlCmd);
  const q = (sql) => {
    const r = run(sql);
    if (r.error) throw new Error(`spawn psql: ${r.error.message}`);
    if (r.status !== 0) {
      throw new Error(`SQL status ${r.status}: ${(r.stderr || r.stdout || '').trim().slice(0, 200)}`);
    }
    return (r.stdout || '').trim();
  };

  // DROP difensivo + CREATE: lo schema effimero non deve mai persistere.
  try {
    q(`DROP SCHEMA IF EXISTS ${S} CASCADE; CREATE SCHEMA ${S};`);
  } catch (e) {
    return { ok: false, detail: `CREATE SCHEMA KO: ${e.message}` };
  }

  try {
    // Applica le migration riscritte con search_path sullo schema effimero, poi
    // concedi i privilegi base a 'authenticated' (RLS valutato DOPO il
    // privilegio sulla base-table).
    q(
      `SET search_path TO ${S}, public;\n`
      + `${rewritten}\n`
      + `GRANT USAGE ON SCHEMA ${S} TO authenticated;\n`
      + `GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA ${S} TO authenticated;`,
    );

    // Introspezione dal catalogo: quali tabelle hanno RLS abilitato.
    const rlsEnabled = new Map();
    for (const line of q(
      `SELECT relname || '|' || relrowsecurity FROM pg_class c `
      + `JOIN pg_namespace n ON n.oid = c.relnamespace `
      + `WHERE n.nspname = '${S}' AND c.relkind = 'r' ORDER BY relname;`,
    ).split('\n').filter(Boolean)) {
      const [t, r] = line.split('|');
      // -At concatena il boolean come 'true'/'false' (non 't'/'f'); accetta entrambi.
      rlsEnabled.set(t, r === 'true' || r === 't');
    }

    // Introspezione colonne (nome, tipo, nullabilita', default) per tabella.
    const columns = new Map();
    for (const line of q(
      `SELECT table_name || '|' || column_name || '|' || data_type || '|' `
      + `|| is_nullable || '|' || coalesce(column_default, '') `
      + `FROM information_schema.columns WHERE table_schema = '${S}' `
      + `ORDER BY table_name, ordinal_position;`,
    ).split('\n').filter(Boolean)) {
      const [t, c, dt, nul, def] = line.split('|');
      if (!columns.has(t)) columns.set(t, []);
      columns.get(t).push({ name: c, dataType: dt, nullable: nul === 'YES', hasDefault: def !== '' });
    }

    const assertions = [];
    // Itera in ordine deterministico (per nome tabella) per output stabile.
    for (const [table, cols] of [...columns.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
      // Solo tabelle con RLS abilitato: e' qui che l'isolamento ha senso.
      if (!rlsEnabled.get(table)) continue;

      const disc = TENANT_DISCRIMINATORS.find((d) => cols.some((c) => c.name === d));
      if (!disc) {
        // Nessun discriminante di tenancy: DICHIARA e salta (observed dedicato).
        assertions.push({
          // ID con schema LOGICO FISSO (stabile cross-processo), non lo schema
          // effimero per-pid (vedi ID_SCHEMA).
          id: `rls:${ID_SCHEMA}.${table}`,
          kind: 'rls',
          target: table,
          file: 'supabase/migrations',
          observed: { declared: 'no-tenant-discriminator' },
          degraded: true,
          description:
            `[DICHIARATA] tabella ${table}: nessuna colonna discriminante di `
            + `tenancy (${TENANT_DISCRIMINATORS.join('|')}); isolamento per-tenant `
            + `non misurabile a runtime, snapshot saltato.`,
        });
        continue;
      }

      // Semina COME postgres (bypassa RLS) due tenant. Per ogni tenant, riempi la
      // colonna discriminante con l'uuid del tenant e le altre colonne NOT NULL
      // senza default con valori deterministici per tipo; per le colonne text con
      // default (es. status='draft') sovrascrivi con un valore non-default cosi'
      // policy come "status <> 'draft'" non nascondano le righe seminate.
      for (const tenant of [TENANT_A, TENANT_B]) {
        const names = [];
        const values = [];
        for (const col of cols) {
          if (col.name === disc) {
            names.push(col.name);
            values.push(`'${tenant}'`);
            continue;
          }
          if (col.hasDefault) {
            // Sovrascrivi solo i text con default (es. status) per non far
            // nascondere le righe da policy basate su quel valore.
            if (col.dataType === 'text') {
              names.push(col.name);
              values.push(`'x'`);
            }
            continue; // uuid/timestamp con default: lasciali al default.
          }
          if (!col.nullable) {
            names.push(col.name);
            values.push(typedDummy(col.dataType, tenant));
          }
        }
        q(`INSERT INTO ${S}.${table} (${names.join(', ')}) VALUES (${values.join(', ')});`);
      }

      // Interroga COME tenant A in UNA transazione (RLS applicato): conta le
      // righe visibili e se ne vede di altri tenant.
      // ADDITIVE (O-COL-011 / L-COL-029): imposta sia request.jwt.claims
      // (idioma Supabase auth.uid()) sia app.current_tenant (idioma Postgres
      // non-Supabase con current_setting()). Il secondo set_config e' no-op per
      // le policy Supabase (non usano app.current_tenant) -> BIT-INVARIANTE.
      // Senza app.current_tenant la query su 'notes' (postgres-py) lancia
      // "unrecognized configuration parameter" -> status 3 -> degrada tutta la
      // caratterizzazione a static, rendendo il gate unreachable (FIX ROUND 1).
      const res = q(
        `BEGIN; `
        + `SET LOCAL ROLE authenticated; `
        + `SELECT set_config('request.jwt.claims', json_build_object('sub','${TENANT_A}')::text, true); `
        + `SELECT set_config('app.current_tenant', '${TENANT_A}', true); `
        + `SELECT count(*)::text || '|' || `
        + `coalesce(bool_or(${disc} <> '${TENANT_A}'::uuid)::text, 'false') `
        + `FROM ${S}.${table}; `
        + `COMMIT;`,
      );
      const m = res.split('\n').map((x) => x.trim()).find((x) => /^\d+\|(true|false)$/.test(x));
      if (!m) {
        return { ok: false, detail: `query tenant A su ${table}: output inatteso (${res.slice(0, 120)})` };
      }
      const [visibleStr, seesOtherStr] = m.split('|');

      assertions.push({
        // ID con schema LOGICO FISSO (stabile cross-processo): baseline e
        // recompute (processi distinti) condividono lo stesso id.
        id: `rls:${ID_SCHEMA}.${table}`,
        kind: 'rls',
        target: table,
        file: 'supabase/migrations',
        observed: {
          visible_rows: Number.parseInt(visibleStr, 10),
          sees_other_tenant: seesOtherStr === 'true',
        },
        description:
          `[RUNTIME] tabella ${table} (discriminante ${disc}): come tenant A, `
          + `righe visibili e visibilita' cross-tenant fotografate dal vero RLS `
          + `di Postgres. sees_other_tenant=true => isolamento assente (leak); `
          + `false => isolamento corretto (contrasto).`,
      });
    }

    if (assertions.length === 0) {
      return { ok: false, detail: 'nessuna tabella RLS trovata nello schema effimero' };
    }
    return { ok: true, assertions };
  } catch (e) {
    return { ok: false, detail: e.message };
  } finally {
    // DROP finale: nessuno stato residuo, non mutante su public.
    run(`DROP SCHEMA IF EXISTS ${S} CASCADE;`);
  }
}

// Valore dummy deterministico per tipo, per riempire colonne NOT NULL senza
// default in fase di seeding (lato postgres, bypassa RLS).
function typedDummy(dataType, tenant) {
  const d = (dataType || '').toLowerCase();
  if (d === 'uuid') return `'${tenant}'`;
  if (d.includes('int') || d === 'numeric' || d === 'real' || d === 'double precision') return '1';
  if (d === 'boolean') return 'true';
  if (d === 'jsonb' || d === 'json') return `'{}'::${d}`;
  if (d.includes('timestamp') || d === 'date') return 'now()';
  // text e affini: stringa non-vuota, non-'draft' (per non incappare in policy
  // di filtro su valori specifici come status).
  return `'x'`;
}

export default characterizeRls;
