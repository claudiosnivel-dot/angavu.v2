// coverage.mjs — dichiarazione ONESTA di copertura della characterization (06 §7).
//
// La characterization cattura il comportamento CORRENTE del percorso critico, ma
// NON copre tutto. Questo modulo emette una dichiarazione esplicita di cosa e'
// caratterizzato e cosa NON lo e' (ancora), con il MOTIVO. E' il fondamento del
// "criterio 3 onesto" (10 §5): niente "sicuro"/"safe" come garanzia, niente
// verified senza oracolo (L-COL-006).
//
// Categorie detection-only DIFFERITE a M4 (semgrep, 07 §4):
//   - injection (S6)  -> rilevata staticamente, NON corretta ne caratterizzata a
//                        runtime: serve semgrep (ruleset AI curato), M4.
//   - authz     (S7)  -> idem: rilevazione semantica differita a semgrep, M4.
// Queste NON possono diventare 'verified' in M3 (sarebbe un falso verde M4).
//
// Degradazione RLS a runtime: se la characterization RLS non gira contro un
// Postgres effimero (DB assente/irraggiungibile), si dichiara il limite
// ("RLS behavior not characterized at runtime; static checker used").
//
// GENERICO sopra un projectScan astratto (NON hardcoded alla reference app).
//
// Node ESM, solo built-in.

// Le categorie note che la characterization runtime NON copre ancora, con il
// motivo. GENERICHE: dipendono solo dalle categorie presenti nello scan, non da
// nomi di file specifici.
const DEFERRED_DETECTION_ONLY = {
  injection: {
    what: 'injection (es. SQL injection, S6)',
    why: 'rilevazione semantica differita a semgrep (ruleset AI curato) — M4; non caratterizzata ne corretta a runtime in M3 (07 §4)',
  },
  authz: {
    what: 'authz (controllo di identita/ruolo mancante, S7)',
    why: 'rilevazione semantica differita a semgrep — M4; non caratterizzata ne corretta a runtime in M3 (07 §4)',
  },
};

// coverageDeclaration(projectScan) -> { characterized, declared_uncovered }
//
// projectScan (forma generica, tutti i campi opzionali):
//   {
//     endpoints:   [{ method, path }]   endpoint HTTP del percorso critico
//     pureTargets: [{ name, file }]     funzioni pure caratterizzabili
//     buildIntegrity: boolean           esiste un check di build/typecheck
//     rls: {
//       tables:    [string]             tabelle DDL osservate
//       runtime:   boolean              true se caratterizzata a runtime (DB)
//       degraded:  boolean              true se degradata allo static checker
//       reason:    string               motivo della degradazione
//     }
//     detectionOnlyCategories: [string] categorie rilevate ma detection-only
//                                       (es. ['injection','authz']) -> M4
//   }
//
// Ritorna:
//   characterized        elenco leggibile di cosa e' caratterizzato ORA
//   declared_uncovered   [{ what, why }] cio' che NON e' coperto, col motivo
export function coverageDeclaration(projectScan = {}) {
  const {
    endpoints = [],
    pureTargets = [],
    buildIntegrity = false,
    rls = {},
    detectionOnlyCategories = [],
  } = projectScan;

  const characterized = [];
  for (const e of endpoints) {
    characterized.push(`endpoint:${e.method || 'GET'} ${e.path}`);
  }
  for (const t of pureTargets) {
    characterized.push(`pure:${t.name}`);
  }
  if (buildIntegrity) characterized.push('build-integrity:typecheck/build');

  // RLS: caratterizzata a runtime SOLO se non degradata.
  const rlsRuntime = rls.runtime === true && rls.degraded !== true;
  if (rlsRuntime) {
    for (const tbl of (rls.tables || [])) characterized.push(`rls:${tbl}`);
  }

  const declared_uncovered = [];

  // 1) Categorie detection-only differite a M4 (injection/authz -> semgrep).
  //    Le includiamo se compaiono nello scan; se lo scan non le elenca ma sono
  //    nel set canonico differito, le dichiariamo comunque (la reference app le
  //    contiene per costruzione: meglio onesti che silenti).
  const cats = new Set(detectionOnlyCategories);
  for (const key of Object.keys(DEFERRED_DETECTION_ONLY)) {
    if (cats.size === 0 || cats.has(key)) {
      declared_uncovered.push({ ...DEFERRED_DETECTION_ONLY[key] });
    }
  }

  // 2) Degradazione RLS a runtime: dichiarata esplicitamente.
  if (rls.degraded === true || (rls.runtime !== true && (rls.tables || []).length > 0)) {
    declared_uncovered.push({
      what: 'RLS a runtime (isolamento multi-tenant osservato come un tenant)',
      why: rls.reason
        || 'RLS behavior not characterized at runtime; static checker used (DB effimero assente/irraggiungibile)',
    });
  }

  return { characterized, declared_uncovered };
}

export default coverageDeclaration;
