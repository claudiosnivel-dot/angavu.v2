// stabilize.mjs — STABILIZZAZIONE del non-determinismo per la characterization
// (06 §6.2). Una suite di characterization deve essere RIPRODUCIBILE: due
// esecuzioni sullo stesso codice danno lo stesso esito. Le fonti di
// non-determinismo (uptime, orologio, random, PID, ordine di Map/Set) vanno
// CONGELATE nei test; cio' che NON si puo' congelare va ESCLUSO dalle assertion e
// DICHIARATO in coverage.declared_uncovered — mai un assert flaky (06 §6.2,
// L-COL-002: il verde dev'essere una proprieta' stabile dell'output).
//
// Questo modulo offre:
//   - un CATALOGO generico di sorgenti di non-determinismo note;
//   - rilevatori (su testo sorgente) per decidere cosa stabilizzare vs escludere;
//   - generatori di PROLOGO di stabilizzazione da iniettare nei file di test.
//
// GENERICO: nessun nome della reference app. Node ESM, solo built-in.

// Catalogo: ogni voce ha un id, un matcher (regex sul sorgente), una strategia
// ('override' = stabilizzabile iniettando un valore fisso; 'exclude' = non
// stabilizzabile in modo affidabile, va escluso e dichiarato), e un prologo di
// override (se override-abile).
export const NONDETERMINISM_CATALOG = [
  {
    id: 'process.uptime',
    match: /process\.uptime\s*\(/,
    strategy: 'override',
    prologue: 'process.uptime = () => 0;',
    why: 'uptime cambia a ogni esecuzione: override a 0 (deterministico)',
  },
  {
    id: 'process.hrtime',
    match: /process\.hrtime\b/,
    strategy: 'override',
    prologue: 'process.hrtime = () => [0, 0];\nif (process.hrtime) process.hrtime.bigint = () => 0n;',
    why: 'hrtime e\' un orologio monotono: override a 0',
  },
  {
    id: 'Date.now',
    match: /Date\.now\s*\(|new\s+Date\s*\(\s*\)/,
    strategy: 'override',
    prologue: 'const __FIXED_NOW = 0; Date.now = () => __FIXED_NOW;',
    why: 'orologio di parete: override a un istante fisso (epoch 0)',
  },
  {
    id: 'Math.random',
    match: /Math\.random\s*\(/,
    strategy: 'override',
    prologue: 'Math.random = () => 0;',
    why: 'random: override a 0 (deterministico)',
  },
  {
    id: 'crypto.randomUUID',
    match: /randomUUID\s*\(|randomBytes\s*\(/,
    strategy: 'exclude',
    why: 'UUID/byte casuali crittografici: non stabilizzabili senza alterare la semantica — escludere e dichiarare',
  },
  {
    id: 'process.pid',
    match: /process\.pid\b/,
    strategy: 'exclude',
    why: 'PID del processo: varia a ogni run e non va falsificato — escludere e dichiarare',
  },
  {
    id: 'network-io',
    match: /fetch\s*\(|https?\.request|axios|net\.connect/,
    strategy: 'exclude',
    why: 'I/O di rete: esito non deterministico/offline — escludere dalle assertion e dichiarare',
  },
];

// scanNondeterminism(sourceText) -> { override:[...], exclude:[...] }
// Classifica le sorgenti di non-determinismo presenti nel testo.
export function scanNondeterminism(sourceText) {
  const text = String(sourceText || '');
  const override = [];
  const exclude = [];
  for (const entry of NONDETERMINISM_CATALOG) {
    if (entry.match.test(text)) {
      if (entry.strategy === 'override') override.push(entry);
      else exclude.push(entry);
    }
  }
  return { override, exclude };
}

// stabilizationPrologue(sources) -> { prologue:string, excluded:[{what,why}] }
//
// Dato un insieme di testi sorgente (o un singolo testo), produce:
//   - prologue: le righe JS da iniettare in cima a un file di test per congelare
//     le sorgenti override-abili (uptime/clock/random...). Deduplicato.
//   - excluded: l'elenco di cio' che NON si puo' stabilizzare, da riversare in
//     coverage.declared_uncovered.
export function stabilizationPrologue(sources) {
  const texts = Array.isArray(sources) ? sources : [sources];
  const prologues = new Set();
  const excluded = [];
  const excludedSeen = new Set();

  for (const t of texts) {
    const { override, exclude } = scanNondeterminism(t);
    for (const o of override) if (o.prologue) prologues.add(o.prologue);
    for (const x of exclude) {
      if (!excludedSeen.has(x.id)) {
        excludedSeen.add(x.id);
        excluded.push({ what: x.id, why: x.why });
      }
    }
  }

  const header = '// --- STABILIZZAZIONE non-determinismo (06 §6.2) ---';
  const prologue = prologues.size
    ? [header, ...prologues].join('\n')
    : `${header}\n// (nessuna sorgente override-abile rilevata)`;

  return { prologue, excluded };
}

export default stabilizationPrologue;
