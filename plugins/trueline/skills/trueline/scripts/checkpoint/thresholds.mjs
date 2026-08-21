// thresholds.mjs — loader unico delle soglie del checkpoint e del budget del loop.
//
// FONTE DI VERITA leggibile: trueline/references/oracles/thresholds.md. Questo
// modulo ne e' la trascrizione eseguibile: i numeri DEVONO restare allineati al
// reference (un disallineamento e' un bug, non una feature — vedi thresholds.md §6).
//
// Le SOGLIE di gating (GATE_SEVERITY, RLS_*, DEADCODE_*) restano default di policy
// ragionati. Il BUDGET del loop (O-COL-006) e' ora PINNATO EMPIRICAMENTE al parity
// gate M5 (10-EVALUATION §6): GLOBAL_WALL_CLOCK_MS = round(p95 x 1.25) sui campioni
// misurati da eval/harness/measure_budget.mjs. Vedi WALL_CLOCK_DERIVATION sotto.
//
// Node ESM, solo built-in (nessuna dipendenza npm, nessuna rete).

// Ordine di severita decrescente (04 §4). Indice piu' basso = piu' grave.
export const SEVERITY_ORDER = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];

// Soglia del controllo 2 (sicurezza): blocca i finding NUOVI con
// severity >= GATE_SEVERITY (default HIGH => blocca CRITICAL e HIGH).
export const GATE_SEVERITY = 'HIGH';

// Controllo 1 (dead-code): gate per DELTA, mai per severita (il dead-code non
// ha severita OWASP). Solo i finding baseline_status=new bloccano.
export const DEADCODE_GATE_ON = 'delta-only';

// Categorie del set verificato-a-zero v1 (L-COL-010): le categorie che il loop
// puo' portare a VERIFIED (auto-fix con riesecuzione dell'oracolo). Le detection-
// only (injection/authz) NON entrano qui: trovate/spiegate/prioritizzate ma MAI
// promosse a verificata-a-zero (registry: S6/S7 expected_fix_state=detection-only).
// INVARIATO da M0 (il loop non auto-fixa S6/S7).
export const VERIFIED_ZERO_CATEGORIES = new Set(['secret', 'rls', 'dead-code']);

// Categorie che BLOCCANO il controllo 2 (sicurezza) del checkpoint quando un
// finding e' NUOVO (baseline-delta) e sopra soglia. E' un superinsieme del set
// verificato-a-zero: oltre alle categorie auto-fixabili (secret/rls), aggiunge le
// DETECTION-BLOCKING injection/authz (07 §4.2/§4.3, M4). Cosi un NUOVO finding
// semgrep injection/authz introdotto in BUILD BLOCCA il gate (regressione di
// sicurezza), mentre un S6/S7 PRE-ESISTENTE non blocca (baseline-delta intatto).
// dead-code NON e' qui: il controllo 1 lo gestisce per DELTA, non il controllo 2.
// NB distinzione (L-COL-010): "blocca-il-gate-se-nuovo" (detection) NON significa
// "promosso a verificato": injection/authz restano detection-only (non in
// VERIFIED_ZERO_CATEGORIES), il loop non li auto-fixa.
export const CONTROL2_GATE_CATEGORIES = new Set(['secret', 'rls', 'injection', 'authz']);

// --- Loop-budget (O-COL-006, policy chiusa in 05 §4; budget PINNATO al M5) ---
// Derivazione empirica del tetto di tempo di parete (10-EVALUATION §6 / thresholds.md
// §5.1): p95 dei campioni di `run_loop --eval --mode=remediate --characterize` sulla
// reference app, con margine x1.25. Riproducibile con eval/harness/measure_budget.mjs.
export const WALL_CLOCK_DERIVATION = Object.freeze({
  // 95° percentile su 12 campioni: 10 dedicati (warm) + 2 del gate criterio-A
  // (1 cold 193921ms, 1 warm 161960ms). Conservativo (~max per n=12: il cold-start
  // che il gate esercita realmente domina la coda della distribuzione).
  p95_ms: 193_921,
  margin: 1.25,   // margine sopra il p95 (05 §4 / thresholds.md §5.1 step 4)
  samples: 12,    // >= 10 richiesti (thresholds.md §5.1 step 3)
});
export const LOOP_BUDGET = Object.freeze({
  // Cap per-finding: 2 retry = 3 tentativi totali (deciso/chiuso in 05 §4).
  MAX_RETRIES_PER_FINDING: 2,
  // Tetto di tempo di parete per sessione di verifica: PINNATO = round(p95 x margin)
  // = round(193_921 x 1.25) = 242_401 ms (~242s). Vedi WALL_CLOCK_DERIVATION.
  GLOBAL_WALL_CLOCK_MS: 242_401,
  // Budget di token per sessione: nella skill reale lo applica il runtime LLM; in
  // eval (fix provider deterministico, nessun token) NON si applica e NON e'
  // misurabile da questo banco -> resta null, DICHIARATO (L-COL-006), non finto.
  GLOBAL_TOKEN_BUDGET: null,
});

// Confronta due severita. Ritorna true se `sev` e' >= `floor` (piu' grave o
// uguale alla soglia). Severita sconosciuta => trattata come la meno grave.
export function severityAtLeast(sev, floor) {
  const i = SEVERITY_ORDER.indexOf(String(sev).toUpperCase());
  const j = SEVERITY_ORDER.indexOf(String(floor).toUpperCase());
  if (i === -1) return false; // severita ignota: non superare mai la soglia
  if (j === -1) return false;
  return i <= j; // indice minore = piu' grave
}

// Deriva da un manifest (SP-0): le categorie che il loop può portare a verified.
export function verifiedSetFrom(manifest) {
  return new Set((manifest && manifest.verified_set) || [...VERIFIED_ZERO_CATEGORIES]);
}
// Categorie che bloccano il controllo 2: verified_set "di sicurezza" (secret/rls)
// + le detection-blocking injection/authz SE legate nel manifest. Default = costante.
export function control2CategoriesFrom(manifest) {
  if (!manifest || !manifest.oracles) return new Set(CONTROL2_GATE_CATEGORIES);
  const cats = new Set();
  for (const key of Object.keys(manifest.oracles)) for (const c of key.split('|')) cats.add(c.trim());
  // mantieni solo le categorie "di sicurezza" gate-abili (no dead-code/dependency-vuln-here)
  return new Set([...cats].filter((c) => CONTROL2_GATE_CATEGORIES.has(c)));
}
